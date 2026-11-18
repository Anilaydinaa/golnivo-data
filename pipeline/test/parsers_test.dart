import 'dart:convert';
import 'package:test/test.dart';
import 'package:golnivo_pipeline/src/domain.dart';
import 'package:golnivo_pipeline/src/parsers.dart';
import 'helpers.dart';

void main() {
  final teams = fixtureTeams();
  group('Gerçek openfootball anlık kopyaları', () {
    const counts = {
      '2018-19': 306,
      '2019-20': 306,
      '2020-21': 420,
      '2023-24': 380,
      '2024-25': 342,
      '2025-26': 306,
      '2026-27': 306
    };
    for (final e in counts.entries) {
      test('${e.key}: tam fikstür ve benzersiz kimlik', () {
        final games = parseOpenFootball(
            fixture('openfootball-${e.key}.txt'), e.key, teams);
        expect(games.length, e.value);
        expect(games.map((g) => g.id).toSet().length, e.value);
        expect(
            games.every((g) => g.round > 0 && g.home.id != g.away.id), isTrue);
      });
    }
    test('2026-27 skor önde, saat devri, gol atan satırları, null saat', () {
      final list = parseOpenFootball(
          fixture('openfootball-2026-27.txt'), '2026-27', teams);
      final first = list.first;
      expect(first.homeGoals, 2);
      expect(first.awayGoals, 2);
      expect(iso(first.kickoff!), '2026-08-14T18:30:00Z');
      final kas =
          list.firstWhere((g) => g.home.id == 'kasimpasa' && g.round == 1);
      expect(iso(kas.kickoff!), '2026-08-15T16:00:00Z');
      final round7 = list.where((g) => g.round == 7);
      expect(round7.every((g) => g.kickoff == null), isTrue);
      expect(list.last.date, '2027-05-23');
    });
    test('Eski biçim, devre skoru, hükmen sonuç notu', () {
      final list = parseOpenFootball(
          fixture('openfootball-2024-25.txt'), '2024-25', teams);
      final g = list.firstWhere(
          (g) => g.home.id == 'galatasaray' && g.away.id == 'adana-demirspor');
      expect(g.homeGoals, 3);
      expect(g.awayGoals, 0);
      expect(list.where((g) => !g.finished).length, 4);
    });
    test('Yıl geçişi ve tarih bloğunda saat sıfırlama', () {
      final list = parseOpenFootball(
          '▪ Matchday 1\nWed Dec 30 2026\n21:00 Galatasaray v Fenerbahçe 1-0\n▪ Matchday 2\nSun Jan 3\nFenerbahçe v Galatasaray\n',
          '2026-27',
          teams);
      expect(list.last.date, '2027-01-03');
      expect(list.last.kickoff, isNull);
      expect(iso(list.last.freezeAt), '2026-12-30T21:00:00Z');
    });
    test('Eşlenemeyen ad ve yinelenen maç hata verir', () {
      expect(
          () => parseOpenFootball(
              '▪ Matchday 1\nFri Aug 14 2026\nHayali v Galatasaray',
              '2026-27',
              teams),
          throwsFormatException);
      expect(
          () => parseOpenFootball(
              '▪ Matchday 1\nFri Aug 14 2026\nFenerbahçe v Galatasaray\nFenerbahçe v Galatasaray',
              '2026-27',
              teams),
          throwsFormatException);
    });
  });
  group('Gerçek Wikipedia anlık kopyaları', () {
    test('2025-26 306 sonuç, Unicode kodlar ve bağlantı içi skor', () {
      final s =
          parseWikipedia(fixture('wikipedia-2025-26.json'), '2025-26', teams);
      expect(s.length, 306);
      expect(s['2025-26-fenerbahce-galatasaray'], (1, 1));
      expect(s['2025-26-basaksehir-besiktas'], (2, 3));
    });
    test('2026-27 98 sonuç ve üç tire biçimi', () {
      final s =
          parseWikipedia(fixture('wikipedia-2026-27.json'), '2026-27', teams);
      expect(s.length, 98);
      expect(s['2026-27-amedspor-eyupspor'], (5, 1));
      expect(s['2026-27-besiktas-corum-fk'], (6, 2));
      expect(s['2026-27-caykur-rizespor-trabzonspor'], (3, 4));
    });
    test('Results dışı blok okunmaz', () {
      final j = jsonDecode(fixture('wikipedia-2026-27.json')) as Json;
      final p = j['parse'] as Json;
      p['wikitext'] =
          '{{#invoke:sports results|main\n|match_X_Y = 9–9\n}}\n${p['wikitext']}';
      expect(parseWikipedia(jsonEncode(j), '2026-27', teams).length, 98);
    });
    test('API hatası, bozuk matris ve bilinmeyen ad durdurur', () {
      expect(
          () => parseWikipedia(
              '{"error":{"code":"missingtitle"}}', '2026-27', teams),
          throwsFormatException);
      expect(
          () => parseWikipedia(
              fixture('wikipedia-2026-27.json')
                  .replaceAll('[[Alanyaspor]]', '[[Hayali]]'),
              '2026-27',
              teams),
          throwsFormatException);
      expect(
          () => parseWikipedia(
              fixture('wikipedia-2026-27.json')
                  .replaceAll('name_ALA', 'name_BBB'),
              '2026-27',
              teams),
          throwsFormatException);
    });
  });
  test('Skor önceliği, çelişki uyarısı ve tarih düzeltmesi', () {
    final g = game(hg: 1, ag: 0);
    final warnings = <String>[];
    final result = mergeGames([
      g
    ], {
      g.id: (2, 1)
    }, [
      {
        'season': '2026-27',
        'homeId': g.home.id,
        'awayId': g.away.id,
        'homeGoals': '3',
        'awayGoals': '2',
        'date': '2026-08-15',
        'kickoff': '2026-08-15T18:00:00Z'
      }
    ], warnings)
        .single;
    expect(result.homeGoals, 3);
    expect(result.awayGoals, 2);
    expect(result.date, '2026-08-15');
    expect(warnings.length, 2);
  });
  test('Erteleme ve saati null yapma skoru temizler', () {
    final g = game(kickoff: '2026-08-14T18:00:00Z', hg: 2, ag: 0);
    final result = mergeGames([
      g
    ], {}, [
      {
        'season': g.season,
        'homeId': g.home.id,
        'awayId': g.away.id,
        'status': 'postponed',
        'kickoff': 'null'
      }
    ], []).single;
    expect(result.postponed, isTrue);
    expect(result.finished, isFalse);
    expect(result.kickoff, isNull);
  });
  test('Fikstürde olmayan Wikipedia sonucu durdurur', () {
    expect(() => mergeGames([game()], {'2026-27-hayali-baska': (1, 0)}, [], []),
        throwsFormatException);
  });
  test('CSV virgül, tırnak ve çok satırlı açıklama', () {
    expect(parseCsv('a,b\n1,"iki, üç"\n2,"satır\nsonu"\n'), [
      ['a', 'b'],
      ['1', 'iki, üç'],
      ['2', 'satır\nsonu']
    ]);
    expect(() => csvRecords('a,b\n1\n'), throwsFormatException);
  });
}
