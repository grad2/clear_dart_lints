import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../support/api_checks.dart';
import '../../support/configuration.dart' show skipNewRule;

import 'package:analyzer/dart/element/element.dart';

class AvoidPublicLateFinalFields extends AnalysisRule {
  static const code = LintCode(
    'avoid_public_late_final_fields',
    'Avoid public late final fields without initializers.',
  );
  AvoidPublicLateFinalFields()
    : super(name: code.lowerCaseName, description: 'Keep late final setters private.');
  @override
  LintCode get diagnosticCode => code;
  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addFieldDeclaration(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;
  _Visitor(this.rule, this.context);
  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (skipNewRule(context)) return;
    if (!node.fields.isLate || !node.fields.isFinal) return;
    for (final variable in node.fields.variables) {
      final field = variable.declaredFragment?.element;
      if (variable.initializer == null &&
          !variable.name.lexeme.startsWith('_') &&
          !overridesContract(field is FieldElement ? field.getter : null)) {
        rule.reportAtToken(variable.name);
      }
    }
  }
}
