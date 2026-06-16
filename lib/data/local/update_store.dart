import 'local_storage.dart';

/// Tracks which manga have unread updates (new chapters since last viewed).
class UpdateStore {
  final LocalStorage _storage;
  static const _key = 'update_status';

  Map<String, dynamic>? _cache;

  UpdateStore({required LocalStorage storage}) : _storage = storage;

  Future<Map<String, dynamic>> _getData() async {
    _cache ??= await _storage.read(_key) ?? {};
    return _cache!;
  }

  /// Check if a manga has new chapters.
  Future<bool> hasUpdate(String sourceId, String mangaId) async {
    final data = await _getData();
    final key = '${sourceId}_$mangaId';
    return data[key] == true;
  }

  /// Mark a manga as having new chapters.
  Future<void> markUpdated(String sourceId, String mangaId) async {
    final data = await _getData();
    data['${sourceId}_$mangaId'] = true;
    _cache = data;
    await _storage.write(_key, data);
  }

  /// Clear update badge for a manga (user opened it).
  Future<void> clearUpdate(String sourceId, String mangaId) async {
    final data = await _getData();
    data.remove('${sourceId}_$mangaId');
    _cache = data;
    await _storage.write(_key, data);
  }

  /// Get all manga keys that have updates.
  Future<Set<String>> getAllUpdated() async {
    final data = await _getData();
    return data.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toSet();
  }

  /// Clear all update badges.
  Future<void> clearAll() async {
    _cache = {};
    await _storage.write(_key, {});
  }
}
