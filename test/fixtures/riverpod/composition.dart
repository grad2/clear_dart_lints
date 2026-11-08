import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'item_repository.dart';

part 'composition.g.dart';

@Riverpod(keepAlive: true)
ItemRepository repository(Ref ref) => ItemRepositoryImpl();
