# clear_dart_lints

An independent Dart/Flutter analyzer plugin implementing selected Effective Dart recommendations and opt-in custom conventions. This package is not an official Dart or Flutter product.

| Category | Rule | Since |
| --- | --- | --- |
| Effective Dart | `avoid_public_late_final_fields` | 0.3.0 |
| Effective Dart | `avoid_nullable_async_returns` | 0.3.0 |
| Effective Dart | `avoid_nullable_collection_returns` | 0.4.0 |
| Custom conventions | `prefer_block_body_for_long_expression` | 0.2.0 |
| Custom conventions | `prefer_block_body_for_build` | 0.2.0 |
| Custom conventions | `one_public_class_per_file` | 0.2.0 |
| Custom conventions | `layer_dependencies` | 0.3.0 |
| Custom conventions | `repositories_only_in_blocs` | 0.3.0 |
| Custom conventions | `depend_on_contracts` | 0.4.0 |
| Custom conventions | `no_transport_in_domain` | 0.4.0 |
| Custom conventions | `avoid_nested_widget_ternaries` | 0.4.0 |

All rules are opt-in. Diagnostics appear in supported IDEs and in `dart analyze` or `flutter analyze`.

## Requirements

- Dart SDK **>=3.13.0 <4.0.0**.
- Flutter projects must use a Flutter SDK containing a compatible Dart version.
- The implementation was checked on Dart **3.13.2** and Flutter **3.47.2**. See [Validation history](https://github.com/grad2/clear_dart_lints/blob/main/VALIDATION.md).

This is a development tool; it does not add runtime behavior to your application.

## Installation

Add the plugin to the root `analysis_options.yaml` of your package or pub workspace:

```yaml
formatter:
  page_width: 100

plugins:
  clear_dart_lints:
    version: ^0.4.0
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

## Configurable custom architecture conventions

These four rules express author-defined architecture policies. They are independent of any application, state management or dependency injection package. Names such as `ItemsBloc` below are examples configured by the consumer, not built-in assumptions.

Enable the desired diagnostics:

```yaml
plugins:
  clear_dart_lints:
    version: ^0.4.0
    diagnostics:
      avoid_public_late_final_fields: true
      avoid_nullable_async_returns: true
      avoid_nullable_collection_returns: true
      layer_dependencies: true
      repositories_only_in_blocs: true
      depend_on_contracts: true
      no_transport_in_domain: true
      avoid_nested_widget_ternaries: true
```

Place one `clear_dart_lints.yaml` in the analyzed package root. Version 1 has no inheritance or nested overrides. Paths are package-relative with normalized separators. Glob matching is case-sensitive. Role `names` and `libraries` must both match an original type declaration; `libraries` can match a package-relative declaration path or its library URI. Resolved ancestors and implemented interfaces also confer roles.

```yaml
schema_version: 1
exclude: ['lib/generated/**']
layers:
  presentation: ['lib/presentation/**']
  domain: ['lib/domain/**']
  data: ['lib/data/**']
roles:
  repository:
    names: ['*Repository', '*RepositoryImpl']
    libraries: ['lib/domain/**', 'lib/data/**']
  bloc:
    names: ['*Bloc']
    libraries: ['lib/presentation/**']
  transport:
    names: ['ApiClient']
    libraries: ['lib/data/**']
rules:
  layer_dependencies:
    source_layers: [presentation, domain]
    forbidden:
      - from: [presentation, domain]
        to: [data]
        uris: ['package:http/**']
  repositories_only_in_blocs:
    source_layers: [presentation]
    repository_roles: [repository]
    allowed_consumer_roles: [bloc]
    composition_roots: ['lib/presentation/assembly/**']
  depend_on_contracts:
    source_layers: [presentation, domain]
    dependency_roles: [repository]
    composition_roots: ['lib/presentation/assembly/**']
  no_transport_in_domain:
    source_layers: [domain]
    transport_roles: [transport]
    forbidden_symbols:
      - library: dart:convert
        name: jsonEncode
      - library: dart:convert
        name: jsonDecode
      - library: dart:convert
        name: json
      - library: dart:convert
        name: JsonEncoder
      - library: dart:convert
        name: JsonDecoder
      - library: dart:convert
        name: JsonCodec
```

Each enabled architecture rule requires its own parameters. Missing files, malformed YAML, unsupported schema versions, unknown keys and unknown layer/role references produce `invalid_configuration`. There are no hidden architecture defaults. Configuration uses the analyzer filesystem and is cached per analysis context and package. Restart Analysis Server after editing it.

### layer_dependencies (0.3.0)

Reports forbidden imports, exports and type references. For example, with the configuration above, importing `package:sample_app/data/items.dart` from presentation is reported; importing a domain contract is allowed. `from` intersects the current source layers; a matching `to` layer or URI glob prohibits the dependency. `to` and `uris` may be empty or omitted.

Relative and package URIs, every conditional import/export branch, parts, transitive exports and cyclic export graphs are covered. Original declaration libraries identify referenced types, so barrels do not conceal their layer. No quick fix is provided.

### repositories_only_in_blocs (0.3.0)

Reports references to repository types and values outside allowed consumer classes in `source_layers`, including constructor injection and typed service location such as `locate<ItemRepository>()`. `ItemsBloc` and its subclasses may hold and use an `ItemRepository`; a screen outside an allowed role may not. Public bloc fields do not grant callers permission to use repository values. Configured composition root paths are exempt. No quick fix is provided.

### depend_on_contracts (0.4.0)

Dependencies matching `dependency_roles` must use abstract contracts and enter through constructors. Both `implements` and `extends` confer configured roles.

```dart
class ItemsBloc {
  final ItemRepository repository;
  ItemsBloc(this.repository); // Allowed when ItemRepository is abstract.
}
// Concrete constructor parameters, service location and constructing
// ItemRepositoryImpl are reported outside composition roots.
```

Constructor initializing formals, field initializers and resolved assignments from constructor parameters support injected fields. Composition roots may create concrete implementations. No quick fix is provided.

### no_transport_in_domain (0.4.0)

In configured source layers, reports types matching `transport_roles` and resolved references to `forbidden_symbols`. For example, `jsonEncode(item)` from `dart:convert` is reported; an unrelated application function named `jsonEncode` is allowed. Prefixes and reexports do not change element identity. A class symbol also forbids its constructors and members. No quick fix is provided.

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

All new rules skip `*.g.dart`, `*.freezed.dart` and the standard `// GENERATED CODE - DO NOT MODIFY BY HAND` marker. Optional YAML `exclude` globs also apply to the new rules. Existing style rules retain their behavior.

## Recommended SDK analyzer settings

Use SDK rules such as `prefer_initializing_formals`, `avoid_returning_this`, `unnecessary_lambdas` and `prefer_collection_literals` through the analyzer’s `linter.rules` settings or your chosen SDK lint set. This plugin does not duplicate them.

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

Standard analyzer file exclusions apply. Use the same suppression syntax for every diagnostic, including `clear_dart_lints/invalid_configuration`.

## Examples and development

The repository includes a Flutter example configured with a local `path` dependency on the plugin:

```sh
dart pub get
cd example
flutter pub get
dart analyze
```

The example preserves the original eight style diagnostics and adds `new_rules.dart` covering all eight new rules. `good.dart`, `suppressed.dart`, `excluded_conventions.dart` and generated code have no expected diagnostics.

From the package root, contributors can run:

```sh
dart test
dart analyze
dart run tool/verify_example.dart
```

The verification tool checks the complete example, repeats analysis with the cache, and enables each new diagnostic independently. It restores the example options after those checks. See [Validation history](https://github.com/grad2/clear_dart_lints/blob/main/VALIDATION.md) for the checks performed for this release.

Diagnostics are informational by default. To make them fail a CI check, use:

```sh
dart analyze --fatal-infos
```

## Compatibility notes

Analyzer and formatter dependencies use compatible version ranges, with the resolved versions recorded in the repository lockfile. Duplicate-diagnostic handling uses a small compatibility bridge to the analyzer's internal plugin configuration model. Update these dependencies as a coordinated change.

## License

[MIT](LICENSE), copyright 2026 Grad.
