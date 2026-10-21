import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Configuration;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../support/architecture_rule.dart';
import '../../support/api_checks.dart';
import '../../support/configuration.dart';
import '../../support/dependencies.dart';

class LayerDependencies extends ArchitectureRule {
  static const code = LintCode(
    'layer_dependencies',
    'This dependency is forbidden by the layer configuration.',
  );
  LayerDependencies()
    : super(name: code.lowerCaseName, description: 'Respect configured layer boundaries.');
  @override
  LintCode get diagnosticCode => code;
  @override
  void check(
    CompilationUnit unit,
    RuleContext context,
    Configuration config,
    Map<String, dynamic> options,
  ) {
    final sourceLayers = config.layersFor(context.currentUnit!.file.path);
    bool compute(Uri uri) => dependencies(context, uri).any(
      (target) => (options['forbidden'] as List).any(
        (entry) =>
            sourceLayers.any((layer) => (entry['from'] as List).contains(layer)) &&
            (matches((entry['uris'] as List).cast<String>(), target.uri.toString()) ||
                target.path != null &&
                    config
                        .layersFor(target.path!)
                        .any((layer) => (entry['to'] as List).contains(layer))),
      ),
    );
    final verdicts = <Uri, bool>{};
    bool forbidden(Uri uri) => verdicts.putIfAbsent(uri, () => compute(uri));
    final base = context.currentUnit!.file.toUri();
    for (final directive in unit.directives) {
      final List<StringLiteral> uris = switch (directive) {
        ImportDirective() => [directive.uri, ...directive.configurations.map((c) => c.uri)],
        ExportDirective() => [directive.uri, ...directive.configurations.map((c) => c.uri)],
        PartDirective() => [directive.uri],
        _ => [],
      };
      for (final literal in uris) {
        final value = literal.stringValue;
        if (value != null && forbidden(base.resolve(value))) reportViolation(literal);
      }
    }
    unit.accept(_TypeVisitor(this, forbidden));
  }
}

class _TypeVisitor extends RecursiveAstVisitor<void> {
  final LayerDependencies rule;
  final bool Function(Uri) forbidden;
  _TypeVisitor(this.rule, this.forbidden);
  @override
  void visitNamedType(NamedType node) {
    final libraries = {
      if (node.element?.library case final library?) library,
      for (final element in referencedTypes(node.type)) element.library,
    };
    if (libraries.any((library) => forbidden(library.uri))) rule.reportViolation(node);
    super.visitNamedType(node);
  }
}
