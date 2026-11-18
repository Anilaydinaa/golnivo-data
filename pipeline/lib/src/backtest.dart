import 'dart:io';
import 'domain.dart';
import 'model.dart';
import 'statistics.dart';

class Evaluation {
  final Metrics model = Metrics(), home = Metrics(), frequency = Metrics();
  final Map<String, Metrics> confidence = {
    'low': Metrics(),
    'medium': Metrics(),
    'high': Metrics()
  };
  Json toJson() => {
        'model': model.toJson(),
        'alwaysHome': home.toJson(),
        'trainingFrequency': frequency.toJson(),
        'confidence': confidence.map((k, v) => MapEntry(k, v.toJson()))
      };
}

Evaluation evaluateSeason(List<Game> all, String season, ModelConfig config) {
  all = withRoundFreezeTimes(all);
  final targets = all.where((g) => g.season == season && g.finished).toList()
    ..sort(compareGames);
  final weeks = <String, List<Game>>{};
  for (final g in targets) {
    final local = (g.kickoff ?? g.localDayStart).add(const Duration(hours: 3));
    final monday = DateTime.utc(local.year, local.month, local.day)
        .subtract(Duration(days: local.weekday - 1));
    weeks.putIfAbsent(dateString(monday), () => []).add(g);
  }
  final result = Evaluation();
  for (final week in weeks.values) {
    final cutoff =
        week.map((g) => g.freezeAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final fitted = PoissonModel.fit(all, cutoff, config);
    final training = PoissonModel.training(all, cutoff), counts = [1, 1, 1];
    for (final g in training) {
      counts[g.result]++;
    }
    final freq = counts.map((n) => n / (training.length + 3)).toList();
    for (final g in week) {
      final d = fitted.predict(g),
          goals = (d.goals3Plus >= 0.5) == (g.homeGoals! + g.awayGoals! >= 3),
          both = (d.bothScore >= 0.5) == (g.homeGoals! > 0 && g.awayGoals! > 0);
      result.model
          .add(g.result, d.probabilities, goalsHit: goals, bothHit: both);
      result.confidence[fitted.confidence(g, d)]!
          .add(g.result, d.probabilities, goalsHit: goals, bothHit: both);
      result.home.add(g.result, [1, 0, 0]);
      result.frequency.add(g.result, freq);
    }
  }
  return result;
}

Future<void> runBacktest(
    String root, List<Game> games, List<String> warnings) async {
  final grid = <Json>[];
  ModelConfig? best;
  double bestLoss = double.infinity;
  for (final xi in [0.001, 0.003, 0.006]) {
    for (final reg in [1.0, 5.0, 15.0]) {
      final config = ModelConfig(xi: xi, regularization: reg);
      final a = evaluateSeason(games, '2023-24', config),
          b = evaluateSeason(games, '2024-25', config);
      final loss =
          (a.model.logLoss + b.model.logLoss) / (a.model.n + b.model.n);
      grid.add({
        ...config.toJson(),
        'logLoss': rounded(loss),
        'evaluated': a.model.n + b.model.n
      });
      stdout.writeln(
          'Izgara xi=$xi L2=$reg: log loss ${loss.toStringAsFixed(6)}');
      if (loss < bestLoss) {
        bestLoss = loss;
        best = config;
      }
    }
  }
  final selected = best!;
  final results = <String, Evaluation>{};
  for (final s in ['2023-24', '2024-25', '2025-26']) {
    results[s] = evaluateSeason(games, s, selected);
    stdout.writeln('$s: ${results[s]!.model.toJson()}');
  }
  final report = {
    'modelVersion': modelVersion,
    'selected': selected.toJson(),
    'grid': grid,
    'seasons': results.map((k, v) => MapEntry(k, v.toJson()))
  };
  writeJson('$root/data/model.json', report);
  String percent(num v) =>
      '%${(100 * v).toStringAsFixed(2).replaceAll('.', ',')}';
  final out = StringBuffer('''# Geriye dönük test

Çalıştırma tarihi: 18.11.2026. Model: `$modelVersion`. Bu dosya `dart run bin/backtest.dart` ile gerçek kaynak anlık kopyalarından üretilir.

## Yöntem

Maçlar kaynak tarihi/başlangıcının takvim haftasına ayrılır; her grubun en erken dondurma anında yeniden eğitim yapılır. Başlangıcı bilinen maçta dondurma anı başlangıçtır; saatsiz maçta aynı sezon/round içindeki saatsiz maçların en erken yerel tarihinden üç gün önce 00:00 Türkiye saatidir. Saatli maçlar bu erken sınıra çekilmez. Eğitim: o tarihin sezonu ve önceki üç sezon içinde, sonucu eğitim kesiminden önce bilinebilir olan maçlar. Saat biliniyorsa başlangıç +3 saat; bilinmiyorsa Türkiye yerel gününün sonu kullanılır. Aynı haftanın sonraki sonuçları eğitime alınmaz. Ertelenip başka haftaya taşınan maç kendi tarihindeki haftaya girer. İstatistikler güncel kaynakta düzeltilmiş sonuçları içerir; geçmiş kaynak revizyonlarının ilk yayımlanma zamanları bilinmiyor.

Karar: Planın kaynak listesi 2021-22 ve 2022-23 içermediğinden bu sezonlar eklenmedi. Özellikle 2023-24 başlangıcında eğitim penceresinde yalnız 2020-21 var; bu veri boşluğu karşılaştırmanın sınırıdır. 2018-19 ve 2019-20 geçmiş ilk sezon önselini ve H2H bilgisini destekler.

L2 cezası 0.5 × λ_reg × toplam parametre farkı karesi. Çözüm deterministik L-BFGS, en fazla 600 adım, en büyük mutlak gradyan <0.0001. Yakınsamayan eğitim çalıştırmayı durdurur. Yükselen takım önseli yalnız önceki sezonu da veri setinde bulunan geçmiş ilk sezonların (en az 20 maç) lig ortalamasına göre log gol güçlerinden hesaplanır; veri yoksa sıfırdır. Gelecek sonuçlar kullanılmaz.

Skor matrisi 0–10, kesilen kuyruk toplamına bölünerek normalize edilir. Brier üç sınıftaki kare farkların toplamıdır (0–2). Log loss doğal logaritma kullanır. Tek sınıf seçen ev sahibi taban çizgisinde sıfır olasılıklar yalnız log hesabında 1e-15 ile sınırlanır. Frekans taban çizgisi aynı eğitim penceresindeki sonuç sayılarından, sınıf başına +1 yumuşatmayla üretilir. Piyasa fiyatları kullanılmadı; ücretsiz ve uygun lisanslı kaynak bulunmuyor.

## Parametre seçimi

2023-24 + 2024-25 toplam log loss en aza indirilir. 2025-26 yalnız raporlanan holdout; seçimde kullanılmaz.

| ξ (gün⁻¹) | λ_reg | Maç | Log loss |
|---:|---:|---:|---:|
''');
  for (final r in grid) {
    out.writeln(
        '| ${r['xi']} | ${r['regularization']} | ${r['evaluated']} | ${r['logLoss']} |');
  }
  out.writeln(
      '\nSeçilen ξ=${selected.xi}, λ_reg=${selected.regularization}.\n');
  out.writeln(
      '## Sonuçlar\n\n| Sezon | Yöntem | Maç | 1X2 isabet | Log loss | Brier | 3+ gol isabet | İki takım gol isabet |\n|---|---|---:|---:|---:|---:|---:|---:|');
  for (final e in results.entries) {
    for (final pair in [
      ('Poisson', e.value.model),
      ('Her zaman ev sahibi', e.value.home),
      ('Eğitim frekansları', e.value.frequency)
    ]) {
      final j = pair.$2.toJson();
      out.writeln(
          '| ${e.key}${e.key == '2025-26' ? ' (holdout)' : ''} | ${pair.$1} | ${j['evaluated']} | ${j['pickHits']}/${j['evaluated']} (${percent(j['pickRate'] as num)}) | ${j['logLoss']} | ${j['brier']} | ${pair.$1 == 'Poisson' ? percent(j['goals3PlusRate'] as num) : '—'} | ${pair.$1 == 'Poisson' ? percent(j['bothScoreRate'] as num) : '—'} |');
    }
  }
  out.writeln(
      '\n## Kalibrasyon\n\nHer maçın üç sınıf olasılığı ayrı gözlemdir. Boş kovalar çizgiyle gösterilir.\n\n| Sezon | Olasılık kovası | Gözlem | Ortalama tahmin | Gerçekleşme |\n|---|---|---:|---:|---:|');
  for (final e in results.entries) {
    for (final b in e.value.model.toJson()['calibration'] as List<dynamic>) {
      final j = b as Json;
      out.writeln(
          '| ${e.key} | ${j['bucket']} | ${j['count']} | ${j['meanProbability'] ?? '—'} | ${j['observedRate'] ?? '—'} |');
    }
  }
  out.writeln(
      '\n## Güven etiketleri\n\nDüşük: en büyük olasılık <0.42 veya takımlardan biri için eğitim penceresinde <6 lig maçı. Yüksek: en büyük olasılık ≥0.55 ve iki takımda da toplam zaman ağırlığı ≥12. Diğerleri orta. Eşikler holdout üzerinden ayarlanmadı; aşağıdaki grup büyüklükleri ve isabetler etiketin yorumlanmasını sağlar. Yüksek etiketi sonuç sözü değildir.\n\n| Sezon | Etiket | Maç | 1X2 isabet |\n|---|---|---:|---:|');
  for (final e in results.entries) {
    for (final c in e.value.confidence.entries) {
      out.writeln(
          '| ${e.key} | ${c.key} | ${c.value.n} | ${c.value.n == 0 ? '—' : percent(c.value.hits / c.value.n)} |');
    }
  }
  out.writeln(
      '\n## Veri ve sınırlar\n\n[openfootball/europe](https://github.com/openfootball/europe) (CC0 1.0), [Wikipedia katkıcıları: 2025–26 Süper Lig](https://en.wikipedia.org/wiki/2025%E2%80%9326_S%C3%BCper_Lig) ve [2026–27 Süper Lig](https://en.wikipedia.org/wiki/2026%E2%80%9327_S%C3%BCper_Lig) (CC BY-SA 4.0). Wikipedia sonuçları takım kimliklerine dönüştürülüp openfootball fikstürüne birleştirildi. İndirilen asıllar `data/cache/`, ağsız test kopyaları `pipeline/test/fixtures/`, makinece okunur rapor `data/model.json` altında. Wikipedia kaynaklı türetilmiş sonuçlar aynı lisansla sunulur; [lisans](https://creativecommons.org/licenses/by-sa/4.0/), [sayfa geçmişi](https://en.wikipedia.org/w/index.php?title=2025%E2%80%9326_S%C3%BCper_Lig&action=history).\n');
  for (final s in seasons) {
    final list = games.where((g) => g.season == s).toList();
    if (list.isNotEmpty) {
      out.writeln(
          '- $s: ${list.length} fikstür, ${list.where((g) => g.finished).length} sonuç.');
    }
  }
  out.writeln(
      '\nEksik sonuçlar (değerlendirme dışı; gelecek fikstür hariç):\n\n| Sezon | Tarih | Ev sahibi | Deplasman |\n|---|---|---|---|');
  final referenceTime = DateTime.parse('2026-11-18T06:00:00Z');
  for (final g in games
      .where((g) => !g.finished && g.resultAt.isBefore(referenceTime))) {
    out.writeln(
        '| ${g.season} | ${g.date} | ${g.home.name} | ${g.away.name} |');
  }
  out.writeln(
      '\nKarar: Sözleşmede sonuç bekleniyor durumu bulunmadığından, başlangıcı geçmiş ve sonucu eksik maç postponed olarak işaretlenir; bu teknik etiket resmî erteleme tespiti değildir. meta.json uyarısı bu belirsizliği bildirir.\n');
  for (final w in warnings) {
    out.writeln('- Kaynak uyarısı: $w');
  }
  out.writeln(
      '\nİlk üretimde geçmiş tahminler walk-forward ile tamamlanır ve `backfilled: true` taşır. Bunlar gerçek zamanda yayımlanmış isabet olarak sayılmaz. Poisson bağımsız gol varsayımı, eksik sezonlar ve saat bilgisi olmayan maçlar başlıca sınırlardır.');
  File('$root/docs/BACKTEST.md').writeAsStringSync(out.toString());
}
