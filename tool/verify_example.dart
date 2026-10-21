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
  const added = {
    'avoid_public_late_final_fields',
    'avoid_nullable_async_returns',
    'avoid_nullable_collection_returns',
    'layer_dependencies',
    'repositories_only_in_blocs',
    'depend_on_contracts',
    'no_transport_in_domain',
    'avoid_nested_widget_ternaries',
  };
  final newRows = example
      .where((row) => row[3].replaceAll('\\', '/').endsWith('/lib/new_rules.dart'))
      .toList();
  final found = newRows.map((row) => row[2].toLowerCase()).toSet();
  if (found.length != added.length || !found.containsAll(added)) {
    throw StateError('Expected every new rule in new_rules.dart, got $newRows');
  }
  if (example.length != 8 + newRows.length) {
    throw StateError('Unexpected example diagnostics: $example');
  }
  for (final file in ['suppressed.dart', 'excluded_conventions.dart', 'generated.g.dart']) {
    expectFile(example, '/lib/$file', []);
  }
  expectFile(example, '/lib/bad.dart', [build, build, build, build, long, long]);
  expectFile(example, '/lib/good.dart', []);
  expectFile(example, '/lib/multiple_classes.dart', [classes]);
  expectFile(example, '/lib/parts/main.dart', []);
  expectFile(example, '/lib/parts/one.dart', []);
  expectFile(example, '/lib/parts/two.dart', [classes]);
  stdout.writeln(
    'PASS: all eleven rules, parts, suppressions, YAML exclusions and generated code.',
  );

  final repeated = await diagnostics('example');
  final firstFingerprint = example.map((row) => row.join('|')).toList()..sort();
  final repeatedFingerprint = repeated.map((row) => row.join('|')).toList()..sort();
  if (firstFingerprint.join('\n') != repeatedFingerprint.join('\n')) {
    throw StateError('Repeated analysis lost diagnostics: $repeated');
  }
  stdout.writeln('PASS: repeated analysis with the existing cache preserves all diagnostics.');

  // Mutate only a local test fixture, and restore it even on failed assertions.
  final options = File('example/analysis_options.yaml');
  final original = options.readAsStringSync();
  try {
    for (final enabled in added) {
      var content = original;
      for (final name in [build, long, classes, ...added]) {
        content = content.replaceAll('$name: true', '$name: ${name == enabled}');
      }
      options.writeAsStringSync(content);
      final independent = await diagnostics('example');
      if (independent.isEmpty || independent.any((row) => row[2].toLowerCase() != enabled)) {
        throw StateError('Independent $enabled: $independent');
      }
    }
    stdout.writeln('PASS: each new diagnostic can be enabled independently.');
    options.writeAsStringSync('analyzer:\n  exclude: [lib/new_rules.dart]\n$original');
    final excluded = await diagnostics('example');
    expectFile(excluded, '/lib/new_rules.dart', []);
    if (excluded.length != 8) throw StateError('Analyzer exclusion failed: $excluded');
    stdout.writeln('PASS: standard analyzer file exclusions.');
  } finally {
    options.writeAsStringSync(original);
  }
}
