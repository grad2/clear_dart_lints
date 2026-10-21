import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Configuration;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'configuration.dart';

abstract class ArchitectureRule extends MultiAnalysisRule {
  static const invalidConfiguration = LintCode('invalid_configuration', '{0}');
  ArchitectureRule({required super.name, required super.description});
  DiagnosticCode get diagnosticCode;
  void reportViolation(AstNode node) => super.reportAtNode(node, diagnosticCode: diagnosticCode);
  @override
  List<DiagnosticCode> get diagnosticCodes => [diagnosticCode, invalidConfiguration];
  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addCompilationUnit(this, _Visitor(this, context));
  }

  void check(
    CompilationUnit unit,
    RuleContext context,
    Configuration config,
    Map<String, dynamic> options,
  );
}

class _Visitor extends SimpleAstVisitor<void> {
  final ArchitectureRule rule;
  final RuleContext context;
  _Visitor(this.rule, this.context);
  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (generated(context)) return;
    final result = configurationFor(context);
    final config = result.configuration;
    if (config != null && config.excluded(context.currentUnit!.file.path)) return;
    final rules = config?.data['rules'] as Map<String, dynamic>?;
    if (config == null || rules?[rule.name] == null) {
      rule.reportAtOffset(
        0,
        0,
        diagnosticCode: ArchitectureRule.invalidConfiguration,
        arguments: ['${rule.name}: ${result.error ?? 'Missing rule parameters.'}'],
      );
      return;
    }
    final options = config.parameters(rule.name);
    if (!config
        .layersFor(context.currentUnit!.file.path)
        .any((layer) => (options['source_layers'] as List).contains(layer)))
      return;
    rule.check(node, context, config, options);
  }
}
