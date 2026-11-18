import 'package:test/test.dart';
import 'package:golnivo_pipeline/src/domain.dart';
import 'package:golnivo_pipeline/src/model.dart';
import 'package:golnivo_pipeline/src/statistics.dart';
import 'helpers.dart';

void main() {
  final all = fixtureGames();
  const config = ModelConfig(xi: 0.003, regularization: 5);
  test('Poisson matrisi analitik olasılıklar ve normalizasyon', () {
    final d = poisson(1.6, 0.9);
    expect(d.probabilities.reduce((a, b) => a + b), closeTo(1, 1e-12));
    expect(d.bothScore, closeTo(0.4736, 0.0001));
    expect(d.goals3Plus, closeTo(0.4562, 0.0001));
    expect(d.topScores.length, 3);
    expect(d.topScores.first['home'], 1);
    expect(d.topScores.first['away'], 0);
    expect(d.pick, 0);
  });
  test('Simetrik takımlarda ev ve deplasman eşit', () {
    final d = poisson(1, 1);
    expect(d.probabilities[0], closeTo(d.probabilities[2], 1e-14));
  });
  test('Gerçek veride yakınsama ve deterministik çözüm', () {
    final t = DateTime.parse('2026-11-18T06:00:00Z');
    final a = PoissonModel.fit(all, t, config),
        b = PoissonModel.fit(all, t, config);
    expect(a.converged, isTrue);
    expect(a.gradientNorm, lessThan(0.0001));
    expect(a.iterations, lessThan(600));
    expect(a.parameters, b.parameters);
    expect(a.promoted, containsAll(['amedspor', 'erzurumspor-fk', 'corum-fk']));
    expect(a.promotedPrior.$1, isNot(0));
  });
  test('Gelecek skorlar ve aynı gün bilinmeyen sonuçlar sızmaz', () {
    final t = DateTime.parse('2025-08-08T17:30:00Z');
    final poisoned = all
        .map((g) =>
            !g.resultAt.isBefore(t) ? g.copy(homeGoals: 99, awayGoals: 77) : g)
        .toList();
    final a = PoissonModel.fit(all, t, config),
        b = PoissonModel.fit(poisoned, t, config);
    expect(a.parameters, b.parameters);
    expect(PoissonModel.training(all, t).every((g) => g.resultAt.isBefore(t)),
        isTrue);
  });
  test('Üç sezon penceresinden eski maçlar eğitime girmez', () {
    final t = DateTime.parse('2026-11-18T06:00:00Z');
    expect(
        PoissonModel.training(all, t)
            .every((g) => int.parse(g.season.substring(0, 4)) >= 2023),
        isTrue);
  });
  test('Yakınsamayan çözüm ve boş eğitim hata verir', () {
    expect(
        () => PoissonModel.fit(
            all, DateTime.parse('2026-11-18T06:00:00Z'), config,
            maxIterations: 0),
        throwsStateError);
    expect(() => PoissonModel.fit([], DateTime.utc(2026), config),
        throwsStateError);
  });
  test('Az verili yeni takım düşük güven alır', () {
    final t = DateTime.parse('2026-08-13T06:00:00Z'),
        m = PoissonModel.fit(all, t, config);
    final g =
        all.firstWhere((g) => g.season == '2026-27' && g.home.id == 'amedspor');
    expect(m.count('amedspor'), 0);
    expect(m.confidence(g, m.predict(g)), 'low');
  });
  test('Metriklerin bilinen örneği ve kalibrasyon gözlem sayısı', () {
    final m = Metrics()..add(0, [0.5, 0.25, 0.25]);
    final j = m.toJson();
    expect(j['logLoss'], 0.6931);
    expect(j['brier'], 0.375);
    expect(j['pickHits'], 1);
    final bins = j['calibration'] as List<dynamic>;
    expect(bins.fold<int>(0, (s, b) => s + ((b as Json)['count'] as int)), 3);
  });
}
