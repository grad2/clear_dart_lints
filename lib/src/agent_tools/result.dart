/// A stable, structured finding shared by the read-only agent tools.
class ToolIssue {
  final String code, path, message;
  final String? filePath;
  final int? line, column;
  const ToolIssue(this.code, this.path, this.message, {this.filePath, this.line, this.column});
  Map<String, Object?> toJson() => {
    'code': code,
    'path': filePath ?? path,
    'message': message,
    if (line != null) 'line': line,
    if (column != null) 'column': column,
  };
}

/// Versioned CLI envelope. The data is command-specific; findings are uniform.
Map<String, Object?> toolReport(
  String command,
  String packageRoot,
  bool passed,
  Map<String, Object?> data,
  Iterable<ToolIssue> issues,
) => {
  'format_version': 1,
  'command': command,
  'package_root': packageRoot,
  'passed': passed,
  'data': data,
  'issues': issues.map((i) => i.toJson()).toList(),
};
