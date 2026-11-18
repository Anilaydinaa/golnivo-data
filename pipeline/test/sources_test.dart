import 'dart:io';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:golnivo_pipeline/src/sources.dart';
import 'helpers.dart';

void main() {
  late Directory dir;
  setUp(() => dir = testDirectory());
  tearDown(() => dir.deleteSync(recursive: true));
  test('Başarılı indirme User-Agent ve doğrulanmış önbellek', () async {
    final client = MockClient((req) async {
      expect(req.headers['User-Agent'], userAgent);
      return http.Response('gerçek', 200,
          headers: {'content-type': 'text/plain; charset=utf-8'});
    });
    final loader = SourceLoader(dir.path, client);
    final v = await loader.fetch(
        'sample.txt', Uri.https('example.test', '/'), (s) => s.length);
    expect(v, 6);
    expect(
        File('${dir.path}/data/cache/sample.txt').readAsStringSync(), 'gerçek');
    expect(loader.warnings, isEmpty);
    client.close();
  });
  test('HTTP hatasında son başarılı kopya ve uyarı', () async {
    File('${dir.path}/data/cache/sample.txt').createSync(recursive: true);
    File('${dir.path}/data/cache/sample.txt').writeAsStringSync('önceki');
    final client = MockClient((_) async => http.Response('hata', 503)),
        loader = SourceLoader(dir.path, client);
    expect(
        await loader.fetch(
            'sample.txt', Uri.https('example.test', '/'), (s) => s),
        'önceki');
    expect(loader.warnings.single, contains('önbellek'));
    client.close();
  });
  test('Önbelleksiz ağ hatası durdurur', () async {
    final client =
            MockClient((_) async => throw const SocketException('ağ yok')),
        loader = SourceLoader(dir.path, client);
    await expectLater(
        loader.fetch('missing.txt', Uri.https('example.test', '/'), (s) => s),
        throwsA(isA<SocketException>()));
    client.close();
  });
  test('Bozuk indirme eski önbelleği korur ve sessiz geri dönmez', () async {
    final cache = File('${dir.path}/data/cache/sample.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('iyi');
    final client = MockClient((_) async => http.Response('bozuk', 200)),
        loader = SourceLoader(dir.path, client);
    await expectLater(
        loader.fetch('sample.txt', Uri.https('example.test', '/'),
            (s) => throw const FormatException('bozuk')),
        throwsFormatException);
    expect(cache.readAsStringSync(), 'iyi');
    client.close();
  });
  test('Ağsız mod hiç istek göndermez', () async {
    final cache = File('${dir.path}/data/cache/sample.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('iyi');
    final client = MockClient((_) async => throw StateError('Ağ yasak')),
        loader = SourceLoader(dir.path, client, offline: true);
    expect(
        await loader.fetch(
            'sample.txt', Uri.https('example.test', '/'), (s) => s),
        cache.readAsStringSync());
    await expectLater(
        loader.fetch('missing.txt', Uri.https('example.test', '/'), (s) => s),
        throwsStateError);
    client.close();
  });
}
