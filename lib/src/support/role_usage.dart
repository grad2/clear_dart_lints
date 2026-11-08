import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

DartType? elementType(Element? element) => switch (element) {
  VariableElement() => element.type,
  ExecutableElement() => element.returnType,
  InterfaceElement() => element.thisType,
  _ => null,
};

class RoleUsage extends RecursiveAstVisitor<void> {
  final void Function(AstNode, DartType?, Element?) check;
  RoleUsage(this.check);
  @override
  void visitNamedType(NamedType node) {
    check(node, node.type, node.element);
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    if (!node.inDeclarationContext() &&
        !(parent is MethodInvocation && identical(parent.methodName, node))) {
      check(node, elementType(node.element), node.element);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    check(node, node.staticType, node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    check(node, node.staticType, null);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    check(node, node.staticType, node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }
}

InterfaceElement? enclosingClass(AstNode node) =>
    node.thisOrAncestorOfType<ClassDeclaration>()?.declaredFragment?.element;

/// A provider factory belongs to its top-level function or variable, including
/// nested callbacks. A class remains the owner of its methods and fields.
Element? enclosingConsumer(AstNode node) {
  for (AstNode? current = node; current != null; current = current.parent) {
    if (current is ClassDeclaration) return current.declaredFragment?.element;
    if (current is ClassTypeAlias) return current.declaredFragment?.element;
    if (current is FunctionDeclaration && current.parent is CompilationUnit) {
      return current.declaredFragment?.element;
    }
    if (current is VariableDeclaration && current.parent?.parent is TopLevelVariableDeclaration) {
      return current.declaredFragment?.element;
    }
  }
  return null;
}
