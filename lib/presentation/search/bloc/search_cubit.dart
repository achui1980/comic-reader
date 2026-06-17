import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  final MangaRepository _repository;
  final SourceRegistry _registry;

  SearchCubit({
    required MangaRepository repository,
    required SourceRegistry registry,
  })  : _repository = repository,
        _registry = registry,
        super(const SearchState());

  void init() {
    final source = _registry.defaultSource;
    if (source != null) {
      emit(state.copyWith(sourceId: source.id));
    }
  }

  Future<void> search(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final source = _registry.get(state.sourceId);
    final firstPage = source?.firstPage ?? 1;
    emit(state.copyWith(
      status: SearchStatus.loading,
      keyword: keyword.trim(),
      results: [],
      currentPage: firstPage,
      hasMore: true,
    ));
    try {
      final results = await _repository.searchManga(state.sourceId, keyword.trim(), firstPage, {});
      emit(state.copyWith(
        status: SearchStatus.loaded,
        results: results,
        hasMore: results.isNotEmpty,
      ));
    } catch (e) {
      emit(state.copyWith(status: SearchStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> loadMore() async {
    if (state.status == SearchStatus.loadingMore || !state.hasMore || state.keyword.isEmpty) return;
    emit(state.copyWith(status: SearchStatus.loadingMore));
    try {
      final nextPage = state.currentPage + 1;
      final results = await _repository.searchManga(state.sourceId, state.keyword, nextPage, {});

      // Detect duplicate content (server returning same page)
      final existingIds = state.results.map((m) => m.id).toSet();
      final newResults = results.where((m) => !existingIds.contains(m.id)).toList();

      if (results.isNotEmpty && newResults.isEmpty) {
        emit(state.copyWith(
          status: SearchStatus.loaded,
          hasMore: false,
        ));
        return;
      }

      emit(state.copyWith(
        status: SearchStatus.loaded,
        results: [...state.results, ...newResults],
        currentPage: nextPage,
        hasMore: newResults.isNotEmpty,
      ));
    } catch (e) {
      emit(state.copyWith(status: SearchStatus.loaded));
    }
  }
}
