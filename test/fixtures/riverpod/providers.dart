import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'composition.dart';

part 'providers.g.dart';

@riverpod
int items(Ref ref) => ref.watch(repositoryProvider).load();

@riverpod
Future<int> asyncItems(Ref ref) async => ref.read(repositoryProvider).load();

@Riverpod(keepAlive: true)
Stream<int> streamItems(Ref ref) => Stream.value(ref.watch(repositoryProvider).load());

@riverpod
int familyItems(Ref ref, int id) => ref.watch(repositoryProvider).load() + id;

@riverpod
class ItemsController extends _$ItemsController {
  @override
  int build() => ref.watch(repositoryProvider).load();

  void reload() => state = ref.read(repositoryProvider).load();
}

@riverpod
class AsyncItemsController extends _$AsyncItemsController {
  @override
  Future<int> build() async => ref.watch(repositoryProvider).load();
}

@riverpod
class StreamItemsController extends _$StreamItemsController {
  @override
  Stream<int> build() => Stream.value(ref.watch(repositoryProvider).load());
}
