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
        throw StateError(
          'Analyzer exited with ${result.exitCode}: ${result.stdout}\n${result.stderr}',
        );
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
    await verifySecrets(temp, options, original, diagnostics);
    await verifyFeatures(temp, diagnostics);
    stdout.writeln(
      'PASS: setup audit, native warnings, feature boundaries, agent CLI, optional styles, secret detection, exclusions and clean gate.',
    );
  } finally {
    temp.deleteSync(recursive: true);
  }
}

Future<void> verifySecrets(
  Directory root,
  File options,
  String original,
  Future<List<List<String>>> Function() diagnostics,
) async {
  const code = 'avoid_hardcoded_secrets';
  // Synthetic value assembled here to avoid committing a complete credential.
  final credential = 'ghp_${List.filled(36, 'a').join()}';
  final source = 'const credential = "$credential";\n';
  final main = File('${root.path}/lib/main.dart');
  main.writeAsStringSync(source);
  if ((await diagnostics()).isNotEmpty) {
    throw StateError('Secret detection must be disabled by default.');
  }

  final enabled = original.replaceFirst(
    '    diagnostics:\n',
    '    diagnostics:\n      $code: true\n',
  );
  options.writeAsStringSync(enabled);
  final found = await diagnostics();
  if (found.length != 1 || found.single[0] != 'INFO' || found.single[2].toLowerCase() != code) {
    throw StateError('Enabled secret detection must emit one info and fail the gate: $found');
  }
  if (found.single[4] != '1' ||
      found.single[5] != '20' ||
      found.single[6] != '${credential.length + 2}') {
    throw StateError('Secret detection must highlight the containing string: $found');
  }
  if (found.any((row) => row.join('|').contains(credential))) {
    throw StateError('Secret diagnostics must not disclose the matched credential.');
  }

  for (final directive in ['ignore', 'ignore_for_file']) {
    main.writeAsStringSync('// $directive: clear_dart_lints/$code\n$source');
    if ((await diagnostics()).isNotEmpty) {
      throw StateError('Standard $directive suppression must apply to secret detection.');
    }
  }

  main.writeAsStringSync('void main() {}\n');
  final generated = File('${root.path}/lib/secrets.g.dart');
  generated.writeAsStringSync('// GENERATED CODE - DO NOT MODIFY BY HAND\n$source');
  final excludedByPolicy = File('${root.path}/lib/excluded_conventions.dart');
  excludedByPolicy.writeAsStringSync(source);
  final outsidePolicy = File('${root.path}/test/secrets.dart');
  outsidePolicy.parent.createSync(recursive: true);
  outsidePolicy.writeAsStringSync(source);
  final all = await diagnostics();
  if (all.length != 3 || all.any((row) => row[2].toLowerCase() != code)) {
    throw StateError(
      'Generated and architecture-excluded/out-of-scope sources must be checked: $all',
    );
  }

  options.writeAsStringSync('analyzer:\n  exclude: [lib/secrets.g.dart]\n$enabled');
  final excluded = await diagnostics();
  if (excluded.length != 2 || excluded.any((row) => row[3].endsWith('/lib/secrets.g.dart'))) {
    throw StateError('Secret detection must respect analyzer exclusions: $excluded');
  }

  generated.deleteSync();
  excludedByPolicy.deleteSync();
  outsidePolicy.deleteSync();
  options.writeAsStringSync(enabled);
  if ((await diagnostics()).isNotEmpty) {
    throw StateError('A clean package must pass with secret detection enabled.');
  }
}

Future<void> verifyFeatures(
  Directory root,
  Future<List<List<String>>> Function() diagnostics,
) async {
  const policy = """
schema_version: 2
include: ['lib/**']
exclude: ['lib/**/*.g.dart']
layers:
  app: ['lib/**']
rules:
  layer_dependencies:
    allowed:
      - from: [app]
        to: [app]
        uris: ['dart:*']
  feature_dependencies:
    feature_paths: ['lib/features/{feature}/**']
    shared_paths: ['lib/core/**']
    composition_roots: ['lib/main.dart']
    allowed: []
""";
  final configuration = File('${root.path}/clear_dart_lints.yaml')..writeAsStringSync(policy);
  final source = File('${root.path}/lib/features/catalog/home.dart');
  final target = File('${root.path}/lib/features/checkout/order.dart');
  for (final file in [source, target]) {
    file.parent.createSync(recursive: true);
  }
  source.writeAsStringSync("import '../checkout/order.dart'; Order? order;\n");
  target.writeAsStringSync('class Order {}\n');
  final audit = await verifySetup(root.path);
  if (!audit.passed) throw StateError('Feature fixture audit failed: ${audit.issues}');
  Future<void> requireWarning(String code) async {
    final rows = await diagnostics();
    if (!rows.any((row) => row[0] == 'WARNING' && row[2].toLowerCase() == code)) {
      throw StateError('Expected native warning $code: $rows');
    }
  }

  await requireWarning('feature_dependencies');
  configuration.writeAsStringSync(
    policy.replaceFirst('allowed: []', 'allowed: [{from: [catalog], to: [checkout]}]'),
  );
  if ((await diagnostics()).isNotEmpty) throw StateError('Explicit feature edge must pass.');
  configuration.writeAsStringSync(policy);
  final unclassified = File('${root.path}/lib/loose.dart')..writeAsStringSync('class Loose {}\n');
  await requireWarning('unclassified_feature');
  unclassified.deleteSync();
  configuration.writeAsStringSync(
    policy.replaceFirst(
      "shared_paths: ['lib/core/**']",
      "shared_paths: ['lib/core/**', 'lib/features/**']",
    ),
  );
  await requireWarning('ambiguous_feature');
  configuration.writeAsStringSync(policy);
  for (final command in ['context', 'verify_setup']) {
    final result = await Process.run(Platform.resolvedExecutable, [
      '--suppress-analytics',
      'run',
      'clear_dart_lints:$command',
      if (command == 'context') 'lib/features/future/item.dart',
      '--format=json',
    ], workingDirectory: root.path);
    if (result.exitCode != 0 || result.stderr.toString().trim().isNotEmpty) {
      throw StateError('Consumer $command command failed: ${result.stdout} ${result.stderr}');
    }
    final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    if (json['format_version'] != 1 || json['passed'] != true || json['command'] != command) {
      throw StateError('Invalid consumer $command JSON envelope: $json');
    }
  }
}
