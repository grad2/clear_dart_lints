import 'package:clear_dart_lints/src/architecture/policy.dart';
import 'package:test/test.dart';

import 'new_rules_test.dart' show check;

const policy = '''
schema_version: 2
include: ['main.dart', 'lib/**']
layers:
  ui: ['main.dart', 'lib/ui/**']
  data: ['lib/data/**']
roles:
  repository:
    names: ['*Repository', '*RepositoryImpl']
    libraries: ['lib/data/**']
  manager:
    names: ['*Manager']
    libraries: ['main.dart']
rules:
  layer_dependencies:
    allowed:
      - from: [ui]
        to: [ui, data]
        uris: ['dart:*']
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
''';
const repo = '''
abstract class ItemRepository { void load(); }
class ItemRepositoryImpl implements ItemRepository { void load() {} }
''';
const files = {'lib/data/repository.dart': repo};

void main() {
  test('named mixin application inheritance still obeys layer permissions', () async {
    final config = policy.replaceFirst('to: [ui, data]', 'to: [ui]');
    final result = await check(
      ArchitecturePolicy(),
      "import 'lib/data/repository.dart'; mixin M {} abstract class Other = ItemRepository with M;",
      config: config,
      files: files,
      requireValid: true,
    );
    expect(result, contains('layer_dependencies'));
    expect(result, isNot(contains('role_dependencies')));
  });

  test('resolved updates are verifiable while dynamic property updates remain reported', () async {
    expect(
      await check(
        ArchitecturePolicy(),
        'class Counter { int count = 0; void update() { count++; ++count; count += 1; } }',
        config: policy,
        requireValid: true,
      ),
      isEmpty,
    );
    expect(
      await check(
        ArchitecturePolicy(),
        'void update(dynamic value) { value.count++; ++value.count; }',
        config: policy,
        requireValid: true,
      ),
      contains('unverifiable_dependency'),
    );
  });
  test('missing and invalid config report one warning', () async {
    expect(await check(ArchitecturePolicy(), 'void f() {}'), ['invalid_configuration']);
    expect(await check(ArchitecturePolicy(), 'void f() {}', config: 'schema_version: 1'), [
      'invalid_configuration',
    ]);
  });
  test('included sources need exactly one layer', () async {
    expect(
      await check(
        ArchitecturePolicy(),
        '',
        config: policy.replaceFirst("ui: ['main.dart', ", "ui: ["),
      ),
      ['unclassified_source'],
    );
    expect(
      await check(
        ArchitecturePolicy(),
        '',
        config: policy.replaceFirst("data: ['lib/data/**']", "data: ['main.dart', 'lib/data/**']"),
      ),
      ['ambiguous_layer'],
    );
  });
  test('layer allowlist applies to local package URIs and conditional imports', () async {
    final denied = policy.replaceFirst('to: [ui, data]', 'to: [ui]');
    final diagnostics = await check(
      ArchitecturePolicy(),
      "import 'lib/ui/safe.dart' if (dart.library.io) 'package:fixture/data/repository.dart';",
      config: denied,
      files: {...files, 'lib/ui/safe.dart': ''},
    );
    expect(diagnostics, contains('layer_dependencies'));
  });
  test('role restriction permits managers and rejects top-level repository consumers', () async {
    final source =
        "import 'lib/data/repository.dart'; "
        'class ItemsManager { final ItemRepository repository; ItemsManager(this.repository); } '
        'ItemRepository? dependency;';
    final result = await check(ArchitecturePolicy(), source, config: policy, files: files);
    expect(result, contains('role_dependencies'));
  });
  test('concrete dependencies and forbidden resolved symbols are detected', () async {
    final result = await check(
      ArchitecturePolicy(),
      "import 'dart:convert' as c; import 'lib/data/repository.dart'; "
      'ItemRepositoryImpl? dependency; Object? decode(String value) => c.jsonDecode(value);',
      config: policy,
      files: files,
    );
    expect(result, contains('depend_on_contracts'));
    expect(result, contains('forbidden_symbols'));
  });
  test('explicit exception suppresses only its named diagnostic', () async {
    final config =
        '$policy\nexceptions:\n  - rule: forbidden_symbols\n'
        "    paths: ['main.dart']\n    reason: 'Legacy decoder'\n";
    final result = await check(
      ArchitecturePolicy(),
      "import 'dart:convert'; Object? decode(String s) => jsonDecode(s);",
      config: config,
    );
    expect(result, isNot(contains('forbidden_symbols')));
  });
  test('generated markers do not bypass architecture', () async {
    final config = policy.replaceFirst('to: [ui, data]', 'to: [ui]');
    final result = await check(
      ArchitecturePolicy(),
      "// GENERATED CODE - DO NOT MODIFY BY HAND\nimport 'lib/data/repository.dart';",
      config: config,
      files: files,
    );
    expect(result, contains('layer_dependencies'));
  });
  test('configuration edits invalidate policy cache', () async {
    await check(ArchitecturePolicy(), 'void f() {}', config: policy, repeated: true);
  });
  test('barrel exports and typedefs cannot hide forbidden layer dependencies', () async {
    final config = policy.replaceFirst('to: [ui, data]', 'to: [ui]');
    final result = await check(
      ArchitecturePolicy(),
      "import 'lib/ui/barrel.dart'; Pending? value;",
      config: config,
      files: {
        ...files,
        'lib/ui/barrel.dart': "export '../data/repository.dart'; import '../data/repository.dart'; typedef Pending = Future<ItemRepository>;",
      },
    );
    expect(result, contains('layer_dependencies'));
  });
  test(
    'constructor injection rejects acquisition while accepting a constructor parameter',
    () async {
      const good =
          "import 'lib/data/repository.dart'; "
          'class ItemsManager { final ItemRepository value; ItemsManager(this.value); }';
      const bad =
          "import 'lib/data/repository.dart'; "
          'class ItemsManager { final ItemRepository value = ItemRepositoryImpl(); }';
      expect(
        await check(ArchitecturePolicy(), good, config: policy, files: files),
        isNot(contains('constructor_injection')),
      );
      expect(
        await check(ArchitecturePolicy(), bad, config: policy, files: files),
        contains('constructor_injection'),
      );
    },
  );
  test('inheritance alone does not count as consuming a repository', () async {
    final result = await check(
      ArchitecturePolicy(),
      "import 'lib/data/repository.dart'; abstract class Other implements ItemRepository {}",
      config: policy,
      files: files,
    );
    expect(result, isNot(contains('role_dependencies')));
  });
  test('unresolved dynamic dependencies are reported', () async {
    final result = await check(
      ArchitecturePolicy(),
      'void f(dynamic value) { value.load(); }',
      config: policy,
    );
    expect(result, contains('unverifiable_dependency'));
  });
  test('dynamic member, invocation and index access are unverifiable', () async {
    final result = await check(
      ArchitecturePolicy(),
      'void f(dynamic value) { value.run(); print(value.name); print(value[0]); }',
      config: policy,
    );
    expect(result.where((code) => code == 'unverifiable_dependency'), hasLength(3));
  });
  test('inferred concrete acquisition is rejected', () async {
    final result = await check(
      ArchitecturePolicy(),
      "import 'lib/data/repository.dart'; final value = ItemRepositoryImpl();",
      config: policy,
      files: files,
    );
    expect(result, contains('depend_on_contracts'));
  });
  test('conditional assignment does not prove constructor injection', () async {
    final result = await check(
      ArchitecturePolicy(),
      "import 'lib/data/repository.dart'; class ItemsManager { late final ItemRepository value; ItemsManager(ItemRepository input, bool flag) { if (flag) value = input; } }",
      config: policy,
      files: files,
    );
    expect(result, contains('constructor_injection'));
  });
  test('inheritance still obeys layer dependencies', () async {
    final config = policy.replaceFirst('to: [ui, data]', 'to: [ui]');
    final result = await check(
      ArchitecturePolicy(),
      "import 'lib/data/repository.dart'; abstract class Other implements ItemRepository {}",
      config: config,
      files: files,
    );
    expect(result, contains('layer_dependencies'));
  });
  test('part files are classified and checked at their physical paths', () async {
    final config = policy
        .replaceFirst(
          "include: ['main.dart', 'lib/**']",
          "include: ['main.dart', 'detail.dart', 'lib/**']",
        )
        .replaceFirst(
          "ui: ['main.dart', 'lib/ui/**']",
          "ui: ['main.dart', 'detail.dart', 'lib/ui/**']",
        );
    final result = await check(
      ArchitecturePolicy(),
      "import 'lib/data/repository.dart'; part 'detail.dart';",
      config: config,
      files: {...files, 'detail.dart': "part of 'main.dart'; ItemRepository? value;"},
      target: 'detail.dart',
    );
    expect(result, contains('role_dependencies'));
  });
  test('forbidden symbols use declaration identity rather than matching names', () async {
    expect(
      await check(
        ArchitecturePolicy(),
        'Object jsonDecode(String input) => input;',
        config: policy,
      ),
      isNot(contains('forbidden_symbols')),
    );
  });
  test(
    'injection checks inferred globals and method parameters but permits injected field usage',
    () async {
      final global = await check(
        ArchitecturePolicy(),
        "import 'lib/data/repository.dart'; final ItemRepository global = ItemRepositoryImpl(); class ItemsManager { final value = global; }",
        config: policy,
        files: files,
        inspectDiagnostics: (diagnostics) {
          final field = diagnostics.firstWhere(
            (d) =>
                d.diagnosticCode.lowerCaseName == 'constructor_injection' &&
                d.problemMessage
                    .messageText(includeUrl: false)
                    .contains('through every constructor'),
          );
          expect(
            field.contextMessages.any(
              (m) => m.filePath.endsWith('lib/data/repository.dart') && m.offset > 0,
            ),
            isTrue,
          );
        },
      );
      expect(global, contains('constructor_injection'), reason: 'global field origin');
      final parameter = await check(
        ArchitecturePolicy(),
        "import 'lib/data/repository.dart'; class ItemsManager { void load(ItemRepository value) {} }",
        config: policy,
        files: files,
      );
      expect(parameter, contains('constructor_injection'), reason: 'method parameter');
      final injected = await check(
        ArchitecturePolicy(),
        "import 'lib/data/repository.dart'; class ItemsManager { final ItemRepository value; ItemsManager(this.value); void load() { value.load(); } }",
        config: policy,
        files: files,
      );
      expect(injected, isNot(contains('constructor_injection')), reason: 'injected field usage');
    },
  );
}
