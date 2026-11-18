import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:golnivo_pipeline/src/domain.dart';
import 'package:golnivo_pipeline/src/contract.dart';

void main() {
  final root = p.normalize(p.join(Directory.current.path, '..'));
  try {
    validatePublic({
      for (final name in [
        'meta.json',
        'matches.json',
        'accuracy.json',
        'standings.json'
      ])
        name:
            jsonDecode(File('$root/public/v1/$name').readAsStringSync()) as Json
    });
    stdout.writeln('4 JSON dosyası §3 sözleşmesine uygun.');
  } catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}
