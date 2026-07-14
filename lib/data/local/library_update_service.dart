import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'favorites_store.dart';
import 'update_store.dart';

/// Scans the entire favorites library for new chapters in the background.
///
/// For each favorited manga it fetches the latest info via [MangaRepository],
/// compares `latestChapter` against the stored value, and on change records a
/// structured [NewChapter] in [UpdateStore] and updates the favorite's cached
/// latest chapter. Runs with bounded concurrency to avoid hammering sources.
class LibraryUpdateService extends ChangeNotifier {
  final FavoritesStore _favoritesStore;
  final UpdateStore _updateStore;
  final MangaRepository _repository;

  static const int _concurrency = 3;

  bool _isRunning = false;
  int _progress = 0;
  int _total = 0;
  int _foundCount = 0;

  LibraryUpdateService({
    required FavoritesStore favoritesStore,
    required UpdateStore updateStore,
    required MangaRepository repository,
  })  : _favoritesStore = favoritesStore,
        _updateStore = updateStore,
        _repository = repository;

  bool get isRunning => _isRunning;
  int get progress => _progress;
  int get total => _total;
  int get foundCount => _foundCount;

  /// Runs a full-library update scan. Safe to call fire-and-forget; if a scan
  /// is already running the call is ignored. Returns the number of manga that
  /// received new chapters.
  Future<int> runUpdate() async {
    if (_isRunning) return 0;

    final favorites = await _favoritesStore.getAll();
    if (favorites.isEmpty) return 0;

    _isRunning = true;
    _progress = 0;
    _total = favorites.length;
    _foundCount = 0;
    notifyListeners();

    final queue = List.of(favorites);
    var index = 0;

    Future<void> worker() async {
      while (true) {
        if (index >= queue.length) return;
        final manga = queue[index++];
        try {
          final detail =
              await _repository.getMangaInfo(manga.sourceId, manga.id);
          final latest = detail.latestChapter;
          if (latest != null &&
              latest.isNotEmpty &&
              latest != manga.latestChapter) {
            await _updateStore.addNewChapter(NewChapter(
              sourceId: manga.sourceId,
              mangaId: manga.id,
              mangaTitle: manga.title,
              coverUrl: manga.coverUrl,
              chapterTitle: latest,
              foundAt: DateTime.now().toIso8601String(),
            ));
            await _favoritesStore.updateLatestChapter(
                manga.sourceId, manga.id, latest);
            _foundCount++;
          }
        } catch (_) {
          // Ignore per-manga failures (network/parse); keep scanning.
        } finally {
          _progress++;
          notifyListeners();
        }
      }
    }

    try {
      await Future.wait(
        List.generate(_concurrency, (_) => worker()),
      );
    } finally {
      _isRunning = false;
      notifyListeners();
    }

    return _foundCount;
  }
}
