# clean_riverpod: layer_first

Copy `clear_dart_lints.yaml` to the package root and merge `analysis_options.yaml` into the root options. Pin the matching verifier dev dependency to `0.6.2` as shown in the [agent integration guide](../../../doc/agent_integration.md). These are complete, editable schema 2 policies.

Policy: View → provider/notifier → abstract Repository → DataSource. State providers may compose other state providers. Views cannot consume repositories, data sources or use cases through providers. Domain and core remain independent of Riverpod and Flutter; state cannot import data implementations.

Clean also allows an optional constructor-injected use case in `domain/usecases/`. A state manager may read an abstract repository directly; no pass-through use case is required.

Suggested paths:

```text
lib/presentation/views/items_view.dart
lib/presentation/providers/items_provider.dart
lib/presentation/notifiers/items_notifier.dart
lib/domain/entities/item.dart
lib/domain/repositories/item_repository.dart
lib/domain/usecases/load_items.dart  # optional
lib/data/repositories/item_repository_impl.dart
lib/data/datasources/item_data_source.dart
lib/di/item_providers.dart
lib/core/clock.dart
lib/app/app.dart
lib/main.dart
```

Put dependency providers and concrete assembly in `lib/di/**`, a separate composition layer accessible to state. Return abstract repository contracts from those providers. Keep `ProviderScope`, app setup and state-provider overrides in `lib/app/**` or `lib/main.dart`. Data sources and domain use cases receive dependencies through constructors.

The state-manager role uses explicit provider/notifier declaration folders plus resolved `Notifier`, `AsyncNotifier` and `StreamNotifier` ancestry from Riverpod. Folder selectors trust matching classes, top-level functions and variables, including helpers. Manual provider factories and generated `@riverpod` functions/classes use the same policy. The explicit `allow_provider_reads: true` option permits actual Riverpod `Ref.read` and `Ref.watch`; it does not allow service locators or `ProviderContainer` acquisition.

See the [Riverpod guide](../../../doc/riverpod.md) for manual/generated examples, dependencies, names, and limits. Keep generated parts beside their handwritten libraries. The policy explicitly excludes `*.g.dart`, `*.freezed.dart` and `lib/generated/**` from source checks; excluded targets still need a layer. Handwritten sources remain checked. Generate before verification when using code generation:

```sh
dart run build_runner build
dart run clear_dart_lints:verify_setup
dart analyze --format=machine --fatal-infos
```

Without code generation, omit the first command. Adapt role folders, repository names, and approved package URIs to your application. The networking example approves `http`; add other dependencies explicitly. Feature-spanning globs **do not enforce cross-feature isolation**. Read [configuration semantics](../../../doc/configuration.md), the [agent workflow](../../../doc/agent_integration.md), and [schema 1 migration](../../../doc/migration_0_5.md).
