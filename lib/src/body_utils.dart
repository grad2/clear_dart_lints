import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dart_style/dart_style.dart';

/// Resolves includes and per-directory options using the analyzer itself.
int pageWidthFor(ResolvedUnitResult result) =>
    result.analysisOptions.formatterOptions.pageWidth ?? 80;

bool _flutterType(DartType? type, String name) {
  if (type is! InterfaceType) return false;
  return [type, ...type.allSupertypes].any((candidate) {
    final element = candidate.element;
    return element.name == name &&
        element.library.uri.scheme == 'package' &&
        element.library.uri.path.startsWith('flutter/');
  });
}

bool isFlutterBuilder(ExpressionFunctionBody body) {
  final owner = body.parent;
  if (owner is MethodDeclaration) {
    final element = owner.declaredFragment?.element;
    return !owner.isStatic &&
        owner.name.lexeme == 'build' &&
        element != null &&
        _flutterType(element.returnType, 'Widget') &&
        element.formalParameters.length == 1 &&
        _flutterType(element.formalParameters.single.type, 'BuildContext');
  }
  if (owner is! FunctionExpression) return false;
  AstNode argumentValue = owner;
  while (argumentValue.parent is ParenthesizedExpression) {
    argumentValue = argumentValue.parent!;
  }
  final argument = argumentValue.parent;
  if (argument is! NamedArgument) return false;
  final name = argument.name.lexeme;
  if (name != 'builder' && !name.endsWith('Builder')) return false;
  final parameterType = argument.correspondingParameter?.type;
  return parameterType is FunctionType && _flutterType(parameterType.returnType, 'Widget');
}

AstNode functionOwner(ExpressionFunctionBody body) {
  final parent = body.parent!;
  if (parent is FunctionExpression && parent.parent is FunctionDeclaration) {
    return parent.parent!;
  }
  return parent;
}

/// Formats a copy at a very large width, preserving lexical string contents.
/// Returns null when a single-line representation is impossible.
int? singleLineLength(ExpressionFunctionBody body, String content) {
  for (var token = body.beginToken; ; token = token.next!) {
    if (token.precedingComments != null ||
        token.lexeme.contains('\n') ||
        token.lexeme.contains('\r')) {
      return null;
    }
    if (identical(token, body.endToken)) break;
  }
  final owner = functionOwner(body);
  final start = owner is AnnotatedNode
      ? owner.firstTokenAfterCommentAndMetadata.offset
      : owner.offset;
  final source = content.substring(start, owner.end);
  final formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
    pageWidth: 1000000,
  );
  try {
    final String formatted;
    final AstNode normalized;
    if (owner is MethodDeclaration) {
      formatted = formatter.format('class _Measure { $source }');
      final unit = parseString(content: formatted).unit;
      normalized =
          ((unit.declarations.single as ClassDeclaration).body as BlockClassBody).members.single;
    } else if (owner is FunctionDeclaration) {
      formatted = formatter.format(source);
      normalized = parseString(content: formatted).unit.declarations.single;
    } else {
      formatted = formatter.format('final measure = $source;');
      final variables =
          parseString(content: formatted).unit.declarations.single as TopLevelVariableDeclaration;
      normalized = variables.variables.variables.single.initializer!;
    }
    final line = formatted.substring(normalized.offset, normalized.end).trim();
    if (line.contains('\n') || line.contains('\r')) return null;
    final lineStart = start == 0 ? 0 : content.lastIndexOf('\n', start - 1) + 1;
    final prefix = content.substring(lineStart, start);
    final indent = RegExp(r'^\s*').firstMatch(prefix)!.group(0)!.length;
    // A named callback has a stable prefix even if its value starts on a new line.
    final named = owner.parent;
    final labelWidth = named is NamedArgument ? named.name.lexeme.length + 2 : 0;
    return indent + labelWidth + line.length;
  } on FormatterException {
    return null;
  }
}

/// Pure transformation shared by the IDE fix and tests. Only the smallest
/// differing range is eventually sent to the IDE.
String convertToBlock(
  ExpressionFunctionBody body,
  String content, {
  required int pageWidth,
  required bool returnsVoid,
}) {
  final leading = content.substring(body.functionDefinition.end, body.expression.offset);
  final trailing = content.substring(body.expression.end, body.semicolon?.offset ?? body.end);
  final expression = content.substring(body.expression.offset, body.expression.end);
  // Future<void> async functions can discard their result by awaiting it.
  final expressionType = body.expression.staticType;
  final needsAwait =
      body.isAsynchronous &&
      expressionType is! VoidType &&
      expressionType is! NeverType &&
      body.expression is! AwaitExpression;
  final statement = returnsVoid
      ? (needsAwait ? 'await ($expression)' : expression)
      : 'return $expression';
  final replacement = '{\n$leading$statement$trailing;\n}';
  final updated = content.replaceRange(body.functionDefinition.offset, body.end, replacement);
  return DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
    pageWidth: pageWidth,
  ).format(updated);
}

bool discardsResult(ExpressionFunctionBody body) {
  final owner = body.parent;
  DartType? result;
  if (owner is MethodDeclaration) {
    result = owner.declaredFragment?.element.returnType;
  } else if (owner is FunctionExpression) {
    final type = owner.staticType;
    if (type is FunctionType) result = type.returnType;
    result ??= owner.declaredFragment?.element.returnType;
  }
  if (result is VoidType) return true;
  return body.isAsynchronous &&
      result is InterfaceType &&
      result.isDartAsyncFuture &&
      result.typeArguments.single is VoidType;
}
