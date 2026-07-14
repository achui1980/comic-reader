import 'package:flutter/foundation.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'local_storage.dart';

/// Manages favorite manga persistence.
/// Exposes a [ValueNotifier] so UI can reactively listen for changes.
class FavoritesStore {
  final LocalStorage _storage;
  static const _key = 'favorites';

  List<MangaSummary>? _cache;

  /// Maps a manga key ('${sourceId}_${id}') to the list of category ids it
  /// belongs to. A manga absent from this map (or with an empty list) is
  /// treated as "uncategorized". Kept separate from [MangaSummary] so the
  /// domain entity is not touched.
  Map<String, List<String>>? _categoryIds;

  /// Notifier that increments whenever favorites change.
  final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  FavoritesStore({required LocalStorage storage}) : _storage = storage;

  static String _mangaKey(String sourceId, String mangaId) =>
      '${sourceId}_$mangaId';

  Future<List<MangaSummary>> getAll() async {
    if (_cache != null) return List.of(_cache!);
    final data = await _storage.read(_key);
    if (data == null || data['items'] == null) {
      _cache = [];
      _categoryIds = {};
      return [];
    }
    final categoryIds = <String, List<String>>{};
    final items = (data['items'] as List).map((json) {
      final id = json['id'] as String;
      final sourceId = json['sourceId'] as String;
      final rawCats = json['categoryIds'];
      if (rawCats is List && rawCats.isNotEmpty) {
        categoryIds[_mangaKey(sourceId, id)] =
            rawCats.map((e) => e as String).toList();
      }
      return MangaSummary(
        id: id,
        sourceId: sourceId,
        title: json['title'] as String,
        coverUrl: json['coverUrl'] as String,
        author: json['author'] as String? ?? '',
        latestChapter: json['latestChapter'] as String?,
        updateTime: json['updateTime'] as String?,
      );
    }).toList();
    _cache = items;
    _categoryIds = categoryIds;
    return List.of(items);
  }

  /// Returns the category ids assigned to a favorite manga (empty = uncategorized).
  Future<List<String>> getCategoryIds(String sourceId, String mangaId) async {
    await getAll();
    return List.of(_categoryIds![_mangaKey(sourceId, mangaId)] ?? const []);
  }

  /// Returns the full manga-key -> category-ids map (for bulk filtering in UI).
  Future<Map<String, List<String>>> getCategoryMap() async {
    await getAll();
    return {
      for (final entry in _categoryIds!.entries) entry.key: List.of(entry.value)
    };
  }

  /// Assigns the given category [ids] to a favorite manga (replaces existing).
  /// Passing an empty list marks the manga as uncategorized.
  Future<void> setCategoryIds(
      String sourceId, String mangaId, List<String> ids) async {
    await getAll();
    final key = _mangaKey(sourceId, mangaId);
    if (ids.isEmpty) {
      _categoryIds!.remove(key);
    } else {
      _categoryIds![key] = List.of(ids);
    }
    await _save();
    notifier.value++;
  }

  Future<bool> isFavorite(String sourceId, String mangaId) async {
    final favorites = await getAll();
    return favorites.any((m) => m.id == mangaId && m.sourceId == sourceId);
  }

  Future<void> add(MangaSummary manga) async {
    final favorites = await getAll();
    if (favorites.any((m) => m.id == manga.id && m.sourceId == manga.sourceId)) {
      return;
    }
    _cache = [...favorites, manga];
    await _save();
    notifier.value++;
  }

  Future<void> remove(String sourceId, String mangaId) async {
    final favorites = await getAll();
    _cache = favorites.where((m) => !(m.id == mangaId && m.sourceId == sourceId)).toList();
    _categoryIds!.remove(_mangaKey(sourceId, mangaId));
    await _save();
    notifier.value++;
  }

  /// Update the stored latestChapter for a manga (called after batch update finds new chapters).
  Future<void> updateLatestChapter(String sourceId, String mangaId, String latestChapter) async {
    final favorites = await getAll();
    final index = favorites.indexWhere((m) => m.id == mangaId && m.sourceId == sourceId);
    if (index == -1) return;
    final old = _cache![index];
    final updated = MangaSummary(
      id: old.id,
      sourceId: old.sourceId,
      title: old.title,
      coverUrl: old.coverUrl,
      author: old.author,
      latestChapter: latestChapter,
      updateTime: old.updateTime,
      headers: old.headers,
    );
    _cache![index] = updated;
    await _save();
  }

  Future<void> _save() async {
    final categoryIds = _categoryIds ?? {};
    final items = (_cache ?? []).map((m) {
      final cats = categoryIds[_mangaKey(m.sourceId, m.id)];
      return <String, dynamic>{
        'id': m.id,
        'sourceId': m.sourceId,
        'title': m.title,
        'coverUrl': m.coverUrl,
        'author': m.author,
        'latestChapter': m.latestChapter,
        'updateTime': m.updateTime,
        if (cats != null && cats.isNotEmpty) 'categoryIds': cats,
      };
    }).toList();
    await _storage.write(_key, {'items': items});
  }
}
