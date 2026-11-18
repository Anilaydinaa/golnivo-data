import 'package:test/test.dart';
import 'package:golnivo_pipeline/src/domain.dart';
import 'package:golnivo_pipeline/src/model.dart';
import 'package:golnivo_pipeline/src/build.dart';
import 'package:golnivo_pipeline/src/statistics.dart';
import 'helpers.dart';

void main() {
  final teams = fixtureTeams();
  test('Eşit puanda ikili karşılaşma genel averajdan önce gelir', () {
    final games = [
      game(home: 'galatasaray', away: 'fenerbahce', hg: 1, ag: 0),
      game(home: 'galatasaray', away: 'besiktas', hg: 0, ag: 9),
      game(home: 'fenerbahce', away: 'besiktas', hg: 8, ag: 0)
    ];
    final table = standings(
        games,
        [teams.resolve('galatasaray'), teams.resolve('fenerbahce')],
        '2026-27',
        {});
    expect((table.first['team'] as Json)['id'], 'galatasaray');
  });
  test('Üçlü eşitlikte mini lig puan ve averaj sırası', () {
    final list = [
      game(home: 'galatasaray', away: 'fenerbahce', hg: 3, ag: 0),
      game(home: 'fenerbahce', away: 'besiktas', hg: 2, ag: 0),
      game(home: 'besiktas', away: 'galatasaray', hg: 1, ag: 0)
    ];
    final table = standings(
        list,
        ['galatasaray', 'fenerbahce', 'besiktas'].map(teams.resolve).toList(),
        '2026-27', {});
    expect(table.map((r) => (r['team'] as Json)['id']),
        ['galatasaray', 'fenerbahce', 'besiktas']);
  });
  test('Puan cezası ve boş sezon sıralaması', () {
    final list = [game(hg: 1, ag: 0)];
    final table = standings(
        list,
        [teams.resolve('galatasaray'), teams.resolve('fenerbahce')],
        '2026-27',
        {'galatasaray': -4});
    expect((table.first['team'] as Json)['id'], 'fenerbahce');
    expect(table.last['points'], -1);
    expect(table.last['pointAdjustment'], -4);
  });
  test('Analiz maç öncesi, saha ayrımı ve geçen sezondan form', () {
    final all = fixtureGames(),
        g = all.firstWhere((g) => g.season == '2026-27' && g.round == 1);
    final a = analysisFor(g, all, g.freezeAt, {}, homeCount: 40, awayCount: 0);
    final home = a['home'] as Json;
    expect((home['season'] as Json)['played'], 0);
    expect((home['form'] as List<dynamic>).length, 5);
    expect(
        (home['recent'] as List<dynamic>)
            .every((v) => (v as Json)['date'].toString().compareTo(g.date) < 0),
        isTrue);
    expect((home['venue'] as Json)['label'], 'home');
    expect((a['away'] as Json)['venue']['label'], 'away');
    expect((a['dataQuality'] as Json)['note'], isNotNull);
  });
  test('H2H iki sahayı da bu maçın takım yönüne çevirir', () {
    final target = game(date: '2026-11-22'),
        history = [
          game(date: '2026-08-01', hg: 2, ag: 0),
          game(
              date: '2026-08-02',
              home: 'fenerbahce',
              away: 'galatasaray',
              hg: 0,
              ag: 3),
          game(date: '2026-08-03', hg: 1, ag: 1)
        ];
    final a = analysisFor(target, history, target.freezeAt, {},
            homeCount: 3, awayCount: 3),
        h = a['h2h'] as Json;
    expect(h['played'], 3);
    expect(h['homeWins'], 2);
    expect(h['awayWins'], 0);
    expect(h['draws'], 1);
    expect(h['goalsHome'], 6);
    expect(h['goalsAway'], 1);
  });
  test('Türkçe reasons en fazla üç, adlara ek eklemez', () {
    final all = fixtureGames(),
        g = all.firstWhere((g) => g.season == '2026-27' && g.round == 12);
    final a = analysisFor(g, all, g.freezeAt, {}, homeCount: 30, awayCount: 30);
    final reasons = reasonsFor(g, a, 1.6, 0.9);
    expect(reasons.length, 3);
    expect(reasons.any((s) => s.contains("'") || s.contains('’')), isFalse);
    expect(reasons.any((s) => s.contains('Beklenen gol')), isTrue);
  });
  test('İsabet değerlendirmesi ve canlı/backfilled ayrımı', () {
    final g = game(hg: 2, ag: 1);
    final p = <String, dynamic>{
      'pick': 'home',
      'probabilities': {'home': 0.6, 'draw': 0.2, 'away': 0.2},
      'goals3Plus': 0.5,
      'bothScore': 0.4,
      'frozen': true,
      'backfilled': true
    };
    final outcome = outcomeFor(g, p);
    expect(outcome['pickHit'], isTrue);
    expect(outcome['goals3PlusHit'], isTrue);
    expect(outcome['bothScoreHit'], isFalse);
    final a = accuracyFor([g], {g.id: p}, '2026-11-18T06:00:00Z');
    expect((a['season'] as Json)['liveEvaluated'], 0);
    p['backfilled'] = false;
    final b = accuracyFor([g], {g.id: p}, '2026-11-18T06:00:00Z');
    expect((b['season'] as Json)['livePickHits'], 1);
  });
  test('İsabet gün ve hafta en yeni başta, boş gün null', () {
    expect(accuracyFor([], {}, '2026-11-18T06:00:00Z')['lastMatchDay'], isNull);
    final a = game(date: '2026-08-14', round: 1, hg: 1, ag: 0),
        b = game(
            date: '2026-08-22',
            round: 2,
            home: 'fenerbahce',
            away: 'galatasaray',
            hg: 0,
            ag: 1);
    final pred = <String, dynamic>{
      'pick': 'home',
      'probabilities': {'home': 0.5, 'draw': 0.3, 'away': 0.2},
      'goals3Plus': 0.5,
      'bothScore': 0.5,
      'frozen': true,
      'backfilled': true
    };
    final out =
        accuracyFor([a, b], {a.id: pred, b.id: pred}, '2026-11-18T06:00:00Z');
    expect((out['byDay'] as List<dynamic>).first['date'], '2026-08-22');
    expect((out['byRound'] as List<dynamic>).first['round'], 2);
  });
  test('Üretilen olasılıklar dört ondalık ve toplam bir', () {
    final all = fixtureGames(),
        cutoff = DateTime.parse('2026-11-18T06:00:00Z'),
        m = PoissonModel.fit(
            all, cutoff, const ModelConfig(xi: 0.003, regularization: 5));
    final g = all.firstWhere((g) => g.season == '2026-27' && g.round == 12),
        a = analysisFor(g, all, cutoff, {},
            homeCount: m.count(g.home.id), awayCount: m.count(g.away.id));
    final p = makePrediction(g, m, a, cutoff, false),
        probs = p['probabilities'] as Json;
    expect(probs.values.fold<double>(0, (s, v) => s + (v as num)),
        closeTo(1, 1e-10));
  });
}
