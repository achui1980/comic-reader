import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum HomeStatus { initial, loading, loaded, updating }

class HomeState extends Equatable {
  final HomeStatus status;
  final List<MangaSummary> favorites;
  final Set<String> updatedKeys; // "${sourceId}_${mangaId}" keys
  final int updateProgress; // 0-based index of current batch item
  final int updateTotal; // total items to check
  final String? errorMessage;
  final bool isSelecting;
  final Set<String> selectedKeys; // "${sourceId}_${mangaId}" format

  const HomeState({
    this.status = HomeStatus.initial,
    this.favorites = const [],
    this.updatedKeys = const {},
    this.updateProgress = 0,
    this.updateTotal = 0,
    this.errorMessage,
    this.isSelecting = false,
    this.selectedKeys = const {},
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
    );
  }

  bool hasUpdate(String sourceId, String mangaId) =>
      updatedKeys.contains('${sourceId}_$mangaId');

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
      ];
}
