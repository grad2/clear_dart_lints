import 'dart:io';

import 'package:clear_dart_lints/src/setup_verifier.dart';

/// Audits setup and suppression policy; architecture is checked by dart analyze.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln('Usage: dart run clear_dart_lints:verify_setup [package-root]');
    stdout.writeln(
      'Read-only setup audit. Follow with dart analyze --format=machine --fatal-infos.',
    );
    return;
  }
  if (arguments.length > 1 || arguments.any((argument) => argument.startsWith('-'))) {
    stderr.writeln('Usage: dart run clear_dart_lints:verify_setup [package-root]');
    exitCode = 64;
    return;
  }
  final result = await verifySetup(arguments.firstOrNull ?? Directory.current.path);
  for (final issue in result.issues) {
    stderr.writeln('${issue.path}: ${issue.message} [${issue.code}]');
  }
  if (!result.passed) {
    stderr.writeln(
      'Setup audit failed. Fix the configuration or documented exceptions, then retry.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Setup audit passed: ${result.checkedFiles} Dart files.');
  stdout.writeln(
    'Architecture has not been checked. Run dart analyze --format=machine --fatal-infos.',
  );
}
