import 'dart:convert';
import 'dart:io';

/// Run from the package root after `flutter pub get` in example/.
Future<void> main() async {
  Future<List<List<String>>> diagnostics(String path) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      '--suppress-analytics',
      'analyze',
      '--format=machine',
      path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('Analyzer failed: ${result.stdout}\n${result.stderr}');
    }
    return const LineSplitter()
        .convert(result.stdout.toString())
        .where(
          (line) =>
              line.startsWith('INFO|') || line.startsWith('WARNING|') || line.startsWith('ERROR|'),
        )
        .map((line) => line.split('|'))
        .toList();
  }

  void expectFile(List<List<String>> rows, String suffix, List<String> codes, {List<int>? lines}) {
    final actual = rows.where((row) => row[3].replaceAll('\\', '/').endsWith(suffix)).toList();
    final actualCodes = actual.map((row) => row[2].toLowerCase()).toList()..sort();
    final expectedCodes = [...codes]..sort();
    if (actualCodes.join(',') != expectedCodes.join(',')) {
      throw StateError('$suffix: expected $expectedCodes, got $actual');
    }
    if (lines != null) {
      final actualLines = actual.map((row) => int.parse(row[4])).toList()..sort();
      if (actualLines.join(',') != lines.join(',')) {
        throw StateError('$suffix: expected lines $lines, got $actualLines');
      }
    }
  }

  const build = 'prefer_block_body_for_build';
  const long = 'prefer_block_body_for_long_expression';
  const classes = 'one_public_class_per_file';
  // Analyze the project as a whole so included part files are analyzed with
  // their defining library, rather than treating a part as a standalone target.
  final example = await diagnostics('example');
  if (example.length != 8) throw StateError('Expected 8 example diagnostics: $example');
  expectFile(example, '/lib/bad.dart', [build, build, build, build, long, long]);
  expectFile(example, '/lib/good.dart', []);
  expectFile(example, '/lib/multiple_classes.dart', [classes]);
  expectFile(example, '/lib/parts/main.dart', []);
  expectFile(example, '/lib/parts/one.dart', []);
  expectFile(example, '/lib/parts/two.dart', [classes]);
  stdout.writeln(
    'PASS: all three rules in the Flutter example, including parts and no duplicates.',
  );

  final repeated = await diagnostics('example');
  final firstFingerprint = example.map((row) => row.join('|')).toList()..sort();
  final repeatedFingerprint = repeated.map((row) => row.join('|')).toList()..sort();
  if (firstFingerprint.join('\n') != repeatedFingerprint.join('\n')) {
    throw StateError('Repeated analysis lost diagnostics: $repeated');
  }
  stdout.writeln('PASS: repeated analysis with the existing cache preserves all diagnostics.');
}
