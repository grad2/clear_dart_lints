# Architecture configuration, schema 2

Put one `clear_dart_lints.yaml` in the analyzed package root. Version 0.5.0 has no schema 1 compatibility, configuration inheritance, built-in preset selection, or app generator. Start from a complete [template](../templates/README.md), then edit it. The [agent integration guide](agent_integration.md) explains installation and the required verification commands.

Architecture runs as native analyzer warnings automatically when the plugin is installed. Its diagnostic codes are `invalid_configuration`, `unclassified_source`, `ambiguous_layer`, `layer_dependencies`, `role_dependencies`, `depend_on_contracts`, `constructor_injection`, `forbidden_symbols`, and `unverifiable_dependency`, under the `clear_dart_lints/` prefix. Style diagnostics remain optional. The setup verifier rejects attempts to disable or lower architecture checks; it does not run an alternative architecture engine.

## Files and layers

```yaml
schema_version: 2
include: ['lib/**']
exclude: ['lib/**/*.g.dart', 'lib/**/*.freezed.dart']
layers:
  ui: ['lib/presentation/**']
  state: ['lib/application/**']
  domain: ['lib/domain/**']
  data: ['lib/data/**']
  app: ['lib/main.dart', 'lib/app/**']
```

`schema_version`, a nonempty `include`, nonempty `layers`, and `rules.layer_dependencies.allowed` are required. Unknown keys, duplicate keys, unknown layer/role names, malformed YAML/globs, and empty required selectors fail configuration validation. Lists and mapping keys use the shapes shown here; a typo is not silently ignored.

Paths are package-relative, case-sensitive globs with normalized `/` separators. `lib/**` covers the complete source tree; `lib/*` does not express the same nested coverage. Each included, nonexcluded **physical Dart file** must belong to exactly one layer. This includes part files. Zero matches produces `unclassified_source`; multiple matches produces `ambiguous_layer`. Avoid overlapping a broad `lib/**` layer with narrower layers. Tests and other directories are outside this example's include; add and classify them when you want those sources checked.

`exclude` explicitly skips architecture checks for matching sources. Architecture never automatically skips generated suffixes or a generated-code marker. An excluded local file can still be a dependency target: it must have an unambiguous layer, and its layer must be allowed. Keep generated-file paths within the relevant layer globs. Analyzer file exclusions are separate; the setup audit rejects included sources hidden from analysis without a corresponding architecture exclusion.

## Allowed dependency edges

```yaml
rules:
  layer_dependencies:
    allowed:
      - from: [ui]
        to: [ui, state, domain]
        uris: ['dart:core', 'dart:async', 'package:flutter/**']
      - from: [state]
        to: [state, domain]
        uris: ['dart:core', 'dart:async', 'package:bloc/**']
      - from: [domain]
        to: [domain]
        uris: ['dart:core', 'dart:async', 'dart:collection']
      - from: [data]
        to: [data, domain]
        uris: ['dart:*', 'package:http/**']
      - from: [app]
        to: [app, ui, state, domain, data]
        uris: ['dart:*', 'package:flutter/**', 'package:flutter_bloc/**', 'package:bloc/**', 'package:http/**']
```

The policy denies dependencies by default. An allowance applies when the source layer matches `from`. `to` permits **local target layers**; `uris` permits **external library URIs**. At least one of `to` or `uris` must be nonempty. Matching allowances combine permissions. Same-layer edges and SDK libraries also need explicit permission. An own-package URI wildcard cannot bypass a local target's layer; an unclassified local target is forbidden.

Imports, exports, conditional branches, parts, resolved references and original declaration identities contribute to checks. Own-package barrels are followed through exports/parts, including cycles. Explicitly approving an external package permits its imports/exports without inspecting that package's internal dependency graph. A reference to a configured forbidden symbol is still checked by declaration identity. Do not use a broad `package:**` approval to avoid understanding actual dependencies.

A layer spanning `lib/features/*/domain/**` allows edges among all matching features when that layer is allowed. It **does not enforce cross-feature isolation**. Define separate layers such as `items_domain` and `account_domain`, with disjoint paths and explicit edges, if you require that policy. This is a finite dependency graph, not an implicit feature-name comparison.

## Roles

```yaml
roles:
  view:
    paths: ['lib/presentation/views/**']
  state_manager:
    types:
      - library: package:bloc/bloc.dart
        name: Bloc
  repository:
    names: ['*Repository', '*RepositoryImpl']
    libraries: ['lib/domain/repositories/**', 'lib/data/repositories/**']
```

A role has one or more alternatives: declaration `paths`; paired `names` **and** `libraries`; or resolved base `types`. Alternatives combine with OR. Within the names/libraries alternative both must match. Library selectors may match the declaration's physical package-relative path or library URI. At least one nonempty alternative is required. A `types` entry contains an exact library identity and declaration name, not a class-name glob. A public barrel may identify the base declaration. Resolved superclass and implemented-interface ancestry also establish roles.

`Bloc` and `Cubit` are different bases. A `*Bloc` name alone does not prove Bloc identity, and a Cubit is not a Bloc subtype. The Bloc and Cubit templates deliberately select only their respective resolved bases. Configure both type entries if the project permits both. MVVM has no universal base; its template uses an explicit view-model folder role and documents that convention.

Extending or implementing a role does not itself constitute a forbidden consumer dependency. Role checks examine the containing consumer declaration. A top-level function or untyped consumer has no class role. Merely sharing the state layer does not grant repository access, and exposing a repository through a state manager does not grant a view permission to consume it. Self access within an allowed role is permitted. Nested generic and typedef types are resolved for dependency checks.

## Role consumers and composition roots

```yaml
rules:
  # Keep layer_dependencies from the complete configuration above.
  role_dependencies:
    composition_roots: ['lib/main.dart', 'lib/app/**']
    restrictions:
      - source_layers: [ui, state]
        dependency_roles: [repository]
        allowed_consumer_roles: [state_manager]
      - source_layers: [state]
        dependency_roles: [state_manager]
        allowed_consumer_roles: []
```

Each restriction limits references to its `dependency_roles`, inside its `source_layers`, to consumers with an allowed role. An empty allowed list forbids all such consumers. All matching restrictions must pass; adding a second restriction cannot loosen the first one. Omitted rules impose no extra role constraint. The second restriction prevents a state manager from depending on a sibling state manager while still allowing views to use state managers.

`composition_roots` exempts only the containing rule, only at explicitly matching source paths. It does not override layer edges, forbidden symbols, or file classification. Keep wiring in `lib/main.dart` or `lib/app/**`, give the app layer the required edges, and inject assembled dependencies. This is independent of the DI library; any additional DI package needs explicit URI permission in the app layer.

## Abstract contracts and injection are separate

```yaml
rules:
  # Keep layer_dependencies and roles from your complete configuration.
  depend_on_contracts:
    source_layers: [state]
    dependency_roles: [repository]
    composition_roots: ['lib/main.dart', 'lib/app/**']
  constructor_injection:
    source_layers: [state, data]
    dependency_roles: [repository, data_source]
    composition_roots: ['lib/main.dart', 'lib/app/**']
```

These are fragments: define every referenced role in the complete file. `depend_on_contracts` checks that the dependency type used by a consumer is abstract. It does not prove where that dependency was obtained. `constructor_injection` checks acquisition and field origin: constructor parameters, initializing formals, and supported assignments from constructor parameters establish injected fields. Creating a repository directly or obtaining it through a service locator is not constructor injection. Roots may construct implementations and inject them.

```dart
abstract interface class ItemRepository {
  Future<List<Item>> load();
}

class ItemsCubit extends Cubit<ItemsState> {
  final ItemRepository repository;
  ItemsCubit(this.repository) : super(const ItemsState());
}
```

Clean templates support either direct repository injection into a state manager or an optional use-case object receiving that repository. They do not require empty pass-through use cases. Repository contracts remain abstract in either route. Data implementations implement the domain contracts; they do not force domain to import data.

## Forbidden symbols and explicit exceptions

```yaml
rules:
  # Keep layer_dependencies from your complete configuration.
  forbidden_symbols:
    source_layers: [domain]
    symbols:
      - library: dart:convert
        name: jsonDecode
exceptions:
  - rule: unverifiable_dependency
    paths: ['lib/data/legacy_decoder.dart']
    reason: 'Legacy dynamic decoder is isolated here pending typed replacement.'
```

Forbidden symbol entries identify resolved declarations by library URI and name, including prefixed references and reexports. A class entry also covers its constructors and members. A same-named unrelated application declaration is not that symbol. Domain templates already restrict external libraries; this rule can additionally identify a particular declaration.

An exception has a diagnostic `rule`, nonempty source `paths`, and a nonempty human-readable `reason`. It bypasses that rule in matching source files, so keep paths narrow and review the reason. Valid exception rules are `layer_dependencies`, `role_dependencies`, `depend_on_contracts`, `constructor_injection`, `forbidden_symbols`, and `unverifiable_dependency`. Exceptions cannot excuse invalid configuration, missing layer classification, or ambiguous layers. Do not replace explicit exceptions with analyzer ignores or severity reductions.

## Static boundary

This is resolved static analysis, not a proof of runtime architecture. Dynamic/unresolved dependencies that cannot be classified can produce `unverifiable_dependency`; fix their types and resolution before considering an explicit, reasoned exception. Reflection, generated runtime wiring, behavior hidden inside an approved external library, runtime service-locator registration, and semantic business responsibilities are not fully established by source dependency checks. Neither passing analysis nor the setup audit proves that a class has the correct business responsibility.

The verifier audits setup, files and suppression comments; the native analyzer performs architecture checks. Both are required. The plugin rereads the policy on subsequent analysis. Restart the Analysis Server after installing/updating the plugin or changing plugin options; rerun both commands after policy changes.
