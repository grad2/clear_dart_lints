import 'package:clear_dart_lints/src/architecture/policy.dart';
import 'package:test/test.dart';

import 'new_rules_test.dart' show check;

const _policy = '''
schema_version: 2
include: ['main.dart', 'lib/**']
layers:
  app: ['main.dart', 'lib/**']
rules:
  layer_dependencies:
    allowed:
      - from: [app]
        to: [app]
        uris: ['dart:*']
''';

const _injectionPolicy = '''
schema_version: 2
include: ['main.dart', 'lib/**']
layers:
  app: ['main.dart', 'lib/**']
roles:
  repository:
    names: ['*Repository', '*Datasource']
    libraries: ['lib/**']
rules:
  layer_dependencies:
    allowed:
      - from: [app]
        to: [app]
        uris: ['dart:*']
  constructor_injection:
    source_layers: [app]
    dependency_roles: [repository]
  depend_on_contracts:
    source_layers: [app]
    dependency_roles: [repository]
''';

const _dependencies = {
  'lib/dependencies.dart': '''
abstract interface class ItemRepository { int load(); }
class ItemRepositoryImpl implements ItemRepository {
  @override int load() => 1;
}
ItemRepository locateRepository() => ItemRepositoryImpl();
(ItemRepository,) locateRecord() => (ItemRepositoryImpl(),);
abstract interface class CatalogSnapshotDatasource<T> { Future<T> load(); }
''',
};

Future<List<String>> _run(String source, {bool injection = false, bool valid = true}) => check(
  ArchitecturePolicy(),
  source,
  config: injection ? _injectionPolicy : _policy,
  files: injection ? _dependencies : const {},
  requireValid: valid,
);

void main() {
  group('statically resolved dependency expressions', () {
    test('positional and named record fields work through aliases and expressions', () async {
      expect(
        await _run(r'''
typedef TileKey = (int, int, int);
typedef NamedKey = ({int x, int y});
int positional(TileKey tile) => tile.$1 + tile.$2 + tile.$3;
int named(NamedKey tile) => tile.x + tile.y;
TileKey identity(TileKey tile) => tile;
int expression(TileKey tile) => identity(tile).$1;
int? nullable(TileKey? tile) => tile?.$2;
'''),
        isEmpty,
      );
    });

    test('unknown record fields and dynamic record-like access remain unverifiable', () async {
      expect(
        await _run(r'int read((int, int) tile) => tile.$3;', valid: false),
        contains('unverifiable_dependency'),
      );
      expect(await _run(r'Object? read(dynamic tile) => tile.$1;'), ['unverifiable_dependency']);
      expect(
        await _run(r'void write((int, int) tile) { tile.$1 = 1; }', valid: false),
        contains('unverifiable_dependency'),
      );
    });

    test('typed generic Map writes and read-modify-writes resolve their setters', () async {
      expect(
        await _run('''
void put<K, V>(Map<K, V> map, K key, V value) { map[key] = value; }
void update(Map<String, int> map) {
  map['count'] = 1;
  map['count'] = (map['count'] ?? 0) + 1;
}
void updateList(List<int> values) { values[0] += 1; values[0]++; ++values[0]; }
class WriteOnly { void operator []=(int key, int value) {} }
void write(WriteOnly target) { target[0] = 1; }
'''),
        isEmpty,
      );
    });

    test('dynamic indexes and unresolved index setters remain unverifiable', () async {
      expect(await _run("void write(dynamic target) { target[0] = 1; target[0]++; }"), [
        'unverifiable_dependency',
        'unverifiable_dependency',
      ]);
      expect(
        await _run('''
class ReadOnly { int operator [](int key) => key; }
void write(ReadOnly target) { target[0] = 1; }
''', valid: false),
        contains('unverifiable_dependency'),
      );
    });

    test('nullable function callbacks have a statically known call signature', () async {
      expect(
        await _run('''
typedef TileKey = (int, int, int);
class Synchronizer {
  final Future<void> Function(Set<TileKey>)? synchronize;
  Synchronizer(this.synchronize);
  Future<void> clear() async { await synchronize?.call({}); }
  Future<void> update(Set<TileKey> wanted) async { await synchronize?.call(wanted); }
}
void invoke(void Function(int) callback) { callback.call(1); }
'''),
        isEmpty,
      );
    });

    test('dynamic callables and unresolved callback methods remain unverifiable', () async {
      expect(await _run('void invoke(dynamic callback) { callback.call(); callback(); }'), [
        'unverifiable_dependency',
        'unverifiable_dependency',
      ]);
      expect(
        await _run('void invoke(void Function() callback) { callback.missing(); }', valid: false),
        contains('unverifiable_dependency'),
      );
    });
  });

  group('explicit dependency injection', () {
    const dependencyImport = "import 'lib/dependencies.dart';\n";

    test('free functions receive repositories through positional and named parameters', () async {
      expect(
        await _run('''${dependencyImport}
int load(ItemRepository repository) => repository.load();
int named({required ItemRepository repository}) => repository.load();
int optional([ItemRepository? repository]) => repository?.load() ?? 0;
''', injection: true),
        isEmpty,
      );
    });

    test('free function parameters do not waive construction or locator acquisition', () async {
      final codes = await _run('''${dependencyImport}
int load(ItemRepository injected) {
  final direct = ItemRepositoryImpl();
  final located = locateRepository();
  return injected.load() + direct.load() + located.load();
}
''', injection: true);
      expect(codes.where((c) => c == 'constructor_injection'), hasLength(2));
      expect(codes, contains('depend_on_contracts'));
    });

    test('method and nested callback parameters still require constructor injection', () async {
      for (final source in [
        'class Consumer { int load(ItemRepository repository) => repository.load(); }',
        'Object outer() { int inner(ItemRepository repository) => repository.load(); return inner; }',
        'Object outer() { return (ItemRepository repository) => repository.load(); }',
      ]) {
        expect(
          await _run('$dependencyImport$source', injection: true),
          contains('constructor_injection'),
          reason: source,
        );
      }
    });

    test('record signatures preserve dependency injection and acquisition checks', () async {
      expect(
        await _run('''${dependencyImport}
int load((ItemRepository,) dependencies) => dependencies.\$1.load();
class Consumer {
  final ({ItemRepository repository}) dependencies;
  Consumer(this.dependencies);
  int load() => dependencies.repository.load();
}
''', injection: true),
        isEmpty,
      );
      expect(
        await _run('''${dependencyImport}
int load() { final dependencies = locateRecord(); return dependencies.\$1.load(); }
''', injection: true),
        contains('constructor_injection'),
      );
    });

    test('nullable datasource can be explicitly absent in the loader-only constructor', () async {
      expect(
        await _run('''${dependencyImport}
class CatalogCache<T> {
  final Future<T> Function()? _load;
  final CatalogSnapshotDatasource<T>? _source;
  CatalogCache({required Future<T> Function() load}) : _load = load, _source = null;
  CatalogCache.persistent(CatalogSnapshotDatasource<T> source) : _source = source, _load = null;
  Future<T> load() => _source?.load() ?? _load!();
}
''', injection: true),
        isEmpty,
      );
    });

    test('explicit null field and unconditional constructor assignments are absence', () async {
      expect(
        await _run('''${dependencyImport}
class Absent { final ItemRepository? repository = (null); }
class Optional {
  late final ItemRepository? repository;
  Optional.none() { repository = (null); }
  Optional(this.repository);
}
''', injection: true),
        isEmpty,
      );
    });

    test('nullable dependencies still reject fallbacks and non-parameter origins', () async {
      for (final source in [
        'class Cache { final ItemRepository? repository; Cache(ItemRepository? input) : repository = input ?? ItemRepositoryImpl(); }',
        'class Cache { final ItemRepository? repository; Cache() : repository = locateRepository(); }',
        'final ItemRepository? global = null; class Cache { final ItemRepository? repository; Cache() : repository = global; }',
        'class Cache { ItemRepository? repository; Cache.none(); Cache(this.repository); }',
        'class Cache { late final ItemRepository? repository; Cache(bool absent) { if (absent) repository = null; } }',
        'final ItemRepository? global = null; class Cache { ItemRepository? repository; Cache() : repository = null { repository = global; } }',
        'final ItemRepository? global = null; class Cache { ItemRepository? repository = null; Cache(bool replace) { if (replace) repository = global; } }',
        'final ItemRepository? global = null; class Cache { late ItemRepository? repository; Cache() { repository = null; repository = global; } }',
      ]) {
        expect(
          await _run('$dependencyImport$source', injection: true),
          contains('constructor_injection'),
          reason: source,
        );
      }
    });

    test('invalid null assignment to a non-nullable dependency is not injection', () async {
      expect(
        await _run(
          '''${dependencyImport}
class Invalid { final ItemRepository repository; Invalid() : repository = null; }
''',
          injection: true,
          valid: false,
        ),
        contains('constructor_injection'),
      );
    });
  });
}
