# MVVM MobX templates

Choose [MVVM MobX](../templates/README.md) in feature-first or layer-first layout. Copy the complete `clear_dart_lints.yaml` and merge the analyzer options. The flow is View → MobX Store/ViewModel → abstract Repository → Service. MobX and its generator are development dependencies of this repository's regression tests, not runtime dependencies of the linter.

## Layout and roles

| Responsibility | Feature first | Layer first |
| --- | --- | --- |
| Views and Observer widgets | `lib/features/*/presentation/views/**` | `lib/presentation/views/**` |
| Stores/ViewModels and generated parts | `lib/features/*/presentation/viewmodels/**` | `lib/presentation/viewmodels/**` |
| Domain contracts and entities | `lib/features/*/domain/**` | `lib/domain/**` |
| Repository implementations | `lib/features/*/data/repositories/**` | `lib/data/repositories/**` |
| Services | `lib/features/*/data/services/**` | `lib/data/services/**` |
| Composition roots | `lib/main.dart`, `lib/app/**` | `lib/main.dart`, `lib/app/**` |

The `state_manager` role resolves `Store` from `package:mobx/mobx.dart`, including mixin and superclass ancestry. Both the private abstract base and its public generated-store wrapper qualify. A helper, a class named `ItemsViewModel`, or a local mixin named `Store` does not qualify merely by name or directory. The generic MVVM template retains its independent path-based convention.

Views may use ViewModel state/actions. They cannot consume repositories, including repository objects exposed through Store getters or generic containers. Only Stores may consume repositories in the restricted layers; only repositories may consume services. Stores cannot depend on sibling Stores under this policy. MobX supports other store arrangements; edit the role restrictions deliberately if your application requires those arrangements.

State approves `mobx` and basic Dart libraries. UI and app bootstrap also approve `flutter_mobx` and Flutter. State cannot import Flutter, `flutter_mobx`, data implementations or services. Domain/core cannot import MobX or Flutter. Repository and service dependencies are passed through constructors; no provider-read or service-locator exemption is enabled. Assemble concrete implementations in `lib/main.dart` or `lib/app/**`.

## Dependencies and generation

Add mutually compatible versions to the consuming Flutter application's `pubspec.yaml`, keeping the plugin/verifier installation described in the [agent guide](agent_integration.md). For example, the tested package families are:

```yaml
dependencies:
  flutter:
    sdk: flutter
  mobx: ^2.7.0
  flutter_mobx: ^2.4.0
dev_dependencies:
  clear_dart_lints: 0.6.2
  mobx_codegen: ^2.7.8
  build_runner: ^2.15.1
```

Resolve with `flutter pub get` and retain the resulting lockfile. The generator and this plugin share analyzer/build dependencies, so select compatible versions rather than overriding their constraints. The regression fixtures use MobX 2.7.0 and mobx_codegen 2.7.8. See the official [MobX setup guide](https://mobx.netlify.app/getting-started) and [generator package](https://pub.dev/packages/mobx_codegen).

For feature-first, define the domain contract in `lib/features/items/domain/repositories/item_repository.dart`:

```dart
abstract interface class ItemRepository {
  Future<int> load();
}
```

In `lib/features/items/presentation/viewmodels/items_view_model.dart`:

```dart
import 'package:mobx/mobx.dart';
import '../../domain/repositories/item_repository.dart';

part 'items_view_model.g.dart';

class ItemsViewModel = _ItemsViewModel with _$ItemsViewModel;

abstract class _ItemsViewModel with Store {
  _ItemsViewModel(this._repository);

  final ItemRepository _repository;

  @observable
  int count = 0;

  @computed
  bool get hasItems => count > 0;

  @action
  Future<void> load() async {
    count = await _repository.load();
  }
}
```

The named mixin application inherits the base constructor, so `ItemsViewModel(repository)` receives the abstract dependency. An explicit public wrapper with a forwarding constructor is also supported:

```dart
class ItemsViewModel extends _ItemsViewModel with _$ItemsViewModel {
  ItemsViewModel(super.repository);
}
```

Use one wrapper form per class. Handwritten Store bases are checked for layer, role, abstract-contract and constructor-injection violations. `@observable`, `@computed`, synchronous/async `@action` members, assignments and increment/decrement operations remain subject to normal static analysis.

Put the service in `data/services/item_service.dart`, implement `ItemRepository` in `data/repositories/item_repository_impl.dart`, and inject the service into that implementation. Assemble the graph in `lib/app/composition.dart`:

```dart
import '../features/items/data/services/item_service.dart';
import '../features/items/data/repositories/item_repository_impl.dart';
import '../features/items/presentation/viewmodels/items_view_model.dart';

final itemsViewModel = ItemsViewModel(ItemRepositoryImpl(ItemService()));
```

Adapt constructor arguments to your actual service. Keep transport/networking in data; `http` is the template's example external package permission. A Store can also be written without generation using `Observable`, `Action` and `runInAction`, while keeping the resolved `Store` mixin and constructor injection.

## Flutter views

In `lib/features/items/presentation/views/items_view.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import '../viewmodels/items_view_model.dart';

class ItemsView extends StatelessWidget {
  const ItemsView({super.key, required this.model});

  final ItemsViewModel model;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => Text(model.count.toString()));
  }
}
```

Pass the assembled model from app bootstrap. Adjust the composition imports for layer-first paths; the domain import inside the ViewModel and the relative View → ViewModel import remain the same in both layouts.

Run generation before verification:

```sh
dart run build_runner build
dart run clear_dart_lints:verify_setup
dart analyze --format=machine --fatal-infos
```

The plugin does not run `mobx_codegen`. Keep generated parts beside their handwritten libraries. The policies explicitly exclude `*.g.dart`, `*.freezed.dart` and `lib/generated/**` as sources; excluded local targets still need an unambiguous layer. Missing/stale generated output must be repaired by generation. A generated-file comment alone does not exclude handwritten code.

## Limits and regression checks

The architecture checks do not prove that every mutation occurs in an action, that every Observer tracks the intended observables, or that reactions are disposed. Own the reaction lifecycle and invoke its disposer when the owner is released, as illustrated in MobX's [Store organization guide](https://mobx.netlify.app/guides/stores). The role selector recognizes resolved Store ancestry; it does not verify the generator's runtime behavior or forbid all alternative ways of implementing Store.

Feature-first templates enable `feature_dependencies` for feature isolation; layer-first layouts can opt in with explicit capture patterns. See [configuration semantics](configuration.md) and the [agent workflow](agent_integration.md).

Repository regressions include real generator output, runtime observable/computed/action/reaction checks, and resolved architecture tests for both layouts. Regenerate all framework fixtures together from the repository root:

```sh
dart run build_runner build --build-filter='test/fixtures/**/*.g.dart'
dart format test/fixtures
```

`dart run tool/verify_mobx.dart` resolves temporary Flutter consumers, audits both policies, and checks native clean/failing analyzer gates using real `flutter_mobx` Observer widgets. It uses `flutter` from PATH; optionally pass its executable path as the first argument. Use the matching Flutter Dart SDK and allow normal access to dependency/plugin caches.
