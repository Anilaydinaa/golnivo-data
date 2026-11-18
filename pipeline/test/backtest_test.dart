import 'package:test/test.dart';
import 'package:golnivo_pipeline/src/backtest.dart';
import 'package:golnivo_pipeline/src/model.dart';
import 'helpers.dart';

void main() {
  test('Karma saatli haftada backtest en erken dondurma sınırını kullanır', () {
    final history = fixtureGames().where((g) => g.season != '2026-27').toList();
    final laterResult = game(
        season: '2025-26',
        date: '2026-11-20',
        kickoff: '2026-11-20T12:00:00Z',
        hg: 1,
        ag: 0);
    final targets = [
      game(
          round: 12,
          date: '2026-11-21',
          kickoff: '2026-11-21T17:00:00Z',
          hg: 2,
          ag: 1),
      game(round: 12, date: '2026-11-22', home: 'besiktas', hg: 0, ag: 0),
    ];
    const config = ModelConfig(xi: 0.003, regularization: 5);
    final original = evaluateSeason(
        [...history, laterResult, ...targets], '2026-27', config);
    final poisoned = evaluateSeason([
      ...history,
      laterResult.copy(homeGoals: 99, awayGoals: 77),
      ...targets
    ], '2026-27', config);
    expect(original.model.n, 2);
    expect(poisoned.toJson(), original.toJson());
  });
}
