import 'local_storage.dart';

/// A newly discovered chapter for a favorited manga.
class NewChapter {
  final String sourceId;
  final String mangaId;
  final String mangaTitle;
  final String coverUrl;
  final String chapterTitle;
  final String foundAt; // ISO8601 timestamp

  const NewChapter({
    required this.sourceId,
    required this.mangaId,
    required this.mangaTitle,
    required this.coverUrl,
    required this.chapterTitle,
    required this.foundAt,
  });

  String get mangaKey => '${sourceId}_$mangaId';

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'mangaId': mangaId,
        'mangaTitle': mangaTitle,
        'coverUrl': coverUrl,
        'chapterTitle': chapterTitle,
        'foundAt': foundAt,
      };

  factory NewChapter.fromJson(Map<String, dynamic> json) => NewChapter(
        sourceId: json['sourceId'] as String? ?? '',
        mangaId: json['mangaId'] as String? ?? '',
        mangaTitle: json['mangaTitle'] as String? ?? '',
        coverUrl: json['coverUrl'] as String? ?? '',
        chapterTitle: json['chapterTitle'] as String? ?? '',
        foundAt: json['foundAt'] as String? ?? '',
      );
}

/// Tracks which manga have unread updates (new chapters since last viewed).
///
/// Storage format (key='update_status'):
///   { 'items': [ NewChapter.toJson(), ... ] }
///
/// Backward compatible with the legacy boolean format
///   { '<sourceId>_<mangaId>': true, ... }
/// which is read as marker-only entries (empty chapter details).
class UpdateStore {
  final LocalStorage _storage;
  static const _key = 'update_status';

  List<NewChapter>? _cache;

  UpdateStore({required LocalStorage storage}) : _storage = storage;

  Future<List<NewChapter>> _getData() async {
    if (_cache != null) return _cache!;
    final raw = await _storage.read(_key);
    if (raw == null) {
      _cache = [];
      return _cache!;
    }
    final items = raw['items'];
    if (items is List) {
      _cache = items
          .whereType<Map>()
          .map((e) => NewChapter.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return _cache!;
    }
    // Legacy boolean format: keys like '<sourceId>_<mangaId>' -> true.
    // Convert to marker-only NewChapter entries (no chapter detail available).
    final migrated = <NewChapter>[];
    for (final entry in raw.entries) {
      if (entry.value == true) {
        final key = entry.key;
        final idx = key.indexOf('_');
        final sourceId = idx > 0 ? key.substring(0, idx) : key;
        final mangaId = idx > 0 ? key.substring(idx + 1) : '';
        migrated.add(NewChapter(
          sourceId: sourceId,
          mangaId: mangaId,
          mangaTitle: '',
          coverUrl: '',
          chapterTitle: '',
          foundAt: '',
        ));
      }
    }
    _cache = migrated;
    return _cache!;
  }

  Future<void> _save() async {
    final data = {'items': (_cache ?? []).map((c) => c.toJson()).toList()};
    await _storage.write(_key, data);
  }

  /// Check if a manga has new chapters.
  Future<bool> hasUpdate(String sourceId, String mangaId) async {
    final data = await _getData();
    final key = '${sourceId}_$mangaId';
    return data.any((c) => c.mangaKey == key);
  }

  /// Record a newly discovered chapter for a manga.
  Future<void> addNewChapter(NewChapter chapter) async {
    final data = await _getData();
    // Avoid duplicate (same manga + same chapter title).
    final exists = data.any((c) =>
        c.mangaKey == chapter.mangaKey && c.chapterTitle == chapter.chapterTitle);
    if (exists) return;
    data.add(chapter);
    _cache = data;
    await _save();
  }

  /// Mark a manga as having new chapters (marker only, no chapter detail).
  Future<void> markUpdated(String sourceId, String mangaId) async {
    await addNewChapter(NewChapter(
      sourceId: sourceId,
      mangaId: mangaId,
      mangaTitle: '',
      coverUrl: '',
      chapterTitle: '',
      foundAt: DateTime.now().toIso8601String(),
    ));
  }

  /// Get all new chapters, most recent first.
  Future<List<NewChapter>> getNewChapters() async {
    final data = await _getData();
    final sorted = List<NewChapter>.of(data)
      ..sort((a, b) => b.foundAt.compareTo(a.foundAt));
    return sorted;
  }

  /// Clear update badge for a manga (user opened it).
  Future<void> clearUpdate(String sourceId, String mangaId) async {
    final data = await _getData();
    final key = '${sourceId}_$mangaId';
    data.removeWhere((c) => c.mangaKey == key);
    _cache = data;
    await _save();
  }

  /// Get all manga keys that have updates.
  Future<Set<String>> getAllUpdated() async {
    final data = await _getData();
    return data.map((c) => c.mangaKey).toSet();
  }

  /// Clear all update badges.
  Future<void> clearAll() async {
    _cache = [];
    await _storage.write(_key, {'items': []});
  }
}
