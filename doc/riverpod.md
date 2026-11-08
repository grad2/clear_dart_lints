# Riverpod architecture templates

Choose [Layered Riverpod or Clean Riverpod](../templates/README.md), in feature-first or layer-first layout. Copy the complete policy and merge the analyzer options. These templates target Riverpod 3 providers and notifiers, with or without code generation. The linter has no Riverpod runtime dependency.

## Layout and dependency flow

| Responsibility | Feature first | Layer first |
| --- | --- | --- |
| Views | `lib/features/*/presentation/views/**` | `lib/presentation/views/**` |
| Provider functions and factories | `lib/features/*/presentation/providers/**` | `lib/presentation/providers/**` |
| Notifier classes | `lib/features/*/presentation/notifiers/**` | `lib/presentation/notifiers/**` |
| Domain contracts and entities | `lib/features/*/domain/**` | `lib/domain/**` |
| Data implementations | `lib/features/*/data/**` | `lib/data/**` |
| Dependency providers and assembly | `lib/di/**` | `lib/di/**` |

Layered flow is View → state provider/notifier → abstract Repository → DataSource. Clean also allows an optional domain use case between state and repository. A state manager may still use a repository directly; pass-through use cases are not required.

State may depend on other state providers, so derived providers and notifier providers can compose normally. Views may consume exposed state and notifier APIs, but cannot consume repository, data-source or use-case objects, including when wrapped in a provider or returned by `ref.watch`. Domain and shared core cannot import Riverpod or Flutter. State cannot import data implementations. These templates approve `riverpod` and `riverpod_annotation` in state and DI; views and app bootstrap additionally approve `flutter_riverpod`. Add specific URI permissions if using `hooks_riverpod` or other packages.

`lib/di/**` is a separate composition layer: it may depend on domain, data, core and its own providers. State can read DI providers without gaining access to data implementations. DI cannot depend on presentation/state; register `ProviderScope` and any state-provider overrides in `lib/app/**` or `lib/main.dart`, where all application layers are available. Keep repository providers typed to abstract contracts.

## Without code generation

For feature-first, put this contract in `lib/features/items/domain/repositories/item_repository.dart`:

```dart
abstract interface class ItemRepository {
  Future<List<String>> load();
}
```

Implement it in `lib/features/items/data/repositories/item_repository_impl.dart`. Receive data sources through its constructor. Assemble those dependencies in `lib/di/item_providers.dart`:

```dart
import 'package:riverpod/riverpod.dart';
import '../features/items/data/datasources/item_data_source.dart';
import '../features/items/data/repositories/item_repository_impl.dart';
import '../features/items/domain/repositories/item_repository.dart';

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  final source = ItemDataSource();
  return ItemRepositoryImpl(source);
});
```

In `lib/features/items/presentation/providers/items_provider.dart`:

```dart
import 'package:riverpod/riverpod.dart';
import '../../../../di/item_providers.dart';

final itemsProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(itemRepositoryProvider).load();
});
```

Alternatively, use a notifier in `presentation/notifiers/items_notifier.dart`:

```dart
import 'package:riverpod/riverpod.dart';
import '../../../../di/item_providers.dart';

class ItemsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() {
    return ref.watch(itemRepositoryProvider).load();
  }
}

final itemsProvider = AsyncNotifierProvider<ItemsNotifier, List<String>>(
  ItemsNotifier.new,
);
```

`Provider`, `FutureProvider`, `StreamProvider`, family and autoDispose factories, and `Notifier`, `AsyncNotifier` and `StreamNotifier` are supported. Views use `flutter_riverpod` consumers under a `ProviderScope` installed in the app bootstrap. See the official [providers](https://riverpod.dev/doc/concepts2/providers) and [Refs](https://riverpod.dev/doc/concepts2/refs) guides.

## With code generation

Add consumer dependencies `flutter_riverpod`, `riverpod` and `riverpod_annotation`, and dev dependencies `riverpod_generator` and `build_runner`, using mutually compatible versions. The plugin itself does not install or run a generator. Follow Riverpod's [installation guide](https://riverpod.dev/doc/introduction/getting_started) for the versions in your application.

In `lib/di/item_providers.dart`, the generated equivalent of the repository provider is:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../features/items/data/datasources/item_data_source.dart';
import '../features/items/data/repositories/item_repository_impl.dart';
import '../features/items/domain/repositories/item_repository.dart';

part 'item_providers.g.dart';

@Riverpod(keepAlive: true)
ItemRepository itemRepository(Ref ref) {
  return ItemRepositoryImpl(ItemDataSource());
}
```

In `presentation/providers/items_provider.dart`, choose a generated function:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../di/item_providers.dart';

part 'items_provider.g.dart';

@riverpod
Future<List<String>> items(Ref ref) {
  return ref.watch(itemRepositoryProvider).load();
}
```

Or put a generated notifier in `presentation/notifiers/items_notifier.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../di/item_providers.dart';

part 'items_notifier.g.dart';

@riverpod
class ItemsNotifier extends _$ItemsNotifier {
  @override
  Future<List<String>> build() {
    return ref.watch(itemRepositoryProvider).load();
  }
}
```

Use the provider name emitted by your generator; the function and notifier examples are alternatives. Adjust imports for layer-first paths. In Clean, declare constructor-injected use cases in `domain/usecases/`, expose them through DI providers, then read those providers from state.

Generate before auditing and analyzing:

```sh
dart run build_runner build
dart run clear_dart_lints:verify_setup
dart analyze --format=machine --fatal-infos
```

The policies explicitly exclude `*.g.dart`, `*.freezed.dart` and `lib/generated/**` as source files. Keep parts beside their handwritten libraries so their physical paths still have a layer when referenced. Handwritten `@riverpod` functions and classes remain checked. Missing or stale generated output must be fixed by generation; do not suppress `unverifiable_dependency` or analyzer errors. See Riverpod's [code-generation guide](https://riverpod.dev/doc/concepts/about_code_generation).

## Enforcement and limits

The `state_manager` role selects declarations in the configured provider/notifier folders and classes with resolved Riverpod notifier ancestry. Path selection is a convention: it trusts all matching classes, top-level functions and variables, including helpers. It does not verify that every declaration is annotated or actually used as a provider. Narrow the selectors if your project needs a smaller trusted boundary. A return type or a `*Provider` / `*Notifier` name alone does not give a function a consumer role.

The templates set `rules.constructor_injection.allow_provider_reads: true`. This accepts resolved Riverpod `Ref.read` and `Ref.watch` calls for the rule's dependency roles, including direct lazy-field initializers in notifiers. Abstract-contract checks still apply, including inferred concrete results and nested provider types. Creating a repository directly, calling a service locator, reading through `ProviderContainer`, or using a local class named `Ref` is not an approved acquisition. Data sources and domain use cases still receive dependencies through constructors; their layer permissions do not allow Riverpod. Existing templates retain constructor-only acquisition because the option defaults to false.

The checks use resolved declarations and static types. They do not prove runtime overrides, provider lifetimes, disposal, dynamic provider graphs, or the behavior of excluded generated code. Use `riverpod_lint` for Riverpod API conventions and refactorings. Feature-first templates enable `feature_dependencies` for feature isolation; layer-first layouts can opt in with explicit capture patterns. See [configuration semantics](configuration.md) and the [agent integration workflow](agent_integration.md).

The regression fixtures use real Riverpod packages and checked-in generator output. Regenerate them from the repository root with:

```sh
dart run build_runner build --build-filter='test/fixtures/**/*.g.dart'
dart format test/fixtures
```

Run `dart run tool/verify_riverpod.dart` to audit all four policies and exercise clean and failing native analyzer gates on temporary consumers. This requires the normal Dart plugin cache to be writable.
