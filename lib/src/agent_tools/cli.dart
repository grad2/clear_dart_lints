import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../architecture/configuration.dart';
import '../setup_verifier.dart';
import 'context.dart';
import 'policy_diff.dart';
import 'result.dart';

const _usages = {
  'context': 'context <path> [--root <package-root>] [--format=text|json]',
  'policy_diff': 'policy_diff --base <git-ref> [package-root] [--format=text|json]',
  'verify_setup': 'verify_setup [package-root] [--format=text|json]',
};

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

/// Shared transport only: architecture diagnostics belong to the analyzer.
Future<void> runAgentTool(String command, List<String> arguments) async {
  final usage = 'Usage: dart run clear_dart_lints:${_usages[command]}';
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(usage);
    stdout.writeln(
      command == 'verify_setup'
          ? 'Read-only setup audit. Follow with dart analyze --format=machine --fatal-infos.'
          : 'Read-only policy tool. This does not run architecture analysis.',
    );
    return;
  }
  var json =
      arguments.contains('--format=json') ||
      arguments.indexed.any(
        (entry) =>
            entry.$2 == '--format' &&
            entry.$1 + 1 < arguments.length &&
            arguments[entry.$1 + 1] == 'json',
      );
  var root = p.normalize(Directory.current.absolute.path);
  Map<String, Object?> data = {};
  List<ToolIssue> issues = [];
  var passed = false;
  var resultCode = 0;
  final lines = <String>[];
  try {
    final options = <String, String>{};
    final positional = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      final arg = arguments[i];
      if (!arg.startsWith('-')) {
        positional.add(arg);
        continue;
      }
      final parts = arg.split('=');
      final name = parts.first;
      final allowed = {
        '--format',
        if (command == 'context') '--root',
        if (command == 'policy_diff') '--base',
      };
      if (!allowed.contains(name) || options.containsKey(name)) {
        throw _Usage('Unknown or repeated option: $name');
      }
      String value;
      if (parts.length > 1) {
        value = parts.skip(1).join('=');
      } else if (i + 1 < arguments.length && !arguments[i + 1].startsWith('-')) {
        value = arguments[++i];
      } else {
        throw _Usage('Missing value for $name');
      }
      if (value.isEmpty) throw _Usage('Missing value for $name');
      options[name] = value;
      if (name == '--format' && value == 'json') json = true;
    }
    if (!{'text', 'json'}.contains(options['--format'] ?? 'text')) {
      throw const _Usage('Format must be text or json.');
    }
    if (positional.length > 1 ||
        command == 'context' && positional.length != 1 ||
        command == 'policy_diff' && !options.containsKey('--base')) {
      throw const _Usage('Missing or unexpected arguments.');
    }
    root = p.normalize(
      p.absolute(command == 'context' ? options['--root'] ?? root : positional.firstOrNull ?? root),
    );
    if (command == 'verify_setup') {
      final result = await verifySetup(root);
      passed = result.passed;
      issues = result.issues;
      data = result.toJson();
      if (passed) {
        lines.add('Setup audit passed: ${result.checkedFiles} Dart files.');
        lines.add(
          'Architecture has not been checked. Run dart analyze --format=machine --fatal-infos.',
        );
      } else {
        lines.add(
          'Setup audit failed. Fix the configuration or documented exceptions, then retry.',
        );
      }
    } else if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
      issues = [
        ToolIssue('missing_package', root, 'Expected a package root containing pubspec.yaml.'),
      ];
    } else {
      final file = File(p.join(root, 'clear_dart_lints.yaml'));
      ArchitectureConfiguration? policy;
      try {
        policy = ArchitectureConfiguration.parse(file.readAsStringSync(), root: root);
      } on Object catch (error) {
        issues = [ToolIssue('invalid_configuration', file.path, error.toString())];
      }
      if (policy != null && command == 'context') {
        FilePolicyContext result;
        try {
          result = inspectFilePolicy(policy, positional.single);
        } on FormatException catch (error) {
          throw _Usage(error.message);
        }
        data = result.toJson();
        issues = result.issues;
        passed = result.passed;
        lines.add('Policy context: ${data['relative_path']}');
        lines.add(
          'Included: ${data['included']}; excluded: ${data['excluded']}; enforced: ${data['enforced']}',
        );
        lines.add('Layers: ${(data['layers'] as List).join(', ')}');
        for (final key in [
          'allowed_dependencies',
          'role_selectors',
          'constraints',
          'exceptions',
          'feature_scope',
          'feature_policy',
        ]) {
          if (data.containsKey(key)) {
            lines.add('$key: ${const JsonEncoder.withIndent('  ').convert(data[key])}');
          }
        }
        lines.add(
          'Role selectors are not resolved type assignments. Architecture has not been checked.',
        );
      } else if (policy != null) {
        Future<String> git(List<String> args) async {
          final result = await Process.run('git', ['-C', root, ...args]);
          if (result.exitCode != 0) {
            throw StateError('Git ${args.first} failed: ${result.stderr.toString().trim()}');
          }
          return result.stdout.toString();
        }

        final base = options['--base']!;
        final commit = (await git(['rev-parse', '--verify', '--end-of-options', '$base^{commit}']))
            .trim();
        final repo = (await git(['rev-parse', '--show-toplevel'])).trim();
        final relative = p
            .relative(
              p.join(Directory(root).resolveSymbolicLinksSync(), 'clear_dart_lints.yaml'),
              from: Directory(repo).resolveSymbolicLinksSync(),
            )
            .replaceAll('\\', '/');
        if (relative.startsWith('../')) throw StateError('Policy is outside the Git repository.');
        final previous = await git(['show', '$commit:$relative']);
        final baseline = ArchitectureConfiguration.parse(previous, root: root);
        final result = comparePolicies(baseline, policy);
        data = {'base_ref': base, 'base_commit': commit, ...result.toJson()};
        issues = result.issues;
        passed = result.passed;
        lines.add('Policy comparison against $commit: ${result.passed ? 'passed' : 'blocked'}.');
        for (final c in result.changes) {
          lines.add(
            '${c.assessmentName}: ${c.key}\n  ${jsonEncode(c.before)} -> ${jsonEncode(c.after)}\n  ${c.reason}',
          );
        }
      }
    }
    resultCode = passed ? 0 : 1;
  } on _Usage catch (error) {
    passed = false;
    resultCode = 64;
    issues = [ToolIssue('invalid_arguments', root, '${error.message}\n$usage')];
  } on Object catch (error) {
    passed = false;
    resultCode = 2;
    issues = [ToolIssue('execution_error', root, error.toString())];
  }
  exitCode = resultCode;
  if (json) {
    stdout.writeln(jsonEncode(toolReport(command, root, passed, data, issues)));
  } else {
    for (final issue in issues) {
      stderr.writeln('${issue.path}: ${issue.message} [${issue.code}]');
    }
    for (final line in lines) {
      (passed || command != 'verify_setup' ? stdout : stderr).writeln(line);
    }
  }
}
