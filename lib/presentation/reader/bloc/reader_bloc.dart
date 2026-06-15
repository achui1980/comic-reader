import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'reader_event.dart';
import 'reader_state.dart';

class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  final MangaRepository _repository;
  final ReadingHistoryStore _historyStore;

  ReaderBloc({
    required MangaRepository repository,
    required ReadingHistoryStore readingHistoryStore,
  })  : _repository = repository,
        _historyStore = readingHistoryStore,
        super(const ReaderState()) {
    on<LoadChapter>(_onLoadChapter);
    on<PageChanged>(_onPageChanged);
    on<ToggleControls>(_onToggleControls);
    on<HideControls>(_onHideControls);
    on<ChangeLayoutMode>(_onChangeLayoutMode);
    on<ChangeDirection>(_onChangeDirection);
    on<LoadNextChapter>(_onLoadNextChapter);
    on<LoadPreviousChapter>(_onLoadPreviousChapter);
    on<SeekToPage>(_onSeekToPage);
  }

  Future<void> _onLoadChapter(
      LoadChapter event, Emitter<ReaderState> emit) async {
    emit(state.copyWith(
      status: ReaderStatus.loading,
      sourceId: event.sourceId,
      mangaId: event.mangaId,
      chapterId: event.chapterId,
      chapterList: event.chapterList.isNotEmpty ? event.chapterList : null,
      showControls: false,
    ));

    try {
      final result = await _repository.getChapter(
        event.sourceId,
        event.mangaId,
        event.chapterId,
        1,
      );

      // Find current chapter index in the list
      int chapterIndex = -1;
      if (state.chapterList.isNotEmpty) {
        chapterIndex =
            state.chapterList.indexWhere((c) => c.id == event.chapterId);
      }

      emit(state.copyWith(
        status: ReaderStatus.loaded,
        images: result.chapter.images,
        currentPage: event.initialPage,
        totalPages: result.chapter.images.length,
        chapterTitle: result.chapter.title,
        chapterId: event.chapterId,
        currentChapterIndex: chapterIndex,
        errorMessage: null,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ReaderStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onPageChanged(PageChanged event, Emitter<ReaderState> emit) {
    emit(state.copyWith(currentPage: event.page));
    // Save reading progress
    if (state.sourceId.isNotEmpty && state.mangaId.isNotEmpty && state.chapterId.isNotEmpty) {
      _historyStore.saveProgress(
        state.sourceId, state.mangaId, state.chapterId, event.page,
      );
    }
  }

  void _onToggleControls(ToggleControls event, Emitter<ReaderState> emit) {
    emit(state.copyWith(showControls: !state.showControls));
  }

  void _onHideControls(HideControls event, Emitter<ReaderState> emit) {
    emit(state.copyWith(showControls: false));
  }

  void _onChangeLayoutMode(
      ChangeLayoutMode event, Emitter<ReaderState> emit) {
    emit(state.copyWith(layoutMode: event.mode));
  }

  void _onChangeDirection(
      ChangeDirection event, Emitter<ReaderState> emit) {
    emit(state.copyWith(direction: event.direction));
  }

  Future<void> _onLoadNextChapter(
      LoadNextChapter event, Emitter<ReaderState> emit) async {
    if (!state.hasNextChapter) return;

    final nextIndex = state.currentChapterIndex + 1;
    final nextChapter = state.chapterList[nextIndex];

    add(LoadChapter(
      sourceId: state.sourceId,
      mangaId: state.mangaId,
      chapterId: nextChapter.id,
      initialPage: 0,
    ));
  }

  Future<void> _onLoadPreviousChapter(
      LoadPreviousChapter event, Emitter<ReaderState> emit) async {
    if (!state.hasPreviousChapter) return;

    final prevIndex = state.currentChapterIndex - 1;
    final prevChapter = state.chapterList[prevIndex];

    add(LoadChapter(
      sourceId: state.sourceId,
      mangaId: state.mangaId,
      chapterId: prevChapter.id,
      initialPage: 0,
    ));
  }

  void _onSeekToPage(SeekToPage event, Emitter<ReaderState> emit) {
    emit(state.copyWith(currentPage: event.page, seekPage: event.page));
    // Save progress
    if (state.sourceId.isNotEmpty && state.mangaId.isNotEmpty && state.chapterId.isNotEmpty) {
      _historyStore.saveProgress(
        state.sourceId, state.mangaId, state.chapterId, event.page,
      );
    }
  }
}
