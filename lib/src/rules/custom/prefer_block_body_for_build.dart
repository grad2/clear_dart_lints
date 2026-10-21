import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Configuration;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../support/body_utils.dart';

class PreferBlockBodyForBuild extends AnalysisRule {
  static const code = LintCode(
    'prefer_block_body_for_build',
    'Flutter build methods and builder callbacks must use a block body.',
    correctionMessage: 'Use a block function body.',
  );

  PreferBlockBodyForBuild()
    : super(name: code.lowerCaseName, description: 'Use blocks for Flutter builders.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addExpressionFunctionBody(this, _BuildVisitor(this));
  }
}

class _BuildVisitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  _BuildVisitor(this.rule);

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (isFlutterBuilder(node)) rule.reportAtToken(node.functionDefinition);
  }
}
