import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'download_state.dart';

/// Manages chapter download queue and progress.
class DownloadCubit extends Cubit<DownloadState> {
  final ChapterCacheService _cacheService;
  final MangaRepository _repository;
  final String sourceId;
  final String mangaId;

  CancelToken? _cancelToken;
  bool _isProcessing = false;

  DownloadCubit({
    required ChapterCacheService cacheService,
    required MangaRepository repository,
    required this.sourceId,
    required this.mangaId,
  })  : _cacheService = cacheService,
        _repository = repository,
        super(const DownloadState());

  /// Check which chapters are already cached.
  /// Call this with the chapter list after loading detail.
  Future<void> checkCachedChapters(List<ChapterItem> chapters) async {
    final Map<String, ChapterDownloadStatus> statuses = {};
    for (final chapter in chapters) {
      // We don't know totalImages yet without loading the chapter,
      // so we check if the directory exists and has any files.
      final cached = await _cacheService.isChapterCached(
        sourceId,
        mangaId,
        chapter.id,
        1, // At minimum 1 image means something is cached
      );
      statuses[chapter.id] = cached
          ? ChapterDownloadStatus.cached
          : ChapterDownloadStatus.none;
    }
    emit(state.copyWith(chapters: statuses));
  }

  /// Add a single chapter to download queue.
  Future<void> downloadChapter(ChapterItem chapter) async {
    final chapters = Map<String, ChapterDownloadStatus>.from(state.chapters);
    chapters[chapter.id] = ChapterDownloadStatus.queued;
    final queue = [...state.queue, chapter.id];
    emit(state.copyWith(chapters: chapters, queue: queue));
    _processQueue();
  }

  /// Add multiple chapters to download queue.
  Future<void> downloadMultiple(List<ChapterItem> chapterItems) async {
    final chapters = Map<String, ChapterDownloadStatus>.from(state.chapters);
    final queue = [...state.queue];
    for (final ch in chapterItems) {
      if (chapters[ch.id] != ChapterDownloadStatus.cached &&
          chapters[ch.id] != ChapterDownloadStatus.downloading &&
          !queue.contains(ch.id)) {
        chapters[ch.id] = ChapterDownloadStatus.queued;
        queue.add(ch.id);
      }
    }
    emit(state.copyWith(chapters: chapters, queue: queue));
    _processQueue();
  }

  /// Cancel the current download.
  void cancelDownload() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
    if (state.activeChapterId != null) {
      final chapters = Map<String, ChapterDownloadStatus>.from(state.chapters);
      chapters[state.activeChapterId!] = ChapterDownloadStatus.none;
      emit(state.copyWith(
        chapters: chapters,
        queue: [],
        clearActive: true,
        activeProgress: 0,
        activeTotal: 0,
      ));
    }
    _isProcessing = false;
  }

  /// Process the download queue sequentially.
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    if (state.queue.isEmpty) return;
    _isProcessing = true;

    while (state.queue.isNotEmpty) {
      final chapterId = state.queue.first;
      final remainingQueue = state.queue.sublist(1);

      final chapters = Map<String, ChapterDownloadStatus>.from(state.chapters);
      chapters[chapterId] = ChapterDownloadStatus.downloading;
      emit(state.copyWith(
        chapters: chapters,
        activeChapterId: chapterId,
        activeProgress: 0,
        activeTotal: 0,
        queue: remainingQueue,
      ));

      // First, fetch chapter images from the source
      try {
        final result = await _repository.getChapter(sourceId, mangaId, chapterId, 1);
        final images = result.chapter.images;

        emit(state.copyWith(activeTotal: images.length));

        // Download all images
        _cancelToken = CancelToken();
        final success = await _cacheService.downloadChapter(
          sourceId: sourceId,
          mangaId: mangaId,
          chapterId: chapterId,
          images: images,
          cancelToken: _cancelToken,
          onProgress: (completed, total) {
            if (!isClosed) {
              emit(state.copyWith(
                activeProgress: completed,
                activeTotal: total,
              ));
            }
          },
        );

        if (isClosed) return;

        final updatedChapters = Map<String, ChapterDownloadStatus>.from(state.chapters);
        updatedChapters[chapterId] = success
            ? ChapterDownloadStatus.cached
            : ChapterDownloadStatus.failed;
        emit(state.copyWith(
          chapters: updatedChapters,
          clearActive: true,
          activeProgress: 0,
          activeTotal: 0,
        ));
      } catch (_) {
        if (isClosed) return;
        final updatedChapters = Map<String, ChapterDownloadStatus>.from(state.chapters);
        updatedChapters[chapterId] = ChapterDownloadStatus.failed;
        emit(state.copyWith(
          chapters: updatedChapters,
          clearActive: true,
          activeProgress: 0,
          activeTotal: 0,
        ));
      }
    }

    _isProcessing = false;
  }

  @override
  Future<void> close() {
    _cancelToken?.cancel('Cubit closed');
    return super.close();
  }
}
