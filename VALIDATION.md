# Validation history

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
