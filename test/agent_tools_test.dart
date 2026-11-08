import 'dart:convert';
import 'dart:io';

import 'package:clear_dart_lints/agent_tools.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'body_rules_test.dart' show Fixture;
import 'feature_dependencies_test.dart' show featurePolicy;

final _packageRoot = Directory.current.absolute.path;
ArchitectureConfiguration _parse(String yaml, {String root = '/project'}) =>
    ArchitectureConfiguration.parse(yaml, root: root);
PolicyComparison _compare(String before, String after) =>
    comparePolicies(_parse(before), _parse(after));
Future<ProcessResult> _cli(String command, List<String> args) =>
    Process.run(Platform.resolvedExecutable, [
      '--packages=${p.join(_packageRoot, '.dart_tool/package_config.json')}',
      p.join(_packageRoot, 'bin', '$command.dart'),
      ...args,
    ]);
Map<String, dynamic> _json(ProcessResult result, int code) {
  expect(result.exitCode, code, reason: '${result.stdout}\n${result.stderr}');
  expect(result.stderr, isEmpty);
  final value = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  expect(value['format_version'], 1);
  expect(value['passed'], code == 0);
  expect(value.keys, containsAll(['command', 'package_root', 'data', 'issues']));
  return value;
}

Future<Fixture> _fixture() async {
  final fixture = await Fixture.create(
    'void main() {}',
    realPackages: true,
    options: 'plugins:\n  clear_dart_lints:\n    path: ${jsonEncode(_packageRoot)}\n',
  );
  File(p.join(fixture.root.path, 'clear_dart_lints.yaml')).writeAsStringSync(featurePolicy);
  return fixture;
}

void main() {
  group('context API', () {
    test('future paths and exclusions do not require application resolution', () {
      final policy = _parse(featurePolicy);
      final context = inspectFilePolicy(policy, 'lib/features/new/item.dart');
      expect(context.passed, isTrue);
      expect(context.toJson()['feature_scope'], containsPair('features', ['new']));
      expect(context.toJson()['architecture_checked'], isFalse);
      expect(inspectFilePolicy(policy, 'lib/unowned.g.dart').enforced, isFalse);
      expect(
        inspectFilePolicy(policy, 'lib/unowned.dart').issues.single.code,
        'unclassified_feature',
      );
      expect(policy.locations['rules.feature_dependencies']!.line, greaterThan(1));
      for (final path in ['../outside.dart', '/elsewhere/file.dart', 'lib/file.txt']) {
        expect(() => inspectFilePolicy(policy, path), throwsFormatException);
      }
    });
    test('matching role selectors are not reported as resolved roles', () {
      final yaml = featurePolicy.replaceFirst(
        'rules:',
        "roles:\n  view:\n    paths: ['lib/features/*/presentation/**']\nrules:",
      );
      final data = inspectFilePolicy(
        _parse(yaml),
        'lib/features/items/presentation/view.dart',
      ).toJson();
      expect((data['role_selectors'] as Map)['view'], containsPair('resolved', false));
      expect((data['role_selectors'] as Map)['view'], containsPair('path_matches', true));
    });
  });
  group('policy comparison', () {
    test('comments, key/list order and regrouped edges are equivalent', () {
      final before = featurePolicy
          .replaceFirst('to: [app]', 'to: [app]\n        uris: [dart:core, dart:async]')
          .replaceFirst("        uris: ['dart:*']\n", '');
      final after = before
          .replaceFirst(
            'to: [app]\n        uris: [dart:core, dart:async]',
            'to: [app]\n      - from: [app]\n        uris: [dart:async]\n      - from: [app]\n        uris: [dart:core]',
          )
          .replaceFirst(
            "include: ['main.dart', 'lib/**']",
            "include: ['lib/**', 'main.dart'] # comment",
          );
      expect(_compare(before, after).changes, isEmpty);
    });
    test('expanded permissions, exclusions and narrowed scope block', () {
      for (final after in [
        featurePolicy.replaceFirst('allowed: []', 'allowed: [{from: [catalog], to: [checkout]}]'),
        featurePolicy.replaceFirst(
          "exclude: ['lib/**/*.g.dart']",
          "exclude: ['lib/**/*.g.dart', 'lib/legacy/**']",
        ),
        featurePolicy.replaceFirst("['main.dart', 'lib/**']", "['lib/**']"),
        featurePolicy.replaceFirst(
          "['main.dart', 'lib/app/**', 'lib/di/**']",
          "['main.dart', 'lib/app/**', 'lib/di/**', 'lib/wiring/**']",
        ),
      ]) {
        final result = _compare(featurePolicy, after);
        expect(result.passed, isFalse);
        expect(result.changes.any((c) => c.assessment == PolicyAssessment.weakening), isTrue);
      }
    });
    test('glob replacement and selectors require review', () {
      for (final after in [
        featurePolicy.replaceFirst(
          "include: ['main.dart', 'lib/**']",
          "include: ['main.dart', 'lib/features/**']",
        ),
        featurePolicy.replaceFirst('lib/features/{feature}/**', 'lib/areas/{feature}/**'),
        featurePolicy.replaceFirst(
          "app: ['main.dart', 'lib/**']",
          "app: ['main.dart', 'lib/features/**']",
        ),
      ]) {
        final result = _compare(featurePolicy, after);
        expect(result.passed, isFalse);
        expect(result.changes.any((c) => c.assessment == PolicyAssessment.reviewRequired), isTrue);
      }
      final uriChange = _compare(
        featurePolicy,
        featurePolicy.replaceFirst("['dart:*']", "['dart:core']"),
      );
      expect(uriChange.passed, isFalse);
      expect(
        uriChange.changes.every((c) => c.assessment == PolicyAssessment.reviewRequired),
        isTrue,
      );
    });
    test('removing permissions and exceptions passes; reason changes are informational', () {
      final allowed = featurePolicy.replaceFirst(
        'allowed: []',
        'allowed: [{from: [catalog], to: [checkout]}]',
      );
      expect(_compare(allowed, featurePolicy).passed, isTrue);
      final exception =
          '$featurePolicy\nexceptions:\n  - rule: feature_dependencies\n    paths: [lib/features/catalog/home.dart]\n    reason: Temporary integration\n';
      expect(_compare(featurePolicy, exception).passed, isFalse);
      expect(
        _compare(featurePolicy, exception).changes.single.after,
        containsPair('reasons', ['Temporary integration']),
      );
      expect(_compare(exception, featurePolicy).passed, isTrue);
      final reason = _compare(
        exception,
        exception.replaceFirst('Temporary integration', 'Reviewed integration'),
      );
      expect(reason.passed, isTrue);
      expect(reason.changes.single.assessment, PolicyAssessment.informational);
    });
    test('roles, removed rules, contracts, restrictions and provider reads are covered', () {
      const dependency = '''
  constructor_injection:
    source_layers: [app]
    dependency_roles: [repository]
    allow_provider_reads: false
  role_dependencies:
    restrictions:
      - source_layers: [app]
        dependency_roles: [repository]
        allowed_consumer_roles: [repository, manager]
''';
      final policy =
          featurePolicy.replaceFirst(
            'rules:',
            "roles:\n  repository:\n    paths: ['lib/repositories/**']\n  manager:\n    paths: ['lib/managers/**']\nrules:",
          ) +
          dependency;
      expect(
        _compare(
          policy,
          policy.replaceFirst('allow_provider_reads: false', 'allow_provider_reads: true'),
        ).passed,
        isFalse,
      );
      expect(
        _compare(
          policy,
          policy.replaceFirst(
            'allowed_consumer_roles: [repository, manager]',
            'allowed_consumer_roles: [manager]',
          ),
        ).passed,
        isTrue,
      );
      expect(
        _compare(
          policy,
          policy.replaceFirst("['lib/repositories/**']", "['lib/contracts/**']"),
        ).passed,
        isFalse,
      );
      expect(_compare(policy, policy.replaceFirst(dependency, '')).passed, isFalse);
      final symbols =
          '$featurePolicy\n  forbidden_symbols:\n    source_layers: [app]\n    symbols: [{library: dart:convert, name: jsonDecode}]\n';
      expect(_compare(featurePolicy, symbols).passed, isTrue);
      expect(_compare(symbols, featurePolicy).passed, isFalse);
      expect(_compare(symbols, featurePolicy).changes.single.before, isA<Map>());
    });
  });
  group('CLI and read-only audit', () {
    test('context produces one JSON document for success, failure and usage', () async {
      final fixture = await _fixture();
      addTearDown(fixture.dispose);
      final root = fixture.root.path;
      final result = _json(
        await _cli('context', ['lib/features/new/file.dart', '--root', root, '--format=json']),
        0,
      );
      expect((result['data'] as Map)['layers'], ['app']);
      _json(await _cli('context', ['lib/unclassified.dart', '--root', root, '--format=json']), 1);
      _json(await _cli('context', ['../outside.dart', '--root', root, '--format=json']), 64);
      _json(await _cli('context', ['--unknown', '--format=json']), 64);
      _json(await _cli('context', ['--unknown', '--format', 'json']), 64);
      File(p.join(root, 'clear_dart_lints.yaml')).writeAsStringSync('invalid');
      expect(
        (_json(await _cli('context', ['lib/a.dart', '--root', root, '--format=json']), 1)['issues']
                as List)
            .single,
        containsPair('code', 'invalid_configuration'),
      );
      File(p.join(root, 'clear_dart_lints.yaml')).deleteSync();
      _json(await _cli('context', ['lib/a.dart', '--root', root, '--format=json']), 1);
    });
    test('audit retains text output and structured suppression coordinates', () async {
      final fixture = await _fixture();
      addTearDown(fixture.dispose);
      final root = fixture.root.path;
      final original = File(p.join(root, 'main.dart')).readAsStringSync();
      final text = await _cli('verify_setup', [root]);
      expect(text.exitCode, 0, reason: '${text.stdout}${text.stderr}');
      expect(text.stdout, startsWith('Setup audit passed: 1 Dart files.'));
      final success = _json(await _cli('verify_setup', [root, '--format=json']), 0);
      expect(success['data'], {'checked_files': 1, 'architecture_checked': false});
      for (final code in ['feature_dependencies', 'unclassified_feature', 'ambiguous_feature']) {
        final source = File(p.join(root, 'main.dart'));
        source.writeAsStringSync('// ignore_for_file: clear_dart_lints/$code\n$original');
        final failed = _json(await _cli('verify_setup', [root, '--format=json']), 1);
        final issue = (failed['issues'] as List).single as Map;
        expect(issue['code'], 'architecture_suppression');
        expect(issue['path'], source.path);
        expect(issue['line'], 1);
        expect(issue['column'], isA<int>());
        expect(source.readAsStringSync(), contains('// ignore_for_file:'));
      }
    });
    test('audit rejects feature classification failures and severity overrides', () async {
      final fixture = await _fixture();
      addTearDown(fixture.dispose);
      final root = fixture.root.path;
      Directory(p.join(root, 'lib')).createSync();
      File(p.join(root, 'lib/unknown.dart')).writeAsStringSync('class Unknown {}');
      expect((await verifySetup(root)).issues.map((i) => i.code), contains('unclassified_feature'));
      for (final code in ['feature_dependencies', 'unclassified_feature', 'ambiguous_feature']) {
        File(p.join(root, 'analysis_options.yaml')).writeAsStringSync(
          'plugins:\n  clear_dart_lints:\n    path: ${jsonEncode(_packageRoot)}\n    diagnostics:\n      $code: info\n',
        );
        expect(
          (await verifySetup(root)).issues.map((i) => i.code),
          contains('disabled_architecture'),
        );
      }
    });
    test('symlink ancestors outside the package are rejected', () async {
      final fixture = await _fixture();
      addTearDown(fixture.dispose);
      Link(p.join(fixture.root.path, 'linked')).createSync(fixture.external.path);
      expect(
        () =>
            inspectFilePolicy(_parse(featurePolicy, root: fixture.root.path), 'linked/future.dart'),
        throwsFormatException,
      );
    });
    test('Git comparison works for nested packages without changing the tree', () async {
      final repo = Directory.systemTemp.createTempSync('clear_policy_git_');
      addTearDown(() => repo.deleteSync(recursive: true));
      final root = Directory(p.join(repo.path, 'packages/app'))..createSync(recursive: true);
      final policy = File(p.join(root.path, 'clear_dart_lints.yaml'))
        ..writeAsStringSync(featurePolicy);
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
      Future<ProcessResult> git(List<String> args) =>
          Process.run('git', ['-C', repo.path, ...args]);
      expect((await git(['init'])).exitCode, 0);
      expect((await git(['add', 'packages'])).exitCode, 0);
      expect(
        (await git([
          '-c',
          'user.name=Fixture',
          '-c',
          'user.email=fixture@example.invalid',
          '-c',
          'commit.gpgsign=false',
          'commit',
          '-m',
          'baseline',
        ])).exitCode,
        0,
      );
      _json(await _cli('policy_diff', ['--base', 'HEAD', root.path, '--format=json']), 0);
      policy.writeAsStringSync(
        featurePolicy.replaceFirst('allowed: []', 'allowed: [{from: [catalog], to: [checkout]}]'),
      );
      final status = (await git(['status', '--porcelain'])).stdout;
      final content = policy.readAsStringSync();
      final blocked = _json(
        await _cli('policy_diff', ['--base', 'HEAD', root.path, '--format=json']),
        1,
      );
      expect((blocked['data'] as Map)['changes'], isNotEmpty);
      expect(policy.readAsStringSync(), content);
      expect((await git(['status', '--porcelain'])).stdout, status);
      _json(await _cli('policy_diff', ['--base', 'missing-ref', root.path, '--format=json']), 2);
      _json(await _cli('policy_diff', ['--base=--help', root.path, '--format=json']), 2);
      expect((await git(['rm', '--cached', 'packages/app/clear_dart_lints.yaml'])).exitCode, 0);
      expect(
        (await git([
          '-c',
          'user.name=Fixture',
          '-c',
          'user.email=fixture@example.invalid',
          '-c',
          'commit.gpgsign=false',
          'commit',
          '-m',
          'no baseline policy',
        ])).exitCode,
        0,
      );
      _json(await _cli('policy_diff', ['--base', 'HEAD', root.path, '--format=json']), 2);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
