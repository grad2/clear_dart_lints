import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';

bool overridesContract(ExecutableElement? element) {
  final owner = element?.enclosingElement;
  return owner is InterfaceElement &&
      owner.getOverridden(Name(element!.library.uri, element.lookupName!)) != null;
}

bool publicApi(ExecutableElement? element) {
  if (element == null || element.isPrivate || overridesContract(element)) return false;
  final owner = element.enclosingElement;
  return owner is LibraryElement ||
      owner is InterfaceElement && !owner.isPrivate ||
      owner is ExtensionElement && !owner.isPrivate;
}

bool standardNullable(DartType? type, Set<String> names, String uri) =>
    type is InterfaceType &&
    type.nullabilitySuffix == NullabilitySuffix.question &&
    names.contains(type.element.name) &&
    type.element.library.uri.toString() == uri;

bool flutterWidget(DartType? type) =>
    type is InterfaceType &&
    [type, ...type.allSupertypes].any(
      (t) =>
          t.element.name == 'Widget' &&
          t.element.library.uri.toString().startsWith('package:flutter/'),
    );

Expression unparenthesized(Expression expression) {
  while (expression is ParenthesizedExpression) {
    expression = expression.expression;
  }
  return expression;
}

/// Follow resolved typedef expansion, including nested generic containers.
Iterable<InterfaceElement> referencedTypes(DartType? type) sync* {
  if (type is InterfaceType) {
    yield type.element;
    for (final argument in type.typeArguments) {
      yield* referencedTypes(argument);
    }
  } else if (type is FunctionType) {
    yield* referencedTypes(type.returnType);
    for (final parameter in type.formalParameters) {
      yield* referencedTypes(parameter.type);
    }
  }
}
