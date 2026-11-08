import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Recognizes credential formats locally, without checking whether they are valid.
class AvoidHardcodedSecrets extends AnalysisRule {
  static const code = LintCode(
    'avoid_hardcoded_secrets',
    'This string contains a possible hardcoded secret.',
    correctionMessage: 'Remove the credential from source and load it from a secure source.',
  );

  AvoidHardcodedSecrets()
    : super(name: code.lowerCaseName, description: 'Keep recognizable secrets out of source.');

  @override
  bool get canUseParsedResult => true;

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    // No architecture policy or generated-file filtering applies to security.
    registry.addCompilationUnit(this, _Visitor(this));
  }
}

// Adapted from Gitleaks' github-pat, github-fine-grained-pat, gitlab-pat,
// gitlab-pat-routable, openai-api-key, stripe-access-token, slack-bot-token,
// slack-user-token and private-key rules (consulted 2026-11-08):
// https://github.com/gitleaks/gitleaks/blob/master/config/gitleaks.toml
// Copyright (c) 2019 Zachary Rice. MIT license: third_party/gitleaks.LICENSE.
// Match decoded Dart values, with explicit ASCII token boundaries. Deliberately
// omit entropy and provider-agnostic heuristics; these are format checks only.
final _tokens = [
  r'ghp_[A-Za-z0-9]{36}',
  r'github_pat_[A-Za-z0-9_]{82}',
  r'glpat-(?:[A-Za-z0-9_-]{27,300}\.[0-9a-z]{9}|[A-Za-z0-9_-]{20})',
  r'sk-(?:(?:proj|svcacct|admin)-(?:[A-Za-z0-9_-]{74}|[A-Za-z0-9_-]{58})'
      r'T3BlbkFJ(?:[A-Za-z0-9_-]{74}|[A-Za-z0-9_-]{58})'
      r'|[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20})',
  r'(?:sk|rk)_(?:test|live|prod)_[A-Za-z0-9]{10,99}',
  r'xoxb-[0-9]{10,13}-[0-9]{10,13}[A-Za-z0-9-]*',
  r'xox[pe](?:-[0-9]{10,13}){3}-[A-Za-z0-9-]{28,34}',
].map((pattern) => RegExp('(?:^|[^A-Za-z0-9_-])(?:$pattern)(?![A-Za-z0-9_-])')).toList();

// Require a complete block and matching labels, rather than just a BEGIN marker.
final _privateKey = RegExp(
  r'-----BEGIN ((?:(?:RSA|EC|DSA|ENCRYPTED|OPENSSH) )?PRIVATE KEY)-----'
  r'([\s\S]{64,}?)-----END \1-----',
);
final _whitespace = RegExp(r'\s');

bool _containsSecret(String value) {
  return _tokens.any((pattern) => pattern.hasMatch(value)) ||
      _privateKey
          .allMatches(value)
          .any((match) => match.group(2)!.replaceAll(_whitespace, '').length >= 64);
}

/// Coalesces adjacent static text, but never joins across an interpolation hole.
Iterable<String> _staticFragments(StringLiteral literal) sync* {
  var buffer = StringBuffer();
  final fragments = <String>[];
  void append(StringLiteral node) {
    switch (node) {
      case SimpleStringLiteral():
        buffer.write(node.value);
      case AdjacentStrings():
        for (final string in node.strings) {
          append(string);
        }
      case StringInterpolation():
        for (final element in node.elements) {
          if (element is InterpolationString) {
            buffer.write(element.value);
          } else {
            fragments.add(buffer.toString());
            buffer = StringBuffer();
          }
        }
    }
  }

  append(literal);
  yield* fragments;
  yield buffer.toString();
}

class _Visitor extends RecursiveAstVisitor<void> {
  final AvoidHardcodedSecrets rule;
  _Visitor(this.rule);

  void check(StringLiteral node) {
    // The outer adjacent string checks its combined value exactly once.
    if (node.parent is AdjacentStrings) return;
    if (_staticFragments(node).any(_containsSecret)) rule.reportAtNode(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    check(node);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    check(node);
    super.visitAdjacentStrings(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    check(node);
    // Visit literal expressions inside interpolation holes independently.
    super.visitStringInterpolation(node);
  }
}
