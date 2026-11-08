import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'features.dart';
export 'features.dart';

/// Location of a policy value, measured directly from its YAML span.
class PolicyLocation {
  final int offset, length, line, column;
  const PolicyLocation(this.offset, this.length, this.line, this.column);
}

String _norm(String s) => s.replaceAll('\\', '/');
bool matchesPatterns(Iterable<String> patterns, String value) =>
    patterns.any((s) => Glob(_norm(s)).matches(_norm(value)));

class SymbolSpec {
  final String library, name;
  const SymbolSpec(this.library, this.name);
}

class RoleSpec {
  final List<String> paths, names, libraries;
  final List<SymbolSpec> types;
  const RoleSpec(this.paths, this.names, this.libraries, this.types);
}

class LayerAllowance {
  final List<String> from, to, uris;
  const LayerAllowance(this.from, this.to, this.uris);
}

class RoleRestriction {
  final List<String> sourceLayers, dependencyRoles, allowedConsumerRoles;
  const RoleRestriction(this.sourceLayers, this.dependencyRoles, this.allowedConsumerRoles);
}

class RoleDependencies {
  final List<String> compositionRoots;
  final List<RoleRestriction> restrictions;
  const RoleDependencies(this.compositionRoots, this.restrictions);
}

class DependencyRule {
  final List<String> sourceLayers, dependencyRoles, compositionRoots;
  final bool allowProviderReads;
  const DependencyRule(
    this.sourceLayers,
    this.dependencyRoles,
    this.compositionRoots, {
    this.allowProviderReads = false,
  });
}

class ForbiddenSymbolsRule {
  final List<String> sourceLayers;
  final List<SymbolSpec> symbols;
  const ForbiddenSymbolsRule(this.sourceLayers, this.symbols);
}

class ArchitectureRules {
  final List<LayerAllowance> layerDependencies;
  final RoleDependencies? roleDependencies;
  final DependencyRule? dependOnContracts, constructorInjection;
  final ForbiddenSymbolsRule? forbiddenSymbols;
  final FeatureDependencies? featureDependencies;
  const ArchitectureRules(
    this.layerDependencies,
    this.roleDependencies,
    this.dependOnContracts,
    this.constructorInjection,
    this.forbiddenSymbols, {
    this.featureDependencies,
  });
}

class ArchitectureException {
  final String rule, reason;
  final List<String> paths;
  const ArchitectureException(this.rule, this.paths, this.reason);
}

class ArchitectureConfiguration {
  final String root;
  final List<String> include, exclude;
  final Map<String, List<String>> layers;
  final Map<String, RoleSpec> roles;
  final ArchitectureRules rules;
  final List<ArchitectureException> exceptions;
  final Map<String, PolicyLocation> locations;
  const ArchitectureConfiguration(
    this.root,
    this.include,
    this.exclude,
    this.layers,
    this.roles,
    this.rules,
    this.exceptions, {
    this.locations = const {},
  });
  String relative(String path) => _norm(p.isAbsolute(path) ? p.relative(path, from: root) : path);
  bool includes(String path) => matchesPatterns(include, relative(path));
  bool excluded(String path) => matchesPatterns(exclude, relative(path));
  Set<String> layersFor(String path) => {
    for (final e in layers.entries)
      if (matchesPatterns(e.value, relative(path))) e.key,
  };
  bool excepted(String rule, String path) =>
      exceptions.any((e) => e.rule == rule && matchesPatterns(e.paths, relative(path)));
  static ArchitectureConfiguration parse(String content, {required String root}) {
    dynamic yaml;
    late YamlNode yamlNode;
    try {
      yamlNode = loadYamlNode(content);
      yaml = yamlNode.value;
    } on YamlException catch (error) {
      throw FormatException('Invalid YAML: $error');
    }
    final doc = _map(yaml, 'configuration', {
      'schema_version',
      'include',
      'exclude',
      'layers',
      'roles',
      'rules',
      'exceptions',
    });
    if (doc['schema_version'] is! int || doc['schema_version'] != 2) {
      throw const FormatException('schema_version must be 2.');
    }
    final include = _strings(doc['include'], 'include');
    final exclude = _strings(doc['exclude'] ?? [], 'exclude', empty: true);
    final lm = _map(doc['layers'], 'layers');
    if (lm.isEmpty) throw const FormatException('layers must not be empty.');
    final layers = {for (final e in lm.entries) e.key: _strings(e.value, 'layers.${e.key}')};
    final rm = _map(doc['roles'] ?? {}, 'roles');
    final roles = <String, RoleSpec>{};
    for (final e in rm.entries) {
      final key = 'roles.${e.key}';
      final m = _map(e.value, key, {'paths', 'names', 'libraries', 'types'});
      final paths = _strings(m['paths'] ?? [], '$key.paths', empty: true);
      final names = _strings(m['names'] ?? [], '$key.names', empty: true);
      final libraries = _strings(m['libraries'] ?? [], '$key.libraries', empty: true);
      final types = _symbols(m['types'] ?? [], '$key.types', empty: true);
      if (names.isEmpty != libraries.isEmpty || paths.isEmpty && names.isEmpty && types.isEmpty) {
        throw FormatException('$key requires paths, types, or paired names and libraries.');
      }
      roles[e.key] = RoleSpec(paths, names, libraries, types);
    }
    List<String> refs(
      dynamic value,
      String key,
      Map<String, Object?> targets, {
      bool empty = false,
    }) {
      final result = _strings(value, key, empty: empty);
      for (final name in result) {
        if (!targets.containsKey(name)) {
          throw FormatException('$key references unknown name $name.');
        }
      }
      return result;
    }

    final rule = _map(doc['rules'], 'rules', {
      'layer_dependencies',
      'role_dependencies',
      'depend_on_contracts',
      'constructor_injection',
      'forbidden_symbols',
      'feature_dependencies',
    });
    final ld = _map(rule['layer_dependencies'], 'rules.layer_dependencies', {'allowed'});
    final allowed = <LayerAllowance>[];
    for (final v in _list(ld['allowed'], 'rules.layer_dependencies.allowed', empty: true)) {
      final m = _map(v, 'rules.layer_dependencies.allowed', {'from', 'to', 'uris'});
      final to = refs(m['to'] ?? [], 'allowed.to', layers, empty: true);
      final uris = _strings(m['uris'] ?? [], 'allowed.uris', empty: true);
      if (to.isEmpty && uris.isEmpty) throw const FormatException('allowed requires to or uris.');
      allowed.add(LayerAllowance(refs(m['from'], 'allowed.from', layers), to, uris));
    }
    RoleDependencies? rd;
    if (rule.containsKey('role_dependencies')) {
      final m = _map(rule['role_dependencies'], 'rules.role_dependencies', {
        'composition_roots',
        'restrictions',
      });
      final restrictions = <RoleRestriction>[];
      for (final v in _list(m['restrictions'], 'role_dependencies.restrictions')) {
        final x = _map(v, 'role_dependencies.restrictions', {
          'source_layers',
          'dependency_roles',
          'allowed_consumer_roles',
        });
        restrictions.add(
          RoleRestriction(
            refs(x['source_layers'], 'source_layers', layers),
            refs(x['dependency_roles'], 'dependency_roles', roles),
            refs(x['allowed_consumer_roles'], 'allowed_consumer_roles', roles, empty: true),
          ),
        );
      }
      rd = RoleDependencies(
        _strings(m['composition_roots'] ?? [], 'composition_roots', empty: true),
        restrictions,
      );
    }
    DependencyRule? dep(String name) {
      if (!rule.containsKey(name)) return null;
      final m = _map(rule[name], 'rules.$name', {
        'source_layers',
        'dependency_roles',
        'composition_roots',
        if (name == 'constructor_injection') 'allow_provider_reads',
      });
      final providerReads = m['allow_provider_reads'] ?? false;
      if (providerReads is! bool ||
          m.containsKey('allow_provider_reads') && m['allow_provider_reads'] == null) {
        throw FormatException('rules.$name.allow_provider_reads must be a boolean.');
      }
      return DependencyRule(
        refs(m['source_layers'], '$name.source_layers', layers),
        refs(m['dependency_roles'], '$name.dependency_roles', roles),
        _strings(m['composition_roots'] ?? [], '$name.composition_roots', empty: true),
        allowProviderReads: providerReads,
      );
    }

    ForbiddenSymbolsRule? fs;
    if (rule.containsKey('forbidden_symbols')) {
      final m = _map(rule['forbidden_symbols'], 'rules.forbidden_symbols', {
        'source_layers',
        'symbols',
      });
      fs = ForbiddenSymbolsRule(
        refs(m['source_layers'], 'forbidden_symbols.source_layers', layers),
        _symbols(m['symbols'], 'forbidden_symbols.symbols'),
      );
    }
    FeatureDependencies? features;
    if (rule.containsKey('feature_dependencies')) {
      const key = 'rules.feature_dependencies';
      final m = _map(rule['feature_dependencies'], key, {
        'feature_paths',
        'shared_paths',
        'composition_roots',
        'allowed',
      });
      List<String> names(dynamic value, String field) {
        final result = _strings(value, field);
        if (result.any((s) => s == '.' || s == '..' || RegExp(r'[/\\*?\[\]{}]').hasMatch(s))) {
          throw FormatException('$field requires literal feature names.');
        }
        return result;
      }

      features = FeatureDependencies(
        _list(
          m['feature_paths'],
          '$key.feature_paths',
        ).map((v) => FeaturePattern(_string(v, '$key.feature_paths'))).toList(),
        _strings(m['shared_paths'] ?? [], '$key.shared_paths', empty: true),
        _strings(m['composition_roots'] ?? [], '$key.composition_roots', empty: true),
        [
          for (final entry in _list(m['allowed'] ?? [], '$key.allowed', empty: true))
            FeatureAllowance(
              names(_map(entry, '$key.allowed', {'from', 'to'})['from'], '$key.allowed.from'),
              names(_map(entry, '$key.allowed', {'from', 'to'})['to'], '$key.allowed.to'),
            ),
        ],
      );
    }
    final exceptions = <ArchitectureException>[];
    for (final v in _list(doc['exceptions'] ?? [], 'exceptions', empty: true)) {
      final m = _map(v, 'exceptions', {'rule', 'paths', 'reason'});
      final name = _string(m['rule'], 'exceptions.rule');
      if (!{
        'layer_dependencies',
        'role_dependencies',
        'depend_on_contracts',
        'constructor_injection',
        'forbidden_symbols',
        'unverifiable_dependency',
        'feature_dependencies',
      }.contains(name)) {
        throw FormatException('exceptions.rule: unknown rule $name.');
      }
      exceptions.add(
        ArchitectureException(
          name,
          _strings(m['paths'], 'exceptions.paths'),
          _string(m['reason'], 'exceptions.reason'),
        ),
      );
    }
    return ArchitectureConfiguration(
      root,
      include,
      exclude,
      layers,
      roles,
      ArchitectureRules(
        allowed,
        rd,
        dep('depend_on_contracts'),
        dep('constructor_injection'),
        fs,
        featureDependencies: features,
      ),
      exceptions,
      locations: _locations(yamlNode),
    );
  }
}

Map<String, PolicyLocation> _locations(YamlNode root) {
  final result = <String, PolicyLocation>{};
  void visit(YamlNode node, String key) {
    result[key] = PolicyLocation(
      node.span.start.offset,
      node.span.length,
      node.span.start.line + 1,
      node.span.start.column + 1,
    );
    if (node is YamlMap) {
      for (final entry in node.nodes.entries) {
        visit(entry.value, key.isEmpty ? '${entry.key.value}' : '$key.${entry.key.value}');
      }
    } else if (node is YamlList) {
      for (var i = 0; i < node.nodes.length; i++) {
        visit(node.nodes[i], '$key[$i]');
      }
    }
  }

  visit(root, '');
  return Map.unmodifiable(result);
}

Map<String, dynamic> _map(dynamic v, String key, [Set<String>? allowed]) {
  if (v is! Map || v.keys.any((e) => e is! String || (e).isEmpty)) {
    throw FormatException('$key must be a string-keyed mapping.');
  }
  final m = <String, dynamic>{for (final e in v.entries) e.key as String: e.value};
  for (final k in m.keys) {
    if (allowed != null && !allowed.contains(k)) throw FormatException('Unknown key $key.$k.');
  }
  return m;
}

List<dynamic> _list(dynamic v, String key, {bool empty = false}) {
  if (v is! List || (!empty && v.isEmpty)) {
    throw FormatException('$key must be ${empty ? 'a' : 'a nonempty'} list.');
  }
  return v;
}

String _string(dynamic v, String key) {
  if (v is! String || v.trim().isEmpty) throw FormatException('$key must be a nonempty string.');
  return v;
}

List<String> _strings(dynamic v, String key, {bool empty = false}) {
  final result = <String>[];
  for (final item in _list(v, key, empty: empty)) {
    final s = _string(item, key);
    try {
      Glob(_norm(s));
    } on Object catch (e) {
      throw FormatException('$key: invalid glob $s: $e');
    }
    result.add(s);
  }
  return result;
}

List<SymbolSpec> _symbols(dynamic v, String key, {bool empty = false}) => [
  for (final x in _list(v, key, empty: empty)) _symbol(x, key),
];
SymbolSpec _symbol(dynamic v, String key) {
  final m = _map(v, key, {'library', 'name'});
  return SymbolSpec(_string(m['library'], '$key.library'), _string(m['name'], '$key.name'));
}
