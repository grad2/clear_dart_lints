import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' show DiagnosticMessage;
// DiagnosticMessage has no public constructor; keep compatibility access here.
import 'package:analyzer/src/diagnostic/diagnostic.dart' show DiagnosticMessageImpl;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../support/api_checks.dart';
import '../support/dependencies.dart';
import '../support/role_usage.dart';
import 'configuration.dart';

class ArchitectureCode extends DiagnosticCode {
  const ArchitectureCode(
    String name, [
    String correction = 'Review the configured architecture boundary.',
  ]) : super(
         name: name,
         uniqueName: 'Architecture.$name',
         problemMessage: '{0}',
         correctionMessage: correction,
       );
  @override
  DiagnosticSeverity get severity => DiagnosticSeverity.WARNING;
  @override
  DiagnosticType get type => DiagnosticType.STATIC_WARNING;
}

class ArchitecturePolicy extends MultiAnalysisRule {
  static const invalidConfiguration = ArchitectureCode(
    'invalid_configuration',
    'Correct the indicated policy key using schema 2.',
  );
  static const unclassifiedSource = ArchitectureCode(
    'unclassified_source',
    'Place the file in one configured layer or add a disjoint layer selector.',
  );
  static const ambiguousLayer = ArchitectureCode(
    'ambiguous_layer',
    'Make the matching layer path selectors disjoint.',
  );
  static const layerDependencies = ArchitectureCode(
    'layer_dependencies',
    'Use a contract in an allowed layer; review the policy before adding an edge.',
  );
  static const roleDependencies = ArchitectureCode(
    'role_dependencies',
    'Move dependency access to an allowed consumer role and inject the result.',
  );
  static const dependOnContracts = ArchitectureCode(
    'depend_on_contracts',
    'Declare and inject an abstract dependency contract.',
  );
  static const constructorInjection = ArchitectureCode(
    'constructor_injection',
    'Receive dependencies through every constructor; assemble them in a composition root.',
  );
  static const forbiddenSymbols = ArchitectureCode(
    'forbidden_symbols',
    'Replace the symbol with an approved API or move its use to an allowed layer.',
  );
  static const unverifiableDependency = ArchitectureCode(
    'unverifiable_dependency',
    'Resolve imports and replace dynamic dependency access with static types.',
  );
  static const featureDependencies = ArchitectureCode(
    'feature_dependencies',
    'Use the feature public boundary or explicitly review a directed feature permission.',
  );
  static const unclassifiedFeature = ArchitectureCode(
    'unclassified_feature',
    'Assign the file to a feature, shared path or composition root.',
  );
  static const ambiguousFeature = ArchitectureCode(
    'ambiguous_feature',
    'Make feature, shared and composition-root selectors disjoint.',
  );
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
    featureDependencies,
    unclassifiedFeature,
    ambiguousFeature,
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
    String? policyContent;
    try {
      if (!file.exists) throw const FormatException('Missing clear_dart_lints.yaml.');
      final String content = file.readAsStringSync();
      policyContent = content;
      config = ArchitectureConfiguration.parse(content, root: root.path);
    } on Object catch (e) {
      rule.reportAtOffset(
        0,
        0,
        diagnosticCode: ArchitecturePolicy.invalidConfiguration,
        arguments: ['Invalid architecture configuration: $e'],
        contextMessages: _invalidPolicyMessages(file.path, policyContent, e),
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
        arguments: ['${config.relative(path)} has no layer; policy: layers.'],
        contextMessages: _policyMessages(config, 'layers'),
      );
      return;
    }
    if (source.length != 1) {
      rule.reportAtOffset(
        0,
        0,
        diagnosticCode: ArchitecturePolicy.ambiguousLayer,
        arguments: [
          '${config.relative(path)} matches layers ${source.join(', ')}; policy: layers; choose exactly one.',
        ],
        contextMessages: _policyMessages(config, 'layers'),
      );
      return;
    }
    final seen = <String>{};
    void report(
      AstNode node,
      ArchitectureCode code,
      String message, {
      String? target,
      Element? declaration,
      String? policyKey,
    }) {
      declaration ??= switch (node) {
        NamedType() => node.element,
        SimpleIdentifier() => node.element,
        InstanceCreationExpression() => node.constructorName.element,
        MethodInvocation() => node.methodName.element,
        _ => null,
      };
      target ??= declaration?.firstFragment.libraryFragment?.source.fullName;
      final key =
          policyKey ??
          (code == ArchitecturePolicy.unverifiableDependency
              ? 'include'
              : 'rules.${code.lowerCaseName}');
      final targetLayers = target == null ? <String>{} : config.layersFor(target);
      final detail = target == null
          ? ''
          : ' Target: ${config.relative(target)} (layer: ${targetLayers.isEmpty ? '<external or unclassified>' : targetLayers.join(', ')}).';

      if (!config.excepted(code.lowerCaseName, path) &&
          seen.add('${code.lowerCaseName}:${node.offset}')) {
        rule.reportAtNode(
          node,
          diagnosticCode: code,
          arguments: [
            '$message Source: ${config.relative(path)} (layer: ${source.single}).$detail Policy: $key.',
          ],
          contextMessages: [
            ..._policyMessages(config, key),
            if (target != null)
              DiagnosticMessageImpl(
                filePath: target,
                offset: declaration?.firstFragment.nameOffset ?? 0,
                length: declaration?.name?.length ?? 0,
                message: 'Dependency declared here.',
                url: null,
              ),
          ],
        );
      }
    }

    final features = config.rules.featureDependencies;
    final membership = features?.membership(config.relative(path));
    if (membership != null && !membership.valid) {
      report(
        unit,
        membership.count == 0
            ? ArchitecturePolicy.unclassifiedFeature
            : ArchitecturePolicy.ambiguousFeature,
        'Expected exactly one feature scope, found ${membership.count}: ${membership.description}.',
        policyKey: 'rules.feature_dependencies',
      );
      return;
    }
    void checkFeature(AstNode node, String target, {Element? declaration}) {
      if (features == null) return;
      final other = features.membership(config.relative(target));
      if (!other.valid) {
        report(
          node,
          other.count == 0
              ? ArchitecturePolicy.unclassifiedFeature
              : ArchitecturePolicy.ambiguousFeature,
          'Dependency target must have exactly one feature scope, found ${other.count}.',
          target: target,
          declaration: declaration,
          policyKey: 'rules.feature_dependencies',
        );
      } else if (!features.permits(membership!, other)) {
        report(
          node,
          ArchitecturePolicy.featureDependencies,
          'Feature scope ${membership.description} cannot depend on ${other.description}.',
          target: target,
          declaration: declaration,
        );
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
          if (isLocal(dep.path)) checkFeature(literal, dep.path!);
          if (!allowedLayer(dep.uri, dep.path)) {
            report(
              literal,
              ArchitecturePolicy.layerDependencies,
              '${source.single} cannot depend on ${dep.uri} under layer_dependencies.',
              target: dep.path,
              policyKey: 'rules.layer_dependencies.allowed',
            );
          }
        }
      }
    }
    bool declarationHasRole(Element? element, List<String> roles) {
      if (element == null) return false;
      // Declaration selectors describe types and top-level provider declarations,
      // not every parameter or member declared in the same physical file.
      if (element is! InterfaceElement && element.enclosingElement is! LibraryElement) return false;
      final uri = element.library?.uri.toString() ?? '';
      final declaration = element.firstFragment.libraryFragment?.source.fullName;
      if (declaration == null) return false;
      return roles.any((name) {
        final spec = config.roles[name]!;
        return matchesPatterns(spec.paths, config.relative(declaration)) ||
            matchesPatterns(spec.names, element.name ?? '') &&
                (matchesPatterns(spec.libraries, uri) ||
                    matchesPatterns(spec.libraries, config.relative(declaration)));
      });
    }

    bool hasRole(DartType? type, List<String> roles, {bool nested = true}) {
      final elements = nested ? referencedTypes(type) : [if (type is InterfaceType) type.element];
      for (final element in elements) {
        final candidates = [element.thisType, ...element.thisType.allSupertypes];
        for (final candidate in candidates) {
          final e = candidate.element;
          final uri = e.library.uri.toString();
          final declaration = e.firstFragment.libraryFragment.source.fullName;
          for (final name in roles) {
            final spec = config.roles[name]!;
            if (declarationHasRole(e, [name])) return true;
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
        final inheritance = _isInheritance(node);
        // A public barrel can expose symbols declared in another layer or library.
        final declarations = {if (element != null) element, ...referencedTypes(type)};
        for (final declaration in declarations) {
          final target = declaration.firstFragment.libraryFragment?.source.fullName;
          final library = declaration.library;
          if (target == null || target == path) continue;
          if (isLocal(target)) checkFeature(node, target, declaration: declaration);
          if (library != null && !allowedLayer(library.uri, target)) {
            report(
              node,
              ArchitecturePolicy.layerDependencies,
              '${source.single} cannot use a declaration from ${library.uri} under layer_dependencies.',
              target: target,
              declaration: declaration,
              policyKey: 'rules.layer_dependencies.allowed',
            );
          }
        }
        final owner = enclosingConsumer(node);
        final ownerType = owner is InterfaceElement ? owner.thisType : null;
        final rd = config.rules.roleDependencies;
        if (!inheritance && rd != null && !rootMatch(rd.compositionRoots)) {
          for (final (index, restriction) in rd.restrictions.indexed) {
            if (selected(restriction.sourceLayers) &&
                (hasRole(type, restriction.dependencyRoles) ||
                    declarationHasRole(element, restriction.dependencyRoles)) &&
                !(owner is InterfaceElement
                    ? hasRole(ownerType, restriction.allowedConsumerRoles, nested: false)
                    : declarationHasRole(owner, restriction.allowedConsumerRoles)) &&
                !(owner != null && referencedTypes(type).any((e) => e == owner))) {
              report(
                node,
                ArchitecturePolicy.roleDependencies,
                '${source.single} consumer ${owner?.name ?? '<top-level>'} cannot access ${type ?? element?.name ?? '<unresolved>'} (dependency roles: ${restriction.dependencyRoles.join(', ')}; allowed consumer roles: ${restriction.allowedConsumerRoles.isEmpty ? '<none>' : restriction.allowedConsumerRoles.join(', ')}).',
                declaration:
                    referencedTypes(type)
                        .where(
                          (e) => hasRole(e.thisType, restriction.dependencyRoles, nested: false),
                        )
                        .firstOrNull ??
                    element,
                policyKey: 'rules.role_dependencies.restrictions[$index]',
              );
            }
          }
        }
        final contract = config.rules.dependOnContracts;
        if (!inheritance &&
            contract != null &&
            selected(contract.sourceLayers) &&
            !rootMatch(contract.compositionRoots) &&
            (node is NamedType ||
                node is InstanceCreationExpression ||
                node is MethodInvocation ||
                node is FunctionExpressionInvocation)) {
          for (final dependency in referencedTypes(type).whereType<ClassElement>()) {
            if (!dependency.isAbstract &&
                hasRole(dependency.thisType, contract.dependencyRoles, nested: false)) {
              report(
                node,
                ArchitecturePolicy.dependOnContracts,
                'Depend on an abstract contract for ${dependency.name}.',
                declaration: dependency,
              );
            }
          }
        }
        final injection = config.rules.constructorInjection;
        if (!inheritance &&
            injection != null &&
            selected(injection.sourceLayers) &&
            !rootMatch(injection.compositionRoots) &&
            hasRole(type, injection.dependencyRoles, nested: node is! InstanceCreationExpression)) {
          if (node is InstanceCreationExpression ||
              node is MethodInvocation ||
              node is FunctionExpressionInvocation) {
            if (!(injection.allowProviderReads && _providerRead(node))) {
              report(
                node,
                ArchitecturePolicy.constructorInjection,
                '${owner?.name ?? '<top-level>'} must acquire ${type ?? element?.name ?? '<unresolved>'} through a constructor parameter${injection.allowProviderReads ? ' or Riverpod Ref.read/watch' : ''}.',
              );
            }
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
            if (field != null &&
                !_injected(field, allowProviderReads: injection.allowProviderReads)) {
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
              declaration: baseElement ?? referencedTypes(type).firstOrNull,
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
          if (!_injected(field, allowProviderReads: injection.allowProviderReads) &&
              field.fields.variables.any(
                (variable) =>
                    hasRole(variable.declaredFragment?.element.type, injection.dependencyRoles),
              )) {
            report(
              field,
              ArchitecturePolicy.constructorInjection,
              '${field.thisOrAncestorOfType<ClassDeclaration>()?.declaredFragment?.element.name ?? '<top-level>'} must inject ${field.fields.variables.map((variable) => variable.declaredFragment?.element.type).join(', ')} through every constructor.',
              declaration: field.fields.variables
                  .expand((v) => referencedTypes(v.declaredFragment?.element.type))
                  .where((e) => hasRole(e.thisType, injection.dependencyRoles, nested: false))
                  .firstOrNull,
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

bool _isInheritance(AstNode node) {
  for (AstNode? current = node; current != null; current = current.parent) {
    if (current is ExtendsClause || current is ImplementsClause || current is WithClause) {
      return true;
    }
    final parent = current.parent;
    if (parent is ClassTypeAlias && identical(parent.superclass, current)) return true;
  }
  return false;
}

bool _providerRead(AstNode node) {
  if (node is! MethodInvocation || !{'read', 'watch'}.contains(node.methodName.name)) return false;
  final method = node.methodName.element;
  final receiver = node.realTarget?.staticType;
  return method != null &&
      (method.library?.uri.toString().startsWith('package:riverpod/') ?? false) &&
      receiver is InterfaceType &&
      [receiver, ...receiver.allSupertypes].any(
        (type) =>
            type.element.name == 'Ref' &&
            type.element.library.uri.toString().startsWith('package:riverpod/'),
      );
}

bool _injected(FieldDeclaration field, {bool allowProviderReads = false}) {
  if (allowProviderReads &&
      field.fields.variables.every((variable) {
        final initializer = variable.initializer;
        return initializer != null && _providerRead(unparenthesized(initializer));
      })) {
    return true;
  }
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

bool _resolvedWrite(Expression node) {
  final parent = node.parent;
  return switch (parent) {
    AssignmentExpression() => identical(parent.leftHandSide, node) && parent.writeElement != null,
    PostfixExpression() =>
      identical(parent.operand, node) && parent.readElement != null && parent.writeElement != null,
    PrefixExpression() =>
      identical(parent.operand, node) && parent.readElement != null && parent.writeElement != null,
    _ => false,
  };
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
    if (dynamicTarget(node.realTarget) ||
        node.propertyName.element == null && !_resolvedWrite(node)) {
      report(node.propertyName);
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (dynamicTarget(node.prefix) || node.identifier.element == null && !_resolvedWrite(node)) {
      report(node.identifier);
    }
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
        !_resolvedWrite(node) &&
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

List<DiagnosticMessage> _policyMessages(ArchitectureConfiguration config, String key) {
  final location = config.locations[key];
  return [
    if (location != null)
      DiagnosticMessageImpl(
        filePath: p.join(config.root, 'clear_dart_lints.yaml'),
        offset: location.offset,
        length: location.length,
        message: 'Policy: $key (${location.line}:${location.column}).',
        url: null,
      ),
  ];
}

List<DiagnosticMessage> _invalidPolicyMessages(String path, String? content, Object error) {
  if (content == null) return [];
  try {
    var node = loadYamlNode(content);
    final key = RegExp(
      r'(?:schema_version|include|exclude|layers|roles|rules|exceptions)(?:\.[a-zA-Z0-9_]+)*',
    ).firstMatch(error.toString())?.group(0);
    if (key != null) {
      for (final part in key.split('.')) {
        if (node is! YamlMap) break;
        final child = node.nodes.entries.where((e) => e.key.value == part).firstOrNull?.value;
        if (child == null) break;
        node = child;
      }
    }
    return [
      DiagnosticMessageImpl(
        filePath: path,
        offset: node.span.start.offset,
        length: node.span.length,
        message: 'Correct architecture policy${key == null ? '' : ' key $key'}.',
        url: null,
      ),
    ];
  } on YamlException catch (yamlError) {
    final span = yamlError.span;
    return [
      DiagnosticMessageImpl(
        filePath: path,
        offset: span?.start.offset ?? 0,
        length: span?.length ?? 0,
        message: 'Correct invalid YAML here.',
        url: null,
      ),
    ];
  }
}
