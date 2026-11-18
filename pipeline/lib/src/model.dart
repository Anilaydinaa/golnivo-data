import 'dart:math' as math;
import 'domain.dart';

class ModelConfig {
  final double xi, regularization;
  const ModelConfig({required this.xi, required this.regularization});
  Json toJson() => {'xi': xi, 'regularization': regularization};
  factory ModelConfig.fromJson(Json j) => ModelConfig(
      xi: (j['xi'] as num).toDouble(),
      regularization: (j['regularization'] as num).toDouble());
}

class Distribution {
  final double homeGoals, awayGoals;
  final List<double> probabilities;
  final List<Json> topScores;
  final double goals3Plus, bothScore;
  Distribution(this.homeGoals, this.awayGoals, this.probabilities,
      this.topScores, this.goals3Plus, this.bothScore);
  int get pick => probabilities.indexOf(probabilities.reduce(math.max));
}

Distribution poisson(double home, double away) {
  List<double> pmf(double lambda) {
    final p = List<double>.filled(11, 0);
    p[0] = math.exp(-lambda);
    for (var i = 1; i <= 10; i++) {
      p[i] = p[i - 1] * lambda / i;
    }
    return p;
  }

  final h = pmf(home),
      a = pmf(away),
      p = List<double>.filled(3, 0),
      scores = <Json>[];
  double total = 0, g3 = 0, both = 0;
  for (var i = 0; i <= 10; i++) {
    for (var j = 0; j <= 10; j++) {
      final v = h[i] * a[j];
      total += v;
      p[i > j ? 0 : (i == j ? 1 : 2)] += v;
      if (i + j >= 3) g3 += v;
      if (i > 0 && j > 0) both += v;
      scores.add({'home': i, 'away': j, 'p': v});
    }
  }
  scores.sort((a, b) {
    final c = (b['p'] as double).compareTo(a['p'] as double);
    if (c != 0) return c;
    final d = (a['home'] as int).compareTo(b['home'] as int);
    return d != 0 ? d : (a['away'] as int).compareTo(b['away'] as int);
  });
  return Distribution(
      home,
      away,
      p.map((v) => v / total).toList(),
      scores
          .take(3)
          .map((s) => {...s, 'p': rounded((s['p'] as double) / total)})
          .toList(),
      g3 / total,
      both / total);
}

class _Observation {
  final int attack, defense;
  final bool home;
  final double weight;
  final int goals;
  _Observation(this.attack, this.defense, this.home, this.weight, this.goals);
}

class PoissonModel {
  final ModelConfig config;
  final Map<String, int> indexes;
  final List<double> parameters, effective;
  final List<int> counts;
  final (double, double) promotedPrior;
  final Set<String> promoted;
  final bool converged;
  final int iterations;
  final double gradientNorm;
  PoissonModel._(
      this.config,
      this.indexes,
      this.parameters,
      this.effective,
      this.counts,
      this.promotedPrior,
      this.promoted,
      this.converged,
      this.iterations,
      this.gradientNorm);
  static List<Game> training(Iterable<Game> games, DateTime cutoff) {
    final seasonYear = cutoff.month >= 7 ? cutoff.year : cutoff.year - 1;
    return before(games, cutoff)
        .where((g) => int.parse(g.season.substring(0, 4)) >= seasonYear - 3)
        .toList();
  }

  static PoissonModel fit(List<Game> all, DateTime cutoff, ModelConfig config,
      {int maxIterations = 600, double tolerance = 0.0001}) {
    final games = training(all, cutoff);
    if (games.isEmpty) throw StateError('Eğitim verisi yok: ${iso(cutoff)}');
    final ids = games.expand((g) => [g.home.id, g.away.id]).toSet().toList()
      ..sort();
    final indexes = {for (var i = 0; i < ids.length; i++) ids[i]: i},
        n = ids.length;
    final observations = <_Observation>[],
        counts = List<int>.filled(n, 0),
        effective = List<double>.filled(n, 0);
    double homeSum = 0, awaySum = 0, weightSum = 0;
    for (final g in games) {
      final w =
              math.exp(-config.xi * cutoff.difference(g.resultAt).inHours / 24),
          h = indexes[g.home.id]!,
          a = indexes[g.away.id]!;
      observations.add(_Observation(h, a, true, w, g.homeGoals!));
      observations.add(_Observation(a, h, false, w, g.awayGoals!));
      counts[h]++;
      counts[a]++;
      effective[h] += w;
      effective[a] += w;
      homeSum += w * g.homeGoals!;
      awaySum += w * g.awayGoals!;
      weightSum += w;
    }
    // Yalnız eğitim kesiminden önce tamamlanan ilk sezonlardan ampirik önsel.
    final bySeason = <String, List<Game>>{};
    for (final g in before(all, cutoff)) {
      bySeason.putIfAbsent(g.season, () => []).add(g);
    }
    final currentYear = cutoff.month >= 7 ? cutoff.year : cutoff.year - 1;
    double priorAttack = 0, priorDefense = 0;
    var priorN = 0;
    final promoted = <String>{};
    final currentSeasonName =
        '$currentYear-${((currentYear + 1) % 100).toString().padLeft(2, '0')}';
    final previousSeasonName =
        '${currentYear - 1}-${(currentYear % 100).toString().padLeft(2, '0')}';
    final prevIds = (bySeason[previousSeasonName] ?? [])
        .expand((g) => [g.home.id, g.away.id])
        .toSet();
    final currentIds = all
        .where((g) => g.season == currentSeasonName)
        .expand((g) => [g.home.id, g.away.id])
        .toSet();
    if (prevIds.isNotEmpty) promoted.addAll(currentIds.difference(prevIds));
    for (final entry in bySeason.entries) {
      final y = int.parse(entry.key.substring(0, 4));
      if (y >= currentYear) continue;
      final previous =
          bySeason['${y - 1}-${(y % 100).toString().padLeft(2, '0')}'];
      if (previous == null) continue;
      final previousTeams =
          previous.expand((g) => [g.home.id, g.away.id]).toSet();
      final firstTeams = entry.value
          .expand((g) => [g.home.id, g.away.id])
          .toSet()
          .difference(previousTeams);
      final leagueGoals = entry.value
              .fold<double>(0, (s, g) => s + g.homeGoals! + g.awayGoals!) /
          (2 * entry.value.length);
      for (final id in firstTeams) {
        final first = entry.value
            .where((g) => g.home.id == id || g.away.id == id)
            .toList();
        if (first.length < 20) continue;
        final gf = first.fold<int>(
            0, (s, g) => s + (g.home.id == id ? g.homeGoals! : g.awayGoals!));
        final ga = first.fold<int>(
            0, (s, g) => s + (g.home.id == id ? g.awayGoals! : g.homeGoals!));
        priorAttack += math
            .log((gf + 2 * leagueGoals) / ((first.length + 2) * leagueGoals));
        priorDefense -= math
            .log((ga + 2 * leagueGoals) / ((first.length + 2) * leagueGoals));
        priorN++;
      }
    }
    final prior = (
      priorN == 0 ? 0.0 : priorAttack / priorN,
      priorN == 0 ? 0.0 : priorDefense / priorN
    );
    final target = List<double>.filled(2 + 2 * n, 0);
    for (final id in promoted) {
      final i = indexes[id];
      if (i != null) {
        target[2 + i] = prior.$1;
        target[2 + n + i] = prior.$2;
      }
    }
    var x = List<double>.of(target);
    x[0] = math.log((awaySum + 1) / (weightSum + 1));
    x[1] = math.log((homeSum + 1) / (awaySum + 1));
    (double, List<double>) evaluate(List<double> v) {
      double loss = 0;
      final grad = List<double>.filled(v.length, 0);
      for (final o in observations) {
        final ai = 2 + o.attack, di = 2 + n + o.defense;
        final eta = v[0] + (o.home ? v[1] : 0) + v[ai] - v[di];
        if (eta > 30 || eta < -30) return (double.infinity, grad);
        final lambda = math.exp(eta), d = o.weight * (lambda - o.goals);
        loss += o.weight * (lambda - o.goals * eta);
        grad[0] += d;
        if (o.home) grad[1] += d;
        grad[ai] += d;
        grad[di] -= d;
      }
      for (var i = 2; i < v.length; i++) {
        final d = v[i] - target[i];
        loss += 0.5 * config.regularization * d * d;
        grad[i] += config.regularization * d;
      }
      return (loss, grad);
    }

    double dot(List<double> a, List<double> b) {
      double s = 0;
      for (var i = 0; i < a.length; i++) {
        s += a[i] * b[i];
      }
      return s;
    }

    var (loss, grad) = evaluate(x);
    final ss = <List<double>>[], ys = <List<double>>[], rhos = <double>[];
    var iteration = 0;
    double norm = double.infinity;
    for (; iteration < maxIterations; iteration++) {
      norm = grad.map((v) => v.abs()).reduce(math.max);
      if (norm < tolerance) break;
      final q = List<double>.of(grad),
          alpha = List<double>.filled(ss.length, 0);
      for (var k = ss.length - 1; k >= 0; k--) {
        alpha[k] = rhos[k] * dot(ss[k], q);
        for (var i = 0; i < q.length; i++) {
          q[i] -= alpha[k] * ys[k][i];
        }
      }
      final scale = ss.isEmpty
          ? 1 / weightSum
          : dot(ss.last, ys.last) / dot(ys.last, ys.last);
      final direction = q.map((v) => v * scale).toList();
      for (var k = 0; k < ss.length; k++) {
        final beta = rhos[k] * dot(ys[k], direction);
        for (var i = 0; i < q.length; i++) {
          direction[i] += ss[k][i] * (alpha[k] - beta);
        }
      }
      for (var i = 0; i < direction.length; i++) {
        direction[i] = -direction[i];
      }
      var slope = dot(grad, direction);
      if (slope >= 0) {
        for (var i = 0; i < direction.length; i++) {
          direction[i] = -grad[i] / weightSum;
        }
        slope = dot(grad, direction);
        ss.clear();
        ys.clear();
        rhos.clear();
      }
      var step = 1.0;
      List<double> next;
      double nextLoss;
      List<double> nextGrad;
      while (true) {
        next = List.generate(x.length, (i) => x[i] + step * direction[i]);
        (nextLoss, nextGrad) = evaluate(next);
        if (nextLoss <= loss + 0.0001 * step * slope) break;
        step *= 0.5;
        if (step < 1e-12) break;
      }
      final s = List.generate(x.length, (i) => next[i] - x[i]),
          y = List.generate(x.length, (i) => nextGrad[i] - grad[i]),
          sy = dot(s, y);
      if (sy > 1e-12) {
        if (ss.length == 10) {
          ss.removeAt(0);
          ys.removeAt(0);
          rhos.removeAt(0);
        }
        ss.add(s);
        ys.add(y);
        rhos.add(1 / sy);
      }
      x = next;
      loss = nextLoss;
      grad = nextGrad;
    }
    norm = grad.map((v) => v.abs()).reduce(math.max);
    if (norm >= tolerance) {
      throw StateError(
          'Model yakınsamadı: ${iso(cutoff)}, $iteration adım, gradyan=$norm');
    }
    return PoissonModel._(config, indexes, x, effective, counts, prior,
        promoted, true, iteration, norm);
  }

  int count(String id) => indexes.containsKey(id) ? counts[indexes[id]!] : 0;
  double effectiveCount(String id) =>
      indexes.containsKey(id) ? effective[indexes[id]!] : 0;
  Distribution predict(Game game) {
    double att(String id) {
      final i = indexes[id];
      return i == null
          ? (promoted.contains(id) ? promotedPrior.$1 : 0)
          : parameters[2 + i];
    }

    double def(String id) {
      final i = indexes[id];
      return i == null
          ? (promoted.contains(id) ? promotedPrior.$2 : 0)
          : parameters[2 + indexes.length + i];
    }

    return poisson(
        math.exp(parameters[0] +
            parameters[1] +
            att(game.home.id) -
            def(game.away.id)),
        math.exp(parameters[0] + att(game.away.id) - def(game.home.id)));
  }

  String confidence(Game g, Distribution d) {
    final maxP = d.probabilities.reduce(math.max);
    if (maxP < 0.42 || count(g.home.id) < 6 || count(g.away.id) < 6) {
      return 'low';
    }
    if (maxP >= 0.55 &&
        effectiveCount(g.home.id) >= 12 &&
        effectiveCount(g.away.id) >= 12) {
      return 'high';
    }
    return 'medium';
  }
}
