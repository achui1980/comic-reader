import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'local_storage.dart';

enum DownloadTaskStatus { pending, downloading, completed, failed }

class DownloadTask {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final String mangaTitle;
  final String chapterTitle;
  DownloadTaskStatus status;
  int progress; // 0-100
  String? error;

  DownloadTask({
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    required this.mangaTitle,
    required this.chapterTitle,
    this.status = DownloadTaskStatus.pending,
    this.progress = 0,
    this.error,
  });

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
  );
}

/// Global download manager with persistent queue.
class DownloadManager extends ChangeNotifier {
  final MangaRepository _repository;
  final ChapterCacheService _cacheService;
  final LocalStorage _storage;
  static const _key = 'download_tasks';

  final List<DownloadTask> _tasks = [];
  final int _maxConcurrent = 3;
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
          task.status = DownloadTaskStatus.pending;
          task.progress = 0;
        }
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
    if (task != null && task.status == DownloadTaskStatus.failed) {
      task.status = DownloadTaskStatus.pending;
      task.progress = 0;
      task.error = null;
      notifyListeners();
      _processQueue();
    }
  }

  /// Remove a task from the queue.
  void removeTask(String key) {
    _tasks.removeWhere((t) => t.key == key);
    _persist();
    notifyListeners();
  }

  void _processQueue() {
    while (_activeCount < _maxConcurrent) {
      final nextTask = _tasks.cast<DownloadTask?>().firstWhere(
        (t) => t!.status == DownloadTaskStatus.pending,
        orElse: () => null,
      );
      if (nextTask == null) break;
      _activeCount++;
      _downloadTask(nextTask);
    }
  }

  Future<void> _downloadTask(DownloadTask task) async {
    task.status = DownloadTaskStatus.downloading;
    notifyListeners();

    try {
      // First get chapter images from API
      final result = await _repository.getChapter(
        task.sourceId,
        task.mangaId,
        task.chapterId,
        1,
      );
      final images = result.chapter.images;

      // Download and cache images using ChapterCacheService
      await _cacheService.downloadChapter(
        sourceId: task.sourceId,
        mangaId: task.mangaId,
        chapterId: task.chapterId,
        images: images,
        onProgress: (completed, total) {
          task.progress = total > 0 ? (completed * 100 ~/ total) : 0;
          notifyListeners();
        },
      );

      task.status = DownloadTaskStatus.completed;
      task.progress = 100;
    } catch (e) {
      task.status = DownloadTaskStatus.failed;
      task.error = e.toString();
    }

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
