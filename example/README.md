# clear_dart_lints example

This Flutter project demonstrates all eleven opt-in diagnostics. It deliberately
contains violations so you can inspect the diagnostics and try the quick fixes
in your IDE. It is an analyzer fixture, not a runnable Flutter application.

## Requirements and setup

Use Dart >=3.13.0 <4.0.0 and a Flutter SDK containing a compatible Dart version.
From a checkout of the package, run:

```sh
dart pub get
cd example
flutter pub get
dart analyze
```

The example's `analysis_options.yaml` installs the plugin from the parent
directory and enables every diagnostic. `clear_dart_lints.yaml` supplies the
architecture configuration. Restart the Dart Analysis Server after changing
the plugin configuration.

To enable a published version in your own project's root `analysis_options.yaml`:

```yaml
formatter:
  page_width: 100

plugins:
  clear_dart_lints:
    version: ^0.4.1
    diagnostics:
      prefer_block_body_for_long_expression: true
      prefer_block_body_for_build: true
      one_public_class_per_file: true
```

Merge these settings with your existing configuration. The native plugin
configuration installs the plugin; no application dependency is needed.
See the [package guide](https://pub.dev/packages/clear_dart_lints) for all rules
and the architecture configuration schema.

## What to inspect

| File under `lib/` | Expected result |
| --- | --- |
| `good.dart` | No diagnostics: block bodies in Flutter builders and a short arrow function elsewhere. |
| `bad.dart` | Four `prefer_block_body_for_build` and two `prefer_block_body_for_long_expression` diagnostics. Both rules provide a Convert to block body quick fix. |
| `multiple_classes.dart` | One `one_public_class_per_file` diagnostic. |
| `parts/two.dart` | One `one_public_class_per_file` diagnostic; each physical part file is checked independently. |
| `new_rules.dart` | Examples of all eight additional Effective Dart and custom rules, including architecture violations. These rules do not provide quick fixes. |
| `suppressed.dart` | No diagnostics: line and file suppressions. |
| `excluded_conventions.dart` | No diagnostics: excluded by the architecture configuration. |
| `generated.g.dart` | No diagnostics: generated code is skipped. |

Diagnostics are informational by default. `dart analyze --fatal-infos` makes
them fail the command, which is expected for this intentionally invalid fixture.

## Verify the expected diagnostics

After resolving the example's Flutter dependencies, run from the package root:

```sh
dart run tool/verify_example.dart
```

The verifier checks all eleven rules, part files, suppressions, exclusions and
generated code. It repeats analysis with the existing cache and enables each
additional rule independently, restoring the example configuration afterwards.
