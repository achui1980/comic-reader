import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/data/local/category_store.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final FavoritesStore _favoritesStore;
  final UpdateStore _updateStore;
  final CategoryStore _categoryStore;
  final MangaRepository _repository;

  HomeCubit({
    required FavoritesStore favoritesStore,
    required UpdateStore updateStore,
    required CategoryStore categoryStore,
    required MangaRepository repository,
  })  : _favoritesStore = favoritesStore,
        _updateStore = updateStore,
        _categoryStore = categoryStore,
        _repository = repository,
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
  Future<void> batchUpdate() async {
    if (state.favorites.isEmpty) return;

    emit(state.copyWith(
      status: HomeStatus.updating,
      updateProgress: 0,
      updateTotal: state.favorites.length,
    ));

    for (int i = 0; i < state.favorites.length; i++) {
      final manga = state.favorites[i];
      emit(state.copyWith(updateProgress: i));

      try {
        final detail = await _repository.getMangaInfo(manga.sourceId, manga.id);
        // Compare latest chapter from API with stored value
        if (detail.latestChapter != null &&
            detail.latestChapter != manga.latestChapter &&
            detail.latestChapter!.isNotEmpty) {
          await _updateStore.markUpdated(manga.sourceId, manga.id);
          await _favoritesStore.updateLatestChapter(manga.sourceId, manga.id, detail.latestChapter!);
        }
      } catch (_) {
        // Skip failed items silently
      }
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
}
