import 'package:mobx/mobx.dart';

import 'item_repository.dart';

part 'explicit_view_model.g.dart';

class ExplicitViewModel extends _ExplicitViewModel with _$ExplicitViewModel {
  ExplicitViewModel(super.repository);
}

abstract class _ExplicitViewModel with Store {
  _ExplicitViewModel(this._repository);

  final ItemRepository _repository;

  @observable
  int count = 0;

  @computed
  String get label => '$count items';

  @action
  Future<void> load() async {
    count = await _repository.load();
  }
}
