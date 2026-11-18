import 'dart:math' as math;
import 'domain.dart';

class Totals {
  int played = 0, won = 0, drawn = 0, lost = 0, goalsFor = 0, goalsAgainst = 0;
  int get points => 3 * won + drawn;
  void add(int gf, int ga) {
    played++;
    goalsFor += gf;
    goalsAgainst += ga;
    if (gf > ga) {
      won++;
    } else if (gf == ga) {
      drawn++;
    } else {
      lost++;
    }
  }

  Json toJson({bool points = false}) => {
        'played': played,
        'won': won,
        'drawn': drawn,
        'lost': lost,
        'goalsFor': goalsFor,
        'goalsAgainst': goalsAgainst,
        if (points) 'points': this.points
      };
}

String resultFor(Game g, String id) {
  final r = g.home.id == id
      ? g.homeGoals!.compareTo(g.awayGoals!)
      : g.awayGoals!.compareTo(g.homeGoals!);
  return r > 0
      ? 'W'
      : r == 0
          ? 'D'
          : 'L';
}

List<Game> teamGames(List<Game> history, String id) =>
    history.where((g) => g.home.id == id || g.away.id == id).toList()
      ..sort((a, b) => compareGames(b, a));
List<Json> standings(List<Game> history, List<Team> teams, String season,
    Map<String, int> adjustments) {
  final games = history.where((g) => g.season == season).toList();
  final rows = <Json>[];
  for (final t in teams) {
    final totals = Totals();
    for (final g
        in games.where((g) => g.home.id == t.id || g.away.id == t.id)) {
      totals.add(g.home.id == t.id ? g.homeGoals! : g.awayGoals!,
          g.home.id == t.id ? g.awayGoals! : g.homeGoals!);
    }
    rows.add({
      'team': t.toJson(),
      ...totals.toJson(),
      'goalDiff': totals.goalsFor - totals.goalsAgainst,
      'points': totals.points + (adjustments[t.id] ?? 0),
      'pointAdjustment': adjustments[t.id] ?? 0,
      'form': teamGames(history, t.id)
          .where((g) => g.season == season)
          .take(5)
          .map((g) => resultFor(g, t.id))
          .toList()
    });
  }
  final groups = <int, List<Json>>{};
  for (final r in rows) {
    groups.putIfAbsent(r['points'] as int, () => []).add(r);
  }
  final mini = <String, Totals>{};
  for (final group in groups.values) {
    final ids = group.map((r) => (r['team'] as Json)['id'] as String).toSet();
    for (final id in ids) {
      mini[id] = Totals();
    }
    for (final g in games
        .where((g) => ids.contains(g.home.id) && ids.contains(g.away.id))) {
      mini[g.home.id]!.add(g.homeGoals!, g.awayGoals!);
      mini[g.away.id]!.add(g.awayGoals!, g.homeGoals!);
    }
  }
  rows.sort((a, b) {
    int descending(String key) => (b[key] as int).compareTo(a[key] as int);
    var c = descending('points');
    if (c != 0) return c;
    final ma = mini[(a['team'] as Json)['id']]!,
        mb = mini[(b['team'] as Json)['id']]!;
    c = mb.points.compareTo(ma.points);
    if (c != 0) return c;
    c = (mb.goalsFor - mb.goalsAgainst)
        .compareTo(ma.goalsFor - ma.goalsAgainst);
    if (c != 0) return c;
    c = descending('goalDiff');
    if (c != 0) return c;
    c = descending('goalsFor');
    if (c != 0) return c;
    // Türkçe alfabetik sıra; sistem yerel ayarından bağımsız.
    String key(String s) {
      const alphabet = 'abcçdefgğhıijklmnoöprsştuüvyz';
      return s
          .toLowerCase()
          .split('')
          .map((c) => (alphabet.indexOf(c) + 1).toString().padLeft(2, '0'))
          .join();
    }

    return key((a['team'] as Json)['name'] as String)
        .compareTo(key((b['team'] as Json)['name'] as String));
  });
  for (var i = 0; i < rows.length; i++) {
    rows[i]['position'] = i + 1;
  }
  return rows;
}

Json teamAnalysis(Team team, String venue, List<Game> history, String season,
    List<Json> table) {
  final all = teamGames(history, team.id),
      current = all.where((g) => g.season == season).toList();
  final totals = Totals(), venueTotals = Totals();
  var clean = 0, failed = 0, g3 = 0, both = 0;
  for (final g in current) {
    final gf = g.home.id == team.id ? g.homeGoals! : g.awayGoals!,
        ga = g.home.id == team.id ? g.awayGoals! : g.homeGoals!;
    totals.add(gf, ga);
    if ((venue == 'home') == (g.home.id == team.id)) venueTotals.add(gf, ga);
    if (ga == 0) clean++;
    if (gf == 0) failed++;
    if (gf + ga >= 3) g3++;
    if (gf > 0 && ga > 0) both++;
  }
  double rate(num v) => totals.played == 0 ? 0 : rounded(v / totals.played);
  return {
    'team': team.toJson(),
    'position': table
        .firstWhere((r) => (r['team'] as Json)['id'] == team.id)['position'],
    'form': all.take(5).map((g) => resultFor(g, team.id)).toList(),
    'season': totals.toJson(points: true),
    'venue': {'label': venue, ...venueTotals.toJson()},
    'avgGoalsFor': rate(totals.goalsFor),
    'avgGoalsAgainst': rate(totals.goalsAgainst),
    'cleanSheets': clean,
    'failedToScore': failed,
    'goals3PlusRate': rate(g3),
    'bothScoreRate': rate(both),
    'recent': all.take(5).map((g) {
      final home = g.home.id == team.id;
      return {
        'date': g.date,
        'opponent': (home ? g.away : g.home).toJson(),
        'venue': home ? 'H' : 'A',
        'goalsFor': home ? g.homeGoals : g.awayGoals,
        'goalsAgainst': home ? g.awayGoals : g.homeGoals,
        'result': resultFor(g, team.id)
      };
    }).toList()
  };
}

Json analysisFor(
    Game game, List<Game> all, DateTime cutoff, Map<String, int> adjustments,
    {required int homeCount, required int awayCount}) {
  final history = before(all, cutoff), seasonTeams = <String, Team>{};
  for (final g in all.where((g) => g.season == game.season)) {
    seasonTeams[g.home.id] = g.home;
    seasonTeams[g.away.id] = g.away;
  }
  final table =
      standings(history, seasonTeams.values.toList(), game.season, adjustments);
  final h2h = history
      .where((g) =>
          (g.home.id == game.home.id && g.away.id == game.away.id) ||
          (g.home.id == game.away.id && g.away.id == game.home.id))
      .toList()
    ..sort((a, b) => compareGames(b, a));
  var wins = 0, draws = 0, losses = 0, hg = 0, ag = 0;
  for (final g in h2h) {
    final h = g.home.id == game.home.id ? g.homeGoals! : g.awayGoals!,
        a = g.home.id == game.home.id ? g.awayGoals! : g.homeGoals!;
    hg += h;
    ag += a;
    if (h > a) {
      wins++;
    } else if (h == a) {
      draws++;
    } else {
      losses++;
    }
  }
  final limited = [
    if (homeCount < 12) game.home.name,
    if (awayCount < 12) game.away.name
  ];
  return {
    'home': teamAnalysis(game.home, 'home', history, game.season, table),
    'away': teamAnalysis(game.away, 'away', history, game.season, table),
    'h2h': {
      'played': h2h.length,
      'homeWins': wins,
      'draws': draws,
      'awayWins': losses,
      'goalsHome': hg,
      'goalsAway': ag,
      'matches': h2h
          .take(6)
          .map((g) => {
                'date': g.date,
                'season': g.season,
                'home': g.home.toJson(),
                'away': g.away.toJson(),
                'score': g.score
              })
          .toList()
    },
    'dataQuality': {
      'homeMatches': homeCount,
      'awayMatches': awayCount,
      'note': limited.isEmpty
          ? null
          : '${limited.join(', ')}: Süper Lig verisi sınırlı.'
    }
  };
}

List<String> reasonsFor(
    Game game, Json analysis, double homeGoals, double awayGoals) {
  final home = analysis['home'] as Json,
      away = analysis['away'] as Json,
      h2h = analysis['h2h'] as Json;
  final candidates = <(double, String)>[];
  int formPoints(Json t) => (t['form'] as List<dynamic>).fold<int>(
      0,
      (s, r) =>
          s +
          (r == 'W'
              ? 3
              : r == 'D'
                  ? 1
                  : 0));
  final hp = formPoints(home), ap = formPoints(away);
  candidates.add((
    (hp - ap).abs() / 15,
    'Son 5 maç: ${game.home.name} $hp puan, ${game.away.name} $ap puan.'
  ));
  for (final pair in [
    (game.home, home, 'iç saha'),
    (game.away, away, 'deplasman')
  ]) {
    final v = pair.$2['venue'] as Json, n = v['played'] as int;
    if (n > 0) {
      candidates.add((
        ((v['goalsFor'] as int) - (v['goalsAgainst'] as int)).abs() / (n * 3),
        '${pair.$1.name}: bu sezon $n ${pair.$3} maçında ${v['goalsFor']} gol attı, ${v['goalsAgainst']} gol yedi.'
      ));
    }
  }
  if (((home['season'] as Json)['played'] as int) > 0 &&
      ((away['season'] as Json)['played'] as int) > 0) {
    candidates.add((
      ((home['position'] as int) - (away['position'] as int)).abs() / 18,
      'Sezon sıralaması: ${game.home.name} ${home['position']}, ${game.away.name} ${away['position']}.'
    ));
  }
  if ((h2h['played'] as int) >= 3) {
    candidates.add((
      ((h2h['homeWins'] as int) - (h2h['awayWins'] as int)).abs() /
          (h2h['played'] as int),
      'Aralarındaki ${h2h['played']} maç: ${h2h['homeWins']} ${game.home.name} galibiyeti, ${h2h['draws']} beraberlik, ${h2h['awayWins']} ${game.away.name} galibiyeti.'
    ));
  }
  candidates.add((
    0.35 + (homeGoals - awayGoals).abs() / 4,
    'Beklenen gol: ${game.home.name} ${homeGoals.toStringAsFixed(2).replaceAll('.', ',')}, ${game.away.name} ${awayGoals.toStringAsFixed(2).replaceAll('.', ',')}.'
  ));
  candidates.sort((a, b) => b.$1.compareTo(a.$1));
  return candidates.take(3).map((c) => c.$2).toList();
}

Json outcomeFor(Game g, Json p) {
  final probs = p['probabilities'] as Json;
  return {
    'pickHit': p['pick'] == ['home', 'draw', 'away'][g.result],
    'goals3PlusHit':
        ((p['goals3Plus'] as num) >= 0.5) == (g.homeGoals! + g.awayGoals! >= 3),
    'bothScoreHit': ((p['bothScore'] as num) >= 0.5) ==
        (g.homeGoals! > 0 && g.awayGoals! > 0),
    'brier': List.generate(3, (i) {
      final v = (probs[['home', 'draw', 'away'][i]] as num).toDouble() -
          (g.result == i ? 1 : 0);
      return v * v;
    }).reduce((a, b) => a + b)
  };
}

Json accuracyFor(
    List<Game> games, Map<String, Json> predictions, String generatedAt) {
  final evaluated =
      games.where((g) => g.finished && predictions.containsKey(g.id)).toList();
  Json aggregate(Iterable<Game> subset, {bool season = false}) {
    var n = 0, hits = 0, g3 = 0, both = 0, live = 0, liveHits = 0;
    double brier = 0;
    for (final g in subset) {
      final p = predictions[g.id]!, o = outcomeFor(g, p);
      n++;
      if (o['pickHit'] as bool) hits++;
      if (o['goals3PlusHit'] as bool) g3++;
      if (o['bothScoreHit'] as bool) both++;
      brier += o['brier'] as double;
      if (p['backfilled'] == false && p['frozen'] == true) {
        live++;
        if (o['pickHit'] as bool) liveHits++;
      }
    }
    return {
      'evaluated': n,
      'pickHits': hits,
      if (season) 'pickRate': n == 0 ? 0.0 : rounded(hits / n),
      'goals3PlusHits': g3,
      'bothScoreHits': both,
      if (season) 'brier': n == 0 ? 0.0 : rounded(brier / n),
      if (season) 'liveEvaluated': live,
      if (season) 'livePickHits': liveHits
    };
  }

  final dates = evaluated.map((g) => g.date).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  final rounds = evaluated.map((g) => g.round).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  final days = dates
      .map(
          (d) => {'date': d, ...aggregate(evaluated.where((g) => g.date == d))})
      .toList();
  return {
    'generatedAt': generatedAt,
    'season': aggregate(evaluated, season: true),
    'lastMatchDay': days.isEmpty ? null : days.first,
    'byDay': days,
    'byRound': rounds
        .map((r) =>
            {'round': r, ...aggregate(evaluated.where((g) => g.round == r))})
        .toList()
  };
}

class Metrics {
  int n = 0, hits = 0, goalsHits = 0, bothHits = 0;
  double logLoss = 0, brier = 0;
  final bins = List.generate(
      10, (_) => <String, num>{'count': 0, 'sum': 0.0, 'hits': 0});
  void add(int outcome, List<double> p, {bool? goalsHit, bool? bothHit}) {
    n++;
    if (p.indexOf(p.reduce(math.max)) == outcome) hits++;
    logLoss -= math.log(p[outcome].clamp(1e-15, 1));
    for (var i = 0; i < 3; i++) {
      final d = p[i] - (outcome == i ? 1 : 0);
      brier += d * d;
      final bin = bins[math.min(9, (p[i] * 10).floor())];
      bin['count'] = bin['count']! + 1;
      bin['sum'] = bin['sum']! + p[i];
      bin['hits'] = bin['hits']! + (outcome == i ? 1 : 0);
    }
    if (goalsHit == true) goalsHits++;
    if (bothHit == true) bothHits++;
  }

  Json toJson() => {
        'evaluated': n,
        'pickHits': hits,
        'pickRate': n == 0 ? 0 : rounded(hits / n),
        'logLoss': n == 0 ? 0 : rounded(logLoss / n),
        'brier': n == 0 ? 0 : rounded(brier / n),
        'goals3PlusRate': n == 0 ? 0 : rounded(goalsHits / n),
        'bothScoreRate': n == 0 ? 0 : rounded(bothHits / n),
        'calibration': List.generate(10, (i) {
          final b = bins[i], count = b['count']!.toInt();
          return {
            'bucket':
                '${(i / 10).toStringAsFixed(1)}–${((i + 1) / 10).toStringAsFixed(1)}',
            'count': count,
            'meanProbability': count == 0 ? null : rounded(b['sum']! / count),
            'observedRate': count == 0 ? null : rounded(b['hits']! / count)
          };
        })
      };
}
