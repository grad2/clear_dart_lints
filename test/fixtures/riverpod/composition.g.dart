// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(repository)
final repositoryProvider = RepositoryProvider._();

final class RepositoryProvider
    extends $FunctionalProvider<ItemRepository, ItemRepository, ItemRepository>
    with $Provider<ItemRepository> {
  RepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'repositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$repositoryHash();

  @$internal
  @override
  $ProviderElement<ItemRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ItemRepository create(Ref ref) {
    return repository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ItemRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ItemRepository>(value),
    );
  }
}

String _$repositoryHash() => r'0b9f02c5738caeb7beedc2b54632fee7d86982c5';
