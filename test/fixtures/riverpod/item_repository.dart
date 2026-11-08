abstract interface class ItemRepository {
  int load();
}

class ItemRepositoryImpl implements ItemRepository {
  @override
  int load() => 1;
}
