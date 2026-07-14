import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/data/local/category_store.dart';

enum HomeStatus { initial, loading, loaded, updating }

/// Sentinel [selectedCategoryId] values for the virtual tabs.
const String kAllCategoryId = '__all__';
const String kUncategorizedId = '__uncategorized__';

class HomeState extends Equatable {
  final HomeStatus status;
  final List<MangaSummary> favorites;
  final Set<String> updatedKeys; // "${sourceId}_${mangaId}" keys
  final int updateProgress; // 0-based index of current batch item
  final int updateTotal; // total items to check
  final String? errorMessage;
  final bool isSelecting;
  final Set<String> selectedKeys; // "${sourceId}_${mangaId}" format
  final List<Category> categories;
  // null / kAllCategoryId => show all; kUncategorizedId => no/empty ids;
  // otherwise a real Category.id.
  final String? selectedCategoryId;
  final Map<String, List<String>> categoryMap; // mangaKey -> category ids

  const HomeState({
    this.status = HomeStatus.initial,
    this.favorites = const [],
    this.updatedKeys = const {},
    this.updateProgress = 0,
    this.updateTotal = 0,
    this.errorMessage,
    this.isSelecting = false,
    this.selectedKeys = const {},
    this.categories = const [],
    this.selectedCategoryId,
    this.categoryMap = const {},
  });

  HomeState copyWith({
    HomeStatus? status,
    List<MangaSummary>? favorites,
    Set<String>? updatedKeys,
    int? updateProgress,
    int? updateTotal,
    String? errorMessage,
    bool? isSelecting,
    Set<String>? selectedKeys,
    List<Category>? categories,
    String? selectedCategoryId,
    Map<String, List<String>>? categoryMap,
  }) {
    return HomeState(
      status: status ?? this.status,
      favorites: favorites ?? this.favorites,
      updatedKeys: updatedKeys ?? this.updatedKeys,
      updateProgress: updateProgress ?? this.updateProgress,
      updateTotal: updateTotal ?? this.updateTotal,
      errorMessage: errorMessage ?? this.errorMessage,
      isSelecting: isSelecting ?? this.isSelecting,
      selectedKeys: selectedKeys ?? this.selectedKeys,
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      categoryMap: categoryMap ?? this.categoryMap,
    );
  }

  bool hasUpdate(String sourceId, String mangaId) =>
      updatedKeys.contains('${sourceId}_$mangaId');

  /// Favorites filtered by the currently selected category tab.
  List<MangaSummary> get filteredFavorites {
    final id = selectedCategoryId;
    if (id == null || id == kAllCategoryId) return favorites;
    if (id == kUncategorizedId) {
      return favorites.where((m) {
        final ids = categoryMap['${m.sourceId}_${m.id}'];
        return ids == null || ids.isEmpty;
      }).toList();
    }
    return favorites.where((m) {
      final ids = categoryMap['${m.sourceId}_${m.id}'];
      return ids != null && ids.contains(id);
    }).toList();
  }

  @override
  List<Object?> get props => [
        status,
        favorites,
        updatedKeys,
        updateProgress,
        updateTotal,
        errorMessage,
        isSelecting,
        selectedKeys,
        categories,
        selectedCategoryId,
        categoryMap,
      ];
}
