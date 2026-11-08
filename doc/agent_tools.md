# Read-only agent tools

These tools describe and compare policy or audit its installation. The native
analyzer remains responsible for evaluating application architecture.

## File context before editing

```sh
dart run clear_dart_lints:context lib/features/catalog/domain/item.dart --format=json
dart run clear_dart_lints:context lib/features/catalog/domain/item.dart --root packages/shop
```

Paths are relative to the package root (`--root`, otherwise the current directory).
Absolute Dart paths within that package are accepted. Parent traversal and existing
symlink ancestors resolving outside the package are rejected. The file need not exist.
Output describes inclusion, exclusion, layers, allowed layer/URI dependencies,
applicable restrictions, composition-root exemptions, reasoned exceptions and
feature membership. Excluded paths remain visibly unenforced. Role selectors have
`resolved: false`: matching a path does not prove framework ancestry or a consumer role.
No dependency resolution, application parsing or file writing occurs.

## Policy comparison

```sh
dart run clear_dart_lints:policy_diff --base origin/main --format=json
dart run clear_dart_lints:policy_diff --base <trusted-commit> packages/shop
```

The required Git revision identifies a commit with the same package-relative
`clear_dart_lints.yaml`. Comparison reads its Git object and the working-tree policy
without checkout. It does not fetch, stage, commit or change files. Fetch the trusted
base before invoking it. Missing Git history, a missing base policy, or an invalid
base policy is an execution error, not a clean result.

Each change includes `key`, `before`, `after`, `assessment`, and `reason`.
`weakening` and `review_required` block the gate. Added permissions, exceptions and
composition-root paths, removed constraints, reduced source coverage and enabled
provider reads weaken policy. Changed layer/role selectors and feature path patterns
require review. Glob replacement is conservative: containment is not inferred from
the current source tree. Removing permissions/exceptions or adding constraints can
pass as `tightening`. Reason-only exception edits are `informational`.
Comments, mapping/list-set ordering, duplicate permissions, and equivalent grouping
of layer allowances do not create changes. The tool is conservative, not a complete
theorem prover for policy equivalence. It does not compare analyzer options;
`verify_setup` audits their effective enforcement.

## JSON and exit codes

All three commands support `--format=text|json` (text is the default).
`verify_setup [package-root]` retains its original text output and argument.
JSON stdout contains exactly one document, including expected failures and usage
errors when JSON format is selected. `--help` prints usage text.

```json
{
  "format_version": 1,
  "command": "verify_setup",
  "package_root": "/workspace/shop",
  "passed": true,
  "data": {"checked_files": 42, "architecture_checked": false},
  "issues": []
}
```

Issues contain `code`, `path`, `message`, and separate one-based `line`/`column`
when known. Findings never encode source coordinates into the JSON path.
Context data includes `architecture_checked: false`; a successful lookup or audit
does not establish a clean architecture result.

| Exit | Meaning |
| --- | --- |
| 0 | Successful context/audit, or comparison without blocking changes. |
| 1 | Invalid policy/classification, failed audit, weakening, or review required. |
| 2 | Tool execution failure, including unavailable/invalid Git baseline. |
| 64 | Invalid command arguments. |

Use a fail-fast [consumer CI sequence](agent_integration.md#agent-cli-and-ci-policy-gate):
policy comparison, setup audit, then `dart analyze --format=machine --fatal-infos`.
The project supplies the trusted Git baseline. A reviewed policy change is handled
through that project's review and baseline process, not by changing the agent's
comparison target to make its local result pass.

## Public Dart API

```dart
import 'package:clear_dart_lints/agent_tools.dart';

final policy = ArchitectureConfiguration.parse(yaml, root: packageRoot);
final context = inspectFilePolicy(policy, 'lib/features/catalog/domain/item.dart');
final comparison = comparePolicies(previousPolicy, policy);
final audit = await verifySetup(packageRoot);
```

`FilePolicyContext`, `PolicyComparison`, `PolicyChange`, `PolicyAssessment`,
`SetupVerification`, `SetupIssue`, and `ToolIssue` provide typed results.
`toJson()` produces command data or individual findings; `toolReport()` creates
the versioned envelope. `SetupIssue.path` preserves its legacy text location;
its JSON uses `filePath` and numeric coordinates when available. Existing
configuration constructors remain source compatible; optional location metadata
uses `PolicyLocation` values captured from YAML spans.

## Diagnostic repair examples

Messages name the source/target layer, declaration location and YAML key when
available. Related IDE messages point to the policy span and dependency declaration.
Each code has its own correction. Examples below are fragments of an otherwise
complete policy or source, not complete configuration files.

| Code | Before | After |
| --- | --- | --- |
| `invalid_configuration` | `schema_version: 1` in a legacy policy | Migrate the complete policy to schema 2 and correct the indicated key. |
| `unclassified_source` | New `lib/helpers/item.dart` matches no layer. | Place it in the intended configured folder, such as `lib/core/item.dart`. |
| `ambiguous_layer` | Both `lib/**` and `lib/domain/**` select a domain file. | Replace the broad layer with disjoint paths for its responsibility. |
| `layer_dependencies` | Domain imports `ItemRepositoryImpl` from data. | Domain uses its own abstract `ItemRepository`; data implements it. |
| `role_dependencies` | A view receives an `ItemRepository`. | The permitted state manager receives it; the view consumes state. |
| `depend_on_contracts` | `final ItemRepositoryImpl repository;` | `final ItemRepository repository;` using an abstract contract. |
| `constructor_injection` | `final repository = ItemRepositoryImpl();` inside a manager. | `Manager(this.repository);` with assembly at a configured root. |
| `forbidden_symbols` | Domain calls `jsonDecode`. | Data decodes transport data and returns a typed domain object. |
| `unverifiable_dependency` | `void load(dynamic repository)` calls `repository.load()`. | Use a resolvable, permitted `ItemRepository` parameter. |
| `feature_dependencies` | Catalog imports checkout implementation details. | Catalog depends on its own permitted contract, assembled through an explicit integration boundary. A required direct feature edge needs policy review. |
| `unclassified_feature` | `lib/misc/item.dart` belongs to no feature scope. | Move it into its feature or the configured shared folder. |
| `ambiguous_feature` | `lib/features/**` is also listed as shared. | Narrow shared paths to the intended common code, such as `lib/core/**`. |

Do not silence architecture warnings or move dependencies into a helper merely to
change the consumer's apparent role. Classification errors cannot have exceptions.
A narrow exception to a supported dependency rule must retain a concrete reason.
