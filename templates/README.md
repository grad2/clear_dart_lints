# Editable architecture templates

Choose the architecture and folder layout, then copy the two YAML files from that directory into your package root. Merge analyzer options rather than creating duplicate keys. Each directory contains a complete schema 2 configuration and its own setup guide. There is no runtime inheritance, preset loader, generator, or dependency on these template paths.

| Architecture | Feature first | Layer first | State-manager role |
| --- | --- | --- | --- |
| Layered Bloc | [setup](layered_bloc/feature_first/README.md) | [setup](layered_bloc/layer_first/README.md) | Resolved `Bloc` base |
| Layered Cubit | [setup](layered_cubit/feature_first/README.md) | [setup](layered_cubit/layer_first/README.md) | Resolved `Cubit` base |
| Clean Bloc | [setup](clean_bloc/feature_first/README.md) | [setup](clean_bloc/layer_first/README.md) | Resolved `Bloc`; use cases optional |
| Clean Cubit | [setup](clean_cubit/feature_first/README.md) | [setup](clean_cubit/layer_first/README.md) | Resolved `Cubit`; use cases optional |
| Layered Riverpod | [setup](layered_riverpod/feature_first/README.md) | [setup](layered_riverpod/layer_first/README.md) | Provider/notifier declaration paths and resolved notifier bases |
| Clean Riverpod | [setup](clean_riverpod/feature_first/README.md) | [setup](clean_riverpod/layer_first/README.md) | Same Riverpod roles; use cases optional |
| MVVM | [setup](mvvm/feature_first/README.md) | [setup](mvvm/layer_first/README.md) | Explicit view-model declaration paths |
| MVVM MobX | [setup](mvvm_mobx/feature_first/README.md) | [setup](mvvm_mobx/layer_first/README.md) | Resolved `Store` mixin, including generated wrapper ancestry |

Layered flow is View → Bloc/Cubit → abstract Repository → DataSource. Clean adds a domain use-case option; a state manager can still receive a repository directly. MVVM flow is View → ViewModel → abstract Repository → Service. All templates define app/composition roots and a separate shared core layer.

Riverpod uses View → provider/notifier → abstract Repository → DataSource, with optional Clean use cases. Its four templates add `lib/di/**` for dependency providers and assembly, permit provider composition, and support manual and generated providers/notifiers. Read the [Riverpod guide](../doc/riverpod.md) for examples, generation commands and static limits.

MVVM MobX uses View → Store/ViewModel → abstract Repository → Service. Its two templates identify real MobX Stores, support `mobx_codegen` parts and preserve constructor injection. Read the [MobX guide](../doc/mobx.md) for generated/private-base examples and Flutter Observer integration.

Feature-first uses `lib/features/<feature>/presentation`, `domain` and `data`; layer-first uses `lib/presentation`, `lib/domain` and `lib/data`, optionally with feature subdirectories inside the appropriate role folder. All eight feature-first templates enable `feature_dependencies`, with automatic feature names, shared core and explicit composition roots. Cross-feature edges require review and an explicit permission. Layer-first templates can opt in using the [feature path patterns](../doc/configuration.md#feature-dependencies) matching their directory structure.

Adapt the explicit role folders, repository name patterns and external package URI permissions to the consumer before auditing. Data approves `http` as an example, not every networking/DI library. Domain is limited to explicitly listed basic Dart libraries and shared core. Generated exclusions are explicit and editable.

Use the [complete agent integration guide with a copyable consumer AGENTS.md snippet](../doc/agent_integration.md), [field semantics and limitations](../doc/configuration.md), and [0.5 migration guide](../doc/migration_0_5.md).
