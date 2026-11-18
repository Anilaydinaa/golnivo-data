import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'domain.dart';
import 'archive.dart';
import 'contract.dart';
import 'model.dart';
import 'parsers.dart';
import 'sources.dart';
import 'statistics.dart';

Map<String, int> pointAdjustments(String root, String season, Teams teams) {
  final file = File('$root/data/overrides/point_adjustments.csv');
  if (!file.existsSync()) return {};
  final result = <String, int>{};
  for (final r in csvRecords(file.readAsStringSync())
      .where((r) => r['season'] == season)) {
    final id = r['teamId'] as String;
    teams.resolve(id);
    result[id] = (result[id] ?? 0) + int.parse(r['points'] as String);
  }
  return result;
}

Json makePrediction(Game g, PoissonModel model, Json analysis,
    DateTime publishedAt, bool backfilled) {
  final d = model.predict(g), p = d.probabilities.map(rounded).toList();
  // Yuvarlama farkını en büyük sınıfa ver; toplam tam 1 olur.
  p[d.pick] = rounded(p[d.pick] + 1 - p.reduce((a, b) => a + b));
  return {
    'frozen': false,
    'backfilled': backfilled,
    'publishedAt': iso(publishedAt),
    'modelVersion': modelVersion,
    'expectedGoals': {
      'home': rounded(d.homeGoals),
      'away': rounded(d.awayGoals)
    },
    'probabilities': {'home': p[0], 'draw': p[1], 'away': p[2]},
    'pick': ['home', 'draw', 'away'][d.pick],
    'topScores': d.topScores,
    'goals3Plus': rounded(d.goals3Plus),
    'bothScore': rounded(d.bothScore),
    'confidence': model.confidence(g, d),
    'reasons': reasonsFor(g, analysis, d.homeGoals, d.awayGoals)
  };
}

void publishFiles(String root, Map<String, Json> files) {
  validatePublic(files);
  final dir = Directory('$root/public/v1'),
      stage = Directory('$root/public/.v1-stage'),
      backup = Directory('$root/public/.v1-backup');
  if (stage.existsSync()) stage.deleteSync(recursive: true);
  stage.createSync(recursive: true);
  for (final e in files.entries) {
    writeJson('${stage.path}/${e.key}', e.value);
  }
  // Serileştirilmiş dosyalar da aynı sözleşmeden geçer.
  validatePublic({
    for (final name in files.keys)
      name: jsonDecode(File('${stage.path}/$name').readAsStringSync()) as Json
  });
  if (backup.existsSync()) {
    throw StateError('Önceki yayın yedeği var: ${backup.path}');
  }
  final hadPrevious = dir.existsSync();
  if (hadPrevious) dir.renameSync(backup.path);
  try {
    stage.renameSync(dir.path);
  } catch (_) {
    if (hadPrevious) backup.renameSync(dir.path);
    rethrow;
  }
  if (hadPrevious) backup.deleteSync(recursive: true);
}

Future<Map<String, Json>> buildPublic(String root, DateTime now,
    {bool offline = false, http.Client? client}) async {
  final owned = client == null, connection = client ?? http.Client();
  try {
    final teams = Teams.read('$root/data/teams.json'),
        loader = SourceLoader(root, connection, offline: offline);
    final games = await loader.load(teams),
        current = games.where((g) => g.season == currentSeason).toList();
    final rawConfig =
        jsonDecode(File('$root/data/model.json').readAsStringSync()) as Json;
    final config = ModelConfig.fromJson(rawConfig['selected'] as Json);
    final archive = PredictionArchive('$root/data/archive', currentSeason),
        adjustments = pointAdjustments(root, currentSeason, teams);
    final predictions = <String, Json>{}, analyses = <String, Json>{};
    final models = <String, PoissonModel>{};
    PoissonModel modelAt(DateTime cutoff) => models.putIfAbsent(
        iso(cutoff), () => PoissonModel.fit(games, cutoff, config));
    Json analysisAt(Game g, DateTime cutoff) {
      final m = modelAt(cutoff);
      return analysisFor(g, games, cutoff, adjustments,
          homeCount: m.count(g.home.id), awayCount: m.count(g.away.id));
    }

    final future =
        current.where((g) => !g.finished && now.isBefore(g.freezeAt)).toList();
    final round = future.isEmpty
        ? current.map((g) => g.round).reduce((a, b) => a > b ? a : b)
        : future.map((g) => g.round).reduce((a, b) => a < b ? a : b);
    final shown = current
        .where((g) =>
            (g.round >= round && g.round < round + 2) ||
            (g.round >= round - 3 &&
                g.round < round &&
                (g.finished || !now.isBefore(g.freezeAt) || g.postponed)))
        .toList()
      ..sort(compareGames);
    // Geçmiş maçlar dondurulur; yalnız bu yayında gösterilen gelecek maçlar yayımlanmış sayılır.
    final shownIds = shown.map((g) => g.id).toSet();
    for (final g in current) {
      if (!g.finished && now.isBefore(g.freezeAt) && !shownIds.contains(g.id)) {
        continue;
      }
      predictions[g.id] = archive.resolve(g, now, (cutoff, backfilled) {
        final m = modelAt(cutoff), a = analysisAt(g, cutoff);
        return makePrediction(g, m, a, now, backfilled);
      });
    }
    final warnings = List<String>.of(loader.warnings);
    for (final g
        in current.where((g) => g.finished && !g.resultAt.isBefore(now))) {
      warnings.add('kaynak tarihi gerçek tarihten geç olabilir: ${g.id}');
    }
    final missing = current
        .where((g) => !g.finished && !now.isBefore(g.resultAt) && !g.postponed)
        .toList();
    if (missing.isNotEmpty) {
      warnings.add(
          '${missing.length} geçmiş tarihli maçın sonucu kaynaklarda yok; tarih/durum elle doğrulanmalı.');
    }
    warnings.add(
        'openfootball 2021-22 ve 2022-23 eğitim sezonları veri setinde yok.');
    final generatedAt = iso(now),
        history = current.where((g) => g.finished).toList(),
        currentTeams = <String, Team>{};
    for (final g in current) {
      currentTeams[g.home.id] = g.home;
      currentTeams[g.away.id] = g.away;
    }
    final rows = <Json>[];
    for (final g in shown) {
      final finished = g.finished;
      final p = predictions[g.id]!;
      final cutoff = !finished && now.isBefore(g.freezeAt) ? now : g.freezeAt;
      final a = analyses.putIfAbsent(g.id, () => analysisAt(g, cutoff));
      final outcome = finished ? outcomeFor(g, p) : null;
      outcome?.remove('brier');
      rows.add({
        'id': g.id,
        'round': g.round,
        'date': g.date,
        'kickoff': g.kickoff == null ? null : iso(g.kickoff!),
        'status': finished
            ? 'finished'
            : g.postponed || (!now.isBefore(g.resultAt) && !g.finished)
                ? 'postponed'
                : 'scheduled',
        'home': g.home.toJson(),
        'away': g.away.toJson(),
        'score': finished ? g.score : null,
        'prediction': p,
        'outcome': outcome,
        'analysis': a
      });
    }
    final files = <String, Json>{
      'meta.json': {
        'schemaVersion': 1,
        'generatedAt': generatedAt,
        'season': currentSeason,
        'competition': 'Süper Lig',
        'modelVersion': modelVersion,
        'currentRound': round,
        'warnings': warnings,
        'sources': [
          {
            'name': 'openfootball',
            'license': 'CC0 1.0',
            'url': 'https://github.com/openfootball/europe'
          },
          {
            'name': 'Wikipedia katkıcıları',
            'license': 'CC BY-SA 4.0',
            'url':
                'https://en.wikipedia.org/wiki/2026%E2%80%9327_S%C3%BCper_Lig'
          },
          {
            'name': 'Wikipedia katkıcıları (2025–26)',
            'license': 'CC BY-SA 4.0',
            'url':
                'https://en.wikipedia.org/wiki/2025%E2%80%9326_S%C3%BCper_Lig'
          }
        ]
      },
      'matches.json': {'generatedAt': generatedAt, 'matches': rows},
      'accuracy.json': accuracyFor(
          current.where((g) => g.finished).toList(), predictions, generatedAt),
      'standings.json': {
        'generatedAt': generatedAt,
        'rows': standings(
            history, currentTeams.values.toList(), currentSeason, adjustments),
        'note':
            'Sıralama bitmiş maç sonuçlarından hesaplanır; resmî tabloyla farklılık olabilir.'
      },
    };
    publishFiles(root, files);
    archive.save();
    return files;
  } finally {
    if (owned) connection.close();
  }
}
