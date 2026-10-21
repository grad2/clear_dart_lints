import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Configuration;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
// The public options API does not expose enabled plugin diagnostics.
// analyzer is pinned because this small compatibility bridge uses its model.
import 'package:analyzer/src/analysis_options/analysis_options.dart';

import '../../support/body_utils.dart';

import 'prefer_block_body_for_build.dart';

class PreferBlockBodyForLongExpression extends AnalysisRule {
  static const code = LintCode(
    'prefer_block_body_for_long_expression',
    'The single-line arrow function exceeds formatter.page_width or cannot be written on one line.',
    correctionMessage: 'Use a block function body.',
  );

  PreferBlockBodyForLongExpression()
    : super(name: code.lowerCaseName, description: 'Use blocks for long arrow functions.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addExpressionFunctionBody(this, _LongVisitor(this, context));
  }
}

class _LongVisitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;
  _LongVisitor(this.rule, this.context);

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    final unit = context.currentUnit!;
    final options = context.libraryElement!.session.analysisContext.getAnalysisOptionsForFile(
      unit.file,
    );
    final builderEnabled =
        options is AnalysisOptionsImpl &&
        options.pluginConfigurations.any(
          (plugin) =>
              plugin.name == 'clear_dart_lints' &&
              plugin.diagnosticConfigs[PreferBlockBodyForBuild.code.lowerCaseName]?.isEnabled ==
                  true,
        );
    if (builderEnabled && isFlutterBuilder(node)) return;
    final width = options.formatterOptions.pageWidth ?? 80;
    final length = singleLineLength(node, unit.content);
    if (length == null || length > width) {
      rule.reportAtToken(node.functionDefinition);
    }
  }
}
