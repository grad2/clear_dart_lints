import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../support/api_checks.dart';
import '../../support/configuration.dart' show skipNewRule;

class AvoidNullableAsyncReturns extends AnalysisRule {
  static const code = LintCode(
    'avoid_nullable_async_returns',
    'Avoid returning a nullable container from a public API.',
  );
  AvoidNullableAsyncReturns()
    : super(name: code.lowerCaseName, description: 'Return a non-null container.');
  @override
  LintCode get diagnosticCode => code;
  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _Visitor(this, context);
    registry.addFunctionDeclaration(this, visitor);
    registry.addMethodDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;
  _Visitor(this.rule, this.context);
  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (skipNewRule(context)) return;
    final element = node.declaredFragment?.element;
    if (node.parent is CompilationUnit &&
        publicApi(element) &&
        standardNullable(element?.returnType, {'Future', 'Stream'}, 'dart:async')) {
      rule.reportAtNode(node.returnType ?? node);
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (skipNewRule(context)) return;
    final element = node.declaredFragment?.element;
    if (publicApi(element) &&
        standardNullable(element?.returnType, {'Future', 'Stream'}, 'dart:async')) {
      rule.reportAtNode(node.returnType ?? node);
    }
  }
}
