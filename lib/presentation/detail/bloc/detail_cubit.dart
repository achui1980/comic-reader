import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'detail_state.dart';

class DetailCubit extends Cubit<DetailState> {
  final MangaRepository _repository;
  final String sourceId;
  final String mangaId;

  DetailCubit({
    required MangaRepository repository,
    required this.sourceId,
    required this.mangaId,
  })  : _repository = repository,
        super(const DetailState());

  Future<void> loadDetail() async {
    emit(state.copyWith(status: DetailStatus.loading));
    try {
      final manga = await _repository.getMangaInfo(sourceId, mangaId);
      emit(state.copyWith(status: DetailStatus.loaded, manga: manga));
      await loadChapters();
    } catch (e) {
      emit(state.copyWith(status: DetailStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> loadChapters() async {
    emit(state.copyWith(chaptersLoading: true));
    try {
      final result = await _repository.getChapterList(sourceId, mangaId, 1);
      emit(state.copyWith(
        chapters: result.chapters,
        chaptersLoading: false,
        canLoadMoreChapters: result.canLoadMore,
        chapterPage: 1,
      ));
    } catch (e) {
      emit(state.copyWith(chaptersLoading: false));
    }
  }

  Future<void> loadMoreChapters() async {
    if (state.chaptersLoading || !state.canLoadMoreChapters) return;
    emit(state.copyWith(chaptersLoading: true));
    try {
      final nextPage = state.chapterPage + 1;
      final result = await _repository.getChapterList(sourceId, mangaId, nextPage);
      emit(state.copyWith(
        chapters: [...state.chapters, ...result.chapters],
        chaptersLoading: false,
        canLoadMoreChapters: result.canLoadMore,
        chapterPage: nextPage,
      ));
    } catch (e) {
      emit(state.copyWith(chaptersLoading: false));
    }
  }

  void toggleSortOrder() {
    emit(state.copyWith(chaptersReversed: !state.chaptersReversed));
  }

  void toggleFavorite() {
    emit(state.copyWith(isFavorite: !state.isFavorite));
    // TODO: persist favorite to local storage
  }
}
