import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/settings_store.dart' as settings;
import 'dart:collection' show Queue;
import 'dart:ui' show Size;

import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:comic_reader/data/translation/translation_pipeline.dart';
import '../widgets/manga_image_loader.dart';
import 'reader_event.dart';
import 'reader_state.dart';

final _log = Logger('ReaderBloc');

class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  final MangaRepository _repository;
  final ReadingHistoryStore _historyStore;
  final settings.SettingsStore _settingsStore;
  Timer? _autoPageTimer;
  StreamSubscription<ChapterResult>? _chapterStreamSubscription;

  /// Chapter ids that have already had a background prefetch triggered, so
  /// we don't kick off redundant `getChapter` calls every time the user
  /// nears the end of the same chapter.
  final Set<String> _prefetchedChapterIds = {};

  final TranslationPipeline _translationPipeline;

  /// Injectable for testing; defaults to the real network+cache loader.
  final Future<Uint8List> Function({
    required ChapterImage image,
    String? sourceId,
    String? mangaId,
    String? chapterId,
    int? imageIndex,
  }) _loadImageBytes;

  /// Page index currently being translated, or null if the queue is idle.
  int? _translatingPage;
  final Queue<int> _translationQueue = Queue<int>();

  /// Bumped every time a new chapter's content starts loading. Captured by
  /// [_drainTranslationQueue] before it awaits anything, and checked by
  /// [_updatePageStatus] before writing a result into `state.pageTranslations`
  /// — this discards translation results that resolve after the user has
  /// already navigated away from the chapter that kicked them off, instead
  /// of writing a stale (wrong-chapter) result into the current state.
  int _translationEpoch = 0;

  ReaderBloc({
    required MangaRepository repository,
    required ReadingHistoryStore readingHistoryStore,
    required settings.SettingsStore settingsStore,
    TranslationPipeline? translationPipeline,
    Future<Uint8List> Function({
      required ChapterImage image,
      String? sourceId,
      String? mangaId,
      String? chapterId,
      int? imageIndex,
    }) loadImageBytes = loadAndCacheImageBytes,
  })  : _repository = repository,
        _historyStore = readingHistoryStore,
        _settingsStore = settingsStore,
        _translationPipeline =
            translationPipeline ?? GetIt.instance<TranslationPipeline>(),
        _loadImageBytes = loadImageBytes,
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
    on<PrefetchNextChapter>(_onPrefetchNextChapter);
    on<SeekToPage>(_onSeekToPage);
    on<StartAutoPageTurn>(_onStartAutoPageTurn);
    on<StopAutoPageTurn>(_onStopAutoPageTurn);
    on<AutoPageTick>(_onAutoPageTick);
    on<RefreshChapter>(_onRefreshChapter);
    on<ImagesUpdated>(_onImagesUpdated);
    on<TranslateChapterToggled>(_onTranslateChapterToggled);
    on<TranslatePageRequested>(_onTranslatePageRequested);
    on<TranslatePageRetried>(_onTranslatePageRetried);
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
    emit(state.copyWith(
      layoutMode: layoutMode,
      direction: direction,
      cropBorders: s.cropBorders,
      scaleType: s.scaleType,
      splitWidePages: s.splitWidePages,
      showPageNumber: s.showPageNumber,
      tapZonesInvert: s.tapZonesInvert,
      showTapZones: s.showTapZones,
      translationFeatureEnabled: s.mangaTranslationEnabled,
    ));

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
    // Cancel any existing stream subscription
    await _chapterStreamSubscription?.cancel();
    _chapterStreamSubscription = null;

    // A new chapter load is starting (this is the single entry point for
    // LoadChapter/RefreshChapter/LoadNextChapter/LoadPreviousChapter, which
    // all funnel through `add(LoadChapter(...))`): anything queued/in-flight
    // for the previous chapter is now stale, and translation state must
    // never carry over across chapters (see _drainTranslationQueue /
    // _updatePageStatus for how the epoch bump is enforced on the async
    // side).
    _translationEpoch++;
    _translationQueue.clear();
    _translatingPage = null;

    emit(state.copyWith(
      status: ReaderStatus.loading,
      sourceId: event.sourceId,
      mangaId: event.mangaId,
      chapterId: event.chapterId,
      mangaTitle: event.mangaTitle.isNotEmpty ? event.mangaTitle : state.mangaTitle,
      coverUrl: event.coverUrl.isNotEmpty ? event.coverUrl : state.coverUrl,
      chapterList: event.chapterList.isNotEmpty ? event.chapterList : null,
      showControls: false,
      isProgressiveLoading: false,
      currentPage: event.initialPage,
      translationEnabled: false,
      pageTranslations: const {},
    ));

    try {
      final stream = _repository.getChapterStream(
        event.sourceId,
        event.mangaId,
        event.chapterId,
        1,
      );

      _chapterStreamSubscription = stream.listen(
        (result) {
          add(ImagesUpdated(
            images: result.chapter.images,
            isComplete: false,
            chapterTitle: result.chapter.title,
          ));
        },
        onDone: () {
          add(const ImagesUpdated(images: [], isComplete: true));
        },
        onError: (e, stack) {
          debugPrint('[ReaderBloc] Stream error: $e');
          debugPrint('[ReaderBloc] Stack: ${stack.toString().split('\n').take(5).join('\n')}');
          add(ImagesUpdated(
            images: const [],
            isComplete: true,
            errorMessage: _cleanErrorMessage(e),
          ));
        },
      );
    } catch (e, stack) {
      debugPrint('[ReaderBloc] ERROR loading chapter: $e');
      debugPrint('[ReaderBloc] Stack: ${stack.toString().split('\n').take(5).join('\n')}');
      emit(state.copyWith(
        status: ReaderStatus.error,
        errorMessage: _cleanErrorMessage(e),
      ));
    }
  }

  /// Strips the noisy "Exception: " prefix that Dart's Exception.toString()
  /// prepends, so user-facing error messages read cleanly.
  String _cleanErrorMessage(Object e) {
    var msg = e.toString();
    const prefix = 'Exception: ';
    if (msg.startsWith(prefix)) {
      msg = msg.substring(prefix.length);
    }
    return msg;
  }

  void _onImagesUpdated(ImagesUpdated event, Emitter<ReaderState> emit) {
    if (event.isComplete && event.images.isEmpty) {
      if (state.status == ReaderStatus.loading) {
        emit(state.copyWith(
          status: ReaderStatus.error,
          errorMessage: event.errorMessage ?? '未能加载章节内容',
          isProgressiveLoading: false,
        ));
        return;
      }

      // Stream completed - mark progressive loading as done
      emit(state.copyWith(isProgressiveLoading: false));
      _historyStore.markChapterRead(state.sourceId, state.mangaId, state.chapterId);
      _historyStore.addHistory(HistoryEntry(
        sourceId: state.sourceId,
        mangaId: state.mangaId,
        mangaTitle: state.mangaTitle,
        coverUrl: state.coverUrl,
        chapterId: state.chapterId,
        chapterTitle: state.chapterTitle ?? '',
        page: state.currentPage,
        timestamp: DateTime.now().toIso8601String(),
      ));
      return;
    }

    if (state.status == ReaderStatus.loading) {
      // First batch arrived - transition to loaded
      int chapterIndex = -1;
      if (state.chapterList.isNotEmpty) {
        chapterIndex = state.chapterList.indexWhere((c) => c.id == state.chapterId);
      }
      final initialBoundary = ChapterBoundary(
        startIndex: 0,
        chapterId: state.chapterId,
        chapterTitle: event.chapterTitle ?? '',
      );
      emit(state.copyWith(
        status: ReaderStatus.loaded,
        images: event.images,
        currentPage: state.currentPage,
        totalPages: event.images.length,
        chapterTitle: event.chapterTitle ?? state.chapterTitle,
        currentChapterIndex: chapterIndex,
        lastLoadedChapterIndex: chapterIndex,
        errorMessage: null,
        chapterBoundaries: [initialBoundary],
        isAppendingNext: false,
        isProgressiveLoading: true,
      ));
      debugPrint('[ReaderBloc] First batch: ${event.images.length} images (progressive)');
    } else {
      // Subsequent batches - update images list
      emit(state.copyWith(
        images: event.images,
        totalPages: event.images.length,
        isProgressiveLoading: true,
      ));
      debugPrint('[ReaderBloc] Updated: ${event.images.where((img) => img.url.isNotEmpty).length}/${event.images.length} resolved');
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

    // Kick off a background prefetch of the next chapter's images once the
    // reader is near the end of the currently loaded images, so they're
    // already cached by the time the user actually gets there.
    if (state.images.isNotEmpty &&
        event.page >= state.images.length - 2 &&
        state.canAppendNext) {
      add(const PrefetchNextChapter());
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

  /// Silently downloads the next chapter's images into [ChapterCacheService]
  /// (via [loadAndCacheImageBytes]) without touching `state.images` — unlike
  /// [_onAppendNextChapter], this does not change what's currently
  /// displayed. Guarded by [_prefetchedChapterIds] so the same chapter is
  /// only prefetched once per bloc lifetime.
  Future<void> _onPrefetchNextChapter(
      PrefetchNextChapter event, Emitter<ReaderState> emit) async {
    if (!state.canAppendNext) return;

    final nextIndex = state.lastLoadedChapterIndex + 1;
    final nextChapter = state.chapterList[nextIndex];

    if (!_prefetchedChapterIds.add(nextChapter.id)) return;

    try {
      final result = await _repository.getChapter(
        state.sourceId,
        state.mangaId,
        nextChapter.id,
        1,
      );

      for (var i = 0; i < result.chapter.images.length; i++) {
        await loadAndCacheImageBytes(
          image: result.chapter.images[i],
          sourceId: state.sourceId,
          mangaId: state.mangaId,
          chapterId: nextChapter.id,
          imageIndex: i,
        );
      }
    } catch (e, stack) {
      _log.warning('Failed to prefetch next chapter: $e', e, stack);
      // Allow a later PageChanged to retry the prefetch.
      _prefetchedChapterIds.remove(nextChapter.id);
    }
  }

  void _onRefreshChapter(RefreshChapter event, Emitter<ReaderState> emit) {
    if (state.sourceId.isEmpty || state.mangaId.isEmpty || state.chapterId.isEmpty) return;

    add(LoadChapter(
      sourceId: state.sourceId,
      mangaId: state.mangaId,
      chapterId: state.chapterId,
      chapterList: state.chapterList,
      initialPage: state.currentPage,
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

  Future<void> _onTranslateChapterToggled(
      TranslateChapterToggled event, Emitter<ReaderState> emit) async {
    // 总开关关闭时忽略事件（按钮本就不该渲染，这是纵深防御）。
    if (!state.translationFeatureEnabled) return;
    emit(state.copyWith(translationEnabled: event.enabled));
    if (event.enabled) {
      _enqueueTranslate(state.currentPage);
    } else {
      // Drop anything not yet started; let an in-flight translation finish
      // normally (its result still lands via _updatePageStatus).
      _translationQueue.clear();
    }
  }

  Future<void> _onTranslatePageRequested(
      TranslatePageRequested event, Emitter<ReaderState> emit) async {
    if (!state.translationEnabled) return;
    final info =
        state.pageTranslations[event.pageIndex] ?? PageTranslationInfo.idle;
    if (info.status != PageTranslationStatus.idle) return;
    _enqueueTranslate(event.pageIndex);
  }

  Future<void> _onTranslatePageRetried(
      TranslatePageRetried event, Emitter<ReaderState> emit) async {
    // Unconditional: bypasses the idle-only guard so a page stuck in
    // `error` can be retried.
    _enqueueTranslate(event.pageIndex);
  }

  void _enqueueTranslate(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= state.images.length) return;
    if (pageIndex == _translatingPage || _translationQueue.contains(pageIndex)) {
      return;
    }
    _translationQueue.add(pageIndex);
    unawaited(_drainTranslationQueue());
  }

  Future<void> _drainTranslationQueue() async {
    if (_translatingPage != null || _translationQueue.isEmpty) return;
    final pageIndex = _translationQueue.removeFirst();
    _translatingPage = pageIndex;
    // Captured once, before any `await`: if the user navigates to a
    // different chapter while this translation is in flight, `state` will
    // have already moved on to the new chapter's sourceId/mangaId/chapterId
    // by the time we get past the awaits below. Using the captured locals
    // (instead of re-reading `state.xxx`) ensures the pipeline is always
    // called with the ids of the chapter the image actually belongs to.
    final epoch = _translationEpoch;
    final sourceId = state.sourceId;
    final mangaId = state.mangaId;
    final chapterId = state.chapterId;
    _updatePageStatus(
      epoch,
      pageIndex,
      const PageTranslationInfo(status: PageTranslationStatus.loading),
    );
    try {
      final image = state.images[pageIndex];
      final bytes = await _loadImageBytes(
        image: image,
        sourceId: sourceId,
        mangaId: mangaId,
        chapterId: chapterId,
        imageIndex: pageIndex,
      );
      final decoded = img.decodeImage(bytes);
      final imageSize = decoded != null
          ? Size(decoded.width.toDouble(), decoded.height.toDouble())
          : null;
      final result = await _translationPipeline.translatePage(
        sourceId,
        mangaId,
        chapterId,
        pageIndex,
        bytes,
      );
      _updatePageStatus(
        epoch,
        pageIndex,
        PageTranslationInfo(
          status: PageTranslationStatus.done,
          translation: result,
          imageSize: imageSize,
        ),
      );
    } catch (e, stack) {
      _log.warning('Translation failed for page $pageIndex: $e', e, stack);
      _updatePageStatus(
        epoch,
        pageIndex,
        PageTranslationInfo(
          status: PageTranslationStatus.error,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      // Only touch the shared queue state if this task's chapter epoch is
      // still the live one. If the user has navigated to a different
      // chapter while this task was in flight, `_translatingPage` may
      // already legitimately belong to a newer task started for the new
      // chapter — clearing it here (or draining the queue, which is the new
      // chapter's own responsibility) would clobber that state and cause
      // the new chapter's page to be enqueued/translated a second time.
      if (epoch == _translationEpoch) {
        _translatingPage = null;
        unawaited(_drainTranslationQueue());
      }
    }
  }

  /// Emits directly via the bloc-level `emit` (rather than a handler's
  /// scoped [Emitter]) because this is invoked from a detached async chain
  /// ([_drainTranslationQueue] is fire-and-forget, mirroring the existing
  /// [_applySettings] pattern below).
  ///
  /// [epoch] is the `_translationEpoch` value captured by
  /// [_drainTranslationQueue] when this translation was kicked off. If the
  /// user has since navigated to a different chapter, `_translationEpoch`
  /// will have moved on and this result is discarded (not emitted) instead
  /// of being written into the new chapter's `pageTranslations`.
  void _updatePageStatus(int epoch, int pageIndex, PageTranslationInfo info) {
    if (isClosed) return;
    if (epoch != _translationEpoch) return;
    // ignore: invalid_use_of_visible_for_testing_member
    emit(state.copyWith(
      pageTranslations: {...state.pageTranslations, pageIndex: info},
    ));
  }

  @override
  Future<void> close() {
    _autoPageTimer?.cancel();
    _chapterStreamSubscription?.cancel();
    return super.close();
  }
}
