import 'package:flutter/foundation.dart';
import 'local_storage.dart';

/// A user-defined library category (e.g. "Reading", "Completed", by genre...).
///
/// Categories are stored separately from favorites. Each favorite manga keeps a
/// list of category ids in [FavoritesStore]; a manga with no ids is treated as
/// "uncategorized". The special "all"/"uncategorized" tabs are virtual and are
/// never persisted here.
@immutable
class Category {
  final String id;
  final String name;
  final int order;

  const Category({
    required this.id,
    required this.name,
    required this.order,
  });

  Category copyWith({String? id, String? name, int? order}) => Category(
        id: id ?? this.id,
        name: name ?? this.name,
        order: order ?? this.order,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'order': order,
      };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        order: json['order'] as int? ?? 0,
      );
}

/// Persists the list of user-defined categories.
///
/// Exposes a [ValueNotifier] so UI can reactively listen for changes, mirroring
/// [FavoritesStore]. The store owns only the category definitions; the mapping
/// of manga -> categories lives in [FavoritesStore].
class CategoryStore {
  final LocalStorage _storage;
  static const _key = 'categories';

  List<Category>? _cache;

  /// Notifier that increments whenever categories change.
  final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  CategoryStore({required LocalStorage storage}) : _storage = storage;

  /// Returns all user-defined categories sorted by [Category.order].
  Future<List<Category>> getAll() async {
    if (_cache != null) return List.of(_cache!);
    final data = await _storage.read(_key);
    if (data == null || data['items'] == null) {
      _cache = [];
      return [];
    }
    final items = (data['items'] as List)
        .map((json) => Category.fromJson(json as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    _cache = items;
    return List.of(items);
  }

  /// Creates a new category with the given [name], appended after existing ones.
  /// Returns the created [Category].
  Future<Category> add(String name) async {
    final categories = await getAll();
    final maxOrder = categories.isEmpty
        ? -1
        : categories.map((c) => c.order).reduce((a, b) => a > b ? a : b);
    final category = Category(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      order: maxOrder + 1,
    );
    _cache = [...categories, category];
    await _save();
    notifier.value++;
    return category;
  }

  /// Renames the category with [id].
  Future<void> rename(String id, String name) async {
    final categories = await getAll();
    final index = categories.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _cache![index] = categories[index].copyWith(name: name.trim());
    await _save();
    notifier.value++;
  }

  /// Removes the category with [id].
  ///
  /// Note: this does NOT clean up the id from favorites; a stale id simply
  /// resolves to nothing when filtering, which is harmless. Callers that want
  /// to scrub the id from favorites should do so explicitly.
  Future<void> remove(String id) async {
    final categories = await getAll();
    _cache = categories.where((c) => c.id != id).toList();
    await _save();
    notifier.value++;
  }

  /// Reorders categories to match the given [orderedIds] sequence.
  Future<void> reorder(List<String> orderedIds) async {
    final categories = await getAll();
    final byId = {for (final c in categories) c.id: c};
    final reordered = <Category>[];
    var order = 0;
    for (final id in orderedIds) {
      final c = byId[id];
      if (c != null) reordered.add(c.copyWith(order: order++));
    }
    // Preserve any categories not present in orderedIds (defensive).
    for (final c in categories) {
      if (!orderedIds.contains(c.id)) reordered.add(c.copyWith(order: order++));
    }
    _cache = reordered;
    await _save();
    notifier.value++;
  }

  Future<void> _save() async {
    final items = (_cache ?? []).map((c) => c.toJson()).toList();
    await _storage.write(_key, {'items': items});
  }
}
