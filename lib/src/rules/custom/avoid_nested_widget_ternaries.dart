import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Configuration;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../support/api_checks.dart';
import '../../support/configuration.dart' show skipNewRule;

class AvoidNestedWidgetTernaries extends AnalysisRule {
  static const code = LintCode(
    'avoid_nested_widget_ternaries',
    'Use collection if or statements for nested Widget choices.',
  );
  AvoidNestedWidgetTernaries()
    : super(name: code.lowerCaseName, description: 'Keep Widget choices readable.');
  @override
  LintCode get diagnosticCode => code;
  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addConditionalExpression(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;
  _Visitor(this.rule, this.context);
  @override
  void visitConditionalExpression(ConditionalExpression node) {
    if (skipNewRule(context)) return;
    if (!flutterWidget(node.staticType)) return;
    for (final branch in [node.thenExpression, node.elseExpression]) {
      final value = unparenthesized(branch);
      if (value is ConditionalExpression && flutterWidget(value.staticType)) {
        rule.reportAtNode(value);
      }
    }
  }
}
