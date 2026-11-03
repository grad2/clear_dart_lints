import 'dart:convert';
import 'dart:io';

import 'package:clear_dart_lints/src/setup_verifier.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'body_rules_test.dart' show Fixture;

const _policy = '''
schema_version: 2
include: ['main.dart', 'nested/**']
layers:
  app: ['main.dart', 'nested/**']
rules:
  layer_dependencies:
    allowed:
      - from: [app]
        to: [app]
        uris: ['dart:*']
''';

Future<Fixture> _fixture({String source = 'void main() {}', String extraOptions = ''}) async {
  final package = Directory.current.absolute.path;
  final fixture = await Fixture.create(
    source,
    options:
        '''
plugins:
  clear_dart_lints:
    path: ${jsonEncode(package)}
$extraOptions
''',
  );
  File(p.join(fixture.root.path, 'clear_dart_lints.yaml')).writeAsStringSync(_policy);
  final packages = File(p.join(fixture.root.path, '.dart_tool', 'package_config.json'));
  final data = jsonDecode(packages.readAsStringSync()) as Map<String, dynamic>;
  (data['packages'] as List).add({
    'name': 'clear_dart_lints',
    'rootUri': Uri.directory(package).toString(),
    'packageUri': 'lib/',
    'languageVersion': '3.13',
  });
  packages.writeAsStringSync(jsonEncode(data));
  return fixture;
}

Future<SetupVerification> _audit(Fixture fixture) => verifySetup(fixture.root.path);

void main() {
  test('a valid setup passes without editing package files', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final originals = {
      for (final entity in fixture.root.listSync(recursive: true).whereType<File>())
        entity.path: entity.readAsStringSync(),
    };
    final result = await _audit(fixture);
    expect(result.issues.map((issue) => issue.message), isEmpty);
    expect(result.checkedFiles, 1);
    for (final entry in originals.entries) {
      expect(File(entry.key).readAsStringSync(), entry.value);
    }
  });

  test('missing and legacy policy configurations fail before analysis', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final policy = File(p.join(fixture.root.path, 'clear_dart_lints.yaml'));
    policy.deleteSync();
    expect((await _audit(fixture)).issues.single.code, 'invalid_configuration');
    policy.writeAsStringSync(_policy.replaceFirst('schema_version: 2', 'schema_version: 1'));
    expect((await _audit(fixture)).issues.single.code, 'invalid_configuration');
  });

  test('missing plugin and disabled/lowered architecture fail', () async {
    for (final value in ['false', 'info']) {
      final fixture = await _fixture(extraOptions: '    diagnostics:\n      architecture: $value');
      try {
        expect(
          (await _audit(fixture)).issues.map((issue) => issue.code),
          contains('disabled_architecture'),
        );
      } finally {
        await fixture.dispose();
      }
    }
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    File(p.join(fixture.root.path, 'analysis_options.yaml'))
        .writeAsStringSync('formatter:\n  page_width: 100\n');
    expect((await _audit(fixture)).issues.map((issue) => issue.code), contains('missing_plugin'));
  });

  test('a diagnostic-specific override cannot lower a warning', () async {
    final fixture = await _fixture(
      extraOptions: '    diagnostics:\n      layer_dependencies: info',
    );
    addTearDown(fixture.dispose);
    expect(
      (await _audit(fixture)).issues.map((issue) => issue.code),
      contains('disabled_architecture'),
    );
  });

  test('effective included options retain plugin checks', () async {
    final fixture = await _fixture(extraOptions: '    diagnostics:\n      architecture: false');
    addTearDown(fixture.dispose);
    final options = File(p.join(fixture.root.path, 'analysis_options.yaml'));
    File(p.join(fixture.root.path, 'shared.yaml')).writeAsStringSync(options.readAsStringSync());
    options.writeAsStringSync('include: shared.yaml\n');
    expect(
      (await _audit(fixture)).issues.map((issue) => issue.code),
      contains('disabled_architecture'),
    );
  });

  test('analyzer exclusions cannot silently remove policy sources', () async {
    final fixture = await _fixture(extraOptions: 'analyzer:\n  exclude: [main.dart]');
    addTearDown(fixture.dispose);
    expect(
      (await _audit(fixture)).issues.map((issue) => issue.code),
      contains('analyzer_exclusion'),
    );
  });

  test('empty, unclassified and overlapping scopes fail', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final policy = File(p.join(fixture.root.path, 'clear_dart_lints.yaml'));
    policy.writeAsStringSync(_policy.replaceFirst("['main.dart', 'nested/**']", "['missing/**']"));
    expect((await _audit(fixture)).issues.map((issue) => issue.code), contains('empty_scope'));
    policy.writeAsStringSync(
      _policy.replaceFirst("app: ['main.dart', 'nested/**']", "app: ['other/**']"),
    );
    expect(
      (await _audit(fixture)).issues.map((issue) => issue.code),
      contains('unclassified_source'),
    );
    policy.writeAsStringSync(
      _policy.replaceFirst('layers:', "layers:\n  duplicate: ['main.dart']"),
    );
    expect((await _audit(fixture)).issues.map((issue) => issue.code), contains('ambiguous_layer'));
  });

  test('prefixed line/file ignores and broad warning ignores fail', () async {
    for (final comment in [
      '// ignore: clear_dart_lints/layer_dependencies',
      '// ignore_for_file: clear_dart_lints/unverifiable_dependency',
      '// ignore_for_file: type=warning',
      '// ignore: CLEAR_DART_LINTS/FORBIDDEN_SYMBOLS',
    ]) {
      final fixture = await _fixture(source: '$comment\nvoid main() {}');
      try {
        final result = await _audit(fixture);
        expect(
          result.issues.map((issue) => issue.code),
          contains('architecture_suppression'),
          reason: comment,
        );
      } finally {
        await fixture.dispose();
      }
    }
  });

  test('strings, unrelated style ignores and marker comments are not suppressions', () async {
    final fixture = await _fixture(
      source: '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore: clear_dart_lints/one_public_class_per_file
const text = '// ignore_for_file: clear_dart_lints/layer_dependencies';
/* // ignore_for_file: type=warning */
void main() {}
''',
    );
    addTearDown(fixture.dispose);
    expect((await _audit(fixture)).issues.map((issue) => issue.message), isEmpty);
  });

  test('explicit policy exclusions permit intentionally skipped files', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    Directory(p.join(fixture.root.path, 'nested')).createSync();
    File(p.join(fixture.root.path, 'nested', 'generated.dart'))
        .writeAsStringSync('// ignore_for_file: type=warning\n');
    File(p.join(fixture.root.path, 'clear_dart_lints.yaml'))
        .writeAsStringSync('exclude: [nested/**]\n$_policy');
    final result = await _audit(fixture);
    expect(result.issues.map((issue) => issue.message), isEmpty);
    expect(result.checkedFiles, 1);
  });

  test('exact plugin version must match the running verifier', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final options = File(p.join(fixture.root.path, 'analysis_options.yaml'));
    options.writeAsStringSync('plugins:\n  clear_dart_lints: 0.4.1\n');
    expect((await _audit(fixture)).issues.map((issue) => issue.code), contains('plugin_version'));
    options.writeAsStringSync('plugins:\n  clear_dart_lints: ^0.5.0\n');
    expect((await _audit(fixture)).issues.map((issue) => issue.code), contains('plugin_version'));
    options.writeAsStringSync('plugins:\n  clear_dart_lints: 0.5.0\n');
    expect((await _audit(fixture)).issues.map((issue) => issue.message), isEmpty);
  });

  test('a linked subtree needs a whole-subtree exclusion, not a sample filename', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final target = Directory(p.join(fixture.root.path, 'linked_target'))..createSync();
    File(p.join(target.path, 'actual.dart')).writeAsStringSync('void run() {}');
    Link(p.join(fixture.root.path, 'nested')).createSync(target.path);
    final policy = File(p.join(fixture.root.path, 'clear_dart_lints.yaml'));
    policy.writeAsStringSync('exclude: [nested/source.dart]\n$_policy');
    expect((await _audit(fixture)).issues.map((issue) => issue.code), contains('linked_scope'));
    policy.writeAsStringSync('exclude: [nested/**]\n$_policy');
    expect((await _audit(fixture)).issues.map((issue) => issue.message), isEmpty);
  });
}
