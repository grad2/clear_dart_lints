# layered_bloc: layer_first

Copy `clear_dart_lints.yaml` to the package root and merge `analysis_options.yaml` into the root options. Pin the matching verifier dev dependency to `0.6.0` as shown in the [agent integration guide](../../../doc/agent_integration.md). These files are explicit, editable configuration; no generator or runtime preset loader is involved.

Policy: View → Bloc → abstract Repository → DataSource. Domain entities/contracts use only the explicitly listed basic Dart libraries and `core`; data owns transport. The data example approves `package:http/**` only. Add specific package URI permissions where your real dependencies require them.

The state-manager role resolves the actual `Bloc` declaration from `package:bloc/bloc.dart`, including ancestry. A class merely named `ItemsBloc` does not qualify. Cubit does not qualify for this preset; switch preset or explicitly add that resolved base identity.

Suggested paths (one `items` feature shown; omit the feature directory for layer-first):

```text
lib/presentation/views/items_view.dart
lib/presentation/blocs/items_bloc.dart
lib/domain/entities/item.dart
lib/domain/repositories/item_repository.dart
lib/data/repositories/item_repository_impl.dart
lib/data/datasources/item_data_source.dart
lib/core/clock.dart
lib/app/composition.dart
lib/main.dart
```

Repository contracts and implementations match `*Repository` / `*RepositoryImpl` together with their configured declaration folders. Change both selectors for other naming. Inheritance and `implements` carry that role. Keep all dependency assembly in `lib/main.dart` or `lib/app/**`: roots may construct concrete repositories, data sources and state managers, while consumers receive dependencies through constructors. Repository consumers require abstract contracts. Root exemptions apply only to the rules that declare them; layer permissions still apply.

Views cannot use repositories directly. Only configured state managers may consume repositories in the restricted layers. Only repositories may consume data sources in the restricted layers. A state manager cannot consume another state manager. Events, states and helpers outside the selected role cannot obtain repository access by sharing a directory or by using a class name suffix.

Every included physical Dart file must match exactly one layer. Put new bootstrap files in `lib/app/`, shared code in `lib/core/`, and adapt globs for other folders. Generated files are excluded explicitly, not by filename magic or a comment marker; excluded local targets still require a classified layer when imported.

These layer globs span all features: **they do not isolate one feature from another**. To enforce that boundary, split feature-specific layers and write explicit allowed edges; see [configuration semantics](../../../doc/configuration.md).

Run the read-only setup audit, then native analysis:

```sh
dart run clear_dart_lints:verify_setup
dart analyze --format=machine --fatal-infos
```

Follow the complete [agent integration guide and copyable consumer AGENTS.md snippet](../../../doc/agent_integration.md). See [migration](../../../doc/migration_0_5.md) for schema 1 projects.
