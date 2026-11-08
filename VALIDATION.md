# Validation history

## 0.6.1 release preparation — 2026-11-08

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64.

- Includes the five static-dependency fixes and 14 positive/negative regression
  tests described below. The full 257-test fix verification remains applicable.
- After updating to 0.6.1, all 29 focused setup, configuration/template and static
  dependency regression tests passed.
- `dart analyze --fatal-infos`: no issues. Formatting checked 68 Dart files
  without changes; diff whitespace and local documentation links passed.
- `dart run tool/verify_example.dart`: native warnings, setup, feature boundaries,
  agent CLI, optional styles, secrets, exclusions and the clean gate passed.
- `dart run tool/verify_riverpod.dart`: all four policy/layout combinations passed
  setup, generated/manual provider sources and native clean/failing gates.
- `dart run tool/verify_mobx.dart <flutter-executable>`: both layouts passed setup,
  generated Stores, Flutter Observer and native warning gates.
- Updated installation examples, all sixteen analyzer template pins, the example
  lockfile and both framework verifier replacements to 0.6.1. The security rule's
  historical introduction version remains 0.6.0.
- Excluded local `.idea/` metadata from the published package. Consumer project
  files and local IDE settings remain untouched.

Publication validation is a clean-commit `dart pub publish --dry-run` gate before
upload. GitHub PR checks run the full test suite and native example gate again.

## Static dependency regression fixes — 2026-11-08

Environment: Dart 3.13.2, macOS arm64. Package version remains 0.6.0;
these changes are recorded as unreleased.

- Reproduced the five reported false-positive categories using minimal resolved
  sources: record fields, typed index writes, nullable function callbacks,
  explicit top-level dependency parameters and nullable constructor modes.
- Added 14 regression tests with valid positive fixtures and negative cases for
  dynamic receivers, unknown record members, unresolved index setters/methods,
  direct repository construction, locator acquisition, non-nullable null values,
  conditional origins and constructor overwrites from globals.
- Record field types are traversed so record-returning factories cannot hide
  repository acquisition. Existing layer, role and abstract-contract checks stay
  active; class methods and nested callbacks retain constructor injection.
- Final `dart test --reporter expanded`: all 257 tests passed. A focused run of
  the new cases, architecture policies and real Riverpod/MobX fixtures also
  passed all 94 tests after adding record-container dependency checks.
- `dart analyze --fatal-infos`: no issues. Formatting checked 68 Dart files
  without changes, and `git diff --check` passed.
- `dart run tool/verify_example.dart`: native warnings, setup, feature boundaries,
  agent CLI, optional styles, secrets, exclusions and the clean gate passed on
  isolated copies.

Consumer project files were not modified. No commit, push, tag, release or package
publication was performed during this local preparation.

## 0.6.0 release review — 2026-11-08

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64.

- Reviewed the architecture/feature policy changes, public agent API and CLI,
  secret recognizers, Riverpod/MobX templates and regression coverage.
- `dart test --reporter expanded`: all 243 tests passed. After replacing the
  fixed version in the setup regression with the package manifest version,
  all 12 setup-verifier tests passed again.
- `dart analyze --fatal-infos`: no issues. Formatting checked 67 Dart files
  without changes; `git diff --check` passed.
- `dart run tool/verify_example.dart`: setup audit, native warnings, feature
  boundaries, consumer agent CLI, optional styles, secrets, exclusions and
  the clean analyzer gate passed on isolated copies.
- `dart run tool/verify_riverpod.dart`: all four policy/layout combinations
  passed setup and native clean/failing analyzer gates.
- `dart run tool/verify_mobx.dart <flutter-executable>`: both layouts passed
  setup, real generated Stores, Flutter Observer and native warning gates.
- The example JSON setup audit passed with 10 checked Dart files. Policy
  comparison against `760eef759ca830004e920fb10215c974ee4f63da` passed without
  example policy changes.
- Updated all current installation/template pins to 0.6.0. The historical
  0.5 migration guide retains its version-specific instructions.
- The publish dry run identified the nonstandard `docs/` directory. Moved
  documentation to `doc/`, updated references, and verified all local Markdown
  link targets. Final publication validation must run from the release commit.
- The first Linux CI runs exposed a duplicate `analyzer` mapping in the
  temporary options used by the native exclusion check. The verifier now merges
  analyzer options structurally, preserving existing settings and exclusions.
  Failure reports include default-format analysis because Dart 3.13.2 omits
  priority configuration errors from machine output. Native verification runs
  before the longer unit suite so failures surface sooner.

The initial Flutter launcher/analytics calls were sandbox-blocked before checks
could complete; validation above used the bundled Dart SDK with cache access.
The package keeps schema 2, and feature isolation remains optional for existing
policies. Secret recognition is opt-in and never validates credentials online.

## Agent tools and feature boundaries — 2026-11-08

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64. Existing Riverpod,
MobX and secret-detection work was retained and included in regression checks.

- The resolved `package:test` runner (`--reporter expanded`) passed all **243
  tests**. Coverage includes the CLI JSON contract and exit codes, future paths,
  symlink traversal, suppression coordinates, conservative semantic comparison,
  temporary Git repositories, nested packages, missing baselines, all sixteen
  templates, feature isolation and existing architecture/style regressions.
- Focused policy-comparison and architecture-diagnostic regressions were also
  checked after refining exception reasons and inferred dependency locations.
- `dart analyze --fatal-infos`: no issues.
- `dart run tool/verify_example.dart`: native warning severity for all three
  feature diagnostics, explicit cross-feature permission, existing architecture,
  optional styles/secret detection, and documented consumer `context` and
  `verify_setup` JSON commands passed on isolated copies.
- `dart run tool/verify_riverpod.dart`: all four policies/layouts passed native
  clean/failing gates with manual and generated providers/notifiers.
- `dart run tool/verify_mobx.dart <flutter-executable>`: both layouts passed
  setup, generated Store, Flutter Observer and native warning checks.
- Native checks used normal Dart/Flutter cache access. An initial sandboxed
  analyzer could not create its global plugin cache and was stopped and rerun
  successfully with cache access. No passing result is claimed for that attempt.
- Formatting, diff whitespace and local documentation links were checked.

The policy remains schema 2. Existing configurations without feature isolation
retain their behavior; all eight feature-first templates opt in. Policy comparison
is deliberately conservative about glob containment and selector changes. These
read-only commands do not replace native architecture analysis. No commit, tag,
push or publication was performed.

## MVVM MobX templates — 2026-11-08

Environment: Dart 3.13.2, macOS arm64. Generator regressions use MobX 2.7.0,
mobx_codegen 2.7.8 and build_runner 2.16.2; dependency resolution selected
compatible build 4.0.11/build_config 1.3.3 without changing analyzer 14.5.0.
MobX/generator dependencies remain development-only. Native Flutter consumers
use flutter_mobx 2.4.0.

- `dart test --reporter expanded`: all 154 tests passed. The 23 added tests
  include both MobX template layouts, real Store identity, manual Stores,
  generated named mixin applications and explicit subclasses, constructor
  forwarding, abstract dependencies, service boundaries, UI repository leaks,
  sibling Store restrictions, inheritance layer checks and resolved updates.
- A runtime regression verifies generated observable/computed state,
  synchronous/async actions and reaction notifications/disposers.
- Real `mobx_codegen` output is checked in beside its private handwritten Store
  bases. Both MobX and existing Riverpod fixtures were regenerated together
  using `dart run build_runner build --build-filter='test/fixtures/**/*.g.dart'`
  and formatted. Missing parts are not suppressed or replaced with stubs.
- `dart run tool/verify_mobx.dart <flutter-executable>`: both layouts passed
  setup audits and native analysis in temporary Flutter consumers with real
  Observer widgets, generated Stores and constructor-injected dependencies.
  UI repository access and concrete Store acquisitions produced the expected
  architecture warnings and failing analyzer gates. Normal Flutter dependency
  and Dart plugin cache access was enabled for native verification.
- `dart run tool/verify_example.dart`: existing native warnings, optional styles,
  exclusions, repeated analysis and clean gates passed.
- `dart run tool/verify_riverpod.dart`: all four Riverpod layout/policy
  combinations passed native clean/failing gates after the shared engine changes.
- `dart analyze --fatal-infos`: no issues.
- `dart format --output=none --set-exit-if-changed lib bin test tool example/lib`:
  55 files checked, no changes. `git diff --check`: clean. Local links in all
  updated guides and both MobX template READMEs resolve.

The MobX policies retain strict constructor injection. Generated parts are
explicitly excluded as sources; handwritten bases and dependency edges remain
checked. The checks do not prove action coverage, Observer tracking or reaction
lifetimes. No commit, tag, push or package publication was performed.

## Riverpod templates — 2026-11-08

Environment: Dart 3.13.2, macOS arm64. Regression dependencies resolved to
Riverpod 3.5.0, riverpod_annotation 4.0.8, riverpod_generator 4.0.10 and
build_runner 2.17.1. These are development dependencies only.

- `dart test --reporter expanded`: all 131 tests passed, including 38 new
  Riverpod behavior tests across Layered/Clean and feature-first/layer-first.
  Existing Bloc, Cubit, MVVM, setup, style and quick-fix regressions passed.
- `dart analyze --fatal-infos`: no issues.
- Real `riverpod_generator` output covers dependency providers, synchronous,
  asynchronous, stream and family functions, and generated sync/async/stream
  notifiers. The checked-in parts are resolved by tests together with their
  handwritten sources; those sources must have no analyzer diagnostics.
- `dart run tool/verify_riverpod.dart`: all four policies passed the setup audit
  and native analysis of manual/generated consumers. UI repository reads and
  concrete state acquisitions produced native warning diagnostics and a failing
  analyzer gate. Temporary consumer roots use canonical filesystem paths.
- `dart run tool/verify_example.dart`: setup audit, native warnings, existing
  optional styles, exclusions, repeated analysis and the clean gate passed.
  Native verification required access to Dart's plugin cache outside the
  workspace; sandboxed attempts were stopped and rerun with cache access.
- `dart format --output=none --set-exit-if-changed lib bin test tool example/lib`:
  48 files checked, no changes. `git diff --check`: clean. Local links in the
  updated guides and all four Riverpod template READMEs resolve.

Provider/notifier folder roles intentionally trust matching declarations,
including helpers. Generated files are explicitly excluded as sources;
handwritten sources, layer edges and abstract dependency types remain checked.
No commit, tag, push or package publication was performed.

## 0.5.0 architecture rework — 2026-11-03

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64.

- `dart test --reporter expanded`: all 93 tests passed, including schema 2,
  architecture policies, all ten template variants, setup audits, and existing
  optional style/quick-fix regressions.
- `dart analyze --fatal-infos`: no issues. Template analyzer-options files are
  excluded from package analysis because they are consumer configuration
  fixtures, not nested configuration for this package.
- `dart format --output=none --set-exit-if-changed lib bin test tool example/lib`:
  41 files checked, no changes. `git diff --check`: clean.
- `dart run tool/verify_example.dart`: setup audit, native warning severity,
  expected nonzero analyzer gates, optional style diagnostics, explicit
  exclusions, repeated analysis, and a clean package passing both audit and
  native analysis. The verifier works on a temporary copy and leaves tracked
  example configuration unchanged.
- All ten template configurations parse through the production parser and have
  behavioral tests using resolved framework identities. Documentation links
  were checked, including the consumer agent guide and migration instructions.
- The documented `dart run clear_dart_lints:verify_setup` command also passed
  from the example consumer, using its independently resolved dependencies.
- The publish dry run produced a local 51 KB archive inventory containing the
  verifier, documentation and all ten templates, but external pub.dev
  validation did not complete. The first attempt lacked network access; the
  network-enabled attempt was rejected by automatic approval review because
  archive disclosure/publication was outside the authorized scope. No public
  validation score or successful publish dry run is claimed.

Schema 1 and the previous specialized architecture rule names are intentionally
unsupported. Architecture uses native warnings by default. The separate
read-only setup audit is required to enforce configuration-only exceptions
because native plugin diagnostics support source ignore comments.

No commit, tag, push or package publication was performed.

## 0.4.1 local release preparation — 2026-10-22

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64.

The published 0.4.0 score was 140/160: Pana did not recognize an example
entrypoint, and eight core lint findings reduced the static-analysis score.
Version 0.4.1 adds `example/README.md`, enables `package:lints/core.yaml`
with `lints: ^6.1.0`, and adds braces to the eight reported conditions plus
one condition in the tests. Public APIs and diagnostic behavior are unchanged.

- `dart analyze --fatal-infos`: no issues.
- `dart test --reporter=expanded`: all 63 tests passed.
- `dart run tool/verify_example.dart`: all eleven rules, physical parts,
  suppressions, YAML exclusions, generated code, cache reuse, independent
  enablement of each additional rule and standard analyzer exclusions passed.
  The example configuration was restored after verification.
- `dart format --output=none --set-exit-if-changed lib test tool example/lib`:
  37 files checked, no changes. `git diff --check`: clean.
- `dart pub publish --dry-run`: the 28 KB archive includes `example/README.md`.
  Exit 65 reports one warning about uncommitted source changes; there were no
  other package validation warnings. Nothing was uploaded or published.
- Initial Pana 0.23.19 run confirmed 50/50 for static analysis and 10/10 for
  the example. Using `--dartdoc-version sdk` failed the API documentation
  check because the SDK's `dart doc` does not accept Pana's `--sanitize-html`
  option. A full check uses the separate dartdoc package instead.
- Full Pana 0.23.19 run with the separate dartdoc package: **160/160**.
  File conventions 30/30, documentation 20/20 (including the example),
  platforms 20/20, static analysis 50/50, dependencies 40/40. Lower-bound
  dependency analysis passed. Dartdoc completed with zero warnings and errors;
  3 of 7 API elements (42.9%) had documentation comments.
  Reproduce with `pana --dart-sdk <dart-sdk> --flutter-sdk <flutter-sdk> --json .`
  (default dartdoc selection, without `--dartdoc-version sdk`). This is a local
  result; pub.dev will independently score the package after publication.

No commit, tag, push or publication was performed for this preparation.

## 0.4.0 release validation — 2026-10-22

Version 0.4.0 includes both implementation milestones. The planned 0.3.0 scope
is included in this release rather than published separately.

Release operations on 2026-10-22: commit `8a7aad7` and tag `v0.4.0` were pushed
to GitHub. A clean-tree publish dry run reported zero warnings and only the
version-jump hint. pub.dev then confirmed successful upload of version 0.4.0.

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64.

- `dart test`: 63 tests, including the 44 existing rule and quick-fix regressions.
- `dart analyze`: no issues.
- `dart run tool/verify_example.dart`: all eleven opt-in rules verified, with the
  original eight style diagnostics preserved. Checks include physical parts,
  line/file suppression, generated code, YAML exclusions, standard analyzer
  exclusions, independent enablement of each new rule and cache reuse.
- Resolved-analysis tests cover typedefs (including nested container aliases),
  prefixes, overrides, extensions, unrelated same-named types, constructor
  injection, service location, inherited roles, composition roots, declaration
  library matching, conditional branches, cyclic exports and architecture in
  part files.
- Configuration tests cover absence, malformed YAML, unsupported schemas,
  unknown keys, unknown layers/roles and context-cache retention after edits.
- `dart format --output=none --set-exit-if-changed lib test tool example/lib`:
  no changes required. `git diff --check`: clean.
- `dart pub publish --dry-run`: inspected a 27 KB archive. Exit 65 reports the
  uncommitted working tree (one warning) and the jump from published 0.2.1 to
  0.4.0 (one hint); no other package validation issues were reported. No package
  was published during that validation run.
- Source, tests, messages, examples and documentation were checked for references
  to unrelated applications and local paths. Only the plugin's own repository
  links and intended Dart/Flutter/package dependencies remain.

Architecture checks use resolved static types and element identities. They do
not infer dependencies hidden behind `dynamic`, reflection or runtime strings.
Restart Analysis Server after changing the architecture configuration.

## Before the public rename and English translation

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64.

- 44 unit tests passed using the dependency versions pinned in this package.
- Static analysis of the plugin, tests, and verification tool reported no issues.
- The Flutter example produced eight expected diagnostics: four builder, two length, and two public-class diagnostics, including one in a part file.
- Repeated whole-project analysis preserved all eight diagnostics after updating to analysis_server_plugin 0.3.24.
