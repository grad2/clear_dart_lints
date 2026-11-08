import 'dart:io';

import 'package:path/path.dart' as p;

import '../architecture/configuration.dart';
import 'result.dart';

/// A path-based description, not resolved type analysis or a setup audit.
class FilePolicyContext {
  final ArchitectureConfiguration policy;
  final String path;
  final List<ToolIssue> issues;
  FilePolicyContext._(this.policy, this.path, Iterable<ToolIssue> issues)
    : issues = List.unmodifiable(issues);
  bool get passed => issues.isEmpty;
  bool get enforced => policy.includes(path) && !policy.excluded(path);

  Map<String, Object?> toJson() {
    final layers = policy.layersFor(path);
    final rules = policy.rules;
    bool selected(List<String> source) => source.any(layers.contains);
    bool root(List<String> roots) => matchesPatterns(roots, policy.relative(path));
    Map<String, Object?> dependency(DependencyRule rule) => {
      'source_layers': rule.sourceLayers,
      'dependency_roles': rule.dependencyRoles,
      'composition_roots': rule.compositionRoots,
      'exempt_at_path': root(rule.compositionRoots),
      'allow_provider_reads': rule.allowProviderReads,
    };
    final rd = rules.roleDependencies;
    final fs = rules.forbiddenSymbols;
    final features = rules.featureDependencies;
    return {
      'path': path,
      'relative_path': policy.relative(path),
      'included': policy.includes(path),
      'excluded': policy.excluded(path),
      'enforced': enforced,
      'architecture_checked': false,
      'layers': layers.toList()..sort(),
      'allowed_dependencies': {
        'layers': {
          for (final a in rules.layerDependencies)
            if (selected(a.from)) ...a.to,
        }.toList()..sort(),
        'uris': {
          for (final a in rules.layerDependencies)
            if (selected(a.from)) ...a.uris,
        }.toList()..sort(),
      },
      'role_selectors': {
        for (final entry in policy.roles.entries)
          entry.key: {
            'paths': entry.value.paths,
            'names': entry.value.names,
            'libraries': entry.value.libraries,
            'types': [
              for (final t in entry.value.types) {'library': t.library, 'name': t.name},
            ],
            'path_matches': matchesPatterns(entry.value.paths, policy.relative(path)),
            'resolved': false,
          },
      },
      'constraints': {
        if (rd != null)
          'role_dependencies': {
            'exempt_at_path': root(rd.compositionRoots),
            'composition_roots': rd.compositionRoots,
            'restrictions': [
              for (final r in rd.restrictions)
                if (selected(r.sourceLayers))
                  {
                    'source_layers': r.sourceLayers,
                    'dependency_roles': r.dependencyRoles,
                    'allowed_consumer_roles': r.allowedConsumerRoles,
                  },
            ],
          },
        if (rules.dependOnContracts case final r? when selected(r.sourceLayers))
          'depend_on_contracts': dependency(r),
        if (rules.constructorInjection case final r? when selected(r.sourceLayers))
          'constructor_injection': dependency(r),
        if (fs != null && selected(fs.sourceLayers))
          'forbidden_symbols': [
            for (final s in fs.symbols) {'library': s.library, 'name': s.name},
          ],
      },
      'exceptions': [
        for (final e in policy.exceptions)
          if (matchesPatterns(e.paths, policy.relative(path)))
            {'rule': e.rule, 'paths': e.paths, 'reason': e.reason},
      ],
      'feature_scope': features?.membership(policy.relative(path)).toJson(),
      if (features != null)
        'feature_policy': {
          'feature_paths': features.featurePaths.map((p) => p.pattern).toList(),
          'shared_paths': features.sharedPaths,
          'composition_roots': features.compositionRoots,
          'allowed': [
            for (final a in features.allowed) {'from': a.from, 'to': a.to},
          ],
        },
    };
  }
}

/// Describes an existing or future Dart file relative to [policy]'s package.
/// Rejects traversal and existing symlink ancestors leading outside the package.
FilePolicyContext inspectFilePolicy(ArchitectureConfiguration policy, String sourcePath) {
  final root = p.normalize(p.absolute(policy.root));
  final path = p.normalize(p.isAbsolute(sourcePath) ? sourcePath : p.join(root, sourcePath));
  if (!p.isWithin(root, path) || !path.endsWith('.dart')) {
    throw const FormatException('Expected a Dart file path inside the package root.');
  }
  var ancestor = path;
  while (FileSystemEntity.typeSync(ancestor, followLinks: false) == FileSystemEntityType.notFound &&
      p.dirname(ancestor) != ancestor) {
    ancestor = p.dirname(ancestor);
  }
  if (Directory(root).existsSync()) {
    final physicalRoot = Directory(root).resolveSymbolicLinksSync();
    final physicalAncestor = File(ancestor).resolveSymbolicLinksSync();
    if (physicalAncestor != physicalRoot && !p.isWithin(physicalRoot, physicalAncestor)) {
      throw const FormatException('The source path resolves outside the package root.');
    }
  }
  final issues = <ToolIssue>[];
  void issue(String code, String message) => issues.add(ToolIssue(code, path, message));
  if (policy.includes(path) && !policy.excluded(path)) {
    final layers = policy.layersFor(path);
    if (layers.length != 1) {
      issue(
        layers.isEmpty ? 'unclassified_source' : 'ambiguous_layer',
        'Expected exactly one layer, found ${layers.length}.',
      );
    }
    final feature = policy.rules.featureDependencies?.membership(policy.relative(path));
    if (feature != null && !feature.valid) {
      issue(
        feature.count == 0 ? 'unclassified_feature' : 'ambiguous_feature',
        'Expected exactly one feature scope, found ${feature.count}.',
      );
    }
  }
  return FilePolicyContext._(policy, path, issues);
}
