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
    emit(state.copyWith(
      status: SearchStatus.loading,
      keyword: keyword.trim(),
      results: [],
      currentPage: 1,
      hasMore: true,
    ));
    try {
      final results = await _repository.searchManga(state.sourceId, keyword.trim(), 1, {});
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
      emit(state.copyWith(
        status: SearchStatus.loaded,
        results: [...state.results, ...results],
        currentPage: nextPage,
        hasMore: results.isNotEmpty,
      ));
    } catch (e) {
      emit(state.copyWith(status: SearchStatus.loaded));
    }
  }
}
