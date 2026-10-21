import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

String normalized(String path) => path.replaceAll('\\', '/');
bool matches(Iterable<String> patterns, String path) =>
    patterns.any((pattern) => Glob(normalized(pattern)).matches(normalized(path)));

bool generated(RuleContext context) {
  final unit = context.currentUnit!;
  return unit.file.path.endsWith('.g.dart') ||
      unit.file.path.endsWith('.freezed.dart') ||
      RegExp(r'//\s*GENERATED CODE - DO NOT MODIFY BY HAND').hasMatch(unit.content);
}

class Configuration {
  final String root;
  final Map<String, dynamic> data;
  Configuration(this.root, this.data);
  String relative(String file) => normalized(p.relative(file, from: root));
  Map<String, dynamic> get layers => data['layers'] as Map<String, dynamic>;
  Map<String, dynamic> get roles => data['roles'] as Map<String, dynamic>;
  Map<String, dynamic> parameters(String rule) =>
      (data['rules'] as Map<String, dynamic>)[rule] as Map<String, dynamic>;
  Set<String> layersFor(String file) => {
    for (final entry in layers.entries)
      if (matches((entry.value as List).cast<String>(), relative(file))) entry.key,
  };
  bool excluded(String file) => matches((data['exclude'] as List).cast<String>(), relative(file));
  bool hasRole(DartType? type, List<String> selected) {
    if (type is! InterfaceType) return false;
    return [
      type,
      ...type.allSupertypes,
    ].any((candidate) => selected.any((role) => elementHasRole(candidate.element, role)));
  }

  bool elementHasRole(InterfaceElement element, String role) {
    final spec = roles[role] as Map<String, dynamic>;
    final uri = element.library.uri.toString();
    final file = element.firstFragment.libraryFragment.source.fullName;
    return matches((spec['names'] as List).cast<String>(), element.name ?? '') &&
        (matches((spec['libraries'] as List).cast<String>(), uri) ||
            matches((spec['libraries'] as List).cast<String>(), relative(file)));
  }
}

class ConfigurationResult {
  final Configuration? configuration;
  final String? error;
  ConfigurationResult(this.configuration, this.error);
}

// Expando keys die with the analysis context. No process-global path-only cache.
final _cache = Expando<Map<String, ConfigurationResult>>();
ConfigurationResult configurationFor(RuleContext context) {
  final analysisContext = context.libraryElement!.session.analysisContext;
  final root = context.package?.root ?? _packageRoot(context.definingUnit.file);
  final cache = _cache[analysisContext] ??= {};
  return cache.putIfAbsent(root.path, () {
    try {
      final file = root.getFile('clear_dart_lints.yaml');
      if (!file.exists) throw const FormatException('Missing clear_dart_lints.yaml.');
      final data = _map(loadYaml(file.readAsStringSync()), 'configuration');
      _keys(data, {'schema_version', 'exclude', 'layers', 'roles', 'rules'});
      if (data['schema_version'] is! int || data['schema_version'] != 1) {
        throw const FormatException('schema_version must be 1.');
      }
      data['exclude'] = _strings(data['exclude'] ?? [], 'exclude');
      final layers = _map(data['layers'], 'layers');
      for (final key in layers.keys) {
        layers[key] = _strings(layers[key], 'layers.$key');
      }
      final roles = _map(data['roles'], 'roles');
      for (final key in roles.keys) {
        final role = _map(roles[key], 'roles.$key');
        _keys(role, {'names', 'libraries'});
        role['names'] = _strings(role['names'], 'roles.$key.names');
        role['libraries'] = _strings(role['libraries'], 'roles.$key.libraries');
        roles[key] = role;
      }
      final rules = _map(data['rules'], 'rules');
      _keys(rules, _ruleKeys.keys.toSet());
      for (final name in rules.keys) {
        final spec = _map(rules[name], 'rules.$name');
        _keys(spec, _ruleKeys[name]!);
        spec['source_layers'] = _references(spec['source_layers'], layers, 'source_layers');
        if (name == 'layer_dependencies') {
          final forbidden = spec['forbidden'];
          if (forbidden is! List) throw const FormatException('forbidden must be a list.');
          spec['forbidden'] = [for (final value in forbidden) _dependency(value, layers)];
        } else {
          for (final key in [
            'repository_roles',
            'allowed_consumer_roles',
            'dependency_roles',
            'transport_roles',
          ]) {
            if (_ruleKeys[name]!.contains(key)) spec[key] = _references(spec[key], roles, key);
          }
          if (_ruleKeys[name]!.contains('composition_roots')) {
            spec['composition_roots'] = _strings(spec['composition_roots'], 'composition_roots');
          }
          if (name == 'no_transport_in_domain') {
            if (spec['forbidden_symbols'] is! List) {
              throw const FormatException('forbidden_symbols must be a list.');
            }
            spec['forbidden_symbols'] = [
              for (final symbol in spec['forbidden_symbols'] as List) _symbol(symbol),
            ];
          }
        }
        rules[name] = spec;
      }
      data['layers'] = layers;
      data['roles'] = roles;
      data['rules'] = rules;
      return ConfigurationResult(Configuration(root.path, data), null);
    } on Object catch (error) {
      return ConfigurationResult(null, error.toString());
    }
  });
}

Folder _packageRoot(File file) {
  var folder = file.parent;
  while (!folder.getFile('pubspec.yaml').exists && folder.parent.path != folder.path) {
    folder = folder.parent;
  }
  return folder;
}

const _ruleKeys = <String, Set<String>>{
  'layer_dependencies': {'source_layers', 'forbidden'},
  'repositories_only_in_blocs': {
    'source_layers',
    'repository_roles',
    'allowed_consumer_roles',
    'composition_roots',
  },
  'depend_on_contracts': {'source_layers', 'dependency_roles', 'composition_roots'},
  'no_transport_in_domain': {'source_layers', 'transport_roles', 'forbidden_symbols'},
};
Map<String, dynamic> _map(dynamic value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$label must be a string-keyed mapping.');
  }
  return {for (final key in value.keys) key as String: value[key]};
}

void _keys(Map<String, dynamic> value, Set<String> allowed) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown key: $key.');
  }
}

List<String> _strings(dynamic value, String label) {
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$label must be a list of strings.');
  }
  final result = value.cast<String>().toList();
  for (final pattern in result) {
    Glob(normalized(pattern));
  }
  return result;
}

List<String> _references(dynamic value, Map<String, dynamic> targets, String label) {
  final result = _strings(value, label);
  for (final name in result) {
    if (!targets.containsKey(name)) throw FormatException('Unknown $label reference: $name.');
  }
  return result;
}

Map<String, dynamic> _dependency(dynamic value, Map<String, dynamic> layers) {
  final spec = _map(value, 'forbidden dependency');
  _keys(spec, {'from', 'to', 'uris'});
  spec['from'] = _references(spec['from'], layers, 'from');
  spec['to'] = _references(spec['to'] ?? [], layers, 'to');
  spec['uris'] = _strings(spec['uris'] ?? [], 'uris');
  return spec;
}

Map<String, dynamic> _symbol(dynamic value) {
  final spec = _map(value, 'forbidden symbol');
  _keys(spec, {'library', 'name'});
  if (spec['library'] is! String || spec['name'] is! String) {
    throw const FormatException('Symbols require library and name strings.');
  }
  return spec;
}

/// Optional exclusions also apply to the configuration-independent new rules.
bool skipNewRule(RuleContext context) =>
    generated(context) ||
    (configurationFor(context).configuration?.excluded(context.currentUnit!.file.path) ?? false);
