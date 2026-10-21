import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

class Dependency {
  final Uri uri;
  final String? path;
  Dependency(this.uri, this.path);
}

/// Explore every conditional branch and transitive export, including parts.
/// Paths identify visited libraries even when reached through different URIs.
Iterable<Dependency> dependencies(RuleContext context, Uri uri) sync* {
  final seen = <String>{};
  final provider = context.currentUnit!.file.provider;
  final converter = context.libraryElement!.session.uriConverter;
  Iterable<Dependency> walk(Uri current) sync* {
    final path = converter.uriToPath(current);
    if (!seen.add(path ?? current.toString())) return;
    final canonical = path == null ? current : converter.pathToUri(path) ?? current;
    yield Dependency(canonical, path);
    if (path == null || current.scheme == 'dart') return;
    final file = provider.getFile(path);
    if (!file.exists) return;
    final unit = parseString(content: file.readAsStringSync(), throwIfDiagnostics: false).unit;
    for (final directive in unit.directives) {
      if (directive is ExportDirective) {
        for (final value in [directive.uri, ...directive.configurations.map((c) => c.uri)]) {
          final text = value.stringValue;
          if (text != null) yield* walk(current.resolve(text));
        }
      } else if (directive is PartDirective) {
        final text = directive.uri.stringValue;
        if (text != null) yield* walk(current.resolve(text));
      }
    }
  }

  yield* walk(uri);
}
