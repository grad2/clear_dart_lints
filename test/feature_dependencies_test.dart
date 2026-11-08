import 'package:clear_dart_lints/agent_tools.dart';
import 'package:clear_dart_lints/src/architecture/policy.dart';
import 'package:test/test.dart';

import 'new_rules_test.dart' show check;

const featurePolicy = '''
schema_version: 2
include: ['main.dart', 'lib/**']
exclude: ['lib/**/*.g.dart']
layers:
  app: ['main.dart', 'lib/**']
rules:
  layer_dependencies:
    allowed:
      - from: [app]
        to: [app]
        uris: ['dart:*']
  feature_dependencies:
    feature_paths: ['lib/features/{feature}/**']
    shared_paths: ['lib/core/**']
    composition_roots: ['main.dart', 'lib/app/**', 'lib/di/**']
    allowed: []
''';
const _source = 'lib/features/catalog/home.dart';
const _other = 'lib/features/checkout/order.dart';
const _files = {_other: 'class Order {}', 'lib/core/shared.dart': 'class Shared {}'};

void main() {
  Future<List<String>> run(
    String source, {
    String config = featurePolicy,
    String target = _source,
    Map<String, String> extra = const {},
  }) => check(
    ArchitecturePolicy(),
    '',
    config: config,
    target: target,
    files: {..._files, ...extra, target: source},
    requireValid: true,
  );

  test('same feature, shared code and DI are accessible, other features are denied', () async {
    expect(
      await run("import '../checkout/order.dart'; Order? order;"),
      contains('feature_dependencies'),
    );
    expect(
      await run(
        "import 'local.dart'; Local? value;",
        extra: {'lib/features/catalog/local.dart': 'class Local {}'},
      ),
      isEmpty,
    );
    expect(await run("import '../../core/shared.dart'; Shared? value;"), isEmpty);
    expect(
      await run(
        "import '../../di/wiring.dart'; Wiring? value;",
        extra: {'lib/di/wiring.dart': 'class Wiring {}'},
      ),
      isEmpty,
    );
  });
  test('permissions are directed and do not waive layer restrictions', () async {
    final allowed = featurePolicy.replaceFirst(
      'allowed: []',
      'allowed: [{from: [catalog], to: [checkout]}]',
    );
    expect(await run("import '../checkout/order.dart'; Order? value;", config: allowed), isEmpty);
    expect(
      await run(
        "import '../catalog/home.dart'; Home? value;",
        config: allowed,
        target: _other,
        extra: {_source: 'class Home {}'},
      ),
      contains('feature_dependencies'),
    );
    expect(
      await run(
        "import '../checkout/order.dart'; Order? value;",
        config: allowed.replaceFirst('to: [app]', 'to: []'),
      ),
      contains('layer_dependencies'),
    );
  });
  test('shared cannot depend on features while composition roots can', () async {
    expect(
      await run(
        "import '../features/checkout/order.dart'; Order? value;",
        target: 'lib/core/other.dart',
      ),
      contains('feature_dependencies'),
    );
    expect(
      await run(
        "import '../features/checkout/order.dart'; Order? value;",
        target: 'lib/app/wiring.dart',
      ),
      isEmpty,
    );
  });
  test('barrels, conditional branches, cycles and physical parts retain boundaries', () async {
    expect(
      await run(
        "import 'barrel.dart'; Order? value;",
        extra: {
          'lib/features/catalog/barrel.dart':
              "export '../checkout/order.dart'; export 'loop.dart';",
          'lib/features/catalog/loop.dart': "export 'barrel.dart';",
        },
      ),
      contains('feature_dependencies'),
    );
    expect(
      await run(
        "import 'safe.dart' if (dart.library.io) '../checkout/order.dart'; Order? value;",
        extra: {'lib/features/catalog/safe.dart': 'class Order {}'},
      ),
      contains('feature_dependencies'),
    );
    expect(
      await run(
        "part '../checkout/detail.dart';",
        extra: {
          'lib/features/checkout/detail.dart': "part of '../catalog/home.dart'; class Detail {}",
        },
      ),
      contains('feature_dependencies'),
    );
  });
  test('excluded targets still require unambiguous feature classification', () async {
    expect(
      await run(
        "import '../../loose.g.dart'; Loose? value;",
        extra: {'lib/loose.g.dart': 'class Loose {}'},
      ),
      contains('unclassified_feature'),
    );
    expect(await run('', target: 'lib/loose.dart'), ['unclassified_feature']);
    expect(
      await run(
        '',
        config: featurePolicy.replaceFirst("['lib/core/**']", "['lib/core/**', 'lib/features/**']"),
      ),
      ['ambiguous_feature'],
    );
  });
  test('only dependency violations can be excepted', () async {
    final excepted =
        '$featurePolicy\nexceptions:\n  - rule: feature_dependencies\n    paths: [$_source]\n    reason: Reviewed integration\n';
    expect(await run("import '../checkout/order.dart'; Order? value;", config: excepted), isEmpty);
    for (final code in ['unclassified_feature', 'ambiguous_feature']) {
      expect(
        () => ArchitectureConfiguration.parse(
          excepted.replaceFirst('rule: feature_dependencies', 'rule: $code'),
          root: '/project',
        ),
        throwsFormatException,
      );
    }
  });
  test('layer-first captures deduplicate and malformed patterns fail', () {
    final config = ArchitectureConfiguration.parse(
      featurePolicy.replaceFirst(
        "['lib/features/{feature}/**']",
        "['lib/domain/{feature}/**', 'lib/data/{feature}/**', 'lib/domain/{feature}/*.dart']",
      ),
      root: '/project',
    );
    final rule = config.rules.featureDependencies!;
    expect(rule.membership('lib/domain/catalog/item.dart').features, {'catalog'});
    expect(
      rule.permits(
        rule.membership('lib/domain/catalog/item.dart'),
        rule.membership('lib/data/catalog/item.dart'),
      ),
      isTrue,
    );
    for (final pattern in [
      'lib/**/{feature}/**',
      'lib/features/*/**',
      'lib/{feature}/{feature}/**',
      '../{feature}/**',
      '/lib/{feature}/**',
      'lib/a{feature}/**',
    ]) {
      expect(
        () => ArchitectureConfiguration.parse(
          featurePolicy.replaceFirst('lib/features/{feature}/**', pattern),
          root: '/project',
        ),
        throwsFormatException,
        reason: pattern,
      );
    }
  });
  test('diagnostics identify the source, target, policy span and declaration', () async {
    await check(
      ArchitecturePolicy(),
      '',
      config: featurePolicy,
      target: _source,
      files: {..._files, _source: "import '../checkout/order.dart'; Order? value;"},
      inspectDiagnostics: (diagnostics) {
        final finding = diagnostics.firstWhere(
          (d) => d.diagnosticCode.lowerCaseName == 'feature_dependencies',
        );
        expect(finding.problemMessage.messageText(includeUrl: false), contains('layer: app'));
        expect(finding.problemMessage.messageText(includeUrl: false), contains(_other));
        expect(finding.correctionMessage, contains('directed feature permission'));
        expect(
          finding.contextMessages.any(
            (m) => m.filePath.endsWith('clear_dart_lints.yaml') && m.offset > 0,
          ),
          isTrue,
        );
        expect(finding.contextMessages.any((m) => m.filePath.endsWith(_other)), isTrue);
      },
    );
  });
  test('invalid policy diagnostics retain YAML locations and specific corrections', () async {
    await check(
      ArchitecturePolicy(),
      'void main() {}',
      config: 'schema_version: 1',
      inspectDiagnostics: (diagnostics) {
        final finding = diagnostics.single;
        expect(finding.contextMessages.single.filePath, endsWith('clear_dart_lints.yaml'));
        expect(finding.contextMessages.single.offset, 'schema_version: '.length);
      },
    );
    final codes = ArchitecturePolicy().diagnosticCodes;
    expect(codes.map((c) => c.correctionMessage).toSet(), hasLength(codes.length));
  });
}
