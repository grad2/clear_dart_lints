import 'dart:convert';
import 'dart:io';

import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:clear_dart_lints/src/rules/security/avoid_hardcoded_secrets.dart';
import 'package:test/test.dart';

import 'body_rules_test.dart' show Fixture;

// All credentials below are synthetic format examples, never real credentials.
String _body(int length) {
  const alphabet = 'aB3dE6gH9jK2mN5pQ8rS1tU4vW7xY0z';
  return List.generate(length, (index) => alphabet[index % alphabet.length]).join();
}

final _github = 'ghp_${_body(36)}';
final _stripe = 'sk_live_${_body(24)}';
String _literal(String value) => jsonEncode(value).replaceAll(r'$', r'\$');

class _Registry implements RuleVisitorRegistry {
  late AstVisitor visitor;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #addCompilationUnit) return super.noSuchMethod(invocation);
    visitor = invocation.positionalArguments[1] as AstVisitor;
  }
}

class _Context implements RuleContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<Diagnostic>> _check(
  String source, {
  String target = 'main.dart',
  String? config,
  Map<String, String> files = const {},
}) async {
  final fixture = await Fixture.create(source);
  try {
    if (config != null) {
      File('${fixture.root.path}/clear_dart_lints.yaml').writeAsStringSync(config);
    }
    for (final entry in files.entries) {
      final file = File('${fixture.root.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    if (target != 'main.dart' && !files.containsKey(target)) {
      final file = File('${fixture.root.path}/$target');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(source);
    }
    final result =
        await fixture.contexts
                .contextFor('${fixture.root.path}/$target')
                .currentSession
                .getResolvedUnit('${fixture.root.path}/$target')
            as ResolvedUnitResult;
    expect(result.diagnostics, isEmpty, reason: 'The synthetic source must resolve cleanly.');
    final listener = RecordingDiagnosticListener();
    final rule = AvoidHardcodedSecrets()
      ..reporter = DiagnosticReporter(listener, result.unit.declaredFragment!.source);
    final registry = _Registry();
    rule.registerNodeProcessors(registry, _Context());
    result.unit.accept(registry.visitor);
    return listener.diagnostics;
  } finally {
    await fixture.dispose();
  }
}

void main() {
  final credentials = <String, String>{
    'GitHub classic PAT': _github,
    'GitHub fine-grained PAT': 'github_pat_${_body(82)}',
    'GitLab classic PAT': 'glpat-${_body(20)}',
    'GitLab routable PAT': 'glpat-${_body(27)}.a1b2c3d4e',
    'GitLab long routable PAT': 'glpat-${_body(300)}.a1b2c3d4e',
    'OpenAI legacy': 'sk-${_body(20)}T3BlbkFJ${_body(20)}',
    for (final kind in ['proj', 'svcacct', 'admin'])
      for (final length in [58, 74])
        'OpenAI $kind $length': 'sk-$kind-${_body(length)}T3BlbkFJ${_body(length)}',
    for (final kind in ['sk', 'rk'])
      for (final environment in ['live', 'test', 'prod'])
        'Stripe $kind $environment': '${kind}_${environment}_${_body(24)}',
    'Stripe minimum length': 'sk_live_${_body(10)}',
    'Stripe maximum length': 'rk_test_${_body(99)}',
    'Slack bot': 'xoxb-123456789012-987654321098-${_body(24)}',
    'Slack user': 'xoxp-123456789012-987654321098-123456789012-${_body(32)}',
    'Slack user variant': 'xoxe-123456789012-987654321098-123456789012-${_body(32)}',
    for (final label in [
      'PRIVATE KEY',
      'RSA PRIVATE KEY',
      'EC PRIVATE KEY',
      'DSA PRIVATE KEY',
      'ENCRYPTED PRIVATE KEY',
      'OPENSSH PRIVATE KEY',
    ])
      label: '-----BEGIN $label-----\n${_body(64)}\n${_body(64)}\n-----END $label-----',
  };
  for (final entry in credentials.entries) {
    test('recognizes ${entry.key}', () async {
      final diagnostics = await _check('const credential = ${_literal(entry.value)};');
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.diagnosticCode, AvoidHardcodedSecrets.code);
    });
  }

  test('finds tokens embedded in ordinary text', () async {
    expect(
      await _check('const header = ${_literal('Bearer $_github; next=$_stripe')};'),
      hasLength(1),
    );
  });

  test('decodes escapes before matching', () async {
    final escaped = _github.replaceFirst('ghp_', r'\u0067\x68p_');
    expect(await _check('const credential = "$escaped";'), hasLength(1));
  });

  test('supports raw and triple-quoted literals', () async {
    final key = credentials['OPENSSH PRIVATE KEY']!;
    expect(await _check("const first = r'$_github'; const second = r'''$key''';"), hasLength(2));
  });

  test('combines adjacent literals and reports the outer string once', () async {
    final expression = "'${_github.substring(0, 12)}' '${_github.substring(12)} $_stripe'";
    final source = 'const credential = $expression;';
    final diagnostics = await _check(source);
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.offset, source.indexOf(expression));
    expect(diagnostics.single.length, expression.length);
  });

  test('joins static text adjacent to an interpolated string', () async {
    final source = "String f(String name) => 'ghp_' '${_body(36)} \$name';";
    expect(await _check(source), hasLength(1));
  });

  test('checks static fragments on both sides of interpolation once', () async {
    expect(await _check('String f(String name) => "$_github \$name $_stripe";'), hasLength(1));
  });

  test('checks string literals nested inside interpolation expressions', () async {
    final source = "String f() => 'value: \${'$_github'}';";
    final diagnostics = await _check(source);
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.offset, source.indexOf("'$_github'"));
  });

  test('does not assemble values across interpolation holes or evaluate expressions', () async {
    expect(
      await _check('''
const suffix = '${_body(36)}';
String f(String middle) => 'ghp_\${middle}${_body(36)}';
const computed = 'ghp_\$suffix';
final concatenated = 'ghp_' + suffix;
final pieces = ['ghp_', suffix].join();
'''),
      isEmpty,
    );
  });

  final negatives = <String, String>{
    'ordinary API key name': 'not-a-credential',
    'UUID': '5fcfa4be-c020-4dd9-b172-e131a0273c58',
    'GitHub short': 'ghp_${_body(35)}',
    'GitHub long': 'ghp_${_body(37)}',
    'GitHub wrong alphabet': 'ghp_${_body(35)}-',
    'fine-grained short': 'github_pat_${_body(81)}',
    'fine-grained long': 'github_pat_${_body(83)}',
    'GitLab short': 'glpat-${_body(19)}',
    'GitLab long classic': 'glpat-${_body(21)}',
    'GitLab malformed routing': 'glpat-${_body(27)}.a1b2c3d4',
    'GitLab route too long': 'glpat-${_body(301)}.a1b2c3d4e',
    'OpenAI short': 'sk-${_body(19)}T3BlbkFJ${_body(20)}',
    'OpenAI missing marker': 'sk-proj-${_body(156)}',
    'Stripe public': 'pk_live_${_body(24)}',
    'Stripe short': 'sk_live_${_body(9)}',
    'Stripe long': 'sk_live_${_body(100)}',
    'Slack incomplete': 'xoxb-123456789012',
    'Slack user short': 'xoxp-123456789012-987654321098-123456789012-${_body(27)}',
    'private key header only': '-----BEGIN PRIVATE KEY-----',
    'private key short body':
        '-----BEGIN PRIVATE KEY-----\n${_body(63)}\n-----END PRIVATE KEY-----',
    'private key mismatched labels':
        '-----BEGIN RSA PRIVATE KEY-----\n${_body(64)}\n-----END EC PRIVATE KEY-----',
    'private key blank body':
        '-----BEGIN PRIVATE KEY-----${List.filled(80, '\n').join()}-----END PRIVATE KEY-----',
    'certificate': '-----BEGIN CERTIFICATE-----\n${_body(128)}\n-----END CERTIFICATE-----',
  };
  for (final entry in negatives.entries) {
    test('ignores ${entry.key}', () async {
      expect(await _check('const apiKey = ${_literal(entry.value)};'), isEmpty);
    });
  }

  for (final character in ['a', '0', '_', '-']) {
    test('requires token boundaries around $character', () async {
      expect(
        await _check('const first = "$character$_github"; const second = "$_github$character";'),
        isEmpty,
      );
    });
  }

  test('does not report comments or environment variable names', () async {
    expect(
      await _check('''
// $_github
/* $_stripe */
const apiKey = String.fromEnvironment('API_KEY');
'''),
      isEmpty,
    );
  });

  test('reports the literal range with no credential in the message', () async {
    final expression = _literal(_github);
    final source = '// before\nconst credential = $expression;';
    final diagnostic = (await _check(source)).single;
    expect(diagnostic.offset, source.indexOf(expression));
    expect(diagnostic.length, expression.length);
    expect(diagnostic.diagnosticCode.severity, DiagnosticSeverity.INFO);
    expect(diagnostic.message, isNot(contains(_github)));
    expect(diagnostic.correctionMessage, isNot(contains(_github)));
  });

  test('checks parts, generated suffixes and generated markers', () async {
    for (final target in ['model.g.dart', 'model.freezed.dart', 'marked.dart']) {
      expect(
        await _check(
          '// GENERATED CODE - DO NOT MODIFY BY HAND\nconst credential = "$_github";',
          target: target,
        ),
        hasLength(1),
      );
    }
    expect(
      await _check(
        "part 'piece.dart';",
        target: 'piece.dart',
        files: {'piece.dart': "part of 'main.dart'; const credential = '$_github';"},
      ),
      hasLength(1),
    );
  });

  test('is independent of absent, invalid or excluding architecture policy', () async {
    for (final config in [
      null,
      '[broken',
      'schema_version: 2\ninclude: [lib/**]\nexclude: [main.dart]\n',
    ]) {
      expect(await _check('const credential = "$_github";', config: config), hasLength(1));
    }
  });
}
