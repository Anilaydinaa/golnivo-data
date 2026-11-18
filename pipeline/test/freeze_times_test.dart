import 'package:test/test.dart';
import 'package:golnivo_pipeline/src/domain.dart';
import 'package:golnivo_pipeline/src/parsers.dart';
import 'package:golnivo_pipeline/src/statistics.dart';
import 'helpers.dart';

void main() {
  test('Saatsiz hafta en erken saatsiz tarihten üç gün önce donar', () {
    final games = withRoundFreezeTimes([
      game(round: 12, date: '2026-11-22'),
      game(round: 12, date: '2026-11-23', home: 'besiktas'),
      game(round: 13, date: '2026-11-29'),
      game(season: '2025-26', round: 12, date: '2025-11-16'),
    ]);
    expect(iso(games[0].freezeAt), '2026-11-18T21:00:00Z');
    expect(games[1].freezeAt, games[0].freezeAt);
    expect(iso(games[2].freezeAt), '2026-11-25T21:00:00Z');
    expect(iso(games[3].freezeAt), '2025-11-12T21:00:00Z');
    // Sonuç kullanılabilirliği dondurma zamanına göre erkene taşınmaz.
    expect(iso(games[1].resultAt), '2026-11-23T21:00:00Z');
  });
  test(
      'Yerel kickoff CSV düzeltmesi kendi saatinde donar, saatsizleri etkilemez',
      () {
    final unknown = game(round: 12, date: '2026-11-22');
    final timed = game(round: 12, date: '2026-11-21', home: 'besiktas');
    final games = mergeGames(
        [unknown, timed],
        {},
        csvRecords('season,homeId,awayId,kickoffLocal,status\n'
            '2026-27,besiktas,fenerbahce,2026-11-20 20:00,scheduled\n'),
        []);
    final corrected = games.singleWhere((g) => g.id == timed.id);
    expect(corrected.date, '2026-11-20');
    expect(iso(corrected.kickoff!), '2026-11-20T17:00:00Z');
    expect(corrected.freezeAt, corrected.kickoff);
    expect(iso(games.singleWhere((g) => g.id == unknown.id).freezeAt),
        '2026-11-18T21:00:00Z');
  });
  test('Erken saatli maçın başlangıcı saatsiz tarihin hesabına girmez', () {
    final games = withRoundFreezeTimes([
      game(round: 12, date: '2026-11-16', kickoff: '2026-11-16T17:00:00Z'),
      game(round: 12, date: '2026-11-22', home: 'besiktas'),
    ]);
    expect(iso(games.first.freezeAt), '2026-11-16T17:00:00Z');
    expect(iso(games.last.freezeAt), '2026-11-18T21:00:00Z');
  });
  test('Geçersiz yerel başlangıç CSV alanı reddedilir', () {
    final g = game();
    for (final value in [
      '2026-02-30 20:00',
      '2026-11-20 24:00',
      '2026-11-20T20:00'
    ]) {
      expect(
          () => mergeGames([
                g
              ], {}, [
                {
                  'season': g.season,
                  'homeId': g.home.id,
                  'awayId': g.away.id,
                  'kickoffLocal': value,
                }
              ], []),
          throwsFormatException);
    }
  });
  test('Form sırası dondurma zamanıyla değil kaynak başlangıcıyla belirlenir',
      () {
    final games = withRoundFreezeTimes([
      game(
          round: 12,
          date: '2026-11-21',
          kickoff: '2026-11-21T17:00:00Z',
          hg: 0,
          ag: 1),
      game(round: 12, date: '2026-11-23', away: 'besiktas', hg: 2, ag: 0),
    ]);
    expect(games.last.freezeAt.isBefore(games.first.freezeAt), isTrue);
    expect(teamGames(games, 'galatasaray').first.id, games.last.id);
  });
}
