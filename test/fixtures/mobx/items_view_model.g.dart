// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'items_view_model.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ItemsViewModel on _ItemsViewModel, Store {
  Computed<bool>? _$hasItemsComputed;

  @override
  bool get hasItems => (_$hasItemsComputed ??= Computed<bool>(
    () => super.hasItems,
    name: '_ItemsViewModel.hasItems',
  )).value;

  late final _$countAtom = Atom(name: '_ItemsViewModel.count', context: context);

  @override
  int get count {
    _$countAtom.reportRead();
    return super.count;
  }

  @override
  set count(int value) {
    _$countAtom.reportWrite(value, super.count, () {
      super.count = value;
    });
  }

  late final _$loadingAtom = Atom(name: '_ItemsViewModel.loading', context: context);

  @override
  bool get loading {
    _$loadingAtom.reportRead();
    return super.loading;
  }

  @override
  set loading(bool value) {
    _$loadingAtom.reportWrite(value, super.loading, () {
      super.loading = value;
    });
  }

  late final _$loadAsyncAction = AsyncAction('_ItemsViewModel.load', context: context);

  @override
  Future<void> load() {
    return _$loadAsyncAction.run(() => super.load());
  }

  late final _$_ItemsViewModelActionController = ActionController(
    name: '_ItemsViewModel',
    context: context,
  );

  @override
  void increment() {
    final _$actionInfo = _$_ItemsViewModelActionController.startAction(
      name: '_ItemsViewModel.increment',
    );
    try {
      return super.increment();
    } finally {
      _$_ItemsViewModelActionController.endAction(_$actionInfo);
    }
  }

  @override
  void adjust() {
    final _$actionInfo = _$_ItemsViewModelActionController.startAction(
      name: '_ItemsViewModel.adjust',
    );
    try {
      return super.adjust();
    } finally {
      _$_ItemsViewModelActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
count: ${count},
loading: ${loading},
hasItems: ${hasItems}
    ''';
  }
}
