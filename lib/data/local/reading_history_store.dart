import 'local_storage.dart';

/// A single entry in the reading timeline (most-recent-first).
class HistoryEntry {
  final String sourceId;
  final String mangaId;
  final String mangaTitle;
  final String coverUrl;
  final String chapterId;
  final String chapterTitle;
  final int page;
  final String timestamp; // ISO8601

  const HistoryEntry({
    required this.sourceId,
    required this.mangaId,
    required this.mangaTitle,
    required this.coverUrl,
    required this.chapterId,
    required this.chapterTitle,
    required this.page,
    required this.timestamp,
  });

  /// Identifies the manga (timeline keeps only the latest entry per manga).
  String get mangaKey => '${sourceId}_$mangaId';

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'mangaId': mangaId,
        'mangaTitle': mangaTitle,
        'coverUrl': coverUrl,
        'chapterId': chapterId,
        'chapterTitle': chapterTitle,
        'page': page,
        'timestamp': timestamp,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        sourceId: json['sourceId'] as String? ?? '',
        mangaId: json['mangaId'] as String? ?? '',
        mangaTitle: json['mangaTitle'] as String? ?? '',
        coverUrl: json['coverUrl'] as String? ?? '',
        chapterId: json['chapterId'] as String? ?? '',
        chapterTitle: json['chapterTitle'] as String? ?? '',
        page: json['page'] as int? ?? 0,
        timestamp: json['timestamp'] as String? ?? '',
      );
}

/// Stores reading progress per manga chapter.
class ReadingHistoryStore {
  final LocalStorage _storage;
  static const _key = 'reading_history';
  static const _timelineKey = 'reading_timeline';
  static const _maxHistory = 200;

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

  // ---- Reading timeline (most-recent-first, de-duplicated per manga) ----

  List<HistoryEntry>? _timelineCache;

  Future<List<HistoryEntry>> _getTimeline() async {
    if (_timelineCache != null) return _timelineCache!;
    final raw = await _storage.read(_timelineKey);
    final items = raw?['items'];
    if (items is List) {
      _timelineCache = items
          .whereType<Map>()
          .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      _timelineCache = [];
    }
    return _timelineCache!;
  }

  Future<void> _saveTimeline() async {
    await _storage.write(_timelineKey, {
      'items': (_timelineCache ?? []).map((e) => e.toJson()).toList(),
    });
  }

  /// Append an entry to the reading timeline. If the same manga already exists,
  /// the previous entry is removed and the new one is placed at the top (most
  /// recent). The list is capped at [_maxHistory].
  Future<void> addHistory(HistoryEntry entry) async {
    final timeline = await _getTimeline();
    timeline.removeWhere((e) => e.mangaKey == entry.mangaKey);
    timeline.insert(0, entry);
    if (timeline.length > _maxHistory) {
      timeline.removeRange(_maxHistory, timeline.length);
    }
    _timelineCache = timeline;
    await _saveTimeline();
  }

  /// Get the reading timeline, most-recent-first.
  Future<List<HistoryEntry>> getHistory() async {
    return List.of(await _getTimeline());
  }

  /// Remove a single manga's entry from the timeline.
  Future<void> removeHistory(String sourceId, String mangaId) async {
    final timeline = await _getTimeline();
    final key = '${sourceId}_$mangaId';
    timeline.removeWhere((e) => e.mangaKey == key);
    _timelineCache = timeline;
    await _saveTimeline();
  }

  /// Clear the entire reading timeline.
  Future<void> clearHistory() async {
    _timelineCache = [];
    await _storage.write(_timelineKey, {'items': []});
  }
}
