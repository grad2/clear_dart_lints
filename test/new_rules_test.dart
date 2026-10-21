import 'dart:io';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/workspace/workspace.dart';
import 'package:clear_dart_lints/src/rules/custom/avoid_nested_widget_ternaries.dart';
import 'package:clear_dart_lints/src/rules/custom/depend_on_contracts.dart';
import 'package:clear_dart_lints/src/rules/custom/layer_dependencies.dart';
import 'package:clear_dart_lints/src/rules/custom/no_transport_in_domain.dart';
import 'package:clear_dart_lints/src/rules/custom/repositories_only_in_blocs.dart';
import 'package:clear_dart_lints/src/rules/effective_dart/avoid_nullable_async_returns.dart';
import 'package:clear_dart_lints/src/rules/effective_dart/avoid_nullable_collection_returns.dart';
import 'package:clear_dart_lints/src/rules/effective_dart/avoid_public_late_final_fields.dart';
import 'package:test/test.dart';

import 'body_rules_test.dart' show Fixture;

class _Registry implements RuleVisitorRegistry {
  final visitors = <Symbol, List<AstVisitor>>{};
  @override
  dynamic noSuchMethod(Invocation invocation) {
    visitors
        .putIfAbsent(invocation.memberName, () => [])
        .add(invocation.positionalArguments[1] as AstVisitor);
  }
}

class _Dispatch extends RecursiveAstVisitor<void> {
  final _Registry registry;
  _Dispatch(this.registry);
  void dispatch(Symbol name, AstNode node) {
    for (final visitor in registry.visitors[name] ?? <AstVisitor>[]) {
      node.accept(visitor);
    }
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    dispatch(#addCompilationUnit, node);
    super.visitCompilationUnit(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    dispatch(#addFunctionDeclaration, node);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    dispatch(#addMethodDeclaration, node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    dispatch(#addFieldDeclaration, node);
    super.visitFieldDeclaration(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    dispatch(#addConditionalExpression, node);
    super.visitConditionalExpression(node);
  }
}

class _Context implements RuleContext {
  final ResolvedUnitResult result;
  @override
  final RuleContextUnit currentUnit;
  _Context(this.result, RecordingDiagnosticListener listener)
    : currentUnit = RuleContextUnit(
        file: result.session.analysisContext.contextRoot.resourceProvider.getFile(result.path),
        content: result.content,
        unit: result.unit,
        diagnosticReporter: DiagnosticReporter(listener, result.unit.declaredFragment!.source),
      );
  @override
  LibraryElement get libraryElement => result.libraryElement;
  @override
  RuleContextUnit get definingUnit => currentUnit;
  @override
  WorkspacePackage? get package => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<String>> check(
  AbstractAnalysisRule rule,
  String source, {
  String? config,
  Map<String, String> files = const {},
  bool repeated = false,
  String target = 'main.dart',
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
    Future<List<String>> run() async {
      final result =
          await fixture.contexts
                  .contextFor('${fixture.root.path}/$target')
                  .currentSession
                  .getResolvedUnit('${fixture.root.path}/$target')
              as ResolvedUnitResult;
      final listener = RecordingDiagnosticListener();
      final context = _Context(result, listener);
      rule.reporter = context.currentUnit.diagnosticReporter;
      final registry = _Registry();
      rule.registerNodeProcessors(registry, context);
      result.unit.accept(_Dispatch(registry));
      return listener.diagnostics.map((d) => d.diagnosticCode.lowerCaseName).toList();
    }

    final actual = await run();
    if (repeated) {
      // Context cache intentionally survives a configuration edit until restart.
      File('${fixture.root.path}/clear_dart_lints.yaml').writeAsStringSync('[broken');
      expect(await run(), actual);
    }
    return actual;
  } finally {
    await fixture.dispose();
  }
}

const architecture = '''
schema_version: 1
layers:
  presentation: ['main.dart']
  data: ['lib/data/**']
roles:
  repository:
    names: ['*Repository', '*RepositoryImpl']
    libraries: ['lib/data/**']
  bloc:
    names: ['*Bloc']
    libraries: ['main.dart']
  transport:
    names: ['ApiClient']
    libraries: ['lib/data/**']
rules:
  layer_dependencies:
    source_layers: [presentation]
    forbidden:
      - from: [presentation]
        to: [data]
        uris: ['dart:convert']
  repositories_only_in_blocs:
    source_layers: [presentation]
    repository_roles: [repository]
    allowed_consumer_roles: [bloc]
    composition_roots: ['lib/assembly/**']
  depend_on_contracts:
    source_layers: [presentation]
    dependency_roles: [repository]
    composition_roots: ['lib/assembly/**']
  no_transport_in_domain:
    source_layers: [presentation]
    transport_roles: [transport]
    forbidden_symbols:
      - library: dart:convert
        name: jsonEncode
      - library: dart:convert
        name: json
''';
const repository = '''
abstract class ItemRepository { void load(); }
class ItemRepositoryImpl implements ItemRepository { void load() {} }
class ApiClient {}
''';
void main() {
  test('late final public instance/static fields, initializer and override exceptions', () async {
    expect(
      await check(AvoidPublicLateFinalFields(), '''
abstract class Contract { int get inherited; set inherited(int value); }
class Sample implements Contract {
 late final int value;
 static late final int global;
 late final int _cache;
 late final int initialized = 1;
 @override late final int inherited;
}
'''),
      ['avoid_public_late_final_fields', 'avoid_public_late_final_fields'],
    );
  });
  test(
    'nullable async types resolve prefixes and aliases and skip inherited and private APIs',
    () async {
      expect(
        await check(AvoidNullableAsyncReturns(), '''
import 'dart:async' as a;
typedef Pending = a.Future<int>?;
Pending load() => null;
a.Stream<int>? get updates => null;
a.Future<int?> value() async => null;
a.Future<int>? _cache() => null;
a.Future<int>? field;
abstract class Contract { a.Future<int>? load(); }
class Impl implements Contract { a.Future<int>? load() => null; }
class Other { a.Future<int>? fresh() => null; }
extension PublicApi on int { a.Future<int>? load() => null; }
extension _PrivateApi on String { a.Future<int>? load() => null; }
'''),
        List.filled(5, 'avoid_nullable_async_returns'),
      );
      expect(
        await check(AvoidNullableAsyncReturns(), 'class Future<T> {} Future<int>? load() => null;'),
        isEmpty,
      );
    },
  );
  test('nullable collections include typedef and exclude nullable items and fields', () async {
    expect(
      await check(AvoidNullableCollectionReturns(), '''
typedef Items = List<int>?;
Items load() => null;
Map<String, int>? get values => null;
List<int?> items() => [];
List<int>? field;
List<int>? _cache() => null;
abstract class C { Set<int>? load(); }
class D extends C { Set<int>? load() => null; }
'''),
      List.filled(3, 'avoid_nullable_collection_returns'),
    );
    expect(
      await check(AvoidNullableCollectionReturns(), 'class List<T> {} List<int>? load() => null;'),
      isEmpty,
    );
  });
  test('nested Widget choices only', () async {
    expect(
      await check(AvoidNestedWidgetTernaries(), '''
import 'package:flutter/src/widgets/framework.dart';
Widget f(bool a, bool b) => a ? (b ? const Text() : const Text()) : const Text();
Widget g(bool a) => a ? const Text() : const Text();
int h(bool a, bool b) => a ? (b ? 1 : 2) : 3;
'''),
      ['avoid_nested_widget_ternaries'],
    );
  });
  for (final factory in <AbstractAnalysisRule Function()>[
    LayerDependencies.new,
    RepositoriesOnlyInBlocs.new,
    DependOnContracts.new,
    NoTransportInDomain.new,
  ]) {
    test('${factory().name} requires valid configuration', () async {
      for (final config in <String?>[
        null,
        '[broken',
        'schema_version: 2',
        architecture.replaceFirst('layers:', 'unknown: true\nlayers:'),
        architecture.replaceFirst('source_layers: [presentation]', 'source_layers: [missing]'),
        architecture.replaceFirst('repository_roles: [repository]', 'repository_roles: [missing]'),
      ]) {
        expect(await check(factory(), 'void f() {}', config: config), ['invalid_configuration']);
      }
    });
  }
  test('dependency graph covers relative/package imports, conditional branches, cyclic exports and parts', () async {
    final files = {
      'lib/data/repository.dart': repository,
      'lib/barrel.dart': "export 'cycle.dart'; export 'data/repository.dart';",
      'lib/cycle.dart': "export 'barrel.dart';",
      'lib/safe.dart': '',
      'detail.dart': "part of 'main.dart';",
    };
    final rows = await check(
      LayerDependencies(),
      '''
import 'package:fixture/barrel.dart';
import 'lib/safe.dart' if (dart.library.io) 'lib/data/repository.dart';
export 'lib/barrel.dart';
part 'detail.dart';
ItemRepository? value;
''',
      config: architecture,
      files: files,
      repeated: true,
    );
    expect(rows.length, 4);
    expect(rows.toSet(), {'layer_dependencies'});
  });
  test('repository consumers, inheritance, getters and service location', () async {
    final rows = await check(
      RepositoriesOnlyInBlocs(),
      '''
import 'lib/data/repository.dart';
abstract class BaseBloc {}
class ItemsBloc extends BaseBloc { final ItemRepository repository; ItemsBloc(this.repository); }
class Child extends ItemsBloc { Child(super.repository); }
T locate<T>() => throw 0;
class Screen { final repository = locate<ItemRepository>(); }
void topLevel() { locate<ItemRepository>().load(); }
''',
      config: architecture,
      files: {'lib/data/repository.dart': repository},
    );
    expect(rows, isNotEmpty);
    expect(rows.toSet(), {'repositories_only_in_blocs'});
    expect(
      await check(
        RepositoriesOnlyInBlocs(),
        '''
import 'lib/data/repository.dart';
class ItemsBloc { final ItemRepository repository; ItemsBloc(this.repository); }
''',
        config: architecture,
        files: {'lib/data/repository.dart': repository},
      ),
      isEmpty,
    );
  });
  test(
    'contracts accept constructor injection, reject construction and concrete parameters',
    () async {
      expect(
        await check(
          DependOnContracts(),
          '''
import 'lib/data/repository.dart';
class Consumer { final ItemRepository repository; Consumer(this.repository); }
''',
          config: architecture,
          files: {'lib/data/repository.dart': repository},
        ),
        isEmpty,
      );
      expect(
        await check(
          DependOnContracts(),
          '''
import 'lib/data/repository.dart';
class Consumer { final ItemRepositoryImpl repository; Consumer(this.repository); }
final item = ItemRepositoryImpl();
''',
          config: architecture,
          files: {'lib/data/repository.dart': repository},
        ),
        isNotEmpty,
      );
    },
  );
  test(
    'transport symbols resolve prefixes, aliases and original declarations through barrels',
    () async {
      expect(
        await check(
          NoTransportInDomain(),
          '''
import 'dart:convert' as c;
import 'lib/barrel.dart';
String encode(Object value) => c.jsonEncode(value);
final codec = c.json;
ApiClient? client;
''',
          config: architecture,
          files: {
            'lib/data/repository.dart': repository,
            'lib/barrel.dart': "export 'data/repository.dart';",
          },
        ),
        hasLength(3),
      );
      expect(
        await check(
          NoTransportInDomain(),
          'String jsonEncode(Object value) => "";',
          config: architecture,
        ),
        isEmpty,
      );
    },
  );
  test('exclusions, generated files and composition roots', () async {
    for (final config in [
      architecture.replaceFirst('layers:', "exclude: ['main.dart']\nlayers:"),
      architecture.replaceAll("['lib/assembly/**']", "['main.dart']"),
    ]) {
      expect(
        await check(
          RepositoriesOnlyInBlocs(),
          "import 'lib/data/repository.dart'; ItemRepository? r;",
          config: config,
          files: {'lib/data/repository.dart': repository},
        ),
        isEmpty,
      );
    }
    expect(
      await check(
        LayerDependencies(),
        "// GENERATED CODE - DO NOT MODIFY BY HAND\nimport 'dart:convert';",
      ),
      isEmpty,
    );
  });
  test(
    'constructor field initializers, inherited repository roles and concrete service location',
    () async {
      final files = {'lib/data/repository.dart': repository};
      expect(
        await check(
          DependOnContracts(),
          "import 'lib/data/repository.dart'; "
          'class Consumer { late final ItemRepository repository; '
          'Consumer(ItemRepository value) { repository = value; } }',
          config: architecture,
          files: files,
        ),
        isEmpty,
      );
      expect(
        await check(
          DependOnContracts(),
          """
import 'lib/data/repository.dart';
class Consumer {
 final ItemRepository repository;
 Consumer(ItemRepository value) : repository = value;
}
""",
          config: architecture,
          files: files,
        ),
        isEmpty,
      );
      expect(
        await check(
          DependOnContracts(),
          """
import 'lib/data/repository.dart';
T locate<T>() => throw 0;
final dependency = locate<ItemRepository>();
""",
          config: architecture,
          files: files,
        ),
        isNotEmpty,
      );
      expect(
        await check(
          RepositoriesOnlyInBlocs(),
          """
import 'lib/data/repository.dart';
class Other extends ItemRepositoryImpl {}
Other? dependency;
""",
          config: architecture,
          files: files,
        ),
        isNotEmpty,
      );
    },
  );
  test('generated marker and optional excludes apply without architecture diagnostics', () async {
    expect(
      await check(
        AvoidNullableAsyncReturns(),
        '// GENERATED CODE - DO NOT MODIFY BY HAND\nFuture<int>? load() => null;',
      ),
      isEmpty,
    );
    expect(
      await check(
        AvoidNullableCollectionReturns(),
        'List<int>? load() => null;',
        config: architecture.replaceFirst('layers:', "exclude: ['main.dart']\nlayers:"),
      ),
      isEmpty,
    );
  });
  test('role names must also match declaration library paths', () async {
    const source = 'class ItemRepository {} ItemRepository? value;';
    expect(await check(RepositoriesOnlyInBlocs(), source, config: architecture), isEmpty);
    expect(await check(DependOnContracts(), source, config: architecture), isEmpty);
  });
  test('architecture checks use original declarations inside part files', () async {
    const source = "import 'lib/data/repository.dart'; part 'detail.dart';";
    final config = architecture.replaceFirst("['main.dart']", "['main.dart', 'detail.dart']");
    final files = {
      'lib/data/repository.dart': repository,
      'detail.dart': "part of 'main.dart'; ItemRepository? dependency;",
    };
    for (final rule in [LayerDependencies(), RepositoriesOnlyInBlocs(), DependOnContracts()]) {
      expect(await check(rule, source, config: config, files: files, target: 'detail.dart'), [
        rule.name,
      ]);
    }
  });
  test('layer policy follows typedef expansion through nested type arguments', () async {
    expect(
      await check(
        LayerDependencies(),
        "import 'lib/contracts.dart'; Pending? load() => null;",
        config: architecture,
        files: {
          'lib/data/repository.dart': repository,
          'lib/contracts.dart':
              "import 'data/repository.dart'; typedef Pending = Future<ItemRepository>;",
        },
      ),
      ['layer_dependencies'],
    );
  });
  test('transport symbol policy follows type aliases', () async {
    final config = architecture.replaceFirst('name: jsonEncode', 'name: JsonEncoder');
    expect(
      await check(
        NoTransportInDomain(),
        "import 'lib/codec.dart'; Encoder? encoder;",
        config: config,
        files: {'lib/codec.dart': "import 'dart:convert'; typedef Encoder = JsonEncoder;"},
      ),
      ['no_transport_in_domain'],
    );
  });
}
