import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/string_source.dart';
import 'package:clear_dart_lints/src/one_public_class_per_file.dart';
import 'package:test/test.dart';

class _Registry implements RuleVisitorRegistry {
  late AstVisitor visitor;
  @override
  void addCompilationUnit(AbstractAnalysisRule rule, AstVisitor visitor) {
    this.visitor = visitor;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Context implements RuleContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late OnePublicClassPerFile rule;
  late _Registry registry;
  setUp(() {
    rule = OnePublicClassPerFile();
    registry = _Registry();
    rule.registerNodeProcessors(registry, _Context());
  });

  void check(String source, List<String> expected) {
    final unit = parseString(content: source).unit;
    final listener = RecordingDiagnosticListener();
    rule.reporter = DiagnosticReporter(listener, StringSource(source, '/test.dart'));
    unit.accept(registry.visitor);
    expect(
      listener.diagnostics.map(
        (diagnostic) => source.substring(diagnostic.offset, diagnostic.offset + diagnostic.length),
      ),
      expected,
    );
    for (final diagnostic in listener.diagnostics) {
      expect(diagnostic.diagnosticCode, OnePublicClassPerFile.code);
      expect(diagnostic.correctionMessage, 'Move the public class to a separate file.');
    }
  }

  test('no classes', () => check('void f() {}', []));
  test('one public class', () => check('class First {}', []));
  test(
    'private classes are unrestricted',
    () => check('''
class _First {}
class Public {}
class _Second {}
class _Third {}
''', []),
  );
  test('only private classes', () => check('class _A {} class _B {}', []));
  test('two public classes', () => check('class First {} class Second {}', ['Second']));
  test(
    'three public classes and interspersed private classes',
    () => check(
      '''
class First {}
class _Private {}
class Second {}
class _Other {}
class Third {}
''',
      ['Second', 'Third'],
    ),
  );
  for (final modifier in [
    'abstract',
    'base',
    'final',
    'interface',
    'sealed',
    'mixin',
    'abstract base',
    'abstract interface',
    'abstract final',
  ]) {
    test(
      '$modifier class counts',
      () => check('class First {} $modifier class Second {}', ['Second']),
    );
  }
  test(
    'mixin, enum, extension and extension type do not count',
    () => check('''
mixin Behavior {}
enum Status { ready }
extension Helpers on int {}
extension type Value(int value) {}
class OnlyClass {}
''', []),
  );
  test(
    'named mixin applications are classes',
    () => check(
      '''
class First {}
mixin M {}
class Second = Object with M;
''',
      ['Second'],
    ),
  );
  test('generic class highlights only the name', () => check('class A {} class B<T> {}', ['B']));
  test('state resets between physical files and parts', () {
    check("part 'p.dart'; class First {}", []);
    check("part of 'main.dart'; class Second {}", []);
    check("part of 'main.dart'; class Second {} class Third {}", ['Third']);
    check('class Fresh {}', []);
  });
}
