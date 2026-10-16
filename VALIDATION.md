# Validation history

## Before the public rename and English translation

Environment: Dart 3.13.2, Flutter 3.47.2, macOS arm64.

- 44 unit tests passed using the dependency versions pinned in this package.
- Static analysis of the plugin, tests, and verification tool reported no issues.
- The Flutter example produced eight expected diagnostics: four builder, two length, and two public-class diagnostics, including one in a part file.
- Repeated whole-project analysis preserved all eight diagnostics after updating to analysis_server_plugin 0.3.24.
