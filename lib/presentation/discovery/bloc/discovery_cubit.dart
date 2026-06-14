import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'discovery_state.dart';

class DiscoveryCubit extends Cubit<DiscoveryState> {
  final MangaRepository _repository;
  final SourceRegistry _registry;

  DiscoveryCubit({
    required MangaRepository repository,
    required SourceRegistry registry,
  })  : _repository = repository,
        _registry = registry,
        super(const DiscoveryState());

  void init() {
    final source = _registry.defaultSource;
    if (source == null) return;
    emit(state.copyWith(
      sourceId: source.id,
      filterOptions: source.discoveryFilters,
      filters: {for (final f in source.discoveryFilters) f.name: f.defaultValue},
    ));
    loadDiscovery();
  }

  void changeSource(String sourceId) {
    final source = _registry.get(sourceId);
    if (source == null) return;
    emit(state.copyWith(
      sourceId: sourceId,
      filterOptions: source.discoveryFilters,
      filters: {for (final f in source.discoveryFilters) f.name: f.defaultValue},
      manga: [],
      currentPage: 1,
      hasMore: true,
    ));
    loadDiscovery();
  }

  void changeFilter(String name, String value) {
    final newFilters = Map<String, String>.from(state.filters);
    newFilters[name] = value;
    emit(state.copyWith(
      filters: newFilters,
      manga: [],
      currentPage: 1,
      hasMore: true,
    ));
    loadDiscovery();
  }

  Future<void> loadDiscovery() async {
    if (state.sourceId.isEmpty) return;
    emit(state.copyWith(status: DiscoveryStatus.loading));
    try {
      final results = await _repository.getDiscovery(state.sourceId, 1, state.filters);
      emit(state.copyWith(
        status: DiscoveryStatus.loaded,
        manga: results,
        currentPage: 1,
        hasMore: results.isNotEmpty,
        errorMessage: null,
      ));
    } catch (e) {
      emit(state.copyWith(status: DiscoveryStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> loadMore() async {
    if (state.status == DiscoveryStatus.loadingMore || !state.hasMore) return;
    emit(state.copyWith(status: DiscoveryStatus.loadingMore));
    try {
      final nextPage = state.currentPage + 1;
      final results = await _repository.getDiscovery(state.sourceId, nextPage, state.filters);
      emit(state.copyWith(
        status: DiscoveryStatus.loaded,
        manga: [...state.manga, ...results],
        currentPage: nextPage,
        hasMore: results.isNotEmpty,
      ));
    } catch (e) {
      emit(state.copyWith(status: DiscoveryStatus.loaded));
    }
  }

  Future<void> refresh() async {
    emit(state.copyWith(manga: [], currentPage: 1, hasMore: true));
    await loadDiscovery();
  }
}
