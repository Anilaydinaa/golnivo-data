import 'dart:convert';
import 'dart:io';

typedef Json = Map<String, dynamic>;
const currentSeason = '2026-27';
const modelVersion = 'poisson-tw-1';
const seasons = [
  '2018-19',
  '2019-20',
  '2020-21',
  '2023-24',
  '2024-25',
  '2025-26',
  '2026-27'
];
String iso(DateTime t) =>
    t.toUtc().toIso8601String().replaceFirst('.000Z', 'Z');
double rounded(num v) => double.parse(v.toStringAsFixed(4));
String dateString(DateTime t) => t.toIso8601String().substring(0, 10);
String normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('i̇', 'i')
    .replaceAll('ı', 'i')
    .replaceAll(RegExp(r'\s+'), ' ');

class Team {
  final String id, name;
  final List<String> aliases, wikiCodes;
  Team(this.id, this.name, this.aliases, this.wikiCodes);
  Json toJson() => {'id': id, 'name': name};
}

class Teams {
  final List<Team> all;
  final Map<String, Team> _names = {};
  Teams(this.all) {
    for (final t in all) {
      for (final n in [t.id, t.name, ...t.aliases]) {
        final key = normalize(n);
        if (_names.containsKey(key) && _names[key]!.id != t.id) {
          throw FormatException('Çakışan takım adı: $n');
        }
        _names[key] = t;
      }
    }
  }
  factory Teams.read(String file) =>
      Teams((jsonDecode(File(file).readAsStringSync()) as List<dynamic>)
          .map((dynamic v) {
        final j = v as Json;
        return Team(
            j['id'] as String,
            j['name'] as String,
            (j['aliases'] as List<dynamic>).cast<String>(),
            (j['wikiCodes'] as List<dynamic>).cast<String>());
      }).toList());
  Team resolve(String name) =>
      _names[normalize(name)] ??
      (throw FormatException('Eşlenemeyen takım: $name'));
}

class Game {
  final String season;
  final int round;
  final String date;
  final DateTime? kickoff;
  final DateTime? unknownRoundFreezeAt;
  final Team home, away;
  final int? homeGoals, awayGoals;
  final bool postponed;
  Game(
      {required this.season,
      required this.round,
      required this.date,
      required this.kickoff,
      required this.home,
      required this.away,
      this.unknownRoundFreezeAt,
      this.homeGoals,
      this.awayGoals,
      this.postponed = false});
  String get id => '$season-${home.id}-${away.id}';
  bool get finished => homeGoals != null && awayGoals != null;
  DateTime get localDayStart =>
      DateTime.parse('${date}T00:00:00+03:00').toUtc();
  DateTime get freezeAt =>
      kickoff ??
      unknownRoundFreezeAt ??
      localDayStart.subtract(const Duration(days: 3));
  // Sonucun bilinebilirliği: saat varsa 3 saat sonra; yoksa yerel gün sonu.
  DateTime get resultAt =>
      kickoff?.add(const Duration(hours: 3)) ??
      localDayStart.add(const Duration(days: 1));
  int get result =>
      homeGoals! > awayGoals! ? 0 : (homeGoals == awayGoals ? 1 : 2);
  Json? get score => finished ? {'home': homeGoals, 'away': awayGoals} : null;
  Game copy(
          {String? date,
          DateTime? kickoff,
          DateTime? unknownRoundFreezeAt,
          bool clearKickoff = false,
          int? homeGoals,
          int? awayGoals,
          bool? postponed,
          bool clearScore = false}) =>
      Game(
          season: season,
          round: round,
          date: date ?? this.date,
          kickoff: clearKickoff ? null : kickoff ?? this.kickoff,
          unknownRoundFreezeAt:
              unknownRoundFreezeAt ?? this.unknownRoundFreezeAt,
          home: home,
          away: away,
          homeGoals: clearScore ? null : homeGoals ?? this.homeGoals,
          awayGoals: clearScore ? null : awayGoals ?? this.awayGoals,
          postponed: postponed ?? this.postponed);
}

// Birleştirme ve saat düzeltmelerinden sonra sezon/hafta bağlamını uygula.
List<Game> withRoundFreezeTimes(Iterable<Game> games) {
  final all = games.toList(), earliest = <String, DateTime>{};
  for (final g in all.where((g) => g.kickoff == null)) {
    final key = '${g.season}/${g.round}', start = g.localDayStart;
    if (earliest[key] == null || start.isBefore(earliest[key]!)) {
      earliest[key] = start;
    }
  }
  return all
      .map((g) => g.copy(
          unknownRoundFreezeAt: earliest['${g.season}/${g.round}']
              ?.subtract(const Duration(days: 3))))
      .toList();
}

List<Game> before(Iterable<Game> games, DateTime cutoff) =>
    games.where((g) => g.finished && g.resultAt.isBefore(cutoff)).toList()
      ..sort(compareGames);
int compareGames(Game a, Game b) {
  // Form/H2H ve fikstür sırası, erken dondurma sınırından bağımsızdır.
  final c =
      (a.kickoff ?? a.localDayStart).compareTo(b.kickoff ?? b.localDayStart);
  return c == 0 ? a.id.compareTo(b.id) : c;
}

void writeJson(String path, Object? value) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  final tmp = File('$path.tmp');
  tmp.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n');
  tmp.renameSync(path);
}
