import 'dart:io';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/workspace/workspace.dart';
import 'package:clear_dart_lints/src/rules/custom/avoid_nested_widget_ternaries.dart';
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
  bool realPackages = false,
  bool requireValid = false,
  void Function(List<Diagnostic>)? inspectDiagnostics,
}) async {
  final fixture = await Fixture.create(source, realPackages: realPackages);
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
      if (requireValid) {
        expect(
          result.diagnostics,
          isEmpty,
          reason: '$target must resolve without analyzer diagnostics',
        );
      }
      final listener = RecordingDiagnosticListener();
      final context = _Context(result, listener);
      rule.reporter = context.currentUnit.diagnosticReporter;
      final registry = _Registry();
      rule.registerNodeProcessors(registry, context);
      result.unit.accept(_Dispatch(registry));
      inspectDiagnostics?.call(listener.diagnostics);
      return listener.diagnostics.map((d) => d.diagnosticCode.lowerCaseName).toList();
    }

    final actual = await run();
    if (repeated) {
      // Configuration edits must be observed without restarting the analysis context.
      File('${fixture.root.path}/clear_dart_lints.yaml').writeAsStringSync('[broken');
      expect(await run(), ['invalid_configuration']);
    }
    return actual;
  } finally {
    await fixture.dispose();
  }
}

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
  test('generated marker keeps optional style checks disabled', () async {
    expect(
      await check(
        AvoidNullableAsyncReturns(),
        '// GENERATED CODE - DO NOT MODIFY BY HAND\nFuture<int>? load() => null;',
      ),
      isEmpty,
    );
  });
}
