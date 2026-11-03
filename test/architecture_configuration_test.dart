import 'dart:io';

import 'package:clear_dart_lints/src/architecture/configuration.dart';
import 'package:test/test.dart';

const valid = '''
schema_version: 2
include: ['lib/**']
exclude: ['lib/generated/**']
layers:
  ui: ['lib/ui/**']
  data: ['lib/data/**']
roles:
  repository:
    names: ['*Repository']
    libraries: ['lib/data/**']
  manager:
    types:
      - library: package:bloc/bloc.dart
        name: Bloc
rules:
  layer_dependencies:
    allowed:
      - from: [ui]
        to: [ui, data]
        uris: ['dart:core']
      - from: [data]
        to: [data]
        uris: ['dart:*']
  role_dependencies:
    restrictions:
      - source_layers: [ui]
        dependency_roles: [repository]
        allowed_consumer_roles: [manager]
  depend_on_contracts:
    source_layers: [ui]
    dependency_roles: [repository]
  constructor_injection:
    source_layers: [ui]
    dependency_roles: [repository]
  forbidden_symbols:
    source_layers: [ui]
    symbols:
      - library: dart:convert
        name: jsonDecode
exceptions:
  - rule: forbidden_symbols
    paths: ['lib/ui/legacy.dart']
    reason: 'Migration in progress'
''';

void main() {
  test('typed configuration preserves selectors, rules and exceptions', () {
    final c = ArchitectureConfiguration.parse(valid, root: '/project');
    expect(c.includes('/project/lib/ui/home.dart'), isTrue);
    expect(c.includes('/project/test/home.dart'), isFalse);
    expect(c.excluded('/project/lib/generated/model.dart'), isTrue);
    expect(c.layersFor('/project/lib/ui/home.dart'), {'ui'});
    expect(c.layersFor('/project/lib/other.dart'), isEmpty);
    expect(c.roles['repository']!.names, ['*Repository']);
    expect(c.roles['manager']!.types.single.library, 'package:bloc/bloc.dart');
    expect(c.rules.layerDependencies.first.to, ['ui', 'data']);
    expect(c.rules.roleDependencies!.restrictions.single.allowedConsumerRoles, ['manager']);
    expect(c.rules.dependOnContracts!.dependencyRoles, ['repository']);
    expect(c.rules.constructorInjection!.sourceLayers, ['ui']);
    expect(c.rules.forbiddenSymbols!.symbols.single.name, 'jsonDecode');
    expect(c.exceptions.single.reason, 'Migration in progress');
  });

  test('invalid schema, selectors, references and unknown keys fail clearly', () {
    final invalid = <String>[
      valid.replaceFirst('schema_version: 2', 'schema_version: 1'),
      valid.replaceFirst("include: ['lib/**']", 'include: []'),
      valid.replaceFirst('layers:', 'unknown: true\nlayers:'),
      valid.replaceFirst('to: [ui, data]', 'to: [missing]'),
      valid.replaceFirst('dependency_roles: [repository]', 'dependency_roles: [missing]'),
      valid.replaceFirst("    libraries: ['lib/data/**']\n", ''),
      valid.replaceFirst('schema_version: 2', 'schema_version: 2\nschema_version: 2'),
      valid.replaceFirst('reason: \'Migration in progress\'', "reason: ''"),
    ];
    for (final text in invalid) {
      expect(
        () => ArchitectureConfiguration.parse(text, root: '/project'),
        throwsFormatException,
        reason: text,
      );
    }
  });

  test('all ten template configurations parse and cover app and core samples', () {
    for (final preset in ['layered_bloc', 'layered_cubit', 'clean_bloc', 'clean_cubit', 'mvvm']) {
      for (final layout in ['feature_first', 'layer_first']) {
        final path = 'templates/$preset/$layout/clear_dart_lints.yaml';
        final config = ArchitectureConfiguration.parse(
          File(path).readAsStringSync(),
          root: '/project',
        );
        expect(config.includes('/project/lib/main.dart'), isTrue, reason: path);
        expect(config.layersFor('/project/lib/main.dart'), hasLength(1), reason: path);
        expect(config.layersFor('/project/lib/core/example.dart'), hasLength(1), reason: path);
      }
    }
  });
}
