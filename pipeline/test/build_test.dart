import 'dart:convert';
import 'dart:io';
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:golnivo_pipeline/src/build.dart';
import 'package:golnivo_pipeline/src/contract.dart';
import 'package:golnivo_pipeline/src/domain.dart';
import 'helpers.dart';

void main() {
  late Directory dir;
  late Map<String, Json> files;
  final now = DateTime.parse('2026-11-18T06:00:00Z');
  Map<String, String> published() => {
        for (final n in [
          'meta.json',
          'matches.json',
          'accuracy.json',
          'standings.json'
        ])
          n: File('${dir.path}/public/v1/$n').readAsStringSync()
      };
  Map<String, Json> clone() => {
        for (final e in files.entries)
          e.key: jsonDecode(jsonEncode(e.value)) as Json
      };
  setUpAll(() async {
    dir = testDirectory();
    Directory('${dir.path}/data/cache').createSync(recursive: true);
    File('../data/teams.json').copySync('${dir.path}/data/teams.json');
    for (final s in seasons) {
      File('test/fixtures/openfootball-$s.txt')
          .copySync('${dir.path}/data/cache/openfootball-$s.txt');
    }
    for (final s in ['2025-26', '2026-27']) {
      File('test/fixtures/wikipedia-$s.json')
          .copySync('${dir.path}/data/cache/wikipedia-$s.json');
    }
    writeJson('${dir.path}/data/model.json', {
      'selected': {'xi': 0.003, 'regularization': 5.0}
    });
    final client =
        MockClient((_) async => throw StateError('Testler ağ kullanamaz'));
    files = await buildPublic(dir.path, now, offline: true, client: client);
    client.close();
  });
  tearDownAll(() => dir.deleteSync(recursive: true));
  test('Gerçek fixture verisi dört sözleşme dosyasını üretir', () {
    expect(() => validatePublic(files), returnsNormally);
    expect(published().length, 4);
    final meta = files['meta.json']!;
    expect(meta['currentRound'], 12);
    expect(meta['generatedAt'], '2026-11-18T06:00:00Z');
    final matches = files['matches.json']!['matches'] as List<dynamic>;
    expect(matches.length, 45);
    expect(matches.where((dynamic g) => g['status'] == 'scheduled').length, 18);
    expect(matches.where((dynamic g) => g['status'] == 'finished').length, 27);
    expect(matches.where((dynamic g) => g['status'] == 'postponed').length, 0);
    final acc = files['accuracy.json']!['season'] as Json;
    expect(acc['evaluated'], 98);
    expect(acc['liveEvaluated'], 0);
    expect((files['standings.json']!['rows'] as List<dynamic>).length, 18);
  });
  test('Tekrar üretim aynı baytlar ve değişmeyen dondurma arşivi', () async {
    final previous = published(),
        frozen = File('${dir.path}/data/archive/frozen-2026-27.jsonl')
            .readAsBytesSync();
    final client = MockClient((_) async => throw StateError('Test ağı yasak'));
    await buildPublic(dir.path, now, offline: true, client: client);
    client.close();
    expect(published(), previous);
    expect(
        File('${dir.path}/data/archive/frozen-2026-27.jsonl').readAsBytesSync(),
        frozen);
    final latest = jsonDecode(
        File('${dir.path}/data/archive/latest-2026-27.json')
            .readAsStringSync()) as Json;
    expect(latest.length, 18);
    expect(
        latest.keys.every((id) =>
            (files['matches.json']!['matches'] as List<dynamic>)
                .any((dynamic g) => g['id'] == id)),
        isTrue);
  });
  test('Makul olmayan yeni kaynak önceki public dosyalarını korur', () async {
    final cache = File('${dir.path}/data/cache/openfootball-2026-27.txt'),
        original = cache.readAsStringSync(),
        previous = published();
    cache.writeAsStringSync(
        '▪ Matchday 1\nFri Aug 14 2026\nGalatasaray v Fenerbahçe');
    final client = MockClient((_) async => throw StateError('Test ağı yasak'));
    try {
      await expectLater(
          buildPublic(dir.path, now, offline: true, client: client),
          throwsFormatException);
      expect(published(), previous);
    } finally {
      cache.writeAsStringSync(original);
      client.close();
    }
  });
  test('Geçersiz çıktı yayını durdurur ve önceki dosyalar korunur', () {
    final broken = clone(), previous = published();
    broken['meta.json']!['schemaVersion'] = 2;
    expect(() => publishFiles(dir.path, broken), throwsFormatException);
    expect(published(), previous);
  });
  test('Sözleşme eksik alan, olasılık hassasiyeti ve UTC hatasını reddeder',
      () {
    for (final mutate in <void Function(Map<String, Json>)>[
      (f) => f['meta.json']!.remove('sources'),
      (f) => ((f['matches.json']!['matches'] as List<dynamic>)
          .first['prediction']['probabilities'] as Json)['home'] = 0.123456,
      (f) => f['accuracy.json']!['generatedAt'] = '2026-11-18T09:00:00+03:00',
      (f) => (f['standings.json']!['rows'] as List<dynamic>).removeLast(),
      (f) => ((f['matches.json']!['matches'] as List<dynamic>).first['analysis']
              ['dataQuality'] as Json)
          .remove('note'),
    ]) {
      final broken = clone();
      mutate(broken);
      expect(() => validatePublic(broken), throwsFormatException);
    }
  });
  test(
      'Kaynak tarihinden erken gelen skor hemen donar ve meta uyarısı yayımlanır',
      () async {
    final earlyDir = testDirectory();
    addTearDown(() => earlyDir.deleteSync(recursive: true));
    Directory('${earlyDir.path}/data/cache').createSync(recursive: true);
    Directory('${earlyDir.path}/data/overrides').createSync(recursive: true);
    for (final f
        in Directory('${dir.path}/data/cache').listSync().whereType<File>()) {
      f.copySync('${earlyDir.path}/data/cache/${f.uri.pathSegments.last}');
    }
    for (final name in ['teams.json', 'model.json']) {
      File('${dir.path}/data/$name').copySync('${earlyDir.path}/data/$name');
    }
    final target = (files['matches.json']!['matches'] as List<dynamic>)
        .cast<Json>()
        .firstWhere((g) => g['round'] == 12);
    File('${earlyDir.path}/data/overrides/matches.csv').writeAsStringSync(
        'season,homeId,awayId,homeGoals,awayGoals,status\n'
        '2026-27,${target['home']['id']},${target['away']['id']},2,1,finished\n');
    final output = await buildPublic(earlyDir.path, now, offline: true);
    final row = (output['matches.json']!['matches'] as List<dynamic>)
        .cast<Json>()
        .singleWhere((g) => g['id'] == target['id']);
    expect(row['status'], 'finished');
    expect(row['score'], {'home': 2, 'away': 1});
    expect(row['prediction']['frozen'], isTrue);
    expect(row['prediction']['backfilled'], isTrue);
    expect(output['accuracy.json']!['season']['evaluated'], 99);
    expect(
        (output['standings.json']!['rows'] as List<dynamic>)
            .fold<int>(0, (sum, row) => sum + (row['played'] as int)),
        198);
    expect(
        output['meta.json']!['warnings'],
        contains(
            'kaynak tarihi gerçek tarihten geç olabilir: ${target['id']}'));
  });
}
