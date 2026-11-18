import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:golnivo_pipeline/src/build.dart';
import 'package:golnivo_pipeline/src/domain.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('now')
    ..addFlag('offline', negatable: false);
  try {
    final args = parser.parse(arguments),
        root = p.normalize(p.join(Directory.current.path, '..'));
    final raw = args['now'] as String?;
    if (raw != null && !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
      throw const FormatException('--now saat dilimi içermeli');
    }
    final now =
        raw == null ? DateTime.now().toUtc() : DateTime.parse(raw).toUtc();
    final files =
        await buildPublic(root, now, offline: args['offline'] as bool);
    stdout.writeln('Üretildi: ${files.keys.join(', ')}; ${iso(now)}');
    stdout.writeln(
        'Maç: ${(files['matches.json']!['matches'] as List<dynamic>).length}; isabet: ${files['accuracy.json']!['season']}');
    for (final warning in files['meta.json']!['warnings'] as List<dynamic>) {
      stderr.writeln('Uyarı: $warning');
    }
  } catch (e, st) {
    stderr.writeln('Yayın durduruldu: $e\n$st');
    exitCode = 1;
  }
}
