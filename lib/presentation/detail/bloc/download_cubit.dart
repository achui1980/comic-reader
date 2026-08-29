import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'download_state.dart';

/// Thin presentation-layer wrapper around the global [DownloadManager].
///
/// This cubit no longer owns a download queue itself — it forwards
/// `downloadChapter`/`downloadMultiple`/`cancelDownload` calls to the
/// injected [DownloadManager] and projects the manager's task list into a
/// per-chapter [ChapterDownloadStatus] map scoped to this [sourceId]/
/// [mangaId] pair, so existing UI code (`detail_screen.dart`) keeps working
/// unchanged.
class DownloadCubit extends Cubit<DownloadState> {
  final ChapterCacheService _cacheService;
  final DownloadManager _downloadManager;
  final String sourceId;
  final String mangaId;

  /// [repository] is accepted for backward compatibility with existing call
  /// sites (`detail_screen.dart`) but is unused: chapter fetching now
  /// happens inside [DownloadManager] itself, so this cubit no longer needs
  /// direct repository access.
  DownloadCubit({
    required ChapterCacheService cacheService,
    required MangaRepository repository,
    required DownloadManager downloadManager,
    required this.sourceId,
    required this.mangaId,
  })  : _cacheService = cacheService,
        _downloadManager = downloadManager,
        super(const DownloadState()) {
    _downloadManager.addListener(_onManagerChanged);
    // Sync with whatever tasks already exist (e.g. this cubit was rebuilt
    // after navigating back into the detail screen while a download was
    // still in progress/paused in the background).
    _onManagerChanged();
  }

  String _keyFor(String chapterId) => '${sourceId}_${mangaId}_$chapterId';

  void _onManagerChanged() {
    final chapters = <String, ChapterDownloadStatus>{...state.chapters};
    String? activeChapterId;
    int activeProgress = 0;
    int activeTotal = 0;
    for (final task in _downloadManager.tasks) {
      if (task.sourceId != sourceId || task.mangaId != mangaId) continue;
      chapters[task.chapterId] = switch (task.status) {
        DownloadTaskStatus.pending => ChapterDownloadStatus.queued,
        DownloadTaskStatus.downloading => ChapterDownloadStatus.downloading,
        DownloadTaskStatus.completed => ChapterDownloadStatus.cached,
        DownloadTaskStatus.failed => ChapterDownloadStatus.failed,
        DownloadTaskStatus.paused => ChapterDownloadStatus.paused,
        DownloadTaskStatus.partiallyFailed =>
          ChapterDownloadStatus.partiallyFailed,
      };
      if (task.status == DownloadTaskStatus.downloading) {
        activeChapterId = task.chapterId;
        activeProgress = task.completedImages;
        activeTotal = task.totalImages;
      }
    }
    emit(state.copyWith(
      chapters: chapters,
      activeChapterId: activeChapterId,
      activeProgress: activeProgress,
      activeTotal: activeTotal,
      clearActive: activeChapterId == null,
    ));
  }

  /// Check which chapters are already cached on disk.
  /// Call this with the chapter list after loading detail.
  Future<void> checkCachedChapters(List<ChapterItem> chapters) async {
    final result = <String, ChapterDownloadStatus>{};
    for (final chapter in chapters) {
      final cached = await _cacheService.isChapterCached(
        sourceId,
        mangaId,
        chapter.id,
        1, // At minimum 1 image means something is cached
      );
      result[chapter.id] =
          cached ? ChapterDownloadStatus.cached : ChapterDownloadStatus.none;
    }
    emit(state.copyWith(chapters: {...state.chapters, ...result}));
  }

  /// Queue a single chapter for download via the global [DownloadManager].
  void downloadChapter(ChapterItem chapter) {
    _downloadManager.addTask(
      sourceId: sourceId,
      mangaId: mangaId,
      chapterId: chapter.id,
      // The cubit itself has no manga title available; DownloadDrawer's
      // display for tasks queued from the detail screen will show mangaId
      // instead. Acceptable known limitation for this task (see plan notes).
      mangaTitle: mangaId,
      chapterTitle: chapter.title,
    );
  }

  /// Queue multiple chapters, skipping ones already cached/queued/active.
  void downloadMultiple(List<ChapterItem> chapterItems) {
    for (final chapter in chapterItems) {
      final current = state.chapters[chapter.id] ?? ChapterDownloadStatus.none;
      if (current == ChapterDownloadStatus.cached ||
          current == ChapterDownloadStatus.downloading ||
          current == ChapterDownloadStatus.queued) {
        continue;
      }
      downloadChapter(chapter);
    }
  }

  /// Pause the currently active download for this manga.
  void cancelDownload() {
    final activeChapterId = state.activeChapterId;
    if (activeChapterId == null) return;
    _downloadManager.pauseTask(_keyFor(activeChapterId));
  }

  @override
  Future<void> close() {
    _downloadManager.removeListener(_onManagerChanged);
    return super.close();
  }
}
