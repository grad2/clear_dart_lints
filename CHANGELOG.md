## 0.4.1

- Add a discoverable example guide for pub.dev with setup and expected diagnostics.
- Enable core lint checks during development and fix static analysis findings without changing rule behavior.

## 0.4.0

- Add Effective Dart `avoid_nullable_collection_returns`.
- Add custom `depend_on_contracts`, `no_transport_in_domain`, and `avoid_nested_widget_ternaries`.
- Document all eleven opt-in rules, exceptions, SDK lint recommendations, and the version 1 architecture schema.
- Extend resolved-analysis tests and the Flutter verification tool for architecture, suppression, exclusions, independent enablement, and cache reuse.
- New diagnostics have no automatic fixes.

### Included 0.3.0 milestone

- Add Effective Dart `avoid_public_late_final_fields` and `avoid_nullable_async_returns`.
- Add custom `layer_dependencies` and `repositories_only_in_blocs`.
- Introduce optional package-root `clear_dart_lints.yaml`, strict validation with `invalid_configuration`, context-scoped caching, role matching and generated-file exclusions.
- Split Effective Dart and custom rule implementations, preserving existing names, API exports and quick fixes.

## 0.2.1

- Add the `agents` topic to improve package discovery on pub.dev.
- No changes to analyzer rules or quick fixes.

## 0.2.0

Initial public release as `clear_dart_lints`.

- Require block bodies when a potential single-line arrow function exceeds `formatter.page_width`.
- Require block bodies for Flutter `build` methods and widget builder callbacks.
- Report additional public classes in each Dart file, including part files.
- Provide a Convert to block body quick fix for the two arrow-function rules.
