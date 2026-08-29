import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/data/local/category_store.dart';
import 'package:comic_reader/data/local/library_update_service.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final FavoritesStore _favoritesStore;
  final UpdateStore _updateStore;
  final CategoryStore _categoryStore;
  final LibraryUpdateService _libraryUpdateService;
  final MangaRepository _repository;
  final ReadingHistoryStore _historyStore;
  final DownloadManager _downloadManager;

  HomeCubit({
    required FavoritesStore favoritesStore,
    required UpdateStore updateStore,
    required CategoryStore categoryStore,
    required LibraryUpdateService libraryUpdateService,
    required MangaRepository repository,
    required ReadingHistoryStore historyStore,
    required DownloadManager downloadManager,
  })  : _favoritesStore = favoritesStore,
        _updateStore = updateStore,
        _categoryStore = categoryStore,
        _libraryUpdateService = libraryUpdateService,
        _repository = repository,
        _historyStore = historyStore,
        _downloadManager = downloadManager,
        super(const HomeState());

  Future<void> loadFavorites() async {
    emit(state.copyWith(status: HomeStatus.loading));
    final favorites = await _favoritesStore.getAll();
    final updatedKeys = await _updateStore.getAllUpdated();
    final categories = await _categoryStore.getAll();
    final categoryMap = await _favoritesStore.getCategoryMap();
    // Drop a selected category id that no longer exists (e.g. deleted).
    var selectedId = state.selectedCategoryId;
    if (selectedId != null &&
        selectedId != kAllCategoryId &&
        selectedId != kUncategorizedId &&
        !categories.any((c) => c.id == selectedId)) {
      selectedId = kAllCategoryId;
    }
    emit(state.copyWith(
      status: HomeStatus.loaded,
      favorites: favorites,
      updatedKeys: updatedKeys,
      categories: categories,
      selectedCategoryId: selectedId ?? kAllCategoryId,
      categoryMap: categoryMap,
    ));
  }

  // ─── Categories ───────────────────────────────────────────────────────

  void selectCategory(String categoryId) {
    emit(state.copyWith(selectedCategoryId: categoryId));
  }

  Future<void> addCategory(String name) async {
    await _categoryStore.add(name);
    final categories = await _categoryStore.getAll();
    emit(state.copyWith(categories: categories));
  }

  Future<void> renameCategory(String id, String name) async {
    await _categoryStore.rename(id, name);
    final categories = await _categoryStore.getAll();
    emit(state.copyWith(categories: categories));
  }

  Future<void> removeCategory(String id) async {
    await _categoryStore.remove(id);
    final categories = await _categoryStore.getAll();
    var selectedId = state.selectedCategoryId;
    if (selectedId == id) selectedId = kAllCategoryId;
    emit(state.copyWith(
      categories: categories,
      selectedCategoryId: selectedId,
    ));
  }

  /// Set category membership for all currently selected manga, then exit
  /// selection mode and reload.
  Future<void> setCategoriesForSelected(List<String> categoryIds) async {
    for (final key in state.selectedKeys) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        final sourceId = parts[0];
        final mangaId = parts.sublist(1).join('_');
        await _favoritesStore.setCategoryIds(sourceId, mangaId, categoryIds);
      }
    }
    emit(state.copyWith(isSelecting: false, selectedKeys: {}));
    await loadFavorites();
  }

  /// Check all favorites for new chapters.
  ///
  /// Delegates to the shared [LibraryUpdateService] singleton (same one used
  /// by the auto-scan on app start and the Updates tab's pull-to-refresh) so
  /// there is a single source of truth for "latest chapter" comparisons.
  /// Previously this method had its own duplicate scan logic that wrote the
  /// favorite's cached `latestChapter` *before* the real service ran, which
  /// made the real service think nothing had changed and silently swallowed
  /// the new-chapter record (see bug: chapter 104->105 not showing up in the
  /// Updates tab after using this button).
  Future<void> batchUpdate() async {
    if (state.favorites.isEmpty) return;
    if (_libraryUpdateService.isRunning) return;

    emit(state.copyWith(
      status: HomeStatus.updating,
      updateProgress: 0,
      updateTotal: state.favorites.length,
    ));

    void onProgress() {
      if (isClosed) return;
      emit(state.copyWith(
        updateProgress: _libraryUpdateService.progress,
        updateTotal: _libraryUpdateService.total,
      ));
    }

    _libraryUpdateService.addListener(onProgress);
    try {
      await _libraryUpdateService.runUpdate();
    } finally {
      _libraryUpdateService.removeListener(onProgress);
    }

    final updatedKeys = await _updateStore.getAllUpdated();
    emit(state.copyWith(
      status: HomeStatus.loaded,
      updatedKeys: updatedKeys,
    ));
  }

  /// Clear update badge for one manga.
  Future<void> clearUpdate(String sourceId, String mangaId) async {
    await _updateStore.clearUpdate(sourceId, mangaId);
    final updatedKeys = await _updateStore.getAllUpdated();
    emit(state.copyWith(updatedKeys: updatedKeys));
  }

  // ─── Selection Mode ───────────────────────────────────────────────────

  void enterSelectionMode(String sourceId, String mangaId) {
    emit(state.copyWith(
      isSelecting: true,
      selectedKeys: {'${sourceId}_$mangaId'},
    ));
  }

  void toggleSelection(String sourceId, String mangaId) {
    final key = '${sourceId}_$mangaId';
    final newSet = Set<String>.from(state.selectedKeys);
    if (newSet.contains(key)) {
      newSet.remove(key);
    } else {
      newSet.add(key);
    }
    if (newSet.isEmpty) {
      emit(state.copyWith(isSelecting: false, selectedKeys: {}));
    } else {
      emit(state.copyWith(selectedKeys: newSet));
    }
  }

  void selectAll() {
    final allKeys =
        state.filteredFavorites.map((m) => '${m.sourceId}_${m.id}').toSet();
    emit(state.copyWith(selectedKeys: allKeys));
  }

  void exitSelectionMode() {
    emit(state.copyWith(isSelecting: false, selectedKeys: {}));
  }

  Future<void> deleteSelected() async {
    for (final key in state.selectedKeys) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        final sourceId = parts[0];
        final mangaId = parts.sublist(1).join('_');
        await _favoritesStore.remove(sourceId, mangaId);
      }
    }
    emit(state.copyWith(isSelecting: false, selectedKeys: {}));
    await loadFavorites();
  }

  // ─── Downloads ────────────────────────────────────────────────────────

  /// Download every chapter of [manga] that has not been read yet.
  ///
  /// Fetches the *entire* chapter list first — paginating through every page
  /// the source reports via [ChapterListResult.canLoadMore] (mirroring
  /// `DetailCubit.loadChapters`'s loop) — before diffing against the read
  /// set, so paginated sources (e.g. MangaDex) don't silently lose chapters
  /// that only live on page 2+.
  ///
  /// Never throws: any failure fetching the chapter list or read history is
  /// caught and treated as "nothing to queue" for this manga, so a single
  /// manga's failure doesn't take down a batch download (see
  /// [downloadSelected]).
  ///
  /// Returns the number of chapters actually queued for download (0 if none
  /// were unread, or if an error occurred).
  Future<int> downloadUnread(MangaSummary manga) async {
    try {
      var page = 1;
      var result =
          await _repository.getChapterList(manga.sourceId, manga.id, page);
      var allChapters = result.chapters;
      var canLoadMore = result.canLoadMore;
      const maxPages = 200; // safety cap to avoid infinite loops
      while (canLoadMore && page < maxPages) {
        page++;
        result =
            await _repository.getChapterList(manga.sourceId, manga.id, page);
        allChapters = [...allChapters, ...result.chapters];
        canLoadMore = result.canLoadMore;
      }

      final readSet =
          await _historyStore.getReadChapters(manga.sourceId, manga.id);
      final unread = allChapters.where((c) => !readSet.contains(c.id));
      var queued = 0;
      for (final chapter in unread) {
        await _downloadManager.addTask(
          sourceId: manga.sourceId,
          mangaId: manga.id,
          chapterId: chapter.id,
          mangaTitle: manga.title,
          chapterTitle: chapter.title,
        );
        queued++;
      }
      return queued;
    } catch (e) {
      return 0;
    }
  }

  /// Download unread chapters for every currently selected manga.
  ///
  /// [downloadUnread] never throws, so one manga's failure never aborts the
  /// rest of the batch.
  Future<void> downloadSelected() async {
    for (final key in state.selectedKeys) {
      final parts = key.split('_');
      if (parts.length < 2) continue;
      final sourceId = parts.first;
      final mangaId = parts.sublist(1).join('_');
      final manga = state.favorites.firstWhereOrNull(
        (m) => m.sourceId == sourceId && m.id == mangaId,
      );
      if (manga != null) {
        await downloadUnread(manga);
      }
    }
  }
}
