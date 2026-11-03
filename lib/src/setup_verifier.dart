import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
// Keep analyzer-internal compatibility access localized here: these options
// and ignore semantics are not exposed by the public analyzer API.
import 'package:analyzer/src/analysis_options/analysis_options.dart';
import 'package:analyzer/src/ignore_comments/ignore_info.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'architecture/configuration.dart';

const _pluginName = 'clear_dart_lints';
const _architectureCodes = {
  'architecture',
  'invalid_configuration',
  'unclassified_source',
  'ambiguous_layer',
  'layer_dependencies',
  'role_dependencies',
  'depend_on_contracts',
  'constructor_injection',
  'forbidden_symbols',
  'unverifiable_dependency',
};

/// A configuration or source suppression that prevents a trustworthy check.
class SetupIssue {
  final String code;
  final String path;
  final String message;

  const SetupIssue(this.code, this.path, this.message);
}

/// Result of the read-only setup audit, not an architecture analysis result.
class SetupVerification {
  final List<SetupIssue> issues;
  final int checkedFiles;

  SetupVerification(Iterable<SetupIssue> issues, this.checkedFiles)
    : issues = List.unmodifiable(issues);

  bool get passed => issues.isEmpty;
}

/// Validates the physical package scope, effective analyzer setup and ignores.
///
/// Does not resolve application code, launch the plugin, install dependencies or
/// write files. A passing audit must be followed by `dart analyze`.
Future<SetupVerification> verifySetup(
  String packageRoot, {
  String? verifierRoot,
  String? sdkPath,
}) async {
  final root = p.normalize(p.absolute(packageRoot));
  final issues = <SetupIssue>[];
  void problem(String code, String path, String message) =>
      issues.add(SetupIssue(code, path, message));
  final manifest = File(p.join(root, 'pubspec.yaml'));
  final policyFile = File(p.join(root, 'clear_dart_lints.yaml'));
  if (!manifest.existsSync()) {
    problem('missing_package', root, 'Expected a package root containing pubspec.yaml.');
    return SetupVerification(issues, 0);
  }
  ArchitectureConfiguration policy;
  try {
    policy = ArchitectureConfiguration.parse(policyFile.readAsStringSync(), root: root);
  } on Object catch (error) {
    problem('invalid_configuration', policyFile.path, error.toString());
    return SetupVerification(issues, 0);
  }
  String runningRoot;
  Version runningVersion;
  try {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:clear_dart_lints/src/setup_verifier.dart'),
    );
    runningRoot = _canonical(verifierRoot ?? p.dirname(p.dirname(p.dirname(uri!.toFilePath()))));
    runningVersion = Version.parse(_manifestVersion(runningRoot));
    final config = _packageConfigFor(root);
    if (config == null) {
      throw const FormatException(
        'Missing package_config.json. Run dart pub get or flutter pub get.',
      );
    }
    final data = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    final entries = data['packages'] as List;
    final entry = entries.cast<Map<String, dynamic>>().where(
      (value) => value['name'] == _pluginName,
    );
    if (entry.length != 1 ||
        _canonical(config.uri.resolve(entry.single['rootUri'] as String).toFilePath()) !=
            runningRoot) {
      throw const FormatException(
        'The target package must resolve the same clear_dart_lints package as this verifier. '
        'Add the matching dev dependency and run pub get.',
      );
    }
  } on Object catch (error) {
    problem('verifier_version', root, error.toString());
    return SetupVerification(issues, 0);
  }

  final files = <String>[];
  void walk(Directory directory) {
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is Directory) {
        if ({'.git', '.dart_tool'}.contains(p.basename(entity.path))) continue;
        walk(entity);
      } else if (entity is File && entity.path.endsWith('.dart')) {
        if (policy.includes(entity.path) && !policy.excluded(entity.path)) files.add(entity.path);
      } else if (entity is Link) {
        final type = FileSystemEntity.typeSync(entity.path, followLinks: true);
        if (type == FileSystemEntityType.file && entity.path.endsWith('.dart')) {
          if (policy.includes(entity.path) && !policy.excluded(entity.path)) files.add(entity.path);
        } else if (type == FileSystemEntityType.directory) {
          // Do not silently miss sources behind links, or follow cycles/outside
          // directories. The user can explicitly exclude the linked scope.
          final relative = p.relative(entity.path, from: root).replaceAll('\\', '/');
          final couldContainSource = policy.include.any((pattern) {
            final prefix = pattern.split(RegExp(r'[*?\[\{]')).first;
            return prefix.startsWith('$relative/') || relative.startsWith(prefix);
          });
          final subtreeExcluded = policy.exclude.any((pattern) {
            final normalized = pattern.replaceAll('\\', '/');
            if (!normalized.endsWith('/**')) return false;
            final prefix = normalized.substring(0, normalized.length - 3);
            var ancestor = relative;
            while (ancestor != '.') {
              if (matchesPatterns([prefix], ancestor)) return true;
              ancestor = p.posix.dirname(ancestor);
            }
            return false;
          });
          if (couldContainSource && !subtreeExcluded) {
            problem(
              'linked_scope',
              entity.path,
              'Linked source directories require an explicit exclusion or physical source checkout.',
            );
          }
        }
      }
    }
  }

  try {
    walk(Directory(root));
  } on FileSystemException catch (error) {
    problem('unreadable_scope', root, error.message);
  }
  files.sort();
  if (files.isEmpty) {
    problem(
      'empty_scope',
      policyFile.path,
      'No physical Dart files remain in the configured include/exclude scope.',
    );
    return SetupVerification(issues, 0);
  }

  final provider = PhysicalResourceProvider.INSTANCE;
  AnalysisContextCollection? contexts;
  try {
    contexts = AnalysisContextCollection(
      includedPaths: [root],
      sdkPath: sdkPath ?? p.dirname(p.dirname(Platform.resolvedExecutable)),
    );
    final checkedOptions = <String>{};
    for (final path in files) {
      final layers = policy.layersFor(path);
      if (layers.length != 1) {
        problem(
          layers.isEmpty ? 'unclassified_source' : 'ambiguous_layer',
          path,
          'Expected exactly one architecture layer, found ${layers.length}. Update the architecture configuration.',
        );
      }
      try {
        // contextFor deliberately rejects excluded files. Locate their owning
        // context too, so exclusions cannot make physical scope disappear.
        final candidates =
            contexts.contexts
                .where((context) => p.isWithin(context.contextRoot.root.path, path))
                .toList()
              ..sort(
                (a, b) => b.contextRoot.root.path.length.compareTo(a.contextRoot.root.path.length),
              );
        final context = candidates.isEmpty ? contexts.contextFor(path) : candidates.first;
        if (!context.contextRoot.isAnalyzed(path)) {
          problem(
            'analyzer_exclusion',
            path,
            'Excluded by analyzer settings but included by the architecture policy. Declare intentional exclusions in clear_dart_lints.yaml.',
          );
        }
        final options =
            context.getAnalysisOptionsForFile(provider.getFile(path)) as AnalysisOptionsImpl;
        final optionsKey = options.file?.path ?? '<default>';
        if (checkedOptions.add(optionsKey)) {
          final configured = options.pluginConfigurations.where(
            (config) => config.name == _pluginName,
          );
          if (configured.length != 1 || !configured.single.isEnabled) {
            problem(
              'missing_plugin',
              optionsKey,
              'Enable the native clear_dart_lints plugin in the effective root analysis options.',
            );
          } else {
            final plugin = configured.single;
            final source =
                options.pluginsOptions.dependencyOverrides?[_pluginName] ?? plugin.source;
            final matchesVersion = switch (source) {
              PathPluginSource(:final path) => _canonical(path) == runningRoot,
              VersionedPluginSource(:final constraint) =>
                VersionConstraint.parse(constraint) == runningVersion,
              _ => false,
            };
            if (!matchesVersion) {
              problem(
                'plugin_version',
                optionsKey,
                'Pin plugin version exactly to $runningVersion (matching the verifier), or use the same local package path.',
              );
            }
            for (final config in plugin.diagnosticConfigs.values) {
              if (_architectureCodes.contains(config.name.toLowerCase()) &&
                  {'disable', 'info'}.contains(config.severity.name)) {
                problem(
                  'disabled_architecture',
                  optionsKey,
                  'Architecture diagnostic ${config.name} cannot be disabled or lowered below warning.',
                );
              }
            }
          }
          for (final processor in options.errorProcessors) {
            final code = processor.code.toLowerCase().replaceFirst('$_pluginName/', '');
            if (_architectureCodes.contains(code) &&
                (processor.severity == null || processor.severity!.name == 'INFO')) {
              problem(
                'disabled_architecture',
                optionsKey,
                'Analyzer severity override weakens architecture diagnostic $code.',
              );
            }
          }
        }
      } on Object catch (error) {
        problem('analyzer_setup', path, 'Cannot inspect effective analysis options: $error');
      }
      try {
        final content = File(path).readAsStringSync();
        final unit = parseString(content: content, path: path, throwIfDiagnostics: false).unit;
        final ignores = IgnoreInfo.forDart(unit, content);
        final allIgnores = [
          ...ignores.ignoredForFile,
          ...ignores.ignoredOnLine.values.expand((items) => items),
        ];
        for (final ignore in allIgnores) {
          final forbidden = switch (ignore) {
            IgnoredDiagnosticName(:final name, :final pluginName) =>
              pluginName?.toLowerCase() == _pluginName && _architectureCodes.contains(name),
            IgnoredDiagnosticType(:final type) => type == 'warning',
            _ => false,
          };
          if (forbidden) {
            final offset = switch (ignore) {
              IgnoredDiagnosticName(:final offset) => offset,
              IgnoredDiagnosticType(:final offset) => offset,
              _ => 0,
            };
            final location = unit.lineInfo.getLocation(offset);
            problem(
              'architecture_suppression',
              '$path:${location.lineNumber}:${location.columnNumber}',
              'Architecture warnings cannot be suppressed in source. Use a reasoned exception in clear_dart_lints.yaml.',
            );
          }
        }
      } on Object catch (error) {
        problem('unreadable_source', path, 'Cannot audit source comments: $error');
      }
    }
  } on Object catch (error) {
    problem('analyzer_setup', root, error.toString());
  } finally {
    await contexts?.dispose();
  }
  return SetupVerification(issues, files.length);
}

String _canonical(String path) => Directory(path).resolveSymbolicLinksSync();

String _manifestVersion(String root) {
  final value = loadYaml(File(p.join(root, 'pubspec.yaml')).readAsStringSync());
  if (value is! YamlMap || value['version'] is! String) {
    throw const FormatException('The verifier package must have a version in pubspec.yaml.');
  }
  return value['version'] as String;
}

File? _packageConfigFor(String root) {
  var directory = Directory(root);
  while (true) {
    final config = File(p.join(directory.path, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) return config;
    if (directory.parent.path == directory.path) return null;
    directory = directory.parent;
  }
}
