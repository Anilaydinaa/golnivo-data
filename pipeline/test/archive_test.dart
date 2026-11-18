import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:golnivo_pipeline/src/archive.dart';
import 'package:golnivo_pipeline/src/domain.dart';
import 'helpers.dart';

void main() {
  late Directory dir;
  setUp(() => dir = testDirectory());
  tearDown(() => dir.deleteSync(recursive: true));
  Json calculate(DateTime cutoff, bool backfilled) => {
        'publishedAt': '2026-08-14T06:00:00Z',
        'modelVersion': modelVersion,
        'backfilled': backfilled,
        'marker': iso(cutoff)
      };
  test('Başlamadan yayımla, tam başlangıçta dondur, sonra baytları koru', () {
    final g = game(kickoff: '2026-08-14T18:30:00Z'),
        a = PredictionArchive(dir.path, g.season);
    final p = a.resolve(g, DateTime.parse('2026-08-14T06:00:00Z'), calculate);
    expect(p['frozen'], isFalse);
    a.save();
    final b = PredictionArchive(dir.path, g.season);
    final frozen = b.resolve(g, g.freezeAt,
        (_, __) => throw StateError('Önceki yayın kullanılmalı'));
    expect(frozen['frozen'], isTrue);
    expect(frozen['backfilled'], isFalse);
    expect(frozen['publishedAt'], '2026-08-14T06:00:00Z');
    b.save();
    final file = File('${dir.path}/frozen-${g.season}.jsonl'),
        bytes = file.readAsBytesSync();
    final c = PredictionArchive(dir.path, g.season);
    expect(
        c.resolve(
            g.copy(homeGoals: 8, awayGoals: 0),
            g.freezeAt.add(const Duration(days: 1)),
            (_, __) => throw StateError('Donmuş kayıt yeniden hesaplanamaz')),
        frozen);
    c.save();
    expect(file.readAsBytesSync(), bytes);
  });
  test('Saat yoksa üç gün önce yerel gece yarısı ve walk-forward etiketi', () {
    final g = game(), a = PredictionArchive(dir.path, g.season);
    DateTime? cutoff;
    final p = a.resolve(g, DateTime.parse('2026-08-14T06:00:00Z'), (t, b) {
      cutoff = t;
      expect(b, isTrue);
      return calculate(t, b);
    });
    expect(iso(cutoff!), '2026-08-10T21:00:00Z');
    expect(p['frozen'], isTrue);
    expect(p['backfilled'], isTrue);
  });
  test('Başlangıçtan sonraki yayın canlı isabet sayılmaz', () {
    final g = game(kickoff: '2026-08-14T18:30:00Z'),
        a = PredictionArchive(dir.path, g.season);
    a.latest[g.id] = {'publishedAt': iso(g.freezeAt), 'marker': 'geç'};
    final p = a.resolve(g, g.freezeAt.add(const Duration(hours: 1)), calculate);
    expect(p['backfilled'], isTrue);
    expect(p['marker'], isNot('geç'));
  });
  test('Arşivde yinelenen id reddedilir', () {
    final g = game(),
        line =
            jsonEncode({'id': g.id, 'prediction': calculate(g.freezeAt, true)});
    File('${dir.path}/frozen-${g.season}.jsonl')
        .writeAsStringSync('$line\n$line\n');
    expect(() => PredictionArchive(dir.path, g.season), throwsFormatException);
  });
  test('Yayın zamanını geri alma reddedilir', () {
    final g = game(kickoff: '2026-08-14T18:30:00Z'),
        a = PredictionArchive(dir.path, g.season);
    a.resolve(g, DateTime.parse('2026-08-14T10:00:00Z'), calculate);
    expect(
        () => a.resolve(g, DateTime.parse('2026-08-14T09:00:00Z'), calculate),
        throwsStateError);
  });
  for (final publication in [
    null,
    '2026-11-18T06:00:00Z',
    '2026-11-18T21:00:00Z'
  ]) {
    test('Erken biten maç hemen donar; önceki yayın: $publication', () {
      final g = game(date: '2026-11-22', hg: 2, ag: 1);
      final a = PredictionArchive(dir.path, g.season);
      if (publication != null) {
        a.latest[g.id] = {
          'publishedAt': publication,
          'backfilled': false,
          'marker': 'önceki'
        };
      }
      final now = DateTime.parse('2026-11-18T22:00:00Z');
      final p = a.resolve(g, now, calculate);
      expect(now.isBefore(g.freezeAt), isFalse);
      expect(p['frozen'], isTrue);
      final usable = publication != null &&
          DateTime.parse(publication).isBefore(g.freezeAt);
      expect(p['backfilled'], !usable);
      expect(p['marker'], usable ? 'önceki' : iso(g.freezeAt));
      expect(a.latest, isEmpty);
      a.save();
      final bytes =
          File('${dir.path}/frozen-${g.season}.jsonl').readAsBytesSync();
      final b = PredictionArchive(dir.path, g.season);
      b.resolve(g.copy(date: '2026-11-25', homeGoals: 9), now,
          (_, __) => throw StateError('Donmuş tahmin değişemez'));
      b.save();
      expect(File('${dir.path}/frozen-${g.season}.jsonl').readAsBytesSync(),
          bytes);
    });
  }
  test('Skor freezeAt öncesinde biliniyorsa yeni canlı tahmin hesaplanmaz', () {
    final g = game(date: '2026-11-22', hg: 1, ag: 0);
    final now = DateTime.parse('2026-11-18T06:00:00Z');
    final a = PredictionArchive(dir.path, g.season);
    expect(now.isBefore(g.freezeAt), isTrue);
    final p = a.resolve(g, now, (cutoff, backfilled) {
      expect(cutoff, g.freezeAt);
      expect(backfilled, isTrue);
      return calculate(cutoff, backfilled);
    });
    expect(p['frozen'], isTrue);
    expect(p['backfilled'], isTrue);
    expect(a.latest, isEmpty);
  });
  test('Erken bilinen skorda sınırdan önceki yayın canlı olarak korunur', () {
    final g = game(date: '2026-11-22', hg: 1, ag: 0);
    final now = DateTime.parse('2026-11-18T06:00:00Z');
    final a = PredictionArchive(dir.path, g.season);
    a.latest[g.id] = {
      'publishedAt': '2026-11-17T06:00:00Z',
      'backfilled': false
    };
    final p = a.resolve(
        g, now, (_, __) => throw StateError('Önceki yayın kullanılmalı'));
    expect(p['frozen'], isTrue);
    expect(p['backfilled'], isFalse);
    expect(p['publishedAt'], '2026-11-17T06:00:00Z');
  });
}
