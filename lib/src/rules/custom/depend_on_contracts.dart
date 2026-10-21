import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Configuration;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../../support/architecture_rule.dart';
import '../../support/configuration.dart';
import '../../support/role_usage.dart';

class DependOnContracts extends ArchitectureRule {
  static const code = LintCode(
    'depend_on_contracts',
    'Inject dependencies as abstract contracts through a constructor.',
  );
  DependOnContracts()
    : super(name: code.lowerCaseName, description: 'Inject abstract dependency contracts.');
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
        if (!config.hasRole(type, (options['dependency_roles'] as List).cast<String>())) return;
        final abstract =
            type is InterfaceType &&
            type.element is ClassElement &&
            (type.element as ClassElement).isAbstract;
        final constructorParameter =
            node
                .thisOrAncestorOfType<FormalParameter>()
                ?.thisOrAncestorOfType<ConstructorDeclaration>() !=
            null;
        final field = node.thisOrAncestorOfType<FieldDeclaration>();
        final fieldOwner = enclosingClass(node);
        final injectedField =
            field != null && fieldOwner != null && !field.isStatic && _injected(field);
        final usage = node is SimpleIdentifier && element is VariableElement;
        final acquisition =
            node is InstanceCreationExpression ||
            node is MethodInvocation ||
            node is FunctionExpressionInvocation;
        final allowed =
            abstract && !acquisition && (constructorParameter || injectedField || usage);
        if (!allowed && reported.add(node.offset)) reportViolation(node);
      }),
    );
  }
}

// Every generative constructor must receive each dependency from its caller.
bool _injected(FieldDeclaration field) {
  final owner = field.thisOrAncestorOfType<ClassDeclaration>();
  final body = owner?.body;
  if (body is! BlockClassBody) return false;
  final constructors = body.members
      .whereType<ConstructorDeclaration>()
      .where(
        (constructor) =>
            constructor.factoryKeyword == null &&
            constructor.declaredFragment?.element.redirectedConstructor == null,
      )
      .toList();
  if (constructors.isEmpty) return false;
  return field.fields.variables.every(
    (variable) =>
        variable.initializer == null &&
        constructors.every((constructor) {
          final element = constructor.declaredFragment?.element;
          if (element == null) return false;
          if (element.formalParameters.any(
            (parameter) =>
                parameter is FieldFormalParameterElement &&
                parameter.field == variable.declaredFragment?.element,
          ))
            return true;
          final assignments = _Assignments(variable.declaredFragment!.element, element);
          constructor.body.accept(assignments);
          return assignments.injected ||
              constructor.initializers.whereType<ConstructorFieldInitializer>().any((initializer) {
                final value = initializer.expression;
                return initializer.fieldName.name == variable.name.lexeme &&
                    value is SimpleIdentifier &&
                    value.element is FormalParameterElement &&
                    value.element?.enclosingElement == element;
              });
        }),
  );
}

class _Assignments extends RecursiveAstVisitor<void> {
  final VariableElement field;
  final ConstructorElement constructor;
  bool injected = false;
  _Assignments(this.field, this.constructor);
  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final target = node.writeElement;
    final variable = target is PropertyAccessorElement ? target.variable : target;
    final right = node.rightHandSide;
    if (node.operator.lexeme == '=' &&
        variable?.baseElement == field.baseElement &&
        right is SimpleIdentifier &&
        right.element is FormalParameterElement &&
        right.element?.enclosingElement == constructor)
      injected = true;
    super.visitAssignmentExpression(node);
  }
}
