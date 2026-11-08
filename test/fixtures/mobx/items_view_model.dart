import 'package:mobx/mobx.dart';

import 'item_repository.dart';

part 'items_view_model.g.dart';

class ItemsViewModel = _ItemsViewModel with _$ItemsViewModel;

abstract class _ItemsViewModel with Store {
  _ItemsViewModel(this._repository);

  final ItemRepository _repository;

  @observable
  int count = 0;

  @observable
  bool loading = false;

  @computed
  bool get hasItems => count > 0;

  @action
  void increment() {
    count++;
  }

  @action
  void adjust() {
    ++count;
    count += 1;
  }

  @action
  Future<void> load() async {
    loading = true;
    try {
      count = await _repository.load();
    } finally {
      loading = false;
    }
  }
}
