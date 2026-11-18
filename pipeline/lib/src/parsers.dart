import 'dart:convert';
import 'domain.dart';

List<Game> parseOpenFootball(String text, String season, Teams teams) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  var year = int.parse(season.substring(0, 4));
  var previousMonth = 7, round = 0;
  String? date, time;
  final games = <Game>[];
  for (final raw in const LineSplitter().convert(text)) {
    var line = raw.trim().replaceAll(RegExp(r'\s*\[[^\]]*\]'), '').trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('=')) continue;
    if (line.startsWith('▪')) {
      final n = RegExp(r'\d+').firstMatch(line);
      if (n == null) throw FormatException('Hafta başlığı: $line');
      round = int.parse(n[0]!);
      continue;
    }
    final d = RegExp(
            r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+([A-Za-z]{3})\s+(\d{1,2})(?:\s+(\d{4}))?\s*$')
        .firstMatch(line);
    if (d != null) {
      final month = months.indexOf(d[1]!) + 1;
      if (month == 0) throw FormatException('Ay: $line');
      if (d[3] != null) {
        year = int.parse(d[3]!);
      } else if (previousMonth >= 10 && month <= 3) {
        year++;
      }
      previousMonth = month;
      date = dateString(DateTime.utc(year, month, int.parse(d[2]!)));
      time = null;
      continue;
    }
    final tm = RegExp(r'^(\d{1,2}:\d{2})\s+').firstMatch(line);
    if (tm != null) {
      time = tm[1];
      line = line.substring(tm.end);
    }
    if (line.startsWith('(') ||
        !RegExp(r'\s+v\s+|\s+\d+\s*[-–−]\s*\d+').hasMatch(line)) {
      continue;
    }
    if (date == null || round == 0) {
      throw FormatException('Tarihsiz/haftasız maç: $line');
    }
    String home, away;
    int? hg, ag;
    final vs = RegExp(
            r'^(.+?)\s+v\s+(.+?)(?:\s+(\d+)\s*[-–−]\s*(\d+)(?:\s*\([^)]*\))?)?\s*$')
        .firstMatch(line);
    if (vs != null) {
      home = vs[1]!.trim();
      away = vs[2]!.trim();
      hg = int.tryParse(vs[3] ?? '');
      ag = int.tryParse(vs[4] ?? '');
    } else {
      final s =
          RegExp(r'^(.+?)\s+(\d+)\s*[-–−]\s*(\d+)(?:\s*\([^)]*\))?\s+(.+?)\s*$')
              .firstMatch(line);
      if (s == null) throw FormatException('Maç satırı: $line');
      home = s[1]!.trim();
      away = s[4]!.trim();
      hg = int.parse(s[2]!);
      ag = int.parse(s[3]!);
    }
    games.add(Game(
        season: season,
        round: round,
        date: date,
        kickoff: time == null
            ? null
            : DateTime.parse('${date}T${time.padLeft(5, '0')}:00+03:00')
                .toUtc(),
        home: teams.resolve(home),
        away: teams.resolve(away),
        homeGoals: hg,
        awayGoals: ag));
  }
  if (games.map((g) => g.id).toSet().length != games.length) {
    throw FormatException('Tekrarlanan maç: $season');
  }
  if (games.isEmpty) throw FormatException('Boş fikstür: $season');
  return games;
}

String wikiDisplay(String value) => value
    .replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m[1]!.split('|').last)
    .trim();

Map<String, (int, int)> parseWikipedia(
    String source, String season, Teams teams) {
  final decoded = jsonDecode(source) as Json;
  final parse = decoded['parse'] as Json?;
  if (parse == null) {
    throw FormatException('Wikipedia API yanıtı: ${decoded['error']}');
  }
  final text = parse['wikitext'] as String;
  final heading =
      RegExp(r'^==\s*Results\s*==\s*$', multiLine: true, caseSensitive: false)
          .firstMatch(text);
  if (heading == null) throw const FormatException('Results bölümü yok');
  final end = RegExp(r'^==[^=].*==\s*$', multiLine: true)
      .firstMatch(text.substring(heading.end));
  final section = text.substring(
      heading.end, end == null ? text.length : heading.end + end.start);
  final start =
      RegExp(r'\{\{\s*#invoke:sports results\s*\|\s*main', caseSensitive: false)
          .firstMatch(section);
  if (start == null) throw const FormatException('sports results bloğu yok');
  var depth = 1, pos = start.end;
  while (pos < section.length - 1 && depth > 0) {
    final pair = section.substring(pos, pos + 2);
    if (pair == '{{') {
      depth++;
      pos += 2;
    } else if (pair == '}}') {
      depth--;
      pos += 2;
    } else {
      pos++;
    }
  }
  if (depth != 0) {
    throw const FormatException('Kapanmamış sports results bloğu');
  }
  final block = section.substring(start.end, pos - 2);
  final codes = <String, Team>{};
  for (final m
      in RegExp(r'^\s*\|\s*name_([^\s=]+)\s*=\s*(.+)$', multiLine: true)
          .allMatches(block)) {
    final team = teams.resolve(wikiDisplay(m[2]!));
    if (!team.wikiCodes.contains(m[1])) {
      throw FormatException('Wikipedia kodu eşleşmiyor: ${m[1]}');
    }
    codes[m[1]!] = team;
  }
  final scores = <String, (int, int)>{};
  for (final m in RegExp(r'^\s*\|\s*match_([^_\s=]+)_([^\s=]+)\s*=([^\n]*)',
          multiLine: true)
      .allMatches(block)) {
    final value = wikiDisplay(m[3]!);
    if (value.isEmpty) continue;
    final score =
        RegExp(r'^(\d+)\s*[-–−]\s*(\d+)(?:\s|$|\{)').firstMatch(value);
    if (score == null) throw FormatException('Wikipedia skoru: $value');
    final h = codes[m[1]], a = codes[m[2]];
    if (h == null || a == null) {
      throw FormatException('Bilinmeyen Wikipedia kodu: ${m[0]}');
    }
    final id = '$season-${h.id}-${a.id}';
    if (scores.containsKey(id)) {
      throw FormatException('Tekrarlanan Wikipedia skoru: $id');
    }
    scores[id] = (int.parse(score[1]!), int.parse(score[2]!));
  }
  if (codes.length != 18 || scores.length < 30) {
    throw FormatException(
        'Makul olmayan Wikipedia matrisi: ${codes.length} takım, ${scores.length} skor');
  }
  return scores;
}

List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[], row = <String>[];
  var field = '', quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field += '"';
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      row.add(field);
      field = '';
    } else if (c == '\n' && !quoted) {
      row.add(field.trim());
      if (row.any((v) => v.isNotEmpty)) rows.add(List.of(row));
      row.clear();
      field = '';
    } else if (c != '\r') {
      field += c;
    }
  }
  if (quoted) throw const FormatException('Kapanmamış CSV alanı');
  row.add(field.trim());
  if (row.any((v) => v.isNotEmpty)) rows.add(row);
  return rows;
}

List<Json> csvRecords(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return [];
  return rows.skip(1).map((row) {
    if (row.length != rows.first.length) {
      throw const FormatException('CSV sütun sayısı');
    }
    return <String, dynamic>{
      for (var i = 0; i < row.length; i++) rows.first[i]: row[i]
    };
  }).toList();
}

List<Game> mergeGames(List<Game> fixtures, Map<String, (int, int)> wiki,
    List<Json> overrides, List<String> warnings) {
  final ids = fixtures.map((g) => g.id).toSet();
  if (wiki.keys.any((id) => !ids.contains(id))) {
    throw const FormatException('Wikipedia fikstürde olmayan maç içeriyor');
  }
  final result = {for (final g in fixtures) g.id: g};
  for (final entry in wiki.entries) {
    final g = result[entry.key]!;
    final (h, a) = entry.value;
    if (g.finished && (g.homeGoals != h || g.awayGoals != a)) {
      warnings.add('Skor çelişkisi (${g.id}): Wikipedia tercih edildi.');
    }
    result[g.id] = g.copy(homeGoals: h, awayGoals: a);
  }
  for (final row in overrides) {
    final id = '${row['season']}-${row['homeId']}-${row['awayId']}';
    final g = result[id];
    if (g == null) throw FormatException('Düzeltme maçı bulunamadı: $id');
    String value(String k) => (row[k] as String? ?? '').trim();
    final hg = int.tryParse(value('homeGoals')),
        ag = int.tryParse(value('awayGoals'));
    if ((hg == null) != (ag == null)) {
      throw FormatException('Eksik düzeltme skoru: $id');
    }
    if ((value('homeGoals').isNotEmpty && hg == null) ||
        (value('awayGoals').isNotEmpty && ag == null)) {
      throw FormatException('Geçersiz düzeltme skoru: $id');
    }
    final status = value('status');
    if (status.isNotEmpty &&
        !['scheduled', 'postponed', 'finished'].contains(status)) {
      throw FormatException('Düzeltme durumu: $status');
    }
    if (hg != null && (hg < 0 || ag! < 0)) {
      throw const FormatException('Negatif gol');
    }
    if (hg != null && g.finished && (hg != g.homeGoals || ag != g.awayGoals)) {
      warnings.add('Skor çelişkisi ($id): elle düzeltme tercih edildi.');
    }
    var date = value('date');
    var kickoff = value('kickoff');
    final local = value('kickoffLocal');
    if (local.isNotEmpty) {
      final parsed =
          DateTime.tryParse('${local.replaceFirst(' ', 'T')}:00+03:00');
      if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(local) ||
          parsed == null ||
          parsed
                  .add(const Duration(hours: 3))
                  .toIso8601String()
                  .substring(0, 16) !=
              local.replaceFirst(' ', 'T') ||
          (date.isNotEmpty && date != local.substring(0, 10)) ||
          kickoff.isNotEmpty) {
        throw FormatException('Geçersiz/çakışan yerel başlangıç: $local');
      }
      date = local.substring(0, 10);
      kickoff = iso(parsed);
    }
    if (date.isNotEmpty &&
        (DateTime.tryParse(date) == null ||
            dateString(DateTime.parse(date)) != date)) {
      throw FormatException('Geçersiz düzeltme tarihi: $date');
    }
    if (kickoff.isNotEmpty &&
        kickoff != 'null' &&
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(kickoff)) {
      throw FormatException('Düzeltme saati zaman dilimi içermeli: $kickoff');
    }
    if (status == 'finished' && hg == null && !g.finished) {
      throw FormatException('Bitmiş maç düzeltmesinde skor yok: $id');
    }

    result[id] = g.copy(
        date: date.isEmpty ? null : date,
        kickoff: kickoff.isEmpty || kickoff == 'null'
            ? null
            : DateTime.parse(kickoff).toUtc(),
        clearKickoff: kickoff == 'null' || (date.isNotEmpty && kickoff.isEmpty),
        homeGoals: hg,
        awayGoals: ag,
        postponed: status.isEmpty ? null : status == 'postponed',
        clearScore: status == 'postponed' || status == 'scheduled');
  }
  return withRoundFreezeTimes(result.values)..sort(compareGames);
}
