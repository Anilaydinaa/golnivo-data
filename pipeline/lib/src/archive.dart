import 'dart:convert';
import 'dart:io';
import 'domain.dart';

class PredictionArchive {
  final String directory, season;
  final Map<String, Json> latest = {}, frozen = {};
  final Set<String> _pending = {};
  PredictionArchive(this.directory, this.season) {
    final l = File('$directory/latest-$season.json');
    if (l.existsSync()) {
      final j = jsonDecode(l.readAsStringSync()) as Json;
      for (final e in j.entries) {
        latest[e.key] = e.value as Json;
      }
    }
    final f = File('$directory/frozen-$season.jsonl');
    if (f.existsSync()) {
      for (final line
          in f.readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
        final j = jsonDecode(line) as Json, id = j['id'] as String;
        if (frozen.containsKey(id)) {
          throw FormatException('Tekrarlanan donmuş kayıt: $id');
        }
        frozen[id] = j['prediction'] as Json;
      }
    }
  }
  Json resolve(Game game, DateTime now,
      Json Function(DateTime cutoff, bool backfilled) calculate) {
    final fixed = frozen[game.id];
    if (fixed != null) return fixed;
    if (!game.finished && now.isBefore(game.freezeAt)) {
      final previous = latest[game.id];
      if (previous != null &&
          DateTime.parse(previous['publishedAt'] as String).isAfter(now)) {
        throw StateError('Arşivden önceki zamana geri gidilemez');
      }
      final p = calculate(now, false);
      p['frozen'] = false;
      p['backfilled'] = false;
      p['publishedAt'] = iso(now);
      latest[game.id] = p;
      return p;
    }
    final previous = latest[game.id];
    final p = previous != null &&
            DateTime.parse(previous['publishedAt'] as String)
                .isBefore(game.freezeAt)
        ? <String, dynamic>{...previous}
        : calculate(game.freezeAt, true);
    p['frozen'] = true;
    if (previous == null ||
        !DateTime.parse(previous['publishedAt'] as String)
            .isBefore(game.freezeAt)) {
      p['backfilled'] = true;
      p['publishedAt'] = iso(now);
    }
    frozen[game.id] = p;
    _pending.add(game.id);
    latest.remove(game.id);
    return p;
  }

  void save() {
    Directory(directory).createSync(recursive: true);
    // Sadece yeni kayıtlar eklenir; mevcut JSONL baytları değişmez.
    final file = File('$directory/frozen-$season.jsonl');
    if (_pending.isNotEmpty) {
      final sink = file.openSync(mode: FileMode.append);
      try {
        final ids = _pending.toList()..sort();
        for (final id in ids) {
          sink.writeStringSync(
              '${jsonEncode({'id': id, 'prediction': frozen[id]})}\n');
        }
        sink.flushSync();
      } finally {
        sink.closeSync();
      }
      _pending.clear();
    }
    writeJson('$directory/latest-$season.json', latest);
  }
}
