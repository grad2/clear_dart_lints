import 'dart:convert';
import 'dart:io';

import 'package:clear_dart_lints/src/setup_verifier.dart';

/// Verifies both MobX policies on real Flutter consumers, including Observer.
/// Optionally pass the path to the Flutter executable as the first argument.
Future<void> main(List<String> args) async {
  if (args.length > 1) throw ArgumentError('Usage: dart run tool/verify_mobx.dart [flutter]');
  final flutter = args.isEmpty ? 'flutter' : args.single;
  final packageRoot = Directory.current.resolveSymbolicLinksSync();
  for (final layout in ['feature_first', 'layer_first']) {
    final temp = Directory(
      Directory.systemTemp.createTempSync('clear_dart_lints_mobx_').resolveSymbolicLinksSync(),
    );
    void write(String path, String content) {
      final file = File('${temp.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    try {
      final base = layout == 'feature_first' ? 'lib/features/items' : 'lib';
      String uri(String path) => 'package:mobx_fixture/${path.substring(4)}';
      final repo = '$base/domain/repositories/item_repository.dart';
      final impl = '$base/data/repositories/item_repository_impl.dart';
      final service = '$base/data/services/item_service.dart';
      final state = '$base/presentation/viewmodels/items_view_model.dart';
      write('pubspec.yaml', '''
name: mobx_fixture
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  mobx: ^2.7.0
  flutter_mobx: ^2.4.0
dev_dependencies:
  clear_dart_lints:
    path: $packageRoot
''');
      write(
        'analysis_options.yaml',
        File('templates/mvvm_mobx/$layout/analysis_options.yaml')
            .readAsStringSync()
            .replaceFirst('version: 0.6.2', 'path: $packageRoot'),
      );
      write(
        'clear_dart_lints.yaml',
        File('templates/mvvm_mobx/$layout/clear_dart_lints.yaml').readAsStringSync(),
      );
      write(repo, File('test/fixtures/mobx/item_repository.dart').readAsStringSync());
      write(service, 'class ItemService { Future<int> load() async => 42; }');
      write(
        impl,
        "import '${uri(repo)}'; import '${uri(service)}'; class ItemRepositoryImpl implements ItemRepository { final ItemService service; ItemRepositoryImpl(this.service); @override Future<int> load() => service.load(); }",
      );
      for (final name in ['items_view_model', 'explicit_view_model']) {
        write(
          '$base/presentation/viewmodels/$name.dart',
          File('test/fixtures/mobx/$name.dart')
              .readAsStringSync()
              .replaceFirst("'item_repository.dart'", "'${uri(repo)}'"),
        );
        write(
          '$base/presentation/viewmodels/$name.g.dart',
          File('test/fixtures/mobx/$name.g.dart').readAsStringSync(),
        );
      }
      write(
        'lib/app/composition.dart',
        "import '${uri(impl)}'; import '${uri(service)}'; import '${uri(state)}'; final model = ItemsViewModel(ItemRepositoryImpl(ItemService()));",
      );
      write('$base/presentation/views/items_view.dart', '''
import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import '${uri(state)}';
class ItemsView extends StatelessWidget {
  const ItemsView({super.key, required this.model});
  final ItemsViewModel model;
  @override Widget build(BuildContext context) {
    return Observer(builder: (_) => Text(model.count.toString()));
  }
}
''');
      final resolved = await Process.run(flutter, ['pub', 'get'], workingDirectory: temp.path);
      if (resolved.exitCode != 0) {
        throw StateError(
          'mvvm_mobx/$layout dependency resolution: ${resolved.stdout}\n${resolved.stderr}',
        );
      }
      final audit = await verifySetup(temp.path, verifierRoot: packageRoot);
      if (!audit.passed) {
        throw StateError(
          'mvvm_mobx/$layout audit: ${audit.issues.map((i) => '${i.code}: ${i.message}').join('; ')}',
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
        throw StateError('mvvm_mobx/$layout clean analysis: ${clean.stdout}\n${clean.stderr}');
      }
      write(
        '$base/presentation/views/bad.dart',
        "import '${uri(repo)}'; Future<int> render(ItemRepository repository) => repository.load();",
      );
      write(
        '$base/presentation/viewmodels/bad.dart',
        "import 'package:mobx/mobx.dart'; import '${uri(impl)}'; import '${uri(service)}'; class BadViewModel with Store { final repository = ItemRepositoryImpl(ItemService()); }",
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
        throw StateError('mvvm_mobx/$layout negative analysis: ${bad.stdout}\n${bad.stderr}');
      }
      stdout.writeln(
        'PASS: mvvm_mobx/$layout audit, generated Stores, Flutter Observer and native warning gate.',
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  }
}
