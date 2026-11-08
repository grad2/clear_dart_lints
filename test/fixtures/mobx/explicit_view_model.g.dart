// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'explicit_view_model.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ExplicitViewModel on _ExplicitViewModel, Store {
  Computed<String>? _$labelComputed;

  @override
  String get label => (_$labelComputed ??= Computed<String>(
    () => super.label,
    name: '_ExplicitViewModel.label',
  )).value;

  late final _$countAtom = Atom(name: '_ExplicitViewModel.count', context: context);

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

  late final _$loadAsyncAction = AsyncAction('_ExplicitViewModel.load', context: context);

  @override
  Future<void> load() {
    return _$loadAsyncAction.run(() => super.load());
  }

  @override
  String toString() {
    return '''
count: ${count},
label: ${label}
    ''';
  }
}
