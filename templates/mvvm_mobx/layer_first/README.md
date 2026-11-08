# mvvm_mobx: layer_first

Copy `clear_dart_lints.yaml` to the package root and merge `analysis_options.yaml` into the root options. Pin the matching verifier dev dependency to `0.6.2` as shown in the [agent integration guide](../../../doc/agent_integration.md). These are complete, editable schema 2 policies.

Policy: View → MobX Store/ViewModel → abstract Repository → Service. Views consume model state/actions. Repositories receive services through their constructors. Domain and core remain independent of MobX and Flutter; state uses MobX without importing Flutter or data implementations.

The state-manager role resolves the actual `Store` mixin from `package:mobx/mobx.dart`, including private base classes and generated wrapper ancestry. A class name suffix, a ViewModel directory or a local `Store` namesake does not grant repository access. Both `class Model = _Model with _$Model` and explicit generated-mixin subclasses are supported. Generic MVVM keeps its own path-based role convention.

Suggested paths:

```text
lib/presentation/views/items_view.dart
lib/presentation/viewmodels/items_view_model.dart
lib/presentation/viewmodels/items_view_model.g.dart  # generated
lib/domain/entities/item.dart
lib/domain/repositories/item_repository.dart
lib/data/repositories/item_repository_impl.dart
lib/data/services/item_service.dart
lib/core/clock.dart
lib/app/composition.dart
lib/main.dart
```

Keep concrete assembly in `lib/main.dart` or `lib/app/**`. Stores must receive abstract repositories through constructor parameters; direct construction, service locators and provider reads do not satisfy that policy. Only repositories consume services in the restricted layers. Views cannot consume repository objects exposed through a Store. Stores cannot depend on sibling Stores under this policy.

Add compatible consumer dependencies `mobx` and `flutter_mobx`, plus dev dependencies `mobx_codegen` and `build_runner`. See the [MobX guide](../../../doc/mobx.md) for complete annotated Store, constructor, generated-mixin and Observer examples. Generate before verification:

```sh
dart run build_runner build
dart run clear_dart_lints:verify_setup
dart analyze --format=machine --fatal-infos
```

Keep generated parts beside the handwritten Store library. The policy explicitly excludes `*.g.dart`, `*.freezed.dart` and `lib/generated/**` as sources; imported targets still require an unambiguous layer. Handwritten Store bases and actions remain checked. A generated-code comment alone does not waive architecture checks. Manual Stores using `Observable`/`Action` are also supported; omit generation when no parts are required.

Adapt role folders, repository names and package URI permissions to your app. Data approves `http` as an example. These feature-spanning globs **do not enforce cross-feature isolation**. Read [configuration semantics](../../../doc/configuration.md), the [agent workflow](../../../doc/agent_integration.md), and [schema 1 migration](../../../doc/migration_0_5.md). Architecture checks do not prove action coverage, Observer tracking or reaction disposal; see the [MobX limits](../../../doc/mobx.md#limits-and-regression-checks).
