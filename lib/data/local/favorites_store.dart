import 'package:flutter/foundation.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'local_storage.dart';

/// Manages favorite manga persistence.
/// Exposes a [ValueNotifier] so UI can reactively listen for changes.
class FavoritesStore {
  final LocalStorage _storage;
  static const _key = 'favorites';

  List<MangaSummary>? _cache;

  /// Notifier that increments whenever favorites change.
  final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  FavoritesStore({required LocalStorage storage}) : _storage = storage;

  Future<List<MangaSummary>> getAll() async {
    if (_cache != null) return List.of(_cache!);
    final data = await _storage.read(_key);
    if (data == null || data['items'] == null) {
      _cache = [];
      return [];
    }
    final items = (data['items'] as List).map((json) => MangaSummary(
      id: json['id'] as String,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String,
      coverUrl: json['coverUrl'] as String,
      author: json['author'] as String? ?? '',
      latestChapter: json['latestChapter'] as String?,
      updateTime: json['updateTime'] as String?,
    )).toList();
    _cache = items;
    return List.of(items);
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
    await _save();
    notifier.value++;
  }

  Future<void> _save() async {
    final items = (_cache ?? []).map((m) => <String, dynamic>{
      'id': m.id,
      'sourceId': m.sourceId,
      'title': m.title,
      'coverUrl': m.coverUrl,
      'author': m.author,
      'latestChapter': m.latestChapter,
      'updateTime': m.updateTime,
    }).toList();
    await _storage.write(_key, {'items': items});
  }
}
