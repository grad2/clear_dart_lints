# clear_dart_lints example

This Flutter project is an intentionally invalid analyzer fixture. It demonstrates optional style diagnostics and schema 2 architecture warnings in the IDE and native analyzer; it is not a runnable Flutter application or a clean consumer baseline.

## Setup

Use Dart `>=3.13.0 <4.0.0` and a compatible Flutter SDK. From a checkout:

```sh
dart pub get
cd example
flutter pub get
dart analyze --format=machine --fatal-infos
```

The analysis command is expected to fail because the fixture deliberately violates rules. Its `analysis_options.yaml` installs the native plugin from the parent directory and opts into styles. Its `clear_dart_lints.yaml` supplies the explicit schema 2 architecture policy. Architecture diagnostics are warnings automatically; optional styles remain informational. Restart the Analysis Server after changing plugin installation/options.

For a real consumer project, start from a [complete architecture template](../templates/README.md) and follow the [agent integration guide, including the consumer AGENTS.md snippet](../docs/agent_integration.md). Pin matching plugin/verifier versions, adapt paths and approved dependencies, then require both `dart run clear_dart_lints:verify_setup` and `dart analyze --format=machine --fatal-infos` to succeed. This intentionally failing fixture is checked with its dedicated verifier instead.

## What to inspect

| File under `lib/` | Purpose |
| --- | --- |
| `good.dart` | Valid block bodies in Flutter builders and a short arrow function elsewhere. |
| `bad.dart` | Arrow-body style violations; try **Convert to block body** in the IDE. |
| `multiple_classes.dart` | Additional public class style diagnostic. |
| `parts/two.dart` | Part-file class organization, checked per physical file. |
| `new_rules.dart` | Effective Dart/style examples and schema 2 layer, role, contract, constructor-injection and forbidden-symbol violations. |
| `data/internal.dart` | A local data target deliberately imported across a forbidden layer boundary by `new_rules.dart`. |
| `suppressed.dart` | Standard suppressions for optional style diagnostics. |
| `excluded_conventions.dart` | Explicit configuration exclusion. |
| `generated.g.dart` | Generated-file behavior; architecture skips require explicit configuration, while optional styles retain their existing behavior. |

All included sources are classified in the example layer. This deliberately compact graph demonstrates rule behavior, not a recommended production layout. Use the templates to establish real UI/state/domain/data/core/app boundaries. See [configuration semantics and static limitations](../docs/configuration.md).

## Verify expected diagnostics

After resolving the example's Flutter dependencies, run from the package root:

```sh
dart run tool/verify_example.dart
```

The verifier works with a temporary copy and checks expected native architecture warning severity, optional styles, style suppressions, exclusions and repeated analysis. It validates an intentionally failing fixture; it does not replace the two-command setup/analyzer gate for consumer projects.
