import 'dart:convert';

import 'package:path/path.dart' as p;

import '../architecture/configuration.dart';
import 'result.dart';

enum PolicyAssessment { tightening, weakening, reviewRequired, informational }

/// One semantic policy change; uncertainty blocks the gate conservatively.
class PolicyChange {
  final String key, reason;
  final Object? before, after;
  final PolicyAssessment assessment;
  const PolicyChange(this.key, this.before, this.after, this.assessment, this.reason);
  bool get blocking =>
      assessment == PolicyAssessment.weakening || assessment == PolicyAssessment.reviewRequired;
  String get assessmentName =>
      assessment == PolicyAssessment.reviewRequired ? 'review_required' : assessment.name;
  Map<String, Object?> toJson() => {
    'key': key,
    'before': before,
    'after': after,
    'assessment': assessmentName,
    'reason': reason,
  };
}

class PolicyComparison {
  final String policyPath;
  final List<PolicyChange> changes;
  PolicyComparison(this.policyPath, Iterable<PolicyChange> changes)
    : changes = List.unmodifiable(changes);
  bool get passed => !changes.any((c) => c.blocking);
  List<ToolIssue> get issues => [
    for (final c in changes)
      if (c.blocking)
        ToolIssue(
          c.assessment == PolicyAssessment.weakening
              ? 'policy_weakening'
              : 'policy_review_required',
          policyPath,
          '${c.key}: ${c.reason}',
        ),
  ];
  Map<String, Object?> toJson() => {'changes': changes.map((c) => c.toJson()).toList()};
}

/// Compares executable policy meaning, not YAML formatting or list ordering.
/// Glob containment and selector equivalence are deliberately not guessed.
PolicyComparison comparePolicies(
  ArchitectureConfiguration base,
  ArchitectureConfiguration current,
) {
  final changes = <PolicyChange>[];
  const tight = PolicyAssessment.tightening;
  const weak = PolicyAssessment.weakening;
  const review = PolicyAssessment.reviewRequired;
  void change(String key, Object? before, Object? after, PolicyAssessment assessment) {
    if (_encode(before) == _encode(after)) return;
    changes.add(
      PolicyChange(key, before, after, assessment, switch (assessment) {
        PolicyAssessment.tightening => 'This change only adds constraints or removes permissions.',
        PolicyAssessment.weakening => 'This change removes constraints or expands permissions.',
        PolicyAssessment.reviewRequired =>
          'Selector equivalence or containment cannot be proved; review is required.',
        PolicyAssessment.informational => 'Only the documented reason changed.',
      }),
    );
  }

  void sets(
    String key,
    Iterable<String> before,
    Iterable<String> after,
    PolicyAssessment addition,
    PolicyAssessment removal, {
    bool patterns = false,
  }) {
    final b = before.toSet(), a = after.toSet();
    final added = a.difference(b), removed = b.difference(a);
    final replacing = patterns && added.isNotEmpty && removed.isNotEmpty;
    bool uriRewrite(String value, Set<String> opposite) {
      if (key != 'rules.layer_dependencies.allowed') return false;
      final edge = jsonDecode(value) as Map;
      if (edge['uri'] is! String) return false;
      return opposite.any((other) {
        final candidate = jsonDecode(other) as Map;
        return candidate['from'] == edge['from'] &&
            candidate['uri'] is String &&
            RegExp(r'[*?\[\]{},]').hasMatch('${edge['uri']}${candidate['uri']}');
      });
    }

    Object? display(String value) =>
        key.endsWith('.allowed') || key == 'exceptions' || key.endsWith('.symbols')
        ? jsonDecode(value)
        : value;
    for (final value in removed.toList()..sort()) {
      change(key, display(value), null, replacing || uriRewrite(value, added) ? review : removal);
    }
    for (final value in added.toList()..sort()) {
      change(
        key,
        null,
        display(value),
        replacing || uriRewrite(value, removed) ? review : addition,
      );
    }
  }

  List<String> paths(Iterable<String> values) =>
      values.map((s) => s.replaceAll('\\', '/')).toList();
  void roots(String key, List<String> b, List<String> a) =>
      sets(key, paths(b), paths(a), weak, tight, patterns: true);
  sets('include', paths(base.include), paths(current.include), tight, weak, patterns: true);
  roots('exclude', base.exclude, current.exclude);
  final layerNames = {...base.layers.keys, ...current.layers.keys}.toList()..sort();
  for (final name in layerNames) {
    change(
      'layers.$name',
      base.layers[name] == null ? null : paths(base.layers[name]!),
      current.layers[name] == null ? null : paths(current.layers[name]!),
      review,
    );
  }
  Object? role(RoleSpec? r) => r == null
      ? null
      : {
          'paths': paths(r.paths),
          'names': r.names,
          'libraries': paths(r.libraries),
          'types': [
            for (final t in r.types) {'library': t.library, 'name': t.name},
          ],
        };
  for (final name in {...base.roles.keys, ...current.roles.keys}.toList()..sort()) {
    change('roles.$name', role(base.roles[name]), role(current.roles[name]), review);
  }
  List<String> layerEdges(ArchitectureConfiguration c) => [
    for (final a in c.rules.layerDependencies)
      for (final from in a.from) ...[
        for (final to in a.to) _encode({'from': from, 'to': to}),
        for (final uri in a.uris) _encode({'from': from, 'uri': uri}),
      ],
  ];
  sets('rules.layer_dependencies.allowed', layerEdges(base), layerEdges(current), weak, tight);
  Object? dependencyValue(DependencyRule? r) => r == null
      ? null
      : {
          'source_layers': r.sourceLayers,
          'dependency_roles': r.dependencyRoles,
          'composition_roots': paths(r.compositionRoots),
          'allow_provider_reads': r.allowProviderReads,
        };
  Object? roleValue(RoleDependencies? r) => r == null
      ? null
      : {
          'composition_roots': paths(r.compositionRoots),
          'restrictions': [
            for (final v in r.restrictions)
              {
                'source_layers': v.sourceLayers,
                'dependency_roles': v.dependencyRoles,
                'allowed_consumer_roles': v.allowedConsumerRoles,
              },
          ],
        };
  Object? symbolsValue(ForbiddenSymbolsRule? r) => r == null
      ? null
      : {
          'source_layers': r.sourceLayers,
          'symbols': [
            for (final v in r.symbols) {'library': v.library, 'name': v.name},
          ],
        };
  Object? featureValue(FeatureDependencies? r) => r == null
      ? null
      : {
          'feature_paths': r.featurePaths.map((v) => v.pattern).toList(),
          'shared_paths': paths(r.sharedPaths),
          'composition_roots': paths(r.compositionRoots),
          'allowed': [
            for (final v in r.allowed) {'from': v.from, 'to': v.to},
          ],
        };
  void dependency(String name, DependencyRule? b, DependencyRule? a) {
    final key = 'rules.$name';
    if (b == null || a == null) {
      change(key, dependencyValue(b), dependencyValue(a), a == null ? weak : tight);
      return;
    }
    sets('$key.source_layers', b.sourceLayers, a.sourceLayers, tight, weak);
    sets('$key.dependency_roles', b.dependencyRoles, a.dependencyRoles, tight, weak);
    roots('$key.composition_roots', b.compositionRoots, a.compositionRoots);
    change(
      '$key.allow_provider_reads',
      b.allowProviderReads,
      a.allowProviderReads,
      a.allowProviderReads ? weak : tight,
    );
  }

  dependency('depend_on_contracts', base.rules.dependOnContracts, current.rules.dependOnContracts);
  dependency(
    'constructor_injection',
    base.rules.constructorInjection,
    current.rules.constructorInjection,
  );
  final br = base.rules.roleDependencies, ar = current.rules.roleDependencies;
  if (br == null || ar == null) {
    change('rules.role_dependencies', roleValue(br), roleValue(ar), ar == null ? weak : tight);
  } else {
    roots('rules.role_dependencies.composition_roots', br.compositionRoots, ar.compositionRoots);
    Map<String, List<RoleRestriction>> group(RoleDependencies r) {
      final groups = <String, List<RoleRestriction>>{};
      for (final restriction in r.restrictions) {
        final key = _encode({
          'source_layers': restriction.sourceLayers,
          'dependency_roles': restriction.dependencyRoles,
        });
        groups.putIfAbsent(key, () => []).add(restriction);
      }
      return groups;
    }

    final b = group(br), a = group(ar);
    for (final key in {...b.keys, ...a.keys}.toList()..sort()) {
      final before = b[key], after = a[key];
      if (before?.length == 1 && after?.length == 1) {
        sets(
          'rules.role_dependencies.restrictions[$key].allowed_consumer_roles',
          before!.single.allowedConsumerRoles,
          after!.single.allowedConsumerRoles,
          weak,
          tight,
        );
      } else {
        List<String> rows(List<RoleRestriction>? r) => [
          for (final row in r ?? <RoleRestriction>[]) _encode(row.allowedConsumerRoles),
        ];
        sets('rules.role_dependencies.restrictions[$key]', rows(before), rows(after), tight, weak);
      }
    }
  }
  final bs = base.rules.forbiddenSymbols, currentSymbols = current.rules.forbiddenSymbols;
  if (bs == null || currentSymbols == null) {
    change(
      'rules.forbidden_symbols',
      symbolsValue(bs),
      symbolsValue(currentSymbols),
      currentSymbols == null ? weak : tight,
    );
  } else {
    sets(
      'rules.forbidden_symbols.source_layers',
      bs.sourceLayers,
      currentSymbols.sourceLayers,
      tight,
      weak,
    );
    List<String> symbols(ForbiddenSymbolsRule rule) => [
      for (final s in rule.symbols) _encode({'library': s.library, 'name': s.name}),
    ];
    sets('rules.forbidden_symbols.symbols', symbols(bs), symbols(currentSymbols), tight, weak);
  }
  final bf = base.rules.featureDependencies, af = current.rules.featureDependencies;
  if (bf == null || af == null) {
    change(
      'rules.feature_dependencies',
      featureValue(bf),
      featureValue(af),
      af == null ? weak : tight,
    );
  } else {
    change(
      'rules.feature_dependencies.feature_paths',
      bf.featurePaths.map((f) => f.pattern).toList(),
      af.featurePaths.map((f) => f.pattern).toList(),
      review,
    );
    change(
      'rules.feature_dependencies.shared_paths',
      paths(bf.sharedPaths),
      paths(af.sharedPaths),
      review,
    );
    roots('rules.feature_dependencies.composition_roots', bf.compositionRoots, af.compositionRoots);
    List<String> edges(FeatureDependencies f) => [
      for (final a in f.allowed)
        for (final from in a.from)
          for (final to in a.to) _encode({'from': from, 'to': to}),
    ];
    sets('rules.feature_dependencies.allowed', edges(bf), edges(af), weak, tight);
  }
  Map<String, Set<String>> exceptions(ArchitectureConfiguration c) {
    final result = <String, Set<String>>{};
    for (final e in c.exceptions) {
      for (final path in paths(e.paths)) {
        result.putIfAbsent(_encode({'rule': e.rule, 'path': path}), () => {}).add(e.reason);
      }
    }
    return result;
  }

  final be = exceptions(base), ae = exceptions(current);
  final addedExceptions = ae.keys.toSet().difference(be.keys.toSet());
  final removedExceptions = be.keys.toSet().difference(ae.keys.toSet());
  final replacingExceptions = addedExceptions.isNotEmpty && removedExceptions.isNotEmpty;
  Object exceptionValue(String key, Map<String, Set<String>> values) => {
    ...jsonDecode(key) as Map<String, dynamic>,
    'reasons': values[key]!.toList()..sort(),
  };
  for (final key in removedExceptions.toList()..sort()) {
    change('exceptions', exceptionValue(key, be), null, replacingExceptions ? review : tight);
  }
  for (final key in addedExceptions.toList()..sort()) {
    change('exceptions', null, exceptionValue(key, ae), replacingExceptions ? review : weak);
  }
  for (final key in be.keys.where(ae.containsKey).toList()..sort()) {
    change(
      'exceptions[$key].reason',
      be[key]!.toList(),
      ae[key]!.toList(),
      PolicyAssessment.informational,
    );
  }
  return PolicyComparison(p.join(current.root, 'clear_dart_lints.yaml'), changes);
}

String _encode(Object? value) {
  Object? canonical(Object? v) {
    if (v is Map) {
      return {for (final k in v.keys.cast<String>().toList()..sort()) k: canonical(v[k])};
    }
    if (v is Iterable) {
      final items = {for (final item in v) jsonEncode(canonical(item))}.toList()..sort();
      return items.map(jsonDecode).toList();
    }
    return v;
  }

  return jsonEncode(canonical(value));
}
