import 'package:glob/glob.dart';

/// A directed permission between feature names, independent of layer edges.
class FeatureAllowance {
  final List<String> from, to;
  const FeatureAllowance(this.from, this.to);
}

/// A path pattern with exactly one, single-segment feature capture.
class FeaturePattern {
  final String pattern;
  final List<String> _segments;
  final int _capture;

  FeaturePattern(String pattern)
    : pattern = pattern.replaceAll('\\', '/'),
      _segments = pattern.replaceAll('\\', '/').split('/'),
      _capture = pattern.replaceAll('\\', '/').split('/').indexOf('{feature}') {
    if (RegExp(r'^[A-Za-z]:').hasMatch(pattern) ||
        _capture < 0 ||
        _segments.where((s) => s == '{feature}').length != 1 ||
        _segments.any((s) => s.isEmpty || s == '.' || s == '..') ||
        _segments.take(_capture).any((s) => s.contains('**')) ||
        _segments.where((s) => s != '{feature}').any((s) => s.contains('{feature}'))) {
      throw FormatException(
        'rules.feature_dependencies.feature_paths: expected one full {feature} segment, '
        'a relative path and no ** before the capture: $pattern',
      );
    }
    for (final segment in _segments) {
      if (segment != '{feature}') {
        Glob(segment);
      }
    }
  }

  String? featureFor(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    if (parts.length <= _capture || parts[_capture].isEmpty) return null;
    for (var i = 0; i < _capture; i++) {
      if (!Glob(_segments[i]).matches(parts[i])) return null;
    }
    final suffix = _segments.skip(_capture + 1).join('/');
    if (!Glob(suffix).matches(parts.skip(_capture + 1).join('/'))) return null;
    return parts[_capture];
  }
}

/// Physical membership; overlapping categories are invalid rather than ordered.
class FeatureMembership {
  final Set<String> features;
  final bool shared, compositionRoot;
  const FeatureMembership(this.features, this.shared, this.compositionRoot);
  int get count => features.length + (shared ? 1 : 0) + (compositionRoot ? 1 : 0);
  bool get valid => count == 1;
  String? get feature => features.length == 1 ? features.single : null;
  String get description => [
    ...features.toList()..sort(),
    if (shared) '<shared>',
    if (compositionRoot) '<composition-root>',
  ].join(', ');
  Map<String, Object?> toJson() => {
    'features': features.toList()..sort(),
    'shared': shared,
    'composition_root': compositionRoot,
    'valid': valid,
  };
}

/// Optional feature isolation, applied in addition to all existing rules.
class FeatureDependencies {
  final List<FeaturePattern> featurePaths;
  final List<String> sharedPaths, compositionRoots;
  final List<FeatureAllowance> allowed;
  const FeatureDependencies(
    this.featurePaths,
    this.sharedPaths,
    this.compositionRoots,
    this.allowed,
  );

  FeatureMembership membership(String relativePath) => FeatureMembership(
    {
      for (final pattern in featurePaths)
        if (pattern.featureFor(relativePath) case final f?) f,
    },
    sharedPaths.any(
      (p) => Glob(p.replaceAll('\\', '/')).matches(relativePath.replaceAll('\\', '/')),
    ),
    compositionRoots.any(
      (p) => Glob(p.replaceAll('\\', '/')).matches(relativePath.replaceAll('\\', '/')),
    ),
  );

  bool permits(FeatureMembership from, FeatureMembership to) {
    if (!from.valid || !to.valid) return false;
    if (from.compositionRoot) return true;
    if (from.shared) return to.shared;
    return to.shared ||
        to.compositionRoot ||
        from.feature == to.feature ||
        allowed.any((a) => a.from.contains(from.feature) && a.to.contains(to.feature));
  }
}
