// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(items)
final itemsProvider = ItemsProvider._();

final class ItemsProvider extends $FunctionalProvider<int, int, int> with $Provider<int> {
  ItemsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'itemsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$itemsHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return items(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<int>(value));
  }
}

String _$itemsHash() => r'60b22c34c5413e04b369ecba907d92bf909bbfb4';

@ProviderFor(asyncItems)
final asyncItemsProvider = AsyncItemsProvider._();

final class AsyncItemsProvider extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  AsyncItemsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'asyncItemsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$asyncItemsHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return asyncItems(ref);
  }
}

String _$asyncItemsHash() => r'ec16472537c02fe1c051d33ed123de57f94986bc';

@ProviderFor(streamItems)
final streamItemsProvider = StreamItemsProvider._();

final class StreamItemsProvider extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  StreamItemsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'streamItemsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$streamItemsHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return streamItems(ref);
  }
}

String _$streamItemsHash() => r'974df5106ea949a16353a38bbbc505d667431218';

@ProviderFor(familyItems)
final familyItemsProvider = FamilyItemsFamily._();

final class FamilyItemsProvider extends $FunctionalProvider<int, int, int> with $Provider<int> {
  FamilyItemsProvider._({required FamilyItemsFamily super.from, required int super.argument})
    : super(
        retry: null,
        name: r'familyItemsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$familyItemsHash();

  @override
  String toString() {
    return r'familyItemsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    final argument = this.argument as int;
    return familyItems(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<int>(value));
  }

  @override
  bool operator ==(Object other) {
    return other is FamilyItemsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$familyItemsHash() => r'15c3a106798c51bb8eeefc14c5c8b09255f5a10f';

final class FamilyItemsFamily extends $Family with $FunctionalFamilyOverride<int, int> {
  FamilyItemsFamily._()
    : super(
        retry: null,
        name: r'familyItemsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FamilyItemsProvider call(int id) => FamilyItemsProvider._(argument: id, from: this);

  @override
  String toString() => r'familyItemsProvider';
}

@ProviderFor(ItemsController)
final itemsControllerProvider = ItemsControllerProvider._();

final class ItemsControllerProvider extends $NotifierProvider<ItemsController, int> {
  ItemsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'itemsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$itemsControllerHash();

  @$internal
  @override
  ItemsController create() => ItemsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<int>(value));
  }
}

String _$itemsControllerHash() => r'3834737ae4f25af854e38e2c861c321d27feed6d';

abstract class _$ItemsController extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element as $ClassProviderElement<AnyNotifier<int, int>, int, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(AsyncItemsController)
final asyncItemsControllerProvider = AsyncItemsControllerProvider._();

final class AsyncItemsControllerProvider extends $AsyncNotifierProvider<AsyncItemsController, int> {
  AsyncItemsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'asyncItemsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$asyncItemsControllerHash();

  @$internal
  @override
  AsyncItemsController create() => AsyncItemsController();
}

String _$asyncItemsControllerHash() => r'f1d2effc21550f6ef9e247d23879bd96ed16ebae';

abstract class _$AsyncItemsController extends $AsyncNotifier<int> {
  FutureOr<int> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<int>, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<int>, int>,
              AsyncValue<int>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(StreamItemsController)
final streamItemsControllerProvider = StreamItemsControllerProvider._();

final class StreamItemsControllerProvider
    extends $StreamNotifierProvider<StreamItemsController, int> {
  StreamItemsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'streamItemsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$streamItemsControllerHash();

  @$internal
  @override
  StreamItemsController create() => StreamItemsController();
}

String _$streamItemsControllerHash() => r'578098424e6bdabeb7271d6994d8c4d8ef5eecb0';

abstract class _$StreamItemsController extends $StreamNotifier<int> {
  Stream<int> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<int>, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<int>, int>,
              AsyncValue<int>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
