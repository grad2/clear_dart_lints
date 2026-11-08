## 0.6.2

- Accept resolved Injectable `@factoryMethod` static factories that directly construct their own type from explicit required parameters. Keep dependency acquisition and all other architecture checks active.

## 0.6.1

- Recognize positional/named record fields and typed nullable callback calls by their static signatures. Use resolved write elements for index assignments and updates.
- Accept explicit dependency parameters on top-level functions while retaining constructor injection for class methods and nested callbacks, and rejecting repository construction or locator acquisition.
- Treat explicit `null` in nullable dependency fields and constructor modes as absence. Preserve origin checks for non-null values and reject untrusted constructor overwrites.

## 0.6.0

- Align published documentation with the standard `doc/` package layout and update all installation/template pins to 0.6.0.

- Add read-only `context` and `policy_diff` executables, versioned JSON output for all agent commands, and the public `agent_tools.dart` API.
- Add optional schema 2 feature boundaries with automatic path captures, directed permissions, shared/composition scopes, native warnings and suppression auditing. Enable isolation in all eight feature-first templates.
- Enrich architecture diagnostics with rule-specific corrections, policy YAML spans, source/target layers and declaration locations. Add agent repair examples and a conservative CI policy-change gate.
- Add opt-in `avoid_hardcoded_secrets` for recognizable credentials and complete private-key blocks in Dart strings, including generated sources, adjacent literals and static interpolation fragments. Findings have informational severity and never include the matched value.
- Add MVVM MobX templates in feature-first and layer-first layouts, with resolved `Store` roles, constructor injection, generated private-base/wrapper examples and Flutter Observer verification.
- Treat named mixin application superclasses as inheritance without waiving layer checks. Recognize resolved prefix/postfix updates and property writes when checking unverifiable dependencies.
- Add real MobX generator fixtures, runtime reactive-state regressions, resolved architecture tests and a native Flutter-consumer verification tool.
- Add Layered Riverpod and Clean Riverpod templates in feature-first and layer-first layouts, with a dedicated DI layer, provider composition, optional use cases, and manual/generated provider and notifier examples.
- Apply declaration roles to top-level functions, getters and variables, including provider factory callbacks. Preserve class-based roles and require top-level consumers to match their own declaration selectors.
- Add opt-in `constructor_injection.allow_provider_reads` for resolved Riverpod `Ref.read`/`Ref.watch`; keep contract and layer enforcement active, including inferred concrete provider results and nested generic dependencies.
- Recognize resolved setter assignments when checking unverifiable dependencies, including notifier `state` updates. Add regressions using real Riverpod packages and generator output.

## 0.5.0

- Replace architecture schema 1 with strict schema 2: explicit inclusion, exactly one layer per physical source, and deny-by-default dependency allowances. This is a breaking configuration change with no compatibility mode.
- Enable architecture automatically as native analyzer warnings; add classification, general role restrictions, separate contract/injection checks, forbidden symbols and unverifiable-dependency diagnostics.
- Recognize role base types by resolved identity, including actual Bloc/Cubit ancestry. Check own-package barrels and require explicit generated-source exclusions and reasoned policy exceptions.
- Add read-only `verify_setup` to audit matching plugin/verifier installation, effective analyzer options, coverage and suppression attempts before native `dart analyze --format=machine --fatal-infos`.
- Add ten explicit editable architecture templates, migration/reference documentation and an agent integration guide with a copyable consumer AGENTS.md snippet. Clean use cases remain optional.
- Preserve opt-in style diagnostics and arrow-body quick fixes. Architecture has no custom analysis CLI or automatic fixes.

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
