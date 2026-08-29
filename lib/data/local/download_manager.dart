import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'local_storage.dart';

enum DownloadTaskStatus {
  pending,
  downloading,
  completed,
  failed,
  paused,
  partiallyFailed,
}

class DownloadTask {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final String mangaTitle;
  final String chapterTitle;
  DownloadTaskStatus status;
  int progress; // 0-100
  String? error;
  int totalImages;
  int completedImages;
  List<int> failedImageIndexes;
  int retryCount;
  DateTime? pausedAt;
  int priority;

  DownloadTask({
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    required this.mangaTitle,
    required this.chapterTitle,
    this.status = DownloadTaskStatus.pending,
    this.progress = 0,
    this.error,
    this.totalImages = 0,
    this.completedImages = 0,
    List<int>? failedImageIndexes,
    this.retryCount = 0,
    this.pausedAt,
    this.priority = 0,
  }) : failedImageIndexes = failedImageIndexes ?? [];

  String get key => '${sourceId}_${mangaId}_$chapterId';

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'mangaId': mangaId,
    'chapterId': chapterId,
    'mangaTitle': mangaTitle,
    'chapterTitle': chapterTitle,
    'status': status.index,
    'progress': progress,
    'error': error,
    'totalImages': totalImages,
    'completedImages': completedImages,
    'failedImageIndexes': failedImageIndexes,
    'retryCount': retryCount,
    'pausedAt': pausedAt?.toIso8601String(),
    'priority': priority,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    sourceId: json['sourceId'] as String,
    mangaId: json['mangaId'] as String,
    chapterId: json['chapterId'] as String,
    mangaTitle: json['mangaTitle'] as String? ?? '',
    chapterTitle: json['chapterTitle'] as String? ?? '',
    status: DownloadTaskStatus.values[json['status'] as int? ?? 0],
    progress: json['progress'] as int? ?? 0,
    error: json['error'] as String?,
    totalImages: json['totalImages'] as int? ?? 0,
    completedImages: json['completedImages'] as int? ?? 0,
    failedImageIndexes:
        (json['failedImageIndexes'] as List?)?.map((e) => e as int).toList() ??
        [],
    retryCount: json['retryCount'] as int? ?? 0,
    pausedAt: json['pausedAt'] != null
        ? DateTime.parse(json['pausedAt'] as String)
        : null,
    priority: json['priority'] as int? ?? 0,
  );
}

/// Global download manager with persistent queue.
class DownloadManager extends ChangeNotifier {
  final MangaRepository _repository;
  final ChapterCacheService _cacheService;
  final LocalStorage _storage;
  static const _key = 'download_tasks';

  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _activeCancelTokens = {};
  final int _maxConcurrentChapters = 2;
  int _activeCount = 0;
  bool _initialized = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _activeCount;
  int get pendingCount =>
      _tasks.where((t) => t.status == DownloadTaskStatus.pending).length;

  DownloadManager({
    required MangaRepository repository,
    required ChapterCacheService cacheService,
    required LocalStorage storage,
  })  : _repository = repository,
        _cacheService = cacheService,
        _storage = storage;

  /// Initialize and resume incomplete tasks from storage.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final data = await _storage.read(_key);
    if (data != null && data['tasks'] is List) {
      for (final json in (data['tasks'] as List)) {
        final task = DownloadTask.fromJson(json as Map<String, dynamic>);
        if (task.status == DownloadTaskStatus.downloading) {
          // 重启接续：保留 completedImages/totalImages/failedImageIndexes，
          // 只把状态改回 pending。ChapterCacheService 的按 index 跳过逻辑
          // 会自动跳过已下载的图片，不会重新下载，因此这里不重置进度字段。
          task.status = DownloadTaskStatus.pending;
        }
        // status == paused 的任务保持原样，不自动恢复（需用户手动
        // resumeTask/resumeAll）。
        if (task.status != DownloadTaskStatus.completed) {
          _tasks.add(task);
        }
      }
    }
    _processQueue();
  }

  /// Add a download task.
  Future<void> addTask({
    required String sourceId,
    required String mangaId,
    required String chapterId,
    required String mangaTitle,
    required String chapterTitle,
    int priority = 0,
  }) async {
    final key = '${sourceId}_${mangaId}_$chapterId';
    if (_tasks.any((t) => t.key == key && t.status != DownloadTaskStatus.failed)) {
      return;
    }
    _tasks.removeWhere((t) => t.key == key && t.status == DownloadTaskStatus.failed);
    _tasks.add(DownloadTask(
      sourceId: sourceId,
      mangaId: mangaId,
      chapterId: chapterId,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
      priority: priority,
    ));
    await _persist();
    notifyListeners();
    _processQueue();
  }

  /// Retry a failed task.
  void retryTask(String key) {
    final task = _tasks.cast<DownloadTask?>().firstWhere(
      (t) => t!.key == key,
      orElse: () => null,
    );
    if (task == null) return;
    if (task.status != DownloadTaskStatus.failed &&
        task.status != DownloadTaskStatus.partiallyFailed) {
      return;
    }
    task.status = DownloadTaskStatus.pending;
    task.error = null;
    task.progress = 0;
    _persist();
    notifyListeners();
    _processQueue();
  }

  /// Remove a task from the queue.
  void removeTask(String key) {
    _tasks.removeWhere((t) => t.key == key);
    _persist();
    notifyListeners();
  }

  /// Pause a single task by [key]. A `pending` task is paused immediately;
  /// a `downloading` task has its [CancelToken] cancelled and transitions
  /// to `paused` once `_downloadTask` observes the cancellation.
  void pauseTask(String key) {
    final task = _tasks.firstWhereOrNull((t) => t.key == key);
    if (task == null) return;
    if (task.status == DownloadTaskStatus.pending) {
      task.status = DownloadTaskStatus.paused;
      task.pausedAt = DateTime.now();
      _persist();
      notifyListeners();
      return;
    }
    if (task.status == DownloadTaskStatus.downloading) {
      _activeCancelTokens[key]?.cancel();
      // 状态转换在 _downloadTask 的 cancelled 分支里完成。
    }
  }

  /// Resume a single paused task by [key], re-queueing it as `pending`.
  void resumeTask(String key) {
    final task = _tasks.firstWhereOrNull((t) => t.key == key);
    if (task == null || task.status != DownloadTaskStatus.paused) return;
    task.status = DownloadTaskStatus.pending;
    task.pausedAt = null;
    _persist();
    notifyListeners();
    _processQueue();
  }

  /// Pause every task currently pending or downloading.
  void pauseAll() {
    for (final task in _tasks.toList()) {
      pauseTask(task.key);
    }
  }

  /// Resume every paused task.
  void resumeAll() {
    for (final task
        in _tasks.where((t) => t.status == DownloadTaskStatus.paused).toList()) {
      resumeTask(task.key);
    }
  }

  void _processQueue() {
    while (_activeCount < _maxConcurrentChapters) {
      final pending = _tasks
          .where((t) => t.status == DownloadTaskStatus.pending)
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));
      if (pending.isEmpty) break;
      final task = pending.first;
      task.status = DownloadTaskStatus.downloading;
      notifyListeners();
      _activeCount++;
      _downloadTask(task);
    }
  }

  Future<void> _downloadTask(DownloadTask task) async {
    final cancelToken = CancelToken();
    _activeCancelTokens[task.key] = cancelToken;
    try {
      // First get chapter images from API
      final result = await _repository.getChapter(
        task.sourceId,
        task.mangaId,
        task.chapterId,
        1,
      );
      final images = result.chapter.images;
      task.totalImages = images.length;

      // Download and cache images using ChapterCacheService
      final downloadResult = await _cacheService.downloadChapter(
        sourceId: task.sourceId,
        mangaId: task.mangaId,
        chapterId: task.chapterId,
        images: images,
        onProgress: (completed, total) {
          task.completedImages = completed;
          task.progress = total > 0 ? (completed * 100 ~/ total) : 0;
          notifyListeners();
        },
        cancelToken: cancelToken,
      );

      task.completedImages = downloadResult.completedImages;
      task.failedImageIndexes = downloadResult.failedImageIndexes;
      if (downloadResult.cancelled) {
        // 只要 cancelled == true 就统一置为 paused（不区分具体取消原因），
        // 并保留已完成的 completedImages 供断点续传展示进度。
        task.status = DownloadTaskStatus.paused;
        task.pausedAt = DateTime.now();
      } else if (downloadResult.failedImageIndexes.isEmpty) {
        task.status = DownloadTaskStatus.completed;
        task.progress = 100;
      } else {
        task.status = DownloadTaskStatus.partiallyFailed;
        task.error = '${downloadResult.failedImageIndexes.length} 张图片下载失败';
      }
    } catch (e) {
      task.status = DownloadTaskStatus.failed;
      task.error = e.toString();
    }

    _activeCancelTokens.remove(task.key);
    _activeCount--;
    await _persist();
    notifyListeners();
    _processQueue();
  }

  Future<void> _persist() async {
    final tasks =
        _tasks.where((t) => t.status != DownloadTaskStatus.completed).toList();
    await _storage.write(_key, {
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
  }
}
