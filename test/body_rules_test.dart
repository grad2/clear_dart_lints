import 'dart:convert';
import 'dart:io';

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:clear_dart_lints/src/body_utils.dart';
import 'package:clear_dart_lints/src/convert_to_block.dart';
import 'package:test/test.dart';

class Bodies extends RecursiveAstVisitor<void> {
  final values = <ExpressionFunctionBody>[];
  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    values.add(node);
    super.visitExpressionFunctionBody(node);
  }
}

List<ExpressionFunctionBody> bodies(CompilationUnit unit) {
  final visitor = Bodies();
  unit.accept(visitor);
  return visitor.values;
}

ExpressionFunctionBody parsedBody(String source) => bodies(parseString(content: source).unit).first;

class Fixture {
  final Directory root;
  final AnalysisContextCollection contexts;
  Fixture._(this.root, this.contexts);
  static Future<Fixture> create(String source, {String options = '', String? included}) async {
    final root = Directory.systemTemp.createTempSync('clear_dart_lints_test_');
    final sdk = File(Platform.resolvedExecutable).parent.parent;
    File('${root.path}/pubspec.yaml')
        .writeAsStringSync('name: fixture\nenvironment:\n  sdk: ^3.13.0\n');
    Directory('${root.path}/.dart_tool').createSync();
    Directory('${root.path}/flutter/lib/src/widgets').createSync(recursive: true);
    File('${root.path}/flutter/lib/src/widgets/framework.dart').writeAsStringSync('''
class BuildContext {}
class Widget { const Widget(); }
class Text extends Widget { const Text(); }
class Host {
  Host({Widget Function(BuildContext)? builder,
    Widget? Function(BuildContext, int)? itemBuilder,
    Widget Function(BuildContext)? transitionBuilder});
}
''');
    File('${root.path}/.dart_tool/package_config.json').writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'fixture', 'rootUri': '../', 'packageUri': 'lib/', 'languageVersion': '3.13'},
          {
            'name': 'flutter',
            'rootUri': '../flutter/',
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
        ],
      }),
    );
    if (options.isNotEmpty) File('${root.path}/analysis_options.yaml').writeAsStringSync(options);
    if (included != null) File('${root.path}/shared.yaml').writeAsStringSync(included);
    File('${root.path}/main.dart').writeAsStringSync(source);
    return Fixture._(
      root,
      AnalysisContextCollection(includedPaths: [root.path], sdkPath: sdk.path),
    );
  }

  Future<ResolvedUnitResult> resolve() async =>
      await contexts
              .contextFor('${root.path}/main.dart')
              .currentSession
              .getResolvedUnit('${root.path}/main.dart')
          as ResolvedUnitResult;
  Future<void> dispose() async {
    await contexts.dispose();
    root.deleteSync(recursive: true);
  }
}

void main() {
  group('one-line measurement', () {
    for (final width in [99, 100, 101]) {
      test('$width characters', () {
        final source = "String f() => '${'a' * (width - 17)}';";
        expect(source.length, width);
        expect(singleLineLength(parsedBody(source), source), width);
      });
    }
    test('wrapped arguments and trailing comma measure identically', () {
      const a = 'String f() => someVeryLongExpression(firstArgument, secondArgument);';
      const b = 'String f() => someVeryLongExpression(\n  firstArgument,\n  secondArgument,\n);';
      expect(singleLineLength(parsedBody(b), b), singleLineLength(parsedBody(a), a));
    });
    test('method indentation counts, annotations do not', () {
      const source = 'class C {\n  @override\n  String toString() => "ok";\n}';
      expect(singleLineLength(parsedBody(source), source), '  String toString() => "ok";'.length);
    });
    test('getters, closures and interpolated strings', () {
      for (final source in [
        'String get value => "a  b";',
        'final value = (int x) => x + 1;',
        r'String f(int x) => "value: $x";',
      ]) {
        expect(singleLineLength(parsedBody(source), source), isNotNull);
      }
    });
    test('comments and multiline literals require blocks', () {
      for (final source in [
        'int f() => /* keep */ 1;',
        'int f() => 1 /* tail */;',
        'String f() => """a\nb""";',
      ]) {
        expect(singleLineLength(parsedBody(source), source), isNull);
      }
    });
  });
  group('effective formatter options', () {
    for (final config in <(String, String?, int)>[
      ('', null, 80),
      ('formatter:\n  page_width: 100\n', null, 100),
      ('include: shared.yaml\n', 'formatter:\n  page_width: 100\n', 100),
      (
        'include: shared.yaml\nformatter:\n  page_width: 120\n',
        'formatter:\n  page_width: 100\n',
        120,
      ),
    ]) {
      test('width ${config.$3}: ${config.$1}', () async {
        final fixture = await Fixture.create(
          'int f() => 1;',
          options: config.$1,
          included: config.$2,
        );
        addTearDown(fixture.dispose);
        expect(pageWidthFor(await fixture.resolve()), config.$3);
      });
    }
  });
  test('Flutter methods, builder arguments, subtypes and nullable Widget', () async {
    final fixture = await Fixture.create('''
import 'package:flutter/src/widgets/framework.dart';
class Screen {
  Widget build(BuildContext context) => const Widget();
  Text other(BuildContext context) => const Text();
}
class Derived { Text build(BuildContext context) => const Text(); }
class Other { int build(BuildContext context) => 1; }
final host = Host(
  builder: (context) => const Widget(),
  itemBuilder: (context, index) => null,
  transitionBuilder: ((context) => const Widget()),
);
void unrelated({int Function()? builder}) {}
void caller() { unrelated(builder: () => 1); }
''');
    addTearDown(fixture.dispose);
    final result = await fixture.resolve();
    expect(result.diagnostics, isEmpty);
    expect(bodies(result.unit).map(isFlutterBuilder).toList(), [
      true,
      false,
      true,
      false,
      true,
      true,
      true,
      false,
    ]);
  });
  test('unrelated types named Widget and BuildContext do not match', () async {
    final fixture = await Fixture.create('''
class Widget {}
class BuildContext {}
class Screen { Widget build(BuildContext context) => Widget(); }
void host({Widget Function(BuildContext)? builder}) {}
void f() { host(builder: (context) => Widget()); }
''');
    addTearDown(fixture.dispose);
    expect(bodies((await fixture.resolve()).unit).any(isFlutterBuilder), isFalse);
  });
  group('correction producer', () {
    for (final sample in <(String, String)>[
      ('int f() => 42;', 'return 42;'),
      (
        'Future<void> f(bool x) async => x ? Future<void>.value() : Future<void>.value();',
        'await (',
      ),
      ('Future<int> f() async => 42;', 'return 42;'),
      ('Future<void> f() async => print("hello");', 'print("hello");'),
      ('Future<void> f() async => throw StateError("x");', 'throw StateError'),
      ('int f() => 42 // tail\n;', 'return 42'),
      ('class C { int get value => 42; }', 'return 42;'),
      ('void f() => print("hello");', 'print("hello");'),
      ('Future<void> f() async => Future<void>.value();', 'await (Future<void>.value());'),
      ('int f() => /* keep */ 42 /* tail */;', 'return 42'),
      ('int f() => // keep\n 42;', 'return 42;'),
      (
        'void takes(void Function() callback) {}\nvoid f() { takes(() => print("x")); }',
        'print("x");',
      ),
    ]) {
      test(sample.$1, () async {
        final fixture = await Fixture.create(sample.$1);
        addTearDown(fixture.dispose);
        final result = await fixture.resolve();
        final body = bodies(result.unit).first;
        final library =
            await result.session.getResolvedLibrary(result.path) as ResolvedLibraryResult;
        final producer = ConvertToBlock(
          context: CorrectionProducerContext.createResolved(
            libraryResult: library,
            unitResult: result,
            selectionOffset: body.functionDefinition.offset,
            selectionLength: 2,
          ),
        );
        final builder = ChangeBuilder(session: result.session);
        await producer.compute(builder);
        final fixed = SourceEdit.applySequence(sample.$1, builder.sourceChange.edits.single.edits);
        expect(fixed, contains(sample.$2));
        expect(parseString(content: fixed).errors, isEmpty);
        expect(bodies(parseString(content: fixed).unit), isEmpty);
        if (sample.$1.contains('/* keep */')) {
          expect(fixed, contains('/* keep */'));
          expect(fixed, contains('/* tail */'));
        }
        if (sample.$1.contains('// keep')) expect(fixed, contains('// keep'));
        File(result.path).writeAsStringSync(fixed);
        final context = fixture.contexts.contextFor(result.path);
        context.changeFile(result.path);
        await context.applyPendingFileChanges();
        expect((await fixture.resolve()).diagnostics, isEmpty);
      });
    }
  });
}
