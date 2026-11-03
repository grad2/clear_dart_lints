import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../support/api_checks.dart';
import '../support/dependencies.dart';
import '../support/role_usage.dart';
import 'configuration.dart';

class ArchitectureCode extends DiagnosticCode {
  const ArchitectureCode(String name)
    : super(
        name: name,
        uniqueName: 'Architecture.$name',
        problemMessage: '{0}',
        correctionMessage: 'Route the dependency through an allowed boundary; change the policy only when the architecture requires it.',
      );
  @override
  DiagnosticSeverity get severity => DiagnosticSeverity.WARNING;
  @override
  DiagnosticType get type => DiagnosticType.STATIC_WARNING;
}

class ArchitecturePolicy extends MultiAnalysisRule {
  static const invalidConfiguration = ArchitectureCode('invalid_configuration');
  static const unclassifiedSource = ArchitectureCode('unclassified_source');
  static const ambiguousLayer = ArchitectureCode('ambiguous_layer');
  static const layerDependencies = ArchitectureCode('layer_dependencies');
  static const roleDependencies = ArchitectureCode('role_dependencies');
  static const dependOnContracts = ArchitectureCode('depend_on_contracts');
  static const constructorInjection = ArchitectureCode('constructor_injection');
  static const forbiddenSymbols = ArchitectureCode('forbidden_symbols');
  static const unverifiableDependency = ArchitectureCode('unverifiable_dependency');
  ArchitecturePolicy()
    : super(name: 'architecture', description: 'Enforce the configured architecture.');
  @override
  List<DiagnosticCode> get diagnosticCodes => [
    invalidConfiguration,
    unclassifiedSource,
    ambiguousLayer,
    layerDependencies,
    roleDependencies,
    dependOnContracts,
    constructorInjection,
    forbiddenSymbols,
    unverifiableDependency,
  ];
  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) =>
      registry.addCompilationUnit(this, _Visitor(this, context));
}

class _Visitor extends SimpleAstVisitor<void> {
  final ArchitecturePolicy rule;
  final RuleContext context;
  _Visitor(this.rule, this.context);
  @override
  void visitCompilationUnit(CompilationUnit unit) {
    final root = context.package?.root ?? _root();
    final file = root.getFile('clear_dart_lints.yaml');
    ArchitectureConfiguration config;
    try {
      if (!file.exists) throw const FormatException('Missing clear_dart_lints.yaml.');
      config = ArchitectureConfiguration.parse(file.readAsStringSync(), root: root.path);
    } on Object catch (e) {
      rule.reportAtOffset(
        0,
        0,
        diagnosticCode: ArchitecturePolicy.invalidConfiguration,
        arguments: ['Invalid architecture configuration: $e'],
      );
      return;
    }
    final path = context.currentUnit!.file.path;
    if (!config.includes(path) || config.excluded(path)) return;
    final source = config.layersFor(path);
    if (source.isEmpty) {
      rule.reportAtOffset(
        0,
        0,
        diagnosticCode: ArchitecturePolicy.unclassifiedSource,
        arguments: ['${config.relative(path)} has no layer; add a matching layer path.'],
      );
      return;
    }
    if (source.length != 1) {
      rule.reportAtOffset(
        0,
        0,
        diagnosticCode: ArchitecturePolicy.ambiguousLayer,
        arguments: [
          '${config.relative(path)} matches layers ${source.join(', ')}; choose exactly one.',
        ],
      );
      return;
    }
    final seen = <String>{};
    void report(AstNode node, ArchitectureCode code, String message) {
      if (!config.excepted(code.lowerCaseName, path) &&
          seen.add('${code.lowerCaseName}:${node.offset}')) {
        rule.reportAtNode(node, diagnosticCode: code, arguments: [message]);
      }
    }

    final converter = context.libraryElement!.session.uriConverter;
    String? packageName;
    try {
      final manifest = root.getFile('pubspec.yaml');
      if (manifest.exists) {
        final yaml = loadYaml(manifest.readAsStringSync());
        if (yaml is Map && yaml['name'] is String) packageName = yaml['name'] as String;
      }
    } on Object {
      // Invalid package metadata is separately diagnosed by the analyzer.
    }
    bool isLocal(String? path) {
      if (path == null) return false;
      final canonical = converter.pathToUri(path);
      if (canonical?.scheme == 'package' && packageName != null) {
        return canonical!.pathSegments.first == packageName;
      }
      return p.isWithin(root.path, path);
    }

    // A directly approved external public library grants access to its exported
    // declarations. It cannot grant access to local package layers.
    final approvedExternalDeclarations = <String>{};
    bool allowedLayer(Uri uri, String? target) {
      final local = isLocal(target);
      final layers = local ? config.layersFor(target!) : <String>{};
      return config.rules.layerDependencies.any(
        (a) =>
            a.from.any(source.contains) &&
            (local
                ? layers.length == 1 && a.to.contains(layers.single)
                : matchesPatterns(a.uris, uri.toString()) ||
                      target != null && approvedExternalDeclarations.contains(target)),
      );
    }

    final base = context.currentUnit!.file.toUri();
    for (final d in unit.directives) {
      final literals = switch (d) {
        ImportDirective() => [d.uri, ...d.configurations.map((c) => c.uri)],
        ExportDirective() => [d.uri, ...d.configurations.map((c) => c.uri)],
        PartDirective() => [d.uri],
        _ => <StringLiteral>[],
      };
      for (final literal in literals) {
        final text = literal.stringValue;
        if (text == null) continue;
        final uri = base.resolve(text);
        final target = converter.uriToPath(uri);
        if (target == null && uri.scheme != 'dart') {
          report(
            literal,
            ArchitecturePolicy.unverifiableDependency,
            'Cannot resolve dependency $text from ${config.relative(path)}.',
          );
          continue;
        }
        final local = isLocal(target);
        if (!local &&
            config.rules.layerDependencies.any(
              (a) => a.from.any(source.contains) && matchesPatterns(a.uris, uri.toString()),
            )) {
          approvedExternalDeclarations.addAll(
            dependencies(
              context,
              uri,
            ).map((d) => d.path).whereType<String>().where((path) => !isLocal(path)),
          );
        }
        final targets = local
            ? dependencies(context, uri, traverse: isLocal)
            : [Dependency(uri, target)];
        for (final dep in targets) {
          if (!allowedLayer(dep.uri, dep.path)) {
            report(
              literal,
              ArchitecturePolicy.layerDependencies,
              '${source.single} cannot depend on ${dep.uri} under layer_dependencies.',
            );
            break;
          }
        }
      }
    }
    bool hasRole(DartType? type, List<String> roles) {
      for (final element in referencedTypes(type)) {
        final candidates = [element.thisType, ...element.thisType.allSupertypes];
        for (final candidate in candidates) {
          final e = candidate.element;
          final uri = e.library.uri.toString();
          final declaration = e.firstFragment.libraryFragment.source.fullName;
          for (final name in roles) {
            final spec = config.roles[name]!;
            if (matchesPatterns(spec.paths, config.relative(declaration)) ||
                (matchesPatterns(spec.names, e.name ?? '') &&
                    (matchesPatterns(spec.libraries, uri) ||
                        matchesPatterns(spec.libraries, config.relative(declaration))))) {
              return true;
            }
            for (final identity in spec.types) {
              if (identity.name != e.name) continue;
              if (identity.library == uri) return true;
              final resolved = Uri.tryParse(identity.library);
              if (resolved != null &&
                  dependencies(context, resolved).any((d) => d.path == declaration)) {
                return true;
              }
            }
          }
        }
      }
      return false;
    }

    bool selected(List<String> layers) => layers.any(source.contains);
    bool rootMatch(List<String> roots) => matchesPatterns(roots, config.relative(path));
    unit.accept(
      RoleUsage((node, type, element) {
        final inheritance =
            node.thisOrAncestorOfType<ExtendsClause>() != null ||
            node.thisOrAncestorOfType<ImplementsClause>() != null ||
            node.thisOrAncestorOfType<WithClause>() != null;
        // A public barrel can expose symbols declared in another layer or library.
        final libraries = {
          if (element?.library case final library?) library,
          for (final e in referencedTypes(type)) e.library,
        };
        for (final library in libraries) {
          final target = library.firstFragment.source.fullName;
          if (target != path && !allowedLayer(library.uri, target)) {
            report(
              node,
              ArchitecturePolicy.layerDependencies,
              '${source.single} cannot use a declaration from ${library.uri} under layer_dependencies.',
            );
          }
        }
        final owner = enclosingClass(node);
        final rd = config.rules.roleDependencies;
        if (!inheritance && rd != null && !rootMatch(rd.compositionRoots)) {
          for (final restriction in rd.restrictions) {
            if (selected(restriction.sourceLayers) &&
                hasRole(type, restriction.dependencyRoles) &&
                !hasRole(owner?.thisType, restriction.allowedConsumerRoles) &&
                !(owner != null && referencedTypes(type).any((e) => e == owner))) {
              report(
                node,
                ArchitecturePolicy.roleDependencies,
                '${source.single} consumer ${owner?.name ?? '<top-level>'} cannot access ${type ?? element?.name ?? '<unresolved>'} (dependency roles: ${restriction.dependencyRoles.join(', ')}; allowed consumer roles: ${restriction.allowedConsumerRoles.isEmpty ? '<none>' : restriction.allowedConsumerRoles.join(', ')}).',
              );
            }
          }
        }
        final contract = config.rules.dependOnContracts;
        if (!inheritance &&
            contract != null &&
            selected(contract.sourceLayers) &&
            !rootMatch(contract.compositionRoots) &&
            (node is NamedType || node is InstanceCreationExpression) &&
            type is InterfaceType &&
            type.element is ClassElement &&
            hasRole(type.element.thisType, contract.dependencyRoles) &&
            !(type.element as ClassElement).isAbstract) {
          report(
            node,
            ArchitecturePolicy.dependOnContracts,
            'Depend on an abstract contract for ${type.element.name}.',
          );
        }
        final injection = config.rules.constructorInjection;
        if (!inheritance &&
            injection != null &&
            selected(injection.sourceLayers) &&
            !rootMatch(injection.compositionRoots) &&
            hasRole(type, injection.dependencyRoles)) {
          if (node is InstanceCreationExpression ||
              node is MethodInvocation ||
              node is FunctionExpressionInvocation) {
            report(
              node,
              ArchitecturePolicy.constructorInjection,
              '${owner?.name ?? '<top-level>'} must acquire ${type ?? element?.name ?? '<unresolved>'} through a constructor parameter.',
            );
          }
          if (node is NamedType) {
            final parameter = node.thisOrAncestorOfType<FormalParameter>();
            if (parameter != null &&
                parameter.thisOrAncestorOfType<ConstructorDeclaration>() == null) {
              report(
                node,
                ArchitecturePolicy.constructorInjection,
                '${owner?.name ?? '<top-level>'} must receive $type through a constructor parameter.',
              );
            }
            final field = node.thisOrAncestorOfType<FieldDeclaration>();
            if (field != null && !_injected(field)) {
              report(
                node,
                ArchitecturePolicy.constructorInjection,
                '${owner?.name ?? '<top-level>'} must inject $type through every constructor.',
              );
            }
          }
        }
        final forbidden = config.rules.forbiddenSymbols;
        if (forbidden != null && selected(forbidden.sourceLayers)) {
          final baseElement = element?.baseElement;
          final parent = baseElement?.enclosingElement;
          if (forbidden.symbols.any(
            (s) =>
                (s.library == baseElement?.library?.uri.toString() &&
                    (s.name == baseElement?.name ||
                        parent is InterfaceElement && s.name == parent.name)) ||
                referencedTypes(type)
                    .any((e) => e.library.uri.toString() == s.library && e.name == s.name),
          )) {
            report(
              node,
              ArchitecturePolicy.forbiddenSymbols,
              '${source.single} cannot use the forbidden symbol ${baseElement?.name ?? type}; replace it with an allowed API.',
            );
          }
        }
      }),
    );
    final injection = config.rules.constructorInjection;
    if (injection != null &&
        selected(injection.sourceLayers) &&
        !rootMatch(injection.compositionRoots)) {
      unit.accept(
        _FieldVisitor((field) {
          if (!_injected(field) &&
              field.fields.variables.any(
                (variable) =>
                    hasRole(variable.declaredFragment?.element.type, injection.dependencyRoles),
              )) {
            report(
              field,
              ArchitecturePolicy.constructorInjection,
              '${field.thisOrAncestorOfType<ClassDeclaration>()?.declaredFragment?.element.name ?? '<top-level>'} must inject ${field.fields.variables.map((variable) => variable.declaredFragment?.element.type).join(', ')} through every constructor.',
            );
          }
        }),
      );
    }
    unit.accept(
      _UnverifiableVisitor(
        (node) => report(
          node,
          ArchitecturePolicy.unverifiableDependency,
          'Cannot verify dynamic or unresolved dependency in ${config.relative(path)}.',
        ),
      ),
    );
  }

  dynamic _root() {
    var folder = context.definingUnit.file.parent;
    while (!folder.getFile('pubspec.yaml').exists && folder.parent.path != folder.path) {
      folder = folder.parent;
    }
    return folder;
  }
}

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
          )) {
            return true;
          }
          final assignments = _Assignments(variable.declaredFragment!.element, element);
          final constructorBody = constructor.body;
          if (constructorBody is BlockFunctionBody) {
            for (final statement in constructorBody.block.statements) {
              if (statement is ExpressionStatement &&
                  statement.expression is AssignmentExpression) {
                assignments.visitAssignmentExpression(statement.expression as AssignmentExpression);
              }
            }
          }
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
        right.element?.enclosingElement == constructor) {
      injected = true;
    }
  }
}

class _UnverifiableVisitor extends RecursiveAstVisitor<void> {
  final void Function(AstNode) report;
  _UnverifiableVisitor(this.report);
  bool dynamicTarget(Expression? expression) => expression?.staticType is DynamicType;
  @override
  void visitNamedType(NamedType node) {
    if (node.element == null && node.name.lexeme != 'dynamic' && node.name.lexeme != 'void') {
      report(node);
    }
    super.visitNamedType(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (dynamicTarget(node.function)) report(node);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (dynamicTarget(node.realTarget) || node.methodName.element == null) report(node.methodName);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (dynamicTarget(node.realTarget) || node.propertyName.element == null) {
      report(node.propertyName);
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (dynamicTarget(node.prefix) || node.identifier.element == null) report(node.identifier);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    if (dynamicTarget(node.realTarget) || node.element == null) report(node);
    super.visitIndexExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    if (!node.inDeclarationContext() &&
        node.element == null &&
        parent is! MethodInvocation &&
        parent is! PropertyAccess &&
        parent is! PrefixedIdentifier &&
        parent is! NamedType &&
        parent is! Label) {
      report(node);
    }
    super.visitSimpleIdentifier(node);
  }
}

class _FieldVisitor extends RecursiveAstVisitor<void> {
  final void Function(FieldDeclaration) check;
  _FieldVisitor(this.check);
  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    // Explicit types are checked at their type location by RoleUsage.
    if (node.fields.type == null) check(node);
    super.visitFieldDeclaration(node);
  }
}
