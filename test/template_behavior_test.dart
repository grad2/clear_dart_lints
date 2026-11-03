import 'dart:io';

import 'package:clear_dart_lints/src/architecture/policy.dart';
import 'package:test/test.dart';

import 'new_rules_test.dart' show check;

void main() {
  for (final preset in ['layered_bloc', 'layered_cubit', 'clean_bloc', 'clean_cubit', 'mvvm']) {
    for (final layout in ['feature_first', 'layer_first']) {
      test('$preset $layout enforces its documented boundaries', () async {
        final config = File('templates/$preset/$layout/clear_dart_lints.yaml').readAsStringSync();
        final base = layout == 'feature_first' ? 'lib/features/items' : 'lib';
        final stateDir = preset == 'mvvm'
            ? 'viewmodels'
            : preset.endsWith('cubit')
            ? 'cubits'
            : 'blocs';
        final state = '$base/presentation/$stateDir/items.dart';
        final ui = '$base/presentation/views/screen.dart';
        final repo = '$base/domain/repositories/item_repository.dart';
        final impl = '$base/data/repositories/item_repository_impl.dart';
        final domain = '$base/domain/entities/item.dart';
        String uri(String path) => 'package:fixture/${path.substring(4)}';
        final baseType = preset == 'mvvm'
            ? 'ChangeNotifier'
            : preset.endsWith('cubit')
            ? 'Cubit<int>'
            : 'Bloc<int, int>';
        final framework = preset == 'mvvm'
            ? 'package:flutter/foundation.dart'
            : 'package:bloc/bloc.dart';
        final manager =
            "import '$framework'; import '${uri(repo)}'; class ItemsManager extends $baseType { final ItemRepository repo; ItemsManager(this.repo); }";
        final files = <String, String>{
          repo: 'abstract class ItemRepository {}',
          state: manager,
          impl: "import '${uri(repo)}'; class ItemRepositoryImpl implements ItemRepository {}",
        };
        Future<List<String>> run(String target, String source) => check(
          ArchitecturePolicy(),
          '',
          config: config,
          files: {...files, target: source},
          target: target,
        );
        expect(await run(state, manager), isEmpty, reason: 'injected abstract repository');
        expect(
          await run(ui, "import '${uri(repo)}'; ItemRepository? value;"),
          contains('role_dependencies'),
          reason: 'view repository',
        );
        expect(
          await run(
            state,
            "import '$framework'; class Other extends $baseType {} class ItemsManager extends $baseType { Other? sibling; }",
          ),
          contains('role_dependencies'),
          reason: 'sibling manager',
        );
        expect(
          await run(domain, "import 'package:flutter/foundation.dart'; ChangeNotifier? value;"),
          contains('layer_dependencies'),
          reason: 'domain Flutter',
        );
        expect(
          await run(domain, "import 'dart:convert'; Object? f(String s) => jsonDecode(s);"),
          contains('forbidden_symbols'),
          reason: 'domain transport',
        );
        expect(await run(impl, files[impl]!), isEmpty, reason: 'data implements contract');
        if (preset.startsWith('clean')) {
          final usecase = '$base/domain/usecases/load_items.dart';
          final usecaseSource =
              "import '${uri(repo)}'; class LoadItems { final ItemRepository repo; LoadItems(this.repo); }";
          expect(
            await run(usecase, usecaseSource),
            isEmpty,
            reason: 'use case injected repository',
          );
          final managerViaUsecase =
              "import '$framework'; import '${uri(usecase)}'; class ItemsManager extends $baseType { final LoadItems load; ItemsManager(this.load); }";
          expect(
            await check(
              ArchitecturePolicy(),
              '',
              config: config,
              files: {...files, usecase: usecaseSource, state: managerViaUsecase},
              target: state,
            ),
            isEmpty,
            reason: 'manager injected use case',
          );
        }
        expect(
          await run('lib/main.dart', "import '${uri(impl)}'; final value = ItemRepositoryImpl();"),
          isEmpty,
          reason: 'composition root',
        );
      });
    }
  }
}
