import 'dart:io';
import 'package:golnivo_pipeline/src/domain.dart';
import 'package:golnivo_pipeline/src/parsers.dart';

Teams fixtureTeams() => Teams.read('../data/teams.json');
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
List<Game> fixtureGames() {
  final teams = fixtureTeams(), all = <Game>[];
  for (final s in seasons) {
    final games = parseOpenFootball(fixture('openfootball-$s.txt'), s, teams);
    final wiki = ['2025-26', '2026-27'].contains(s)
        ? parseWikipedia(fixture('wikipedia-$s.json'), s, teams)
        : <String, (int, int)>{};
    all.addAll(mergeGames(games, wiki, [], []));
  }
  return withRoundFreezeTimes(all)..sort(compareGames);
}

Game game(
    {String season = '2026-27',
    int round = 1,
    String date = '2026-08-14',
    String? kickoff,
    String home = 'galatasaray',
    String away = 'fenerbahce',
    int? hg,
    int? ag}) {
  final teams = fixtureTeams();
  return Game(
      season: season,
      round: round,
      date: date,
      kickoff: kickoff == null ? null : DateTime.parse(kickoff),
      home: teams.resolve(home),
      away: teams.resolve(away),
      homeGoals: hg,
      awayGoals: ag);
}

Directory testDirectory() =>
    (Directory('test/.tmp')..createSync(recursive: true))
        .createTempSync('case-');
