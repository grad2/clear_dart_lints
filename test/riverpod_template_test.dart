import 'dart:io';

import 'package:clear_dart_lints/src/architecture/policy.dart';
import 'package:test/test.dart';

import 'new_rules_test.dart' show check;

String uri(String path) => 'package:fixture/${path.substring(4)}';

void main() {
  for (final preset in ['layered_riverpod', 'clean_riverpod']) {
    for (final layout in ['feature_first', 'layer_first']) {
      group('$preset $layout', () {
        final config = File('templates/$preset/$layout/clear_dart_lints.yaml').readAsStringSync();
        final base = layout == 'feature_first' ? 'lib/features/items' : 'lib';
        final state = '$base/presentation/providers/providers.dart';
        final notifier = '$base/presentation/notifiers/items.dart';
        final ui = '$base/presentation/views/screen.dart';
        final repo = '$base/domain/repositories/item_repository.dart';
        final impl = '$base/data/repositories/item_repository_impl.dart';
        final usecase = '$base/domain/usecases/load_items.dart';
        const di = 'lib/di/composition.dart';
        final files = {
          repo: 'abstract interface class ItemRepository { int load(); }',
          impl:
              "import '${uri(repo)}'; class ItemRepositoryImpl implements ItemRepository { @override int load() => 1; }",
          di: "import 'package:riverpod/riverpod.dart'; import '${uri(repo)}'; import '${uri(impl)}'; final repositoryProvider = Provider<ItemRepository>((ref) => ItemRepositoryImpl());",
        };
        final imports = "import 'package:riverpod/riverpod.dart'; import '${uri(di)}';";
        Future<List<String>> run(
          String target,
          String source, {
          String? policy,
          Map<String, String> extra = const {},
        }) => check(
          ArchitecturePolicy(),
          '',
          config: policy ?? config,
          files: {...files, ...extra, target: source},
          target: target,
          realPackages: true,
          requireValid: true,
        );

        test('manual sync, future, stream, family and autoDispose provider factories', () async {
          final source =
              '''
$imports
final itemsProvider = Provider<int>((ref) => ref.watch(repositoryProvider).load());
final futureProvider = FutureProvider<int>((ref) async => ref.read(repositoryProvider).load());
final streamProvider = StreamProvider<int>((ref) => Stream.value(ref.watch(repositoryProvider).load()));
final familyProvider = Provider.autoDispose.family<int, int>((ref, id) => ref.watch(repositoryProvider).load() + id);
final composedProvider = Provider<int>((ref) => ref.watch(itemsProvider) + 1);
''';
          expect(await run(state, source), isEmpty);
          expect(
            await run(di, files[di]!),
            isEmpty,
            reason: 'DI can assemble concrete dependencies',
          );
          expect(
            await run(
              ui,
              "import 'package:riverpod/riverpod.dart'; import '${uri(state)}'; int render(Ref ref) => ref.watch(itemsProvider);",
              extra: {state: source},
            ),
            isEmpty,
            reason: 'UI consumes exposed state',
          );
        });

        test('manual notifiers read abstract repositories, including lazy fields', () async {
          expect(
            await run(notifier, '''
$imports
import '${uri(repo)}';
class Items extends Notifier<int> {
  late final ItemRepository repository = ref.read(repositoryProvider);
  late final inferred = ref.read(repositoryProvider);
  @override int build() => ref.watch(repositoryProvider).load();
  void reload() => state = repository.load() + inferred.load();
}
class AsyncItems extends AsyncNotifier<int> {
  @override Future<int> build() async => ref.watch(repositoryProvider).load();
}
class StreamItems extends StreamNotifier<int> {
  @override Stream<int> build() => Stream.value(ref.read(repositoryProvider).load());
}
final itemsProvider = NotifierProvider<Items, int>(Items.new);
final asyncItemsProvider = AsyncNotifierProvider<AsyncItems, int>(AsyncItems.new);
final streamItemsProvider = StreamNotifierProvider<StreamItems, int>(StreamItems.new);
'''),
            isEmpty,
          );
        });

        test('real generated providers and notifiers keep handwritten sources checked', () async {
          final source = File('test/fixtures/riverpod/providers.dart')
              .readAsStringSync()
              .replaceFirst("'composition.dart'", "'${uri(di)}'");
          final generated = File('test/fixtures/riverpod/providers.g.dart').readAsStringSync();
          final composition = File('test/fixtures/riverpod/composition.dart')
              .readAsStringSync()
              .replaceFirst(
                "import 'item_repository.dart';",
                "import '${uri(repo)}'; import '${uri(impl)}';",
              );
          final extra = {
            '$base/presentation/providers/providers.g.dart': generated,
            di: composition,
            'lib/di/composition.g.dart': File('test/fixtures/riverpod/composition.g.dart')
                .readAsStringSync(),
          };
          expect(
            await run(di, composition, extra: extra),
            isEmpty,
            reason: 'generated DI provider',
          );
          expect(await run(state, source, extra: extra), isEmpty);
          expect(
            await run(
              '$base/presentation/providers/providers.g.dart',
              generated,
              extra: {state: source, ...extra},
            ),
            isEmpty,
            reason: 'explicit generated exclusion',
          );
          expect(
            await run(
              state,
              source
                  .replaceFirst(
                    'ref.watch(repositoryProvider).load()',
                    'ItemRepositoryImpl().load()',
                  )
                  .replaceFirst(
                    "part 'providers.g.dart';",
                    "import '${uri(impl)}'; part 'providers.g.dart';",
                  ),
              extra: extra,
            ),
            contains('constructor_injection'),
          );
          expect(
            await run(
              ui,
              "import 'package:riverpod/riverpod.dart'; import '${uri(state)}'; int render(Ref ref) => ref.watch(itemsProvider);",
              extra: {state: source, ...extra},
            ),
            isEmpty,
            reason: 'UI can use a generated provider',
          );
        });

        test('provider reads require explicit opt-in', () async {
          final result = await run(
            state,
            '$imports final itemsProvider = Provider<int>((ref) => ref.watch(repositoryProvider).load());',
            policy: config.replaceFirst(
              'allow_provider_reads: true',
              'allow_provider_reads: false',
            ),
          );
          expect(result, contains('constructor_injection'));
        });

        test('views cannot read or expose repository providers', () async {
          expect(
            await run(ui, "$imports int render(Ref ref) => ref.watch(repositoryProvider).load();"),
            contains('role_dependencies'),
          );
          expect(
            await run(
              state,
              "$imports final exposedProvider = Provider((ref) => ref.watch(repositoryProvider));",
            ),
            isEmpty,
          );
          expect(
            await run(
              ui,
              "import 'package:riverpod/riverpod.dart'; import '${uri(state)}'; int render(Ref ref) => ref.watch(exposedProvider).load();",
              extra: {
                state:
                    "$imports final exposedProvider = Provider((ref) => ref.watch(repositoryProvider));",
              },
            ),
            contains('role_dependencies'),
            reason: 'state provider cannot launder a repository to UI',
          );
        });

        test('concrete and service-locator acquisitions remain forbidden', () async {
          final direct = await run(
            state,
            "import 'package:riverpod/riverpod.dart'; import '${uri(impl)}'; final itemsProvider = Provider<int>((ref) => ItemRepositoryImpl().load());",
          );
          expect(direct, contains('layer_dependencies'));
          expect(direct, contains('depend_on_contracts'));
          expect(direct, contains('constructor_injection'));
          expect(
            await run(notifier, '''
import 'package:riverpod/riverpod.dart';
import '${uri(repo)}';
ItemRepository locate() => throw UnimplementedError();
class Items extends Notifier<int> {
  late final repository = locate();
  @override int build() => repository.load();
}
'''),
            contains('constructor_injection'),
          );
          expect(
            await run(state, '''
import 'package:riverpod/riverpod.dart' show Provider;
import '${uri(repo)}';
class Ref { ItemRepository watch(Object value) => throw UnimplementedError(); }
int items(Ref ref) => ref.watch(Object()).load();
final itemsProvider = Provider<int>((ref) => 1);
'''),
            contains('constructor_injection'),
            reason: 'same-named Ref is not Riverpod',
          );
          expect(
            await run(state, '''
$imports
int items(ProviderContainer container) => container.read(repositoryProvider).load();
'''),
            contains('constructor_injection'),
            reason: 'ProviderContainer is not provider-local Ref',
          );
        });

        test('inferred concrete provider results violate abstract contracts', () async {
          final concreteDi =
              "import 'package:riverpod/riverpod.dart'; import '${uri(impl)}'; final repositoryProvider = Provider((ref) => ItemRepositoryImpl());";
          final result = await run(
            state,
            '$imports final itemsProvider = Provider<int>((ref) => ref.watch(repositoryProvider).load());',
            extra: {di: concreteDi},
          );
          expect(result, contains('depend_on_contracts'));
          expect(result, contains('layer_dependencies'));
        });

        test('only declared provider and notifier folders grant top-level consumer roles', () async {
          final misplaced = '$base/domain/entities/helper.dart';
          expect(
            await run(
              misplaced,
              "import '${uri(repo)}'; ItemRepository use(ItemRepository value) => value;",
            ),
            contains('role_dependencies'),
          );
          // A function returning a notifier does not acquire that notifier's role.
          final manager =
              "import 'package:riverpod/riverpod.dart'; class Items extends Notifier<int> { @override int build() => 1; }";
          expect(
            await run(
              ui,
              "import '${uri(notifier)}'; import '${uri(repo)}'; Items use(ItemRepository repository) => Items();",
              extra: {notifier: manager},
            ),
            contains('role_dependencies'),
          );
        });

        test('domain remains independent of Riverpod and data transport', () async {
          expect(
            await run(
              '$base/domain/entities/item.dart',
              "import 'package:riverpod/riverpod.dart'; int read(Ref ref) => 1;",
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

        if (preset.startsWith('clean')) {
          test('optional use cases are constructor-injected and exposed through DI', () async {
            final source =
                "import '${uri(repo)}'; class LoadItems { final ItemRepository repository; LoadItems(this.repository); int call() => repository.load(); }";
            final validComposition =
                files[di]!.replaceFirst(
                  "import 'package:riverpod/riverpod.dart';",
                  "import 'package:riverpod/riverpod.dart'; import '${uri(usecase)}';",
                ) +
                ' final loadItemsProvider = Provider<LoadItems>((ref) => LoadItems(ref.watch(repositoryProvider)));';
            final extra = {usecase: source, di: validComposition};
            expect(await run(usecase, source), isEmpty);
            expect(await run(di, validComposition, extra: {usecase: source}), isEmpty);
            expect(
              await run(
                state,
                '$imports final itemsProvider = Provider<int>((ref) => ref.watch(loadItemsProvider)());',
                extra: extra,
              ),
              isEmpty,
            );
            expect(
              await run(
                ui,
                "$imports int render(Ref ref) => ref.watch(loadItemsProvider)();",
                extra: extra,
              ),
              contains('role_dependencies'),
            );
          });
        }
      });
    }
  }
}
