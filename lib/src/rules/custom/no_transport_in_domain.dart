import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Configuration;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../../support/architecture_rule.dart';
import '../../support/api_checks.dart';
import '../../support/configuration.dart';
import '../../support/role_usage.dart';

class NoTransportInDomain extends ArchitectureRule {
  static const code = LintCode(
    'no_transport_in_domain',
    'Transport types and APIs are forbidden in this layer.',
  );
  NoTransportInDomain()
    : super(
        name: code.lowerCaseName,
        description: 'Keep configured layers independent of transport.',
      );
  @override
  LintCode get diagnosticCode => code;
  @override
  void check(
    CompilationUnit unit,
    RuleContext context,
    Configuration config,
    Map<String, dynamic> options,
  ) {
    final reported = <int>{};
    unit.accept(
      RoleUsage((node, type, element) {
        final base = element?.baseElement;
        final parent = base?.enclosingElement;
        final symbols = options['forbidden_symbols'] as List;
        final forbiddenSymbol = symbols.any(
          (symbol) =>
              symbol['library'] == base?.library?.uri.toString() &&
              (symbol['name'] == base?.name ||
                  parent is InterfaceElement && symbol['name'] == parent.name),
        );
        final forbiddenType = referencedTypes(type).any(
          (candidate) => symbols.any(
            (symbol) =>
                symbol['library'] == candidate.library.uri.toString() &&
                symbol['name'] == candidate.name,
          ),
        );
        if ((forbiddenSymbol ||
                forbiddenType ||
                config.hasRole(type, (options['transport_roles'] as List).cast<String>())) &&
            reported.add(node.offset)) {
          reportViolation(node);
        }
      }),
    );
  }
}
