# clear_dart_lints

An independent native Dart/Flutter analyzer plugin with configurable architecture policy and optional Effective Dart/style conventions. This package is not an official Dart or Flutter product and adds no application runtime behavior.

Version **0.5.0** makes architecture a default analyzer **warning** policy. Choose an editable architecture template, classify your sources, and run a read-only setup audit followed by native analysis. Optional style rules remain opt-in, with the existing arrow-body quick fixes.

## Start here

1. Choose [Layered Bloc, Layered Cubit, Clean Bloc, Clean Cubit or MVVM](templates/README.md), in feature-first or layer-first layout. Copy the complete YAML policy and merge the analyzer snippet.
2. Follow the [agent integration guide](docs/agent_integration.md) for matching plugin/verifier installation, CI commands and a **copyable consumer AGENTS.md snippet**.
3. Read [configuration semantics and static limitations](docs/configuration.md). Existing 0.4 users must follow the [breaking migration guide](docs/migration_0_5.md); schema 1 is not supported.

Clean use cases are optional: state managers may receive an abstract repository directly or through a use case. Bloc and Cubit presets recognize the corresponding resolved framework base identity, not merely a class-name suffix. Feature-spanning layer globs do not imply cross-feature isolation.

## Requirements and installation

Use Dart SDK **>=3.13.0 <4.0.0**, or a Flutter SDK containing a compatible Dart version. The development baseline uses Dart **3.13.2**. See [validation history](https://github.com/grad2/clear_dart_lints/blob/main/VALIDATION.md) for recorded checks.

In the consumer's root `pubspec.yaml`, add the verifier executable as a development dependency:

```yaml
dev_dependencies:
  clear_dart_lints: 0.5.0
```

In the consumer's root `analysis_options.yaml`, install the native plugin:

```yaml
formatter:
  page_width: 100
plugins:
  clear_dart_lints:
    version: 0.5.0
    diagnostics:
      # Optional styles; architecture is automatically enabled as warnings.
      prefer_block_body_for_long_expression: true
      prefer_block_body_for_build: true
      one_public_class_per_file: true
```

Merge with existing options without duplicate keys. Keep inherited formatter settings. The plugin version must exactly match the verifier dependency; the audit rejects plugin version ranges that could resolve independently. A dev dependency alone does not install the native plugin. For local development, use the same `path: ../clear_dart_lints` directory in both entries. No `custom_lint` integration is required.

Copy a [complete schema 2 `clear_dart_lints.yaml`](templates/README.md) into the consumer package root, adapt its paths and approved package URIs, then resolve dependencies (`dart pub get`, or `flutter pub get` for Flutter projects). Restart the Dart Analysis Server; in VS Code use **Dart: Restart Analysis Server**.

Verify from the consumer root, requiring both commands to succeed:

```sh
dart run clear_dart_lints:verify_setup
dart analyze --format=machine --fatal-infos
```

The first command audits setup, effective analyzer options, layer coverage and suppression comments without editing files or running analysis. It separately reports setup issues such as `missing_plugin`, `disabled_architecture` and `architecture_suppression` when architecture enforcement is hidden or weakened. The second command is the native analyzer and enforces both architecture warnings and enabled style infos. An optional package-root argument is accepted by `verify_setup`. For scripts, stop on the first failure. See the [full workflow](docs/agent_integration.md).

## Architecture policy

Schema 2 requires explicit source inclusion, exactly one layer per included nonexcluded physical source, and a deny-by-default allowed dependency graph. Same-layer edges, SDK libraries and external packages all need explicit permission. Generated sources require explicit exclusion globs; generated markers do not suppress architecture. Excluded local targets remain subject to target-layer classification.

| Diagnostic | Purpose |
| --- | --- |
| `invalid_configuration` | Reject invalid or missing schema 2 architecture policy. |
| `unclassified_source` | Require an included physical source to belong to a layer. |
| `ambiguous_layer` | Require layer globs to be disjoint for included sources. |
| `layer_dependencies` | Enforce allowed local layers and external library URIs. |
| `role_dependencies` | Restrict which consumer roles may reference dependency roles. |
| `depend_on_contracts` | Require abstract dependency types. |
| `constructor_injection` | Require constructor acquisition and injected field origins. |
| `forbidden_symbols` | Forbid configured resolved declaration identities. |
| `unverifiable_dependency` | Report dependency flows that cannot be verified statically. |

All architecture diagnostics are warnings and automatically enabled. Composition roots are explicit per applicable rule; they do not waive layer classification or layer permissions. Exceptions need a supported rule, narrow source paths and a human-readable reason; configuration/classification failures cannot be excepted. See [all fields and their interactions](docs/configuration.md).

## Optional style diagnostics

Enable individual diagnostics under `plugins.clear_dart_lints.diagnostics`:

| Category | Diagnostic | Since |
| --- | --- | --- |
| Effective Dart | `avoid_public_late_final_fields` | 0.3.0 |
| Effective Dart | `avoid_nullable_async_returns` | 0.3.0 |
| Effective Dart | `avoid_nullable_collection_returns` | 0.4.0 |
| Custom style | `prefer_block_body_for_long_expression` | 0.2.0 |
| Custom style | `prefer_block_body_for_build` | 0.2.0 |
| Custom style | `one_public_class_per_file` | 0.2.0 |
| Custom style | `avoid_nested_widget_ternaries` | 0.4.0 |

These diagnostics retain informational severity and their existing generated-file behavior; they do not replace architecture configuration. Architecture has no automatic code fixes.

## Custom conventions

### prefer_block_body_for_long_expression

This is an author-defined convention. [Effective Dart recommends arrow bodies for simple functions](https://dart.dev/effective-dart/usage#consider-using--for-simple-functions); using `formatter.page_width` as the threshold is this plugin’s own implementation.

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

This is an author-defined Flutter style convention, not an Effective Dart requirement.

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

This is an author-defined file organization convention.

The first public class in a file is allowed. Each additional public class is reported at its name. A class is public if its name does not start with `_`; private classes are unrestricted.

```dart
class PublicScreen {}     // Allowed.
class _PrivateHelper {}   // Allowed.
class AnotherScreen {}    // Move to a separate file.
```

Classes with modifiers such as `abstract`, `base`, `final`, `interface`, `sealed`, and `mixin class` count. Named mixin applications (`class C = Object with M;`) also count. Ordinary mixins, enums, extensions, and extension types do not.

Each physical file is checked independently, including `part` files. A public class in a library file and one in its part file are allowed. This rule does not move declarations or edit imports automatically.

## Effective Dart

These independent checks follow [Effective Dart: Design](https://dart.dev/effective-dart/design). They do not require an architecture configuration. Enable each diagnostic explicitly under `plugins.clear_dart_lints.diagnostics`.

### avoid_public_late_final_fields (0.3.0)

Source: [AVOID public late final fields without initializers](https://dart.dev/effective-dart/design#avoid-public-late-final-fields-without-initializers).

```dart
class Item {
  late final String label; // Reported: exposes a public setter.
  static late final int count; // Reported too.
  late final String _cache; // Allowed: private.
  late final String title = computeTitle(); // Allowed: initializer.
}
```

Inherited contracts are exempt. No quick fix is provided.

### avoid_nullable_async_returns (0.3.0)

Source: [AVOID returning nullable Future, Stream, and collection types](https://dart.dev/effective-dart/design#avoid-returning-nullable-future-stream-and-collection-types).

```dart
Future<Item>? load() => null; // Reported.
Stream<Item>? get changes => null; // Reported.
Future<Item?> find() async => null; // Allowed: nullable result, not Future.
```

Checks public top-level functions/getters, members of public types and public extensions. Private APIs, fields, locals and overrides of inherited contracts are exempt. Resolved SDK declarations identify types, including import prefixes and typedefs. Unrelated types with the same names are allowed. No quick fix is provided.

### avoid_nullable_collection_returns (0.4.0)

Source: [AVOID returning nullable Future, Stream, and collection types](https://dart.dev/effective-dart/design#avoid-returning-nullable-future-stream-and-collection-types).

```dart
List<Item>? load() => null; // Reported.
List<Item?> loadOptionalItems() => []; // Allowed.
Map<String, Item> get byId => {}; // Allowed.
```

Checks SDK `Iterable`, `List`, `Set` and `Map` with the same API and override exclusions as the async check. If `null` has a distinct meaning from an empty collection, suppress the diagnostic for that API and document that meaning. No quick fix is provided.

## Additional custom style convention

### avoid_nested_widget_ternaries (0.4.0)

An author-defined Flutter readability rule. Reports a conditional expression in a branch of another conditional when both choose resolved Flutter Widgets (including subtypes and nullable variants).

```dart
// Reported.
Widget buildChoice() => first ? (second ? const A() : const B()) : const C();
// Allowed: a single Widget choice.
Widget simpleChoice() => first ? const A() : const B();
// Allowed: property values, and collection if.
final color = first ? (second ? red : blue) : green;
final children = <Widget>[if (first) const A() else const B()];
```

Unrelated types named `Widget` are allowed. No quick fix is provided.

## Recommended SDK analyzer settings

Use SDK rules such as `prefer_initializing_formals`, `avoid_returning_this`, `unnecessary_lambdas` and `prefer_collection_literals` through the analyzer’s `linter.rules` settings or your chosen SDK lint set. This plugin does not duplicate them.

## Quick fixes

For either arrow-body diagnostic, select **Convert to block body** on the highlighted `=>`.

The fix adds `return` for returned values and keeps expression statements for `void` functions. It preserves `async` and comments; asynchronous `Future<void>` bodies await value-producing expressions when appropriate.

**The fix formats the file** using `formatter.page_width`. Other unformatted portions of the same file can therefore change. Fixes are applied to one arrow at a time.

## Optional style suppression

Optional styles can be disabled individually under the plugin's `diagnostics` mapping. Standard analyzer ignore comments can suppress a style diagnostic:

```dart
class First {}

// ignore: clear_dart_lints/one_public_class_per_file
class Second {}
```

A file-level style suppression uses `// ignore_for_file: clear_dart_lints/one_public_class_per_file`. Architecture uses reviewed configuration exceptions instead. The setup audit rejects architecture ignore comments, broad warning suppressions that can hide architecture, disabled architecture diagnostics and severity reductions. Removing the plugin is also detected by the audit. Keep both verification commands in CI.

## Examples and development

The [Flutter example guide](example/README.md) explains the intentionally invalid analyzer fixture and its local plugin installation. It is not a runnable application. From the package checkout, resolve package dependencies, then resolve the example's Flutter dependencies before verifying its expected diagnostics:

```sh
dart pub get
cd example
flutter pub get
```

From the package root:

```sh
dart test
dart analyze
dart run tool/verify_example.dart
```

The consumer gate is `verify_setup` followed by `dart analyze --format=machine --fatal-infos`; the example verifier has a different purpose because the fixture intentionally contains violations. See [validation history](https://github.com/grad2/clear_dart_lints/blob/main/VALIDATION.md) for recorded release checks.

## Compatibility notes

Analyzer and formatter dependencies use compatible version ranges, with resolved versions recorded in the repository lockfile. Update analyzer/plugin dependencies as a coordinated change. Schema 2 has no inheritance or schema 1 compatibility; templates are copied and edited, never loaded as runtime presets.

## License

[MIT](LICENSE), copyright 2026 Grad.
