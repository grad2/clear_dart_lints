import 'dart:convert';
import 'dart:io';

import 'package:clear_dart_lints/src/setup_verifier.dart';

/// Exercises the native plugin on an isolated copy of the example.
Future<void> main() async {
  final source = Directory('example').absolute;
  final temp = Directory.systemTemp.createTempSync('clear_dart_lints_example_');
  final packageRoot = Directory.current.absolute.path;
  void copy(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync()) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name == 'build' || name == '.DS_Store') continue;
      if (entity is Directory) copy(entity, Directory('${to.path}/$name'));
      if (entity is File) entity.copySync('${to.path}/$name');
    }
  }

  try {
    copy(source, temp);
    final manifest = File('${temp.path}/pubspec.yaml');
    manifest.writeAsStringSync(
      manifest.readAsStringSync().replaceFirst('path: ..', 'path: $packageRoot'),
    );
    final packageConfig = File('${temp.path}/.dart_tool/package_config.json');
    final config = jsonDecode(packageConfig.readAsStringSync()) as Map<String, dynamic>;
    final originalBase = File('${source.path}/.dart_tool/package_config.json').uri;
    for (final package in config['packages'] as List<dynamic>) {
      final entry = package as Map<String, dynamic>;
      final root = Uri.parse(entry['rootUri'] as String);
      if (!root.isAbsolute) {
        entry['rootUri'] = entry['name'] == 'clear_dart_lints_example'
            ? temp.uri.toString()
            : originalBase.resolveUri(root).toString();
      }
    }
    packageConfig.writeAsStringSync(jsonEncode(config));
    final options = File('${temp.path}/analysis_options.yaml');
    final original = options.readAsStringSync().replaceFirst('path: ..', 'path: $packageRoot');
    options.writeAsStringSync(original);
    final audit = await verifySetup(temp.path, verifierRoot: packageRoot);
    if (!audit.passed) {
      throw StateError(
        'Setup audit failed: ${audit.issues.map((i) => '${i.code}: ${i.message}').join('; ')}',
      );
    }
    Future<List<List<String>>> diagnostics() async {
      final result = await Process.run(Platform.resolvedExecutable, [
        '--suppress-analytics',
        'analyze',
        '--format=machine',
        '--fatal-infos',
        temp.path,
      ]);
      if (result.exitCode != 0 && result.exitCode != 1 && result.exitCode != 2) {
        throw StateError('Analyzer failed: ${result.stdout}\n${result.stderr}');
      }
      if (result.stderr.toString().trim().isNotEmpty) {
        throw StateError('Analyzer reported a plugin error: ${result.stderr}');
      }
      final rows = const LineSplitter()
          .convert(result.stdout.toString())
          .where(
            (line) =>
                line.startsWith('INFO|') ||
                line.startsWith('WARNING|') ||
                line.startsWith('ERROR|'),
          )
          .map((line) => line.split('|'))
          .toList();
      if ((rows.isEmpty && result.exitCode != 0) || (rows.isNotEmpty && result.exitCode == 0)) {
        throw StateError('Unexpected gate exit ${result.exitCode}: $rows');
      }
      return rows;
    }

    final rows = await diagnostics();
    final codes = rows.map((r) => r[2].toLowerCase()).toSet();
    for (final code in [
      'prefer_block_body_for_build',
      'prefer_block_body_for_long_expression',
      'one_public_class_per_file',
      'avoid_public_late_final_fields',
      'avoid_nullable_async_returns',
      'avoid_nullable_collection_returns',
      'avoid_nested_widget_ternaries',
      'layer_dependencies',
      'role_dependencies',
      'depend_on_contracts',
      'constructor_injection',
      'forbidden_symbols',
    ]) {
      if (!codes.contains(code)) throw StateError('Missing $code: $rows');
    }
    final architecture = {
      'layer_dependencies',
      'role_dependencies',
      'depend_on_contracts',
      'constructor_injection',
      'forbidden_symbols',
    };
    if (rows
        .where((r) => architecture.contains(r[2].toLowerCase()))
        .any((r) => r[0] != 'WARNING')) {
      throw StateError('Architecture diagnostics must be warnings: $rows');
    }
    for (final file in ['suppressed.dart', 'excluded_conventions.dart', 'generated.g.dart']) {
      if (rows.any((r) => r[3].replaceAll('\\', '/').endsWith('/lib/$file'))) {
        throw StateError('Unexpected diagnostic in $file: $rows');
      }
    }
    final again = await diagnostics();
    List<String> fingerprint(List<List<String>> values) =>
        values.map((r) => r.join('|')).toList()..sort();
    if (fingerprint(rows).join('\n') != fingerprint(again).join('\n')) {
      throw StateError('Repeated analysis changed diagnostics: $again');
    }
    options.writeAsStringSync('analyzer:\n  exclude: [lib/new_rules.dart]\n$original');
    final excluded = await diagnostics();
    if (excluded.any((r) => r[3].replaceAll('\\', '/').endsWith('/lib/new_rules.dart'))) {
      throw StateError('Analyzer exclusion failed: $excluded');
    }
    options.writeAsStringSync(original);
    Directory('${temp.path}/lib').deleteSync(recursive: true);
    Directory('${temp.path}/lib').createSync();
    File('${temp.path}/lib/main.dart').writeAsStringSync('void main() {}\n');
    final cleanAudit = await verifySetup(temp.path, verifierRoot: packageRoot);
    if (!cleanAudit.passed || (await diagnostics()).isNotEmpty) {
      throw StateError('Clean package must pass setup and native analysis.');
    }
    stdout.writeln(
      'PASS: setup audit, native warnings, optional styles, exclusions and clean gate.',
    );
  } finally {
    temp.deleteSync(recursive: true);
  }
}
