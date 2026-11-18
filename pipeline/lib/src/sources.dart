import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'domain.dart';
import 'parsers.dart';

const userAgent = 'GolnivoDataBot/1.0 (+https://github.com/Anilaydinaa/golnivo-data)';
Uri openFootballUrl(String season) => Uri.parse(
    'https://raw.githubusercontent.com/openfootball/europe/master/turkey/${season}_tr1.txt');
Uri wikipediaUrl(String season) => Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'parse',
      'page': '${season.replaceAll('-', '–')} Süper Lig',
      'prop': 'wikitext',
      'format': 'json',
      'formatversion': '2'
    });

class SourceLoader {
  final String root;
  final http.Client client;
  final bool offline;
  final List<String> warnings = [];
  SourceLoader(this.root, this.client, {this.offline = false});
  Future<T> fetch<T>(String filename, Uri url, T Function(String) parse) async {
    final cache = File(p.join(root, 'data', 'cache', filename));
    if (offline) {
      if (!cache.existsSync()) throw StateError('Önbellek yok: $filename');
      return parse(cache.readAsStringSync());
    }
    String body;
    try {
      final response = await client.get(url, headers: {
        'User-Agent': userAgent
      }).timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      body = utf8.decode(response.bodyBytes);
    } catch (e) {
      if (!cache.existsSync()) rethrow;
      warnings.add(
          'İndirme başarısız ($filename); son başarılı önbellek kullanıldı: $e');
      return parse(cache.readAsStringSync());
    }
    // Bozuk yeni içerik önbelleğin üstüne yazılmaz ve eski yayına dokunulmaz.
    final result = parse(body);
    cache.parent.createSync(recursive: true);
    final tmp = File('${cache.path}.tmp')..writeAsStringSync(body);
    tmp.renameSync(cache.path);
    return result;
  }

  Future<List<Game>> load(Teams teams, {bool includeCurrent = true}) async {
    final all = <Game>[];
    final overrideDir = Directory(p.join(root, 'data', 'overrides'));
    final overrides = <Json>[];
    if (overrideDir.existsSync()) {
      final files = overrideDir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.csv') &&
              p.basename(f.path) != 'point_adjustments.csv')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        overrides.addAll(csvRecords(f.readAsStringSync()));
      }
    }
    for (final season
        in seasons.where((s) => includeCurrent || s != currentSeason)) {
      final games =
          await fetch('openfootball-$season.txt', openFootballUrl(season), (s) {
        final parsed = parseOpenFootball(s, season, teams);
        final n = parsed.expand((g) => [g.home.id, g.away.id]).toSet().length;
        final expected =
            RegExp(r'^#\s*Matches\s+(\d+)', multiLine: true).firstMatch(s);
        if (expected != null && parsed.length != int.parse(expected[1]!)) {
          throw FormatException('Kaynak maç sayısı uyuşmuyor: $season');
        }
        if (parsed.length < 50 ||
            (season == currentSeason && (n != 18 || parsed.length != 306))) {
          throw FormatException(
              'Makul olmayan fikstür: $season, ${parsed.length} maç, $n takım');
        }
        return parsed;
      });
      final wiki = ['2025-26', currentSeason].contains(season)
          ? await fetch('wikipedia-$season.json', wikipediaUrl(season),
              (s) => parseWikipedia(s, season, teams))
          : <String, (int, int)>{};
      all.addAll(mergeGames(games, wiki,
          overrides.where((r) => r['season'] == season).toList(), warnings));
      if (season != currentSeason) {
        final missing =
            all.where((g) => g.season == season && !g.finished).length;
        if (missing > 0) {
          warnings.add(
              '$season: $missing sonuç eksik; bu maçlar eğitim ve test değerlendirmesine alınmadı.');
        }
      }
    }
    return withRoundFreezeTimes(all)..sort(compareGames);
  }
}
