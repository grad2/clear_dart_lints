import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/file_system/file_system.dart';

import '../architecture/configuration.dart';

bool generated(RuleContext context) {
  final unit = context.currentUnit!;
  return unit.file.path.endsWith('.g.dart') ||
      unit.file.path.endsWith('.freezed.dart') ||
      RegExp(r'//\s*GENERATED CODE - DO NOT MODIFY BY HAND').hasMatch(unit.content);
}

/// Optional styles retain generated-file and configured exclusions.
bool skipNewRule(RuleContext context) {
  if (generated(context)) return true;
  final root = context.package?.root ?? _packageRoot(context.definingUnit.file);
  final file = root.getFile('clear_dart_lints.yaml');
  try {
    if (!file.exists) return false;
    return ArchitectureConfiguration.parse(
      file.readAsStringSync(),
      root: root.path,
    ).excluded(context.currentUnit!.file.path);
  } on Object {
    return false;
  }
}

Folder _packageRoot(File file) {
  var folder = file.parent;
  while (!folder.getFile('pubspec.yaml').exists && folder.parent.path != folder.path) {
    folder = folder.parent;
  }
  return folder;
}
