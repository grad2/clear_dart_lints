import 'dart:io';

import 'package:clear_dart_lints/src/architecture/policy.dart';
import 'package:mobx/mobx.dart';
import 'package:test/test.dart';

import 'fixtures/mobx/item_repository.dart';
import 'fixtures/mobx/items_view_model.dart' as generated;
import 'new_rules_test.dart' show check;

class _Repository implements ItemRepository {
  @override
  Future<int> load() async => 42;
}

String uri(String path) => 'package:fixture/${path.substring(4)}';

void main() {
  test('generated actions update observables, computed values and reactions', () async {
    final model = generated.ItemsViewModel(_Repository());
    final counts = <int>[];
    final loading = <bool>[];
    final disposeCount = reaction<int>((_) => model.count, counts.add);
    final disposeLoading = reaction<bool>((_) => model.loading, loading.add);
    addTearDown(disposeCount.call);
    addTearDown(disposeLoading.call);
    expect(model.hasItems, isFalse);
    model.increment();
    expect(model.hasItems, isTrue);
    await model.load();
    expect(counts, [1, 42]);
    expect(loading, [true, false]);
    expect(model.loading, isFalse);
  });

  for (final layout in ['feature_first', 'layer_first']) {
    group('mvvm_mobx $layout', () {
      final config = File('templates/mvvm_mobx/$layout/clear_dart_lints.yaml').readAsStringSync();
      final base = layout == 'feature_first' ? 'lib/features/items' : 'lib';
      final state = '$base/presentation/viewmodels/items_view_model.dart';
      final explicit = '$base/presentation/viewmodels/explicit_view_model.dart';
      final ui = '$base/presentation/views/screen.dart';
      final repo = '$base/domain/repositories/item_repository.dart';
      final impl = '$base/data/repositories/item_repository_impl.dart';
      final service = '$base/data/services/item_service.dart';
      final files = {
        repo: File('test/fixtures/mobx/item_repository.dart').readAsStringSync(),
        service: 'class ItemService { Future<int> load() async => 1; }',
        impl:
            "import '${uri(repo)}'; import '${uri(service)}'; class ItemRepositoryImpl implements ItemRepository { final ItemService service; ItemRepositoryImpl(this.service); @override Future<int> load() => service.load(); }",
      };
      String handwritten(String name) =>
          File('test/fixtures/mobx/$name.dart')
              .readAsStringSync()
              .replaceFirst("'item_repository.dart'", "'${uri(repo)}'");
      final generatedFiles = {
        state: handwritten('items_view_model'),
        state.replaceFirst('.dart', '.g.dart'): File('test/fixtures/mobx/items_view_model.g.dart')
            .readAsStringSync(),
        explicit: handwritten('explicit_view_model'),
        explicit.replaceFirst('.dart', '.g.dart'): File(
          'test/fixtures/mobx/explicit_view_model.g.dart',
        ).readAsStringSync(),
      };
      Future<List<String>> run(
        String target,
        String source, {
        Map<String, String> extra = const {},
      }) => check(
        ArchitecturePolicy(),
        '',
        config: config,
        files: {...files, ...generatedFiles, ...extra, target: source},
        target: target,
        realPackages: true,
        requireValid: true,
      );

      test('manual Store receives an abstract repository through its constructor', () async {
        expect(
          await run(state, '''
import 'package:mobx/mobx.dart';
import '${uri(repo)}';
class ManualViewModel with Store {
  ManualViewModel(this._repository);
  final ItemRepository _repository;
  final count = Observable(0);
  Future<void> load() async {
    final value = await _repository.load();
    runInAction(() { count.value = value; });
  }
}
'''),
          isEmpty,
        );
      });

      test('generated named mixin application keeps its injected base checked', () async {
        expect(await run(state, generatedFiles[state]!), isEmpty);
        final part = state.replaceFirst('.dart', '.g.dart');
        expect(
          await run(part, generatedFiles[part]!),
          isEmpty,
          reason: 'explicit generated exclusion',
        );
        expect(
          await run(
            ui,
            "import '${uri(state)}'; bool render(ItemsViewModel model) => model.hasItems;",
          ),
          isEmpty,
        );
      });

      test(
        'explicit subclass with a generated mixin and forwarding constructor is allowed',
        () async {
          expect(await run(explicit, generatedFiles[explicit]!), isEmpty);
          expect(
            await run(
              ui,
              "import '${uri(explicit)}'; String render(ExplicitViewModel model) => model.label;",
            ),
            isEmpty,
          );
        },
      );

      test('handwritten generated-store bodies cannot construct concrete repositories', () async {
        final source = generatedFiles[state]!
            .replaceFirst(
              "part 'items_view_model.g.dart';",
              "import '${uri(impl)}'; import '${uri(service)}'; part 'items_view_model.g.dart';",
            )
            .replaceFirst('count++;', 'count++; ItemRepositoryImpl(ItemService());');
        final result = await run(state, source);
        expect(result, contains('layer_dependencies'));
        expect(result, contains('depend_on_contracts'));
        expect(result, contains('constructor_injection'));
      });

      test('Store identity excludes namesakes, suffixes and unrelated helpers', () async {
        for (final declaration in [
          'class ItemsViewModel',
          'mixin Store {} class ItemsViewModel with Store',
          'class Helper',
        ]) {
          final result = await run(
            state,
            "import '${uri(repo)}'; $declaration { final ItemRepository repository; ItemsViewModel_PLACEHOLDER(this.repository); }"
                .replaceFirst(
                  'ItemsViewModel_PLACEHOLDER',
                  declaration == 'class Helper' ? 'Helper' : 'ItemsViewModel',
                ),
          );
          expect(result, contains('role_dependencies'), reason: declaration);
        }
      });

      test('views cannot consume repositories directly or through Store getters', () async {
        expect(
          await run(
            ui,
            "import '${uri(repo)}'; Future<int> render(ItemRepository repository) => repository.load();",
          ),
          contains('role_dependencies'),
        );
        final exposed = generatedFiles[state]!.replaceFirst(
          '  @observable',
          '  ItemRepository get repository => _repository;\n\n  @observable',
        );
        expect(
          await run(
            ui,
            "import '${uri(state)}'; Future<int> render(ItemsViewModel model) => model.repository.load();",
            extra: {state: exposed},
          ),
          contains('role_dependencies'),
        );
      });

      test('concrete constructor types and service locators remain forbidden', () async {
        expect(
          await run(state, '''
import 'package:mobx/mobx.dart';
import '${uri(impl)}';
class ItemsViewModel with Store {
  final ItemRepositoryImpl repository;
  ItemsViewModel(this.repository);
}
'''),
          contains('depend_on_contracts'),
        );
        expect(
          await run(state, '''
import 'package:mobx/mobx.dart';
import '${uri(repo)}';
ItemRepository locate() => throw UnimplementedError();
class ItemsViewModel with Store {
  late final repository = locate();
}
'''),
          contains('constructor_injection'),
        );
      });

      test('Store siblings are forbidden and self references remain allowed', () async {
        expect(
          await run(state, '''
import 'package:mobx/mobx.dart';
class OtherViewModel with Store {}
class ItemsViewModel with Store { OtherViewModel? other; }
'''),
          contains('role_dependencies'),
        );
        expect(
          await run(state, '''
import 'package:mobx/mobx.dart';
class ItemsViewModel with Store { ItemsViewModel? self; }
'''),
          isEmpty,
        );
      });

      test('only repositories consume services and roots assemble the graph', () async {
        expect(await run(impl, files[impl]!), isEmpty);
        expect(
          await run(state, '''
import 'package:mobx/mobx.dart';
import '${uri(service)}';
class ItemsViewModel with Store {
  final ItemService service;
  ItemsViewModel(this.service);
}
'''),
          contains('role_dependencies'),
        );
        expect(
          await run('lib/app/composition.dart', '''
import '${uri(impl)}';
import '${uri(service)}';
import '${uri(state)}';
final model = ItemsViewModel(ItemRepositoryImpl(ItemService()));
'''),
          isEmpty,
        );
      });

      test('domain and core remain independent of MobX and state remains Flutter-free', () async {
        for (final target in ['$base/domain/entities/item.dart', 'lib/core/item.dart']) {
          expect(
            await run(target, "import 'package:mobx/mobx.dart'; final value = Observable(1);"),
            contains('layer_dependencies'),
          );
        }
        expect(
          await run(
            state,
            "import 'package:flutter/foundation.dart'; class ItemsViewModel extends ChangeNotifier {}",
          ),
          contains('layer_dependencies'),
        );
        expect(
          await run(
            '$base/domain/entities/item.dart',
            "import 'dart:convert'; Object? decode(String value) => jsonDecode(value);",
          ),
          contains('forbidden_symbols'),
        );
      });
    });
  }
}
