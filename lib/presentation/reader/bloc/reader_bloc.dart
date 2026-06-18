import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/settings_store.dart' as settings;
import 'reader_event.dart';
import 'reader_state.dart';

final _log = Logger('ReaderBloc');

class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  final MangaRepository _repository;
  final ReadingHistoryStore _historyStore;
  final settings.SettingsStore _settingsStore;
  Timer? _autoPageTimer;

  ReaderBloc({
    required MangaRepository repository,
    required ReadingHistoryStore readingHistoryStore,
    required settings.SettingsStore settingsStore,
  })  : _repository = repository,
        _historyStore = readingHistoryStore,
        _settingsStore = settingsStore,
        super(const ReaderState()) {
    on<LoadChapter>(_onLoadChapter);
    on<PageChanged>(_onPageChanged);
    on<ToggleControls>(_onToggleControls);
    on<HideControls>(_onHideControls);
    on<ChangeLayoutMode>(_onChangeLayoutMode);
    on<ChangeDirection>(_onChangeDirection);
    on<LoadNextChapter>(_onLoadNextChapter);
    on<LoadPreviousChapter>(_onLoadPreviousChapter);
    on<AppendNextChapter>(_onAppendNextChapter);
    on<SeekToPage>(_onSeekToPage);
    on<StartAutoPageTurn>(_onStartAutoPageTurn);
    on<StopAutoPageTurn>(_onStopAutoPageTurn);
    on<AutoPageTick>(_onAutoPageTick);
    on<RefreshChapter>(_onRefreshChapter);
    _applySettings();
  }

  void _applySettings() async {
    final s = await _settingsStore.load();
    final layoutMode = s.layoutMode == settings.LayoutMode.vertical
        ? LayoutMode.vertical
        : LayoutMode.horizontal;
    final direction = s.readingDirection == settings.ReadingDirection.rtl
        ? ReadingDirection.rtl
        : ReadingDirection.ltr;
    // ignore: invalid_use_of_visible_for_testing_member
    emit(state.copyWith(layoutMode: layoutMode, direction: direction));

    if (s.autoPageTurn) {
      add(StartAutoPageTurn(intervalSeconds: s.autoPageTurnInterval));
    }
  }

  void _onStartAutoPageTurn(StartAutoPageTurn event, Emitter<ReaderState> emit) {
    _autoPageTimer?.cancel();
    _autoPageTimer = Timer.periodic(
      Duration(seconds: event.intervalSeconds),
      (_) => add(const AutoPageTick()),
    );
  }

  void _onStopAutoPageTurn(StopAutoPageTurn event, Emitter<ReaderState> emit) {
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
  }

  void _onAutoPageTick(AutoPageTick event, Emitter<ReaderState> emit) {
    if (state.status == ReaderStatus.loaded && state.currentPage < state.totalPages - 1) {
      final nextPage = state.currentPage + 1;
      emit(state.copyWith(currentPage: nextPage, seekPage: nextPage));
      _historyStore.saveProgress(state.sourceId, state.mangaId, state.chapterId, nextPage);
    } else {
      _autoPageTimer?.cancel();
      _autoPageTimer = null;
    }
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

      final initialBoundary = ChapterBoundary(
        startIndex: 0,
        chapterId: event.chapterId,
        chapterTitle: result.chapter.title,
      );

      emit(state.copyWith(
        status: ReaderStatus.loaded,
        images: result.chapter.images,
        currentPage: event.initialPage,
        totalPages: result.chapter.images.length,
        chapterTitle: result.chapter.title,
        chapterId: event.chapterId,
        currentChapterIndex: chapterIndex,
        lastLoadedChapterIndex: chapterIndex,
        errorMessage: null,
        chapterBoundaries: [initialBoundary],
        isAppendingNext: false,
      ));
      debugPrint('[ReaderBloc] Loaded ${result.chapter.images.length} images');
      if (result.chapter.images.isNotEmpty) {
        debugPrint('[ReaderBloc] First image URL: ${result.chapter.images.first.url}');
      }
      _historyStore.markChapterRead(event.sourceId, event.mangaId, event.chapterId);
    } catch (e, stack) {
      debugPrint('[ReaderBloc] ERROR loading chapter: $e');
      debugPrint('[ReaderBloc] Stack: ${stack.toString().split('\n').take(5).join('\n')}');
      emit(state.copyWith(
        status: ReaderStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onPageChanged(PageChanged event, Emitter<ReaderState> emit) {
    // Find which chapter this page belongs to based on boundaries
    String chapterId = state.chapterId;
    String? chapterTitle = state.chapterTitle;
    int chapterIndex = state.currentChapterIndex;
    int pageInChapter = event.page;

    for (int i = state.chapterBoundaries.length - 1; i >= 0; i--) {
      if (event.page >= state.chapterBoundaries[i].startIndex) {
        chapterId = state.chapterBoundaries[i].chapterId;
        chapterTitle = state.chapterBoundaries[i].chapterTitle;
        pageInChapter = event.page - state.chapterBoundaries[i].startIndex;
        // Resolve chapter index from boundary's chapterId
        final idx = state.chapterList.indexWhere((c) => c.id == chapterId);
        if (idx >= 0) chapterIndex = idx;
        break;
      }
    }

    emit(state.copyWith(
      currentPage: event.page,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      currentChapterIndex: chapterIndex,
    ));

    // Save reading progress
    if (state.sourceId.isNotEmpty && state.mangaId.isNotEmpty) {
      _historyStore.saveProgress(
        state.sourceId, state.mangaId, chapterId, pageInChapter,
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

  Future<void> _onAppendNextChapter(
      AppendNextChapter event, Emitter<ReaderState> emit) async {
    if (!state.canAppendNext || state.isAppendingNext) return;

    emit(state.copyWith(isAppendingNext: true));

    final nextIndex = state.lastLoadedChapterIndex + 1;
    final nextChapter = state.chapterList[nextIndex];

    try {
      final result = await _repository.getChapter(
        state.sourceId,
        state.mangaId,
        nextChapter.id,
        1,
      );

      final newImages = [...state.images, ...result.chapter.images];
      final newBoundary = ChapterBoundary(
        startIndex: state.images.length,
        chapterId: nextChapter.id,
        chapterTitle: result.chapter.title,
      );
      final newBoundaries = [...state.chapterBoundaries, newBoundary];

      emit(state.copyWith(
        images: newImages,
        totalPages: newImages.length,
        lastLoadedChapterIndex: nextIndex,
        chapterBoundaries: newBoundaries,
        isAppendingNext: false,
      ));
    } catch (e, stack) {
      _log.warning('Failed to append next chapter: $e', e, stack);
      emit(state.copyWith(isAppendingNext: false));
    }
  }

  Future<void> _onRefreshChapter(
      RefreshChapter event, Emitter<ReaderState> emit) async {
    if (state.sourceId.isEmpty || state.mangaId.isEmpty || state.chapterId.isEmpty) return;

    try {
      final result = await _repository.getChapter(
        state.sourceId,
        state.mangaId,
        state.chapterId,
        1,
      );

      final initialBoundary = ChapterBoundary(
        startIndex: 0,
        chapterId: state.chapterId,
        chapterTitle: result.chapter.title,
      );

      emit(state.copyWith(
        images: result.chapter.images,
        totalPages: result.chapter.images.length,
        currentPage: 0,
        chapterBoundaries: [initialBoundary],
        lastLoadedChapterIndex: state.currentChapterIndex,
        isAppendingNext: false,
      ));
    } catch (e) {
      // Silently fail - keep current images on screen
      _log.warning('Failed to refresh chapter: $e');
    }
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

  @override
  Future<void> close() {
    _autoPageTimer?.cancel();
    return super.close();
  }
}
