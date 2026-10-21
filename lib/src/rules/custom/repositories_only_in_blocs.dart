import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Configuration;
import 'package:analyzer/error/error.dart';

import '../../support/architecture_rule.dart';
import '../../support/configuration.dart';
import '../../support/role_usage.dart';

class RepositoriesOnlyInBlocs extends ArchitectureRule {
  static const code = LintCode(
    'repositories_only_in_blocs',
    'Repository access requires an allowed consumer or composition root.',
  );
  RepositoriesOnlyInBlocs()
    : super(name: code.lowerCaseName, description: 'Restrict repository consumers.');
  @override
  LintCode get diagnosticCode => code;
  @override
  void check(
    CompilationUnit unit,
    RuleContext context,
    Configuration config,
    Map<String, dynamic> options,
  ) {
    if (matches(
      (options['composition_roots'] as List).cast<String>(),
      config.relative(context.currentUnit!.file.path),
    ))
      return;
    final reported = <int>{};
    unit.accept(
      RoleUsage((node, type, element) {
        if (!config.hasRole(type, (options['repository_roles'] as List).cast<String>())) return;
        final owner = enclosingClass(node);
        if (config.hasRole(
          owner?.thisType,
          (options['allowed_consumer_roles'] as List).cast<String>(),
        ))
          return;
        if (reported.add(node.offset)) reportViolation(node);
      }),
    );
  }
}
