# Validation history

## 0.4.0 release validation — 2026-10-22

Version 0.4.0 includes both implementation milestones. The planned 0.3.0 scope
is included in this release rather than published separately.

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
