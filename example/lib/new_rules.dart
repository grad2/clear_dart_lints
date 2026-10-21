// ignore_for_file: clear_dart_lints/one_public_class_per_file
import 'dart:convert';

import 'package:flutter/widgets.dart';

abstract class ItemRepository {}

class ItemRepositoryImpl implements ItemRepository {}

class ItemsBloc {
  final ItemRepository repository;
  ItemsBloc(this.repository);
}

class ApiClient {}

class Item {
  late final String label;
}

Future<Item>? load() => null;
List<Item>? loadItems() => null;
ItemRepository? repository;
final concrete = ItemRepositoryImpl();
final client = ApiClient();
String encodeItem(Object item) {
  return jsonEncode(item);
}

Widget chooseItem(bool first, bool second) {
  return first ? (second ? const SizedBox() : const SizedBox()) : const SizedBox();
}
