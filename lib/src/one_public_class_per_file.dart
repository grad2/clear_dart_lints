import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

class OnePublicClassPerFile extends AnalysisRule {
  static const code = LintCode(
    'one_public_class_per_file',
    'Only one public class is allowed per file.',
    correctionMessage: 'Move the public class to a separate file.',
  );

  OnePublicClassPerFile()
    : super(name: code.lowerCaseName, description: 'Allow one public class per Dart file.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addCompilationUnit(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final OnePublicClassPerFile rule;
  _Visitor(this.rule);

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // State belongs to this physical file, including when it is a part.
    var seenPublicClass = false;
    for (final declaration in node.declarations) {
      final Token? name = switch (declaration) {
        ClassDeclaration() => declaration.namePart.typeName,
        ClassTypeAlias() => declaration.name,
        _ => null,
      };
      if (name == null || name.isSynthetic || name.lexeme.startsWith('_')) continue;
      if (seenPublicClass) rule.reportAtToken(name);
      seenPublicClass = true;
    }
  }
}
