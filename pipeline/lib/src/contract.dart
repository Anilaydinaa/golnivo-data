import 'domain.dart';

Never _fail(String message) =>
    throw FormatException('JSON sözleşmesi: $message');
Json _object(dynamic value, String label) =>
    value is Json ? value : _fail('$label nesne değil');
List<dynamic> _list(dynamic value, String label) =>
    value is List<dynamic> ? value : _fail('$label dizi değil');
void _keys(Json j, List<String> fields) {
  for (final k in fields) {
    if (!j.containsKey(k)) _fail('$k eksik');
  }
}

void _string(dynamic v, String key) {
  if (v is! String || v.isEmpty) _fail('$key metin değil');
}

void _int(dynamic v, String key, {bool signed = false}) {
  if (v is! int || (!signed && v < 0)) _fail('$key tam sayı değil');
}

void _boolean(dynamic v, String key) {
  if (v is! bool) _fail('$key bool değil');
}

void _utc(dynamic v, String key) {
  if (v is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$')
          .hasMatch(v) ||
      DateTime.tryParse(v) == null) {
    _fail('$key UTC değil');
  }
}

void _date(dynamic v) {
  if (v is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
      DateTime.tryParse(v) == null) {
    _fail('Yerel tarih');
  }
}

void _number(dynamic v, String key) {
  if (v is! num || !v.isFinite) _fail('$key sonlu sayı değil');
}

void _prob(dynamic v, String key) {
  _number(v, key);
  if ((v as num) < 0 ||
      v > 1 ||
      (v * 10000 - (v * 10000).round()).abs() > 1e-7) {
    _fail('$key olasılık veya hassasiyet');
  }
}

void _team(dynamic v) {
  final j = _object(v, 'team');
  _string(j['id'], 'team.id');
  _string(j['name'], 'team.name');
}

void _score(dynamic v) {
  final j = _object(v, 'score');
  _int(j['home'], 'score.home');
  _int(j['away'], 'score.away');
}

void _form(dynamic v) {
  final l = _list(v, 'form');
  if (l.length > 5 || l.any((v) => !['W', 'D', 'L'].contains(v))) _fail('form');
}

void _totals(dynamic v, {bool points = false}) {
  final j = _object(v, 'totals');
  for (final k in [
    'played',
    'won',
    'drawn',
    'lost',
    'goalsFor',
    'goalsAgainst'
  ]) {
    _int(j[k], k);
  }
  if (j['played'] !=
      (j['won'] as int) + (j['drawn'] as int) + (j['lost'] as int)) {
    _fail('O-G-B-M toplamı');
  }
  if (points) {
    _int(j['points'], 'points');
    if (j['points'] != 3 * (j['won'] as int) + (j['drawn'] as int)) {
      _fail('Sezon puanları');
    }
  }
}

void validatePrediction(dynamic value) {
  final p = _object(value, 'prediction');
  _keys(p, [
    'frozen',
    'backfilled',
    'publishedAt',
    'modelVersion',
    'expectedGoals',
    'probabilities',
    'pick',
    'topScores',
    'goals3Plus',
    'bothScore',
    'confidence',
    'reasons'
  ]);
  _boolean(p['frozen'], 'frozen');
  _boolean(p['backfilled'], 'backfilled');
  _utc(p['publishedAt'], 'publishedAt');
  if (p['modelVersion'] != modelVersion) _fail('modelVersion');
  final e = _object(p['expectedGoals'], 'expectedGoals');
  for (final k in ['home', 'away']) {
    _number(e[k], k);
    if ((e[k] as num) < 0) _fail('Negatif beklenen gol');
  }
  final probs = _object(p['probabilities'], 'probabilities');
  double sum = 0;
  for (final k in ['home', 'draw', 'away']) {
    _prob(probs[k], k);
    sum += (probs[k] as num).toDouble();
  }
  if ((sum - 1).abs() > 0.00011) _fail('1X2 toplamı');
  if (!['home', 'draw', 'away'].contains(p['pick'])) _fail('pick');
  final pickValue = probs[p['pick']] as num;
  if (probs.values.any((v) => (v as num) > pickValue + 0.0001)) {
    _fail('pick en büyük olasılık değil');
  }
  final scores = _list(p['topScores'], 'topScores');
  if (scores.length != 3) _fail('Üç skor gerekli');
  double prev = 1;
  final seen = <String>{};
  for (final s in scores) {
    _score(s);
    final j = s as Json;
    _prob(j['p'], 'topScore.p');
    if ((j['home'] as int) > 10 ||
        (j['away'] as int) > 10 ||
        (j['p'] as num) > prev) {
      _fail('Skor matrisi sırası');
    }
    prev = (j['p'] as num).toDouble();
    if (!seen.add('${j['home']}-${j['away']}')) _fail('Tekrarlanan skor');
  }
  _prob(p['goals3Plus'], 'goals3Plus');
  _prob(p['bothScore'], 'bothScore');
  if (!['low', 'medium', 'high'].contains(p['confidence'])) _fail('confidence');
  final reasons = _list(p['reasons'], 'reasons');
  if (reasons.isEmpty || reasons.length > 3) _fail('reasons sayısı');
  for (final r in reasons) {
    _string(r, 'reason');
  }
}

void _analysis(dynamic value) {
  final a = _object(value, 'analysis');
  for (final side in ['home', 'away']) {
    final t = _object(a[side], side);
    _team(t['team']);
    _int(t['position'], 'position');
    _form(t['form']);
    _totals(t['season'], points: true);
    _totals(t['venue']);
    if (_object(t['venue'], 'venue')['label'] != side) _fail('venue.label');
    for (final k in ['avgGoalsFor', 'avgGoalsAgainst']) {
      _number(t[k], k);
      if ((t[k] as num) < 0) _fail(k);
    }
    for (final k in ['cleanSheets', 'failedToScore']) {
      _int(t[k], k);
    }
    for (final k in ['goals3PlusRate', 'bothScoreRate']) {
      _prob(t[k], k);
    }
    final recent = _list(t['recent'], 'recent');
    if (recent.length > 5) _fail('recent sayısı');
    for (final item in recent) {
      final r = _object(item, 'recent');
      _date(r['date']);
      _team(r['opponent']);
      if (!['H', 'A'].contains(r['venue'])) _fail('recent.venue');
      _int(r['goalsFor'], 'goalsFor');
      _int(r['goalsAgainst'], 'goalsAgainst');
      if (!['W', 'D', 'L'].contains(r['result'])) _fail('recent.result');
    }
  }
  final h = _object(a['h2h'], 'h2h');
  for (final k in [
    'played',
    'homeWins',
    'draws',
    'awayWins',
    'goalsHome',
    'goalsAway'
  ]) {
    _int(h[k], k);
  }
  if (h['played'] !=
      (h['homeWins'] as int) + (h['draws'] as int) + (h['awayWins'] as int)) {
    _fail('H2H toplamı');
  }
  final matches = _list(h['matches'], 'h2h.matches');
  if (matches.length > 6) _fail('H2H maç sayısı');
  for (final item in matches) {
    final g = _object(item, 'h2h.game');
    _date(g['date']);
    _string(g['season'], 'season');
    _team(g['home']);
    _team(g['away']);
    _score(g['score']);
  }
  final q = _object(a['dataQuality'], 'dataQuality');
  _int(q['homeMatches'], 'homeMatches');
  _int(q['awayMatches'], 'awayMatches');
  if (!q.containsKey('note')) _fail('dataQuality.note');
  if (q['note'] != null) _string(q['note'], 'note');
}

void _accuracyCounts(dynamic value) {
  final j = _object(value, 'accuracy');
  for (final k in [
    'evaluated',
    'pickHits',
    'goals3PlusHits',
    'bothScoreHits'
  ]) {
    _int(j[k], k);
    if ((j[k] as int) > (j['evaluated'] as int)) _fail('İsabet sayısı');
  }
}

void validatePublic(Map<String, Json> files) {
  final meta = files['meta.json'] ?? _fail('meta.json yok');
  _keys(meta, [
    'schemaVersion',
    'generatedAt',
    'season',
    'competition',
    'modelVersion',
    'currentRound',
    'warnings',
    'sources'
  ]);
  if (meta['schemaVersion'] != 1 ||
      meta['season'] != currentSeason ||
      meta['competition'] != 'Süper Lig' ||
      meta['modelVersion'] != modelVersion) {
    _fail('meta sürüm/sezon');
  }
  _int(meta['currentRound'], 'currentRound');
  _utc(meta['generatedAt'], 'generatedAt');
  for (final w in _list(meta['warnings'], 'warnings')) {
    _string(w, 'warning');
  }
  final sources = _list(meta['sources'], 'sources');
  if (sources.length < 2) _fail('sources');
  for (final s in sources) {
    final j = _object(s, 'source');
    for (final k in ['name', 'license', 'url']) {
      _string(j[k], k);
    }
  }
  for (final name in ['matches.json', 'accuracy.json', 'standings.json']) {
    final j = files[name] ?? _fail('$name yok');
    if (j['generatedAt'] != meta['generatedAt']) _fail('generatedAt tutarsız');
  }
  final ids = <String>{};
  for (final value in _list(files['matches.json']!['matches'], 'matches')) {
    final g = _object(value, 'match');
    _keys(g, [
      'id',
      'round',
      'date',
      'kickoff',
      'status',
      'home',
      'away',
      'score',
      'prediction',
      'outcome',
      'analysis'
    ]);
    _string(g['id'], 'id');
    if (!ids.add(g['id'] as String)) _fail('Tekrarlanan maç');
    _int(g['round'], 'round');
    _date(g['date']);
    if (g['kickoff'] != null) {
      _utc(g['kickoff'], 'kickoff');
      if (dateString(DateTime.parse(g['kickoff'] as String)
              .add(const Duration(hours: 3))) !=
          g['date']) {
        _fail('kickoff/date');
      }
    }
    _team(g['home']);
    _team(g['away']);
    if (!['scheduled', 'finished', 'postponed'].contains(g['status'])) {
      _fail('status');
    }
    if (g['status'] == 'finished') {
      _score(g['score']);
    } else if (g['score'] != null) {
      _fail('Bitmemiş maç skoru');
    }
    if (g['prediction'] != null) validatePrediction(g['prediction']);
    if (g['status'] == 'finished' && g['prediction'] != null) {
      final o = _object(g['outcome'], 'outcome');
      for (final k in ['pickHit', 'goals3PlusHit', 'bothScoreHit']) {
        _boolean(o[k], k);
      }
    } else if (g['outcome'] != null) {
      _fail('Bitmemiş maç outcome');
    }
    _analysis(g['analysis']);
  }
  final accuracy = files['accuracy.json']!,
      season = _object(accuracy['season'], 'accuracy.season');
  _accuracyCounts(season);
  _prob(season['pickRate'], 'pickRate');
  _number(season['brier'], 'brier');
  if ((season['brier'] as num) < 0 || (season['brier'] as num) > 2) {
    _fail('Brier');
  }
  for (final k in ['liveEvaluated', 'livePickHits']) {
    _int(season[k], k);
  }
  if ((season['liveEvaluated'] as int) > (season['evaluated'] as int) ||
      (season['livePickHits'] as int) > (season['liveEvaluated'] as int)) {
    _fail('live sayıları');
  }
  final days = _list(accuracy['byDay'], 'byDay'),
      rounds = _list(accuracy['byRound'], 'byRound');
  String? previousDate;
  int dayTotal = 0, roundTotal = 0, previousRound = 999;
  for (final value in days) {
    final j = _object(value, 'byDay');
    _accuracyCounts(j);
    _date(j['date']);
    final date = j['date'] as String;
    if (previousDate != null && date.compareTo(previousDate) >= 0) {
      _fail('byDay sırası');
    }
    previousDate = date;
    dayTotal += j['evaluated'] as int;
  }
  for (final value in rounds) {
    final j = _object(value, 'byRound');
    _accuracyCounts(j);
    _int(j['round'], 'round');
    if ((j['round'] as int) >= previousRound) _fail('byRound sırası');
    previousRound = j['round'] as int;
    roundTotal += j['evaluated'] as int;
  }
  if (dayTotal != season['evaluated'] || roundTotal != season['evaluated']) {
    _fail('İsabet toplamları');
  }
  if (days.isEmpty) {
    if (accuracy['lastMatchDay'] != null) _fail('lastMatchDay');
  } else {
    _accuracyCounts(accuracy['lastMatchDay']);
    if ((accuracy['lastMatchDay'] as Json)['date'] !=
        (days.first as Json)['date']) {
      _fail('lastMatchDay tarihi');
    }
  }
  final table = files['standings.json']!, rows = _list(table['rows'], 'rows');
  if (rows.length != 18) _fail('18 takım gerekli');
  final teamIds = <String>{};
  for (var i = 0; i < rows.length; i++) {
    final r = _object(rows[i], 'row');
    _team(r['team']);
    if (!teamIds.add((r['team'] as Json)['id'] as String)) {
      _fail('Tekrarlanan sıra takımı');
    }
    _totals(r);
    _int(r['points'], 'points', signed: true);
    _int(r['pointAdjustment'], 'pointAdjustment', signed: true);
    _int(r['goalDiff'], 'goalDiff', signed: true);
    if (r['position'] != i + 1 ||
        r['goalDiff'] != (r['goalsFor'] as int) - (r['goalsAgainst'] as int) ||
        r['points'] !=
            3 * (r['won'] as int) +
                (r['drawn'] as int) +
                (r['pointAdjustment'] as int)) {
      _fail('Puan durumu toplamı');
    }
    _form(r['form']);
  }
  _string(table['note'], 'standings.note');
}
