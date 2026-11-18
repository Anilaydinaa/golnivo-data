import 'dart:io';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:golnivo_pipeline/src/domain.dart';
import 'package:golnivo_pipeline/src/sources.dart';
import 'package:golnivo_pipeline/src/backtest.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()..addFlag('offline', negatable: false);
  final args = parser.parse(arguments),
      root = p.normalize(p.join(Directory.current.path, '..'));
  final client = http.Client();
  try {
    final loader = SourceLoader(root, client, offline: args['offline'] as bool);
    final teams = Teams.read('$root/data/teams.json');
    final games = await loader.load(teams);
    await runBacktest(root, games, loader.warnings);
  } catch (e, st) {
    stderr.writeln('$e\n$st');
    exitCode = 1;
  } finally {
    client.close();
  }
}
