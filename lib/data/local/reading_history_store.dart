import 'local_storage.dart';

/// Stores reading progress per manga chapter.
class ReadingHistoryStore {
  final LocalStorage _storage;
  static const _key = 'reading_history';

  Map<String, dynamic>? _cache;

  ReadingHistoryStore({required LocalStorage storage}) : _storage = storage;

  Future<Map<String, dynamic>> _getData() async {
    _cache ??= await _storage.read(_key) ?? {};
    return _cache!;
  }

  /// Get last read chapter and page for a manga.
  /// Returns {'chapterId': String, 'page': int} or null.
  Future<Map<String, dynamic>?> getProgress(
      String sourceId, String mangaId) async {
    final data = await _getData();
    final key = '${sourceId}_$mangaId';
    final entry = data[key];
    if (entry is Map<String, dynamic>) return entry;
    return null;
  }

  /// Save reading progress.
  Future<void> saveProgress(
      String sourceId, String mangaId, String chapterId, int page) async {
    final data = await _getData();
    final key = '${sourceId}_$mangaId';
    data[key] = <String, dynamic>{
      'chapterId': chapterId,
      'page': page,
      'timestamp': DateTime.now().toIso8601String(),
    };
    _cache = data;
    await _storage.write(_key, data);
  }

  /// Get all chapter IDs that have been read for a manga.
  Future<Set<String>> getReadChapters(String sourceId, String mangaId) async {
    final data = await _getData();
    final Set<String> result = {};
    // The main progress key stores the last-read chapter
    final key = '${sourceId}_$mangaId';
    final entry = data[key];
    if (entry is Map<String, dynamic> && entry['chapterId'] != null) {
      result.add(entry['chapterId'] as String);
    }
    // Also check per-chapter keys if stored
    final chapterHistoryKey = '${sourceId}_${mangaId}_chapters';
    final chapters = data[chapterHistoryKey];
    if (chapters is List) {
      result.addAll(chapters.cast<String>());
    }
    return result;
  }

  /// Record that a chapter has been visited.
  Future<void> markChapterRead(String sourceId, String mangaId, String chapterId) async {
    final data = await _getData();
    final key = '${sourceId}_${mangaId}_chapters';
    final chapters = (data[key] as List<dynamic>?)?.cast<String>().toSet() ?? {};
    chapters.add(chapterId);
    data[key] = chapters.toList();
    _cache = data;
    await _storage.write(_key, data);
  }
}
