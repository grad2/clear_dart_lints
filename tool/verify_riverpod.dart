import 'dart:convert';
import 'dart:io';

import 'package:clear_dart_lints/src/setup_verifier.dart';

/// Runs the native plugin and setup audit on all four Riverpod policies.
Future<void> main() async {
  final packageRoot = Directory.current.absolute.path;
  final packageConfigFile = File('.dart_tool/package_config.json').absolute;
  final packageConfig = jsonDecode(packageConfigFile.readAsStringSync()) as Map<String, dynamic>;
  final dependencies = [
    for (final entry in packageConfig['packages'] as List<dynamic>)
      {
        ...entry as Map<String, dynamic>,
        'rootUri': packageConfigFile.uri.resolve(entry['rootUri'] as String).toString(),
      },
  ];
  for (final preset in ['layered_riverpod', 'clean_riverpod']) {
    for (final layout in ['feature_first', 'layer_first']) {
      final temp = Directory(
        Directory.systemTemp
            .createTempSync('clear_dart_lints_riverpod_')
            .resolveSymbolicLinksSync(),
      );
      void write(String path, String content) {
        final file = File('${temp.path}/$path');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      }

      try {
        final base = layout == 'feature_first' ? 'lib/features/items' : 'lib';
        String uri(String path) => 'package:riverpod_fixture/${path.substring(4)}';
        final repo = '$base/domain/repositories/item_repository.dart';
        final impl = '$base/data/repositories/item_repository_impl.dart';
        final providers = '$base/presentation/providers/providers.dart';
        write('pubspec.yaml', '''
name: riverpod_fixture
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  riverpod: ^3.4.3
  riverpod_annotation: ^4.0.7
dev_dependencies:
  clear_dart_lints:
    path: $packageRoot
''');
        write(
          '.dart_tool/package_config.json',
          jsonEncode({
            'configVersion': 2,
            'packages': [
              ...dependencies,
              {
                'name': 'riverpod_fixture',
                'rootUri': temp.uri.toString(),
                'packageUri': 'lib/',
                'languageVersion': '3.13',
              },
            ],
          }),
        );
        write(
          'analysis_options.yaml',
          File('templates/$preset/$layout/analysis_options.yaml')
              .readAsStringSync()
              .replaceFirst('version: 0.6.2', 'path: $packageRoot'),
        );
        write(
          'clear_dart_lints.yaml',
          File('templates/$preset/$layout/clear_dart_lints.yaml').readAsStringSync(),
        );
        write(repo, 'abstract interface class ItemRepository { int load(); }');
        write(
          impl,
          "import '${uri(repo)}'; class ItemRepositoryImpl implements ItemRepository { @override int load() => 1; }",
        );
        write(
          'lib/di/composition.dart',
          File('test/fixtures/riverpod/composition.dart').readAsStringSync().replaceFirst(
            "import 'item_repository.dart';",
            "import '${uri(repo)}'; import '${uri(impl)}';",
          ),
        );
        write(
          'lib/di/composition.g.dart',
          File('test/fixtures/riverpod/composition.g.dart').readAsStringSync(),
        );
        write(
          providers,
          File('test/fixtures/riverpod/providers.dart')
              .readAsStringSync()
              .replaceFirst("'composition.dart'", "'package:riverpod_fixture/di/composition.dart'"),
        );
        write(
          '$base/presentation/providers/providers.g.dart',
          File('test/fixtures/riverpod/providers.g.dart').readAsStringSync(),
        );
        write('$base/presentation/notifiers/manual.dart', '''
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_fixture/di/composition.dart';
class ManualItems extends Notifier<int> {
  @override int build() => ref.watch(repositoryProvider).load();
  void reload() => state = ref.read(repositoryProvider).load();
}
final manualItemsProvider = NotifierProvider<ManualItems, int>(ManualItems.new);
''');
        write(
          '$base/presentation/views/screen.dart',
          "import 'package:riverpod/riverpod.dart'; import '${uri(providers)}'; int render(Ref ref) => ref.watch(itemsProvider);",
        );
        final audit = await verifySetup(temp.path, verifierRoot: packageRoot);
        if (!audit.passed) {
          throw StateError(
            '$preset/$layout audit: ${audit.issues.map((i) => '${i.code}: ${i.message}').join('; ')}',
          );
        }
        Future<ProcessResult> analyze() => Process.run(Platform.resolvedExecutable, [
          '--suppress-analytics',
          'analyze',
          '--format=machine',
          '--fatal-infos',
          temp.path,
        ]);
        final clean = await analyze();
        if (clean.exitCode != 0 || clean.stderr.toString().trim().isNotEmpty) {
          throw StateError('$preset/$layout clean analysis: ${clean.stdout}\n${clean.stderr}');
        }
        write(
          '$base/presentation/views/bad.dart',
          "import 'package:riverpod/riverpod.dart'; import 'package:riverpod_fixture/di/composition.dart'; int render(Ref ref) => ref.read(repositoryProvider).load();",
        );
        write(
          '$base/presentation/providers/bad.dart',
          "import 'package:riverpod/riverpod.dart'; import '${uri(impl)}'; final badProvider = Provider<int>((ref) => ItemRepositoryImpl().load());",
        );
        final bad = await analyze();
        final rows = const LineSplitter()
            .convert(bad.stdout.toString())
            .map((line) => line.split('|'))
            .where((row) => row.length >= 8)
            .toList();
        final codes = rows.map((row) => row[2].toLowerCase()).toSet();
        if (bad.exitCode == 0 ||
            bad.stderr.toString().trim().isNotEmpty ||
            rows.any((row) => row[0] != 'WARNING') ||
            !codes.containsAll({
              'layer_dependencies',
              'role_dependencies',
              'depend_on_contracts',
              'constructor_injection',
            })) {
          throw StateError('$preset/$layout negative analysis: ${bad.stdout}\n${bad.stderr}');
        }
        stdout.writeln(
          'PASS: $preset/$layout audit, generated/manual sources and native warning gate.',
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    }
  }
}
