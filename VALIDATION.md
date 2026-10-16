# Validation history

## Before the public rename and English translation

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64.

- 44 unit tests passed using the dependency versions pinned in this package.
- Static analysis of the plugin, tests, and verification tool reported no issues.
- The Flutter example produced eight expected diagnostics: four builder, two length, and two public-class diagnostics, including one in a part file.
- Repeated whole-project analysis preserved all eight diagnostics after updating to analysis_server_plugin 0.3.24.

The extended integration scenarios for ignore comments, exclusions, and independently disabling rules were not completed. A temporary-package fixture returned no diagnostics unexpectedly. These scenarios are not claimed as fully verified.

## Publication preparation

The package was renamed and its diagnostics and documentation translated into English. Unit and integration test suites were not rerun during publication preparation. `dart pub publish --dry-run` completed successfully with zero warnings. The package archive contains the intended source, tests, examples, license, changelog, and README; local caches and validation notes are excluded.
