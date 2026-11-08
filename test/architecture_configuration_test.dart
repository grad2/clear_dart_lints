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
    expect(c.rules.constructorInjection!.allowProviderReads, isFalse);
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
      for (final value in ['yes', '1', '[]', 'null'])
        valid.replaceFirst(
          '  constructor_injection:',
          '  constructor_injection:\n    allow_provider_reads: $value',
        ),
      valid.replaceFirst(
        '  depend_on_contracts:',
        '  depend_on_contracts:\n    allow_provider_reads: true',
      ),
    ];
    for (final text in invalid) {
      expect(
        () => ArchitectureConfiguration.parse(text, root: '/project'),
        throwsFormatException,
        reason: text,
      );
    }
  });

  test('all sixteen template configurations parse and cover their source folders', () {
    for (final preset in [
      'layered_bloc',
      'layered_cubit',
      'clean_bloc',
      'clean_cubit',
      'mvvm',
      'layered_riverpod',
      'clean_riverpod',
      'mvvm_mobx',
    ]) {
      for (final layout in ['feature_first', 'layer_first']) {
        final path = 'templates/$preset/$layout/clear_dart_lints.yaml';
        final config = ArchitectureConfiguration.parse(
          File(path).readAsStringSync(),
          root: '/project',
        );
        expect(config.includes('/project/lib/main.dart'), isTrue, reason: path);
        expect(config.layersFor('/project/lib/main.dart'), hasLength(1), reason: path);
        expect(config.layersFor('/project/lib/core/example.dart'), hasLength(1), reason: path);
        if (preset == 'mvvm_mobx') {
          final base = layout == 'feature_first' ? 'lib/features/items' : 'lib';
          for (final suffix in ['.dart', '.g.dart']) {
            expect(config.layersFor('$base/presentation/viewmodels/items$suffix'), {'state'});
          }
          expect(config.excluded('$base/presentation/viewmodels/items.g.dart'), isTrue);
          expect(config.roles['state_manager']!.paths, isEmpty);
          expect(config.roles['state_manager']!.types.single.name, 'Store');
          expect(config.roles['state_manager']!.types.single.library, 'package:mobx/mobx.dart');
          expect(config.rules.constructorInjection!.allowProviderReads, isFalse);
        }
        if (preset.endsWith('riverpod')) {
          final base = layout == 'feature_first' ? 'lib/features/items' : 'lib';
          for (final folder in ['providers', 'notifiers']) {
            expect(config.layersFor('$base/presentation/$folder/items.dart'), {'state'});
            expect(config.layersFor('$base/presentation/$folder/items.g.dart'), {'state'});
            expect(config.excluded('$base/presentation/$folder/items.g.dart'), isTrue);
          }
          expect(config.layersFor('lib/di/repository.dart'), {'di'});
          expect(config.rules.constructorInjection!.allowProviderReads, isTrue);
        }
      }
    }
  });
}
