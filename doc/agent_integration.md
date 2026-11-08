# Agent integration for consumer projects

Use this guide in the application or package that consumes clear_dart_lints. The native Dart analyzer plugin owns diagnostics in the IDE and `dart analyze`. A separate read-only setup audit checks that the policy can actually run and has not been bypassed. No architecture-specific CLI replaces the analyzer.

## 1. Inspect the existing workspace, then choose a policy

Start in the intended consumer package. Check the installed SDK and existing repository before copying a template:

```sh
dart --version
rg --files -g 'pubspec.yaml' -g 'pubspec.lock' -g 'analysis_options.yaml' -g 'clear_dart_lints.yaml' -g 'lib/**' -g '.github/workflows/**'
```

For a Flutter repository, also run `flutter --version` and use the Dart SDK shipped with that Flutter installation. Read the package/workspace `pubspec.yaml`, SDK constraints, dependency lockfile, root and nested analyzer options (including their `include` chain), existing architecture policy, source tree and CI scripts. Identify the package root that owns each source and whether the repository uses pub workspaces. Keep existing dependency management and lint configuration. Determine whether state managers actually inherit Bloc, Cubit or a different base before choosing a preset; do not infer that from filenames alone.

If dependencies are already resolved, `dart pub deps --style=compact` helps confirm the actual framework/DI/transport packages. Resolve missing dependencies using the repository's existing workflow before interpreting missing-type analysis errors.

Choose one of the [sixteen complete templates](../templates/README.md): Layered Bloc/Cubit/Riverpod, Clean Bloc/Cubit/Riverpod, MVVM or MVVM MobX, each in feature-first or layer-first layout. Copy its `clear_dart_lints.yaml` into your package root; merge its analyzer options with the existing root `analysis_options.yaml`.

For Riverpod, follow the [provider/notifier and code-generation guide](riverpod.md). Generate required parts before running the setup audit and analysis. Keep dependency assembly in `lib/di/**`; preserve the state layer's explicit `allow_provider_reads` option and the policy's abstract-contract restrictions.

For MVVM MobX, follow the [Store/code-generation guide](mobx.md). Generate required parts before verification, keep the resolved `Store` selector, and inject repository/service dependencies through constructors. Composition remains in `lib/main.dart` or `lib/app/**`.

Before asking an agent to change application code, align the policy with actual declaration paths, repository contract names, state-manager framework, approved third-party packages, and DI assembly paths. Every included physical Dart file must match exactly one layer. Include a shared `core` layer and an `app`/bootstrap layer rather than silently leaving those files outside classification.

Bloc/Cubit selectors resolve the real framework base identity; suffixes are insufficient. Generic MVVM uses a documented declaration-path selector because there is no universal view-model base; MVVM MobX resolves the framework `Store` mixin instead. Clean use cases are optional: inject the abstract repository directly or inject a use case that receives it. Feature-first templates enable `feature_dependencies`; layer-first layouts can opt in with patterns matching their actual feature folders. See [field semantics and static limitations](configuration.md).

## 2. Install matching plugin and verifier versions

The root `pubspec.yaml` needs the package as a development dependency to expose the setup-audit executable:

```yaml
dev_dependencies:
  clear_dart_lints: 0.6.2
```

The root `analysis_options.yaml` separately installs the native plugin:

```yaml
formatter:
  page_width: 100
plugins:
  clear_dart_lints:
    version: 0.6.2
    # Optional style diagnostics; architecture is automatically enabled.
    diagnostics:
      prefer_block_body_for_build: true
      one_public_class_per_file: true
```

Preserve existing `include`, formatter, analyzer, lint and plugin settings. Merge mappings without duplicate keys. A dev dependency alone does not install the native plugin; a native plugin alone does not make the consumer's `dart run` command available. Pin the plugin to the exact version of the resolved verifier dependency. The audit rejects a range such as `^0.6.2` for the plugin because the two independently resolved installations could drift. Resolve dependencies with `dart pub get`, or `flutter pub get` for Flutter projects, and retain the consumer's lockfile according to its existing policy.

For a local checkout, both entries must resolve to the **same** directory:

```yaml
# pubspec.yaml
dev_dependencies:
  clear_dart_lints:
    path: ../clear_dart_lints
```

```yaml
# analysis_options.yaml
plugins:
  clear_dart_lints:
    path: ../clear_dart_lints
```

Restart the Dart Analysis Server after plugin installation or an update. In VS Code use **Dart: Restart Analysis Server**. This package requires Dart `>=3.13.0 <4.0.0`; Flutter projects need a compatible embedded Dart SDK.

## 3. Establish a visible baseline

From the consumer package root, run these commands in order and require both to succeed:

```sh
dart run clear_dart_lints:verify_setup
dart analyze --format=machine --fatal-infos
```

For shell scripts or CI, stop after a failed audit:

```sh
set -e
dart run clear_dart_lints:verify_setup
dart analyze --format=machine --fatal-infos
```

The audit accepts an optional package-root argument, for example `dart run clear_dart_lints:verify_setup packages/catalog`. Run it in an environment where the verifier dependency is resolved, and analyze the same target package from its root. For a multi-package repository, configure and verify each intended consumer package; the command is not an implicit recursive workspace orchestrator.

The audit reads configuration and source; it does not rewrite files, fix violations, generate configuration, or run analysis. It checks setup/version consistency, effective analyzer options (including includes and nested options), classification of included physical sources, conflicting analyzer exclusions, and architecture suppression comments. It rejects disabled/lowered architecture diagnostics and broad `type=warning` suppression that could conceal them. Style-only `type=lint` suppression does not hide these native architecture warnings and remains allowed. It parses comments rather than treating text inside a string as an ignore directive. Generated-code markers do not grant an architecture exemption.

Native analysis then evaluates the actual source dependencies and emits machine-readable results. Architecture diagnostics are warnings; optional styles are informational. `--fatal-infos` also makes enabled style diagnostics fail the gate. Fix preexisting issues or record reviewed, narrow configuration exceptions with reasons before treating the baseline as clean. The setup audit alone does not establish a clean architecture result.

## 4. Give the agent concrete consumer instructions

Copy the following into the consuming repository's `AGENTS.md` and adapt the named template/folders to its real policy. This is a consumer snippet, not an instruction to change the clear_dart_lints package itself.

```markdown
## Dart architecture and verification

Before choosing a policy or editing Dart sources, check `dart --version` (and
`flutter --version` for Flutter), inspect the source tree, package/workspace
`pubspec.yaml`, lockfile, dependency/CI workflow, nested analyzer options and
existing policy. Confirm the actual state-manager base types and package roots.
Read `clear_dart_lints.yaml` and the effective `analysis_options.yaml`. The configuration is the executable architecture policy.
Check its selected template, physical file layers, role selectors, dependency
edges, composition roots and reasoned exceptions before adding a dependency.

Use constructor injection, or resolved Riverpod Ref.read/Ref.watch when the
selected policy explicitly enables allow_provider_reads. Generate required
Riverpod parts before verification. Views use state managers/view models; repositories
are consumed only by the configured roles and through abstract contracts.
Assemble concrete implementations in the configured composition roots. In a
Clean layout, use cases are optional: a state manager may receive a repository
directly or through a use case, as permitted by the configuration. Do not make
one state manager depend on another when the policy forbids that edge.

Place every new included Dart file in exactly one configured layer, including
parts, bootstrap and shared code. Do not assume broad feature-spanning layers
provide cross-feature isolation. Preserve existing policy strength. Do not
silence architecture diagnostics with ignore comments, disabled diagnostics,
severity reductions, analyzer exclusions or expanded source exclusions.

When a policy change is required by the requested feature, explain the new
edge or role and its reason, update the smallest relevant configuration scope,
and include that change in the review. Use a narrow exception with a concrete
reason only when the limitation cannot be resolved in typed application code;
never use exceptions for invalid or ambiguous classification.

Use the trusted POLICY_BASE Git reference configured by the project/CI. Do not
choose another baseline to hide policy changes. Read path context before adding
a source with `dart run clear_dart_lints:context <path> --format=json`.

After edits, from this package root, run in order and require all to succeed:

    dart run clear_dart_lints:policy_diff --base "$POLICY_BASE"
    dart run clear_dart_lints:verify_setup
    dart analyze --format=machine --fatal-infos

Run the tests relevant to the change as well. Report the commands and outcomes.
Configure POLICY_BASE before using this gate. A successful setup audit does not replace analyzer results. If verification
cannot run, report the exact blocker and do not claim the task passes.
```

Keep these instructions with the consumer so IDE work, agents and CI use the same policy. No separate agent runtime integration or network service is needed.

## 5. Review changes and fix failures

First distinguish the stage that failed. The setup audit reports issue codes in square brackets, such as `missing_plugin` (enable the native plugin), `plugin_version` / `verifier_version` (align the resolved installations), `disabled_architecture` (restore warning checks), `analyzer_exclusion` (reconcile analysis and architecture scope), and `architecture_suppression` (remove the reported ignore comment). A missing/invalid policy can also yield `invalid_configuration` during the audit. `empty_scope` means no included nonexcluded physical Dart sources remain; a successful audit requires actual source coverage. Linked source directories require a physical checkout or explicit exclusion instead of silent traversal. Fix audit findings before invoking analysis.

Native analyzer diagnostics use the `clear_dart_lints/` prefix. Interpret those results separately:

- `invalid_configuration`: fix the reported schema 2 policy/key path before interpreting other analyzer diagnostics.
- `unclassified_source` / `ambiguous_layer`: move the source or correct disjoint layer globs. A new folder needs an explicit policy decision.
- `layer_dependencies`: compare the reported source/target with the allowed graph. Prefer the correct contract boundary; add an edge only when the requested design needs it.
- `role_dependencies`: check the consumer's resolved role. Moving access into a helper in the same state folder does not give that helper a Bloc/Cubit role.
- `depend_on_contracts`: depend on an abstract repository type rather than its implementation.
- `constructor_injection`: receive the dependency through a constructor (or a resolved Riverpod `Ref.read`/`Ref.watch` when explicitly enabled) and move concrete construction/service location to a configured composition root.
- `forbidden_symbols`: move serialization/transport use to the permitted layer or replace the dependency.
- `unverifiable_dependency`: resolve missing imports/types and replace dynamic dependency flows. The [static boundary](configuration.md#static-boundary) describes what analysis can establish.

Review policy changes alongside application changes. Keep composition roots narrow, third-party URI approvals explicit, and exceptions specific and explained. Rerun both commands after changing configuration as well as after changing code. See [migration from 0.4](migration_0_5.md) for breaking changes.

## Agent CLI and CI policy gate

The [agent tools reference](agent_tools.md) documents JSON format version 1,
exit codes, API types and repair examples. `context` works for future file paths;
role selectors are not resolved type assignments. Use `--format=json` on any of
`context`, `policy_diff`, or `verify_setup` for one structured stdout document.

Choose a trusted base revision in project configuration or CI, fetch it, and run
from the consumer package root. For example, CI can set `POLICY_BASE` to the pull
request's base commit and fetch that object before these commands:

```sh
set -e
: "${POLICY_BASE:?Set a trusted Git revision before checking policy changes}"
dart run clear_dart_lints:policy_diff --base "$POLICY_BASE" --format=json
dart run clear_dart_lints:verify_setup --format=json
dart analyze --format=machine --fatal-infos
```

Potential weakening and unproved selector changes block comparison with exit 1.
Review the reported old/new values and reason; correct unintended changes or
review legitimate policy changes through the project's normal review process.
A missing base policy/ref is an execution failure, never a passing comparison.
Initial adoption needs an explicit project/CI decision about establishing its
trusted baseline. The comparison reads only the architecture YAML; the setup
audit checks effective analyzer settings and source suppression separately.
