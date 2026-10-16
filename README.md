# clear_dart_lints

A Dart analyzer plugin for readable function bodies and focused source files.

| Rule | Enforces |
| --- | --- |
| `prefer_block_body_for_long_expression` | Block bodies when a potential single-line arrow function exceeds the project's formatter width. |
| `prefer_block_body_for_build` | Block bodies for Flutter `build` methods and widget builder callbacks. |
| `one_public_class_per_file` | At most one public class in each Dart file. |

All rules are opt-in. Diagnostics appear in supported IDEs and in `dart analyze` or `flutter analyze`.

## Requirements

- Dart SDK **>=3.13.0 <4.0.0**.
- Flutter projects must use a Flutter SDK containing a compatible Dart version.
- The implementation was checked on Dart **3.13.2** and Flutter **3.47.2** before the package rename and English translation. See [Validation history](https://github.com/grad2/clear_dart_lints/blob/main/VALIDATION.md).

This is a development tool; it does not add runtime behavior to your application.

## Installation

Add the plugin to the root `analysis_options.yaml` of your package or pub workspace:

```yaml
formatter:
  page_width: 100

plugins:
  clear_dart_lints:
    version: ^0.2.0
    diagnostics:
      prefer_block_body_for_long_expression: true
      prefer_block_body_for_build: true
      one_public_class_per_file: true
```

Keep existing formatter settings if you already define them, including through `include`. Merge with an existing `plugins` section rather than adding a duplicate YAML key.

Restart the Dart Analysis Server after adding or updating the plugin. In VS Code, use **Dart: Restart Analysis Server**.

The native analyzer plugin configuration installs the plugin. You do not need to add it to your application's `dev_dependencies` or configure `custom_lint`.

For a local checkout, replace `version` with a path:

```yaml
plugins:
  clear_dart_lints:
    path: ../clear_dart_lints
    diagnostics:
      prefer_block_body_for_long_expression: true
      prefer_block_body_for_build: true
      one_public_class_per_file: true
```

See [Dart analyzer plugins](https://dart.dev/tools/analyzer-plugins) for the native plugin configuration.

## Rules

### prefer_block_body_for_long_expression

Use a block when the potential single-line representation of an arrow function exceeds the effective `formatter.page_width` for that source file. With a width of 100, a 100-character representation is allowed and a 101-character representation is reported. If no width is configured, the limit is 80.

```dart
// Reported if the potential single-line representation exceeds the limit.
String label() => someVeryLongExpression(
  firstArgument,
  secondArgument,
);

// Use a block body instead.
String label() {
  return someVeryLongExpression(
    firstArgument,
    secondArgument,
  );
}
```

The rule applies to functions, methods, getters, and closures. Existing argument wrapping and optional trailing commas do not change the potential single-line length. String contents are preserved.

Measurement includes the declaration, indentation, expression, and semicolon. Named callbacks also include the argument label, such as `builder: `. Annotations and documentation before declarations are excluded. Effective formatter options, including `include`, are resolved by the analyzer.

Comments inside an arrow body, multiline string literals, and other bodies that cannot be represented on one formatted line also require a block.

### prefer_block_body_for_build

Always use a block for Flutter build methods, regardless of expression length:

```dart
// Reported.
@override
Widget build(BuildContext context) => const SizedBox();

// Preferred.
@override
Widget build(BuildContext context) {
  return const SizedBox();
}
```

The rule recognizes non-static `build` methods with one Flutter `BuildContext` parameter and a Flutter `Widget` return type or subtype.

It also checks directly supplied closures in arguments named `builder` or ending in `Builder`, when the expected callback returns Flutter `Widget`, a subtype, or a nullable variant. This includes names such as `itemBuilder`, `transitionBuilder`, and `layoutBuilder`.

```dart
Builder(
  builder: (context) {
    return const SizedBox();
  },
);
```

Resolved Flutter types are checked, so unrelated local types named `Widget` or `BuildContext` do not match. Function references and variables holding callbacks are outside this rule's scope.

When both arrow-body rules are enabled, matching builders receive a single builder diagnostic rather than duplicate length and builder diagnostics.

### one_public_class_per_file

The first public class in a file is allowed. Each additional public class is reported at its name. A class is public if its name does not start with `_`; private classes are unrestricted.

```dart
class PublicScreen {}     // Allowed.
class _PrivateHelper {}   // Allowed.
class AnotherScreen {}    // Move to a separate file.
```

Classes with modifiers such as `abstract`, `base`, `final`, `interface`, `sealed`, and `mixin class` count. Named mixin applications (`class C = Object with M;`) also count. Ordinary mixins, enums, extensions, and extension types do not.

Each physical file is checked independently, including `part` files. A public class in a library file and one in its part file are allowed. This rule does not move declarations or edit imports automatically.

## Quick fixes

For either arrow-body diagnostic, select **Convert to block body** on the highlighted `=>`.

The fix adds `return` for returned values and keeps expression statements for `void` functions. It preserves `async` and comments; asynchronous `Future<void>` bodies await value-producing expressions when appropriate.

**The fix formats the file** using `formatter.page_width`. Other unformatted portions of the same file can therefore change. Fixes are applied to one arrow at a time.

## Disable or suppress rules

Set an individual diagnostic to `false`, or remove `clear_dart_lints` from `plugins` to disable the plugin. Restart the Analysis Server after configuration changes.

Use standard analyzer ignore comments with the plugin prefix:

```dart
class First {}

// ignore: clear_dart_lints/one_public_class_per_file
class Second {}
```

For an entire file:

```dart
// ignore_for_file: clear_dart_lints/one_public_class_per_file
```

Standard analyzer file exclusions apply. Extended end-to-end verification of suppression, exclusion, and independently disabled-rule scenarios remains incomplete; see [Validation history](https://github.com/grad2/clear_dart_lints/blob/main/VALIDATION.md).

## Examples and development

The repository includes a Flutter example configured with a local `path` dependency on the plugin:

```sh
dart pub get
cd example
flutter pub get
dart analyze
```

The example intentionally produces **eight diagnostics**: six in `bad.dart`, one in `multiple_classes.dart`, and one in `parts/two.dart`. `good.dart` has no expected diagnostics.

From the package root, contributors can run:

```sh
dart test
dart analyze
dart run tool/verify_example.dart
```

The verification tool checks the complete example and repeats analysis to verify that diagnostics survive cache reuse. These commands are provided for contributors; test suites were not rerun for the rename and translation.

Diagnostics are informational by default. To make them fail a CI check, use:

```sh
dart analyze --fatal-infos
```

## Compatibility notes

Analyzer and formatter dependencies use compatible version ranges, with the resolved versions recorded in the repository lockfile. Duplicate-diagnostic handling uses a small compatibility bridge to the analyzer's internal plugin configuration model. Update these dependencies as a coordinated change.

## License

[MIT](LICENSE), copyright 2026 Grad.
