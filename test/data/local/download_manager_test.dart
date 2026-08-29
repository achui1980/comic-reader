import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';

class MockMangaRepository extends Mock implements MangaRepository {}

class MockChapterCacheService extends Mock implements ChapterCacheService {}

class MockLocalStorage extends Mock implements LocalStorage {}

void main() {
  late MockMangaRepository repository;
  late MockChapterCacheService cacheService;
  late MockLocalStorage storage;
  late DownloadManager manager;

  setUp(() {
    repository = MockMangaRepository();
    cacheService = MockChapterCacheService();
    storage = MockLocalStorage();
    when(() => storage.read(any())).thenAnswer((_) async => null);
    when(() => storage.write(any(), any())).thenAnswer((_) async {});
    manager = DownloadManager(
      repository: repository,
      cacheService: cacheService,
      storage: storage,
    );
  });

  ChapterResult buildChapterResult() => ChapterResult(
    chapter: Chapter(
      id: 'c1',
      mangaId: 'm1',
      title: 'Chapter 1',
      images: const [ChapterImage(url: 'https://example.invalid/1.jpg')],
    ),
    canLoadMore: false,
  );

  test('respects max 2 concurrent chapters', () async {
    final completers = <String, Completer<ChapterDownloadResult>>{};
    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) async => buildChapterResult());
    when(
      () => cacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((invocation) {
      final chapterId =
          invocation.namedArguments[const Symbol('chapterId')] as String;
      final completer = Completer<ChapterDownloadResult>();
      completers[chapterId] = completer;
      return completer.future;
    });

    for (final id in ['c1', 'c2', 'c3']) {
      manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: id,
        mangaTitle: 'Manga',
        chapterTitle: id,
      );
    }
    await Future.delayed(Duration.zero);
    expect(manager.activeCount, 2);

    completers['c1']!.complete(
      const ChapterDownloadResult(
        cancelled: false,
        completedImages: 1,
        failedImageIndexes: [],
      ),
    );
    await Future.delayed(Duration.zero);
    expect(manager.activeCount, 2);
  });

  test('marks task partiallyFailed when some images fail', () async {
    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) async => buildChapterResult());
    when(
      () => cacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => const ChapterDownloadResult(
        cancelled: false,
        completedImages: 0,
        failedImageIndexes: [0],
      ),
    );

    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'Manga',
      chapterTitle: 'c1',
    );
    await Future.delayed(const Duration(milliseconds: 10));
    final task = manager.tasks.firstWhere((t) => t.chapterId == 'c1');
    expect(task.status, DownloadTaskStatus.partiallyFailed);
    expect(task.failedImageIndexes, [0]);
  });

  test('addTask returns true for a brand-new task', () async {
    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) => Completer<ChapterResult>().future);

    final result = await manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'Manga',
      chapterTitle: 'c1',
    );

    expect(result, isTrue);
  });

  test(
    'addTask returns false and does not add a duplicate when a task with '
    'the same key already exists in a non-failed status (e.g. paused)',
    () async {
      manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'c1',
      );
      final key = manager.tasks.first.key;
      manager.pauseTask(key); // pending -> paused synchronously
      expect(manager.tasks.first.status, DownloadTaskStatus.paused);

      final result = await manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'c1',
      );

      expect(result, isFalse);
      expect(manager.tasks.where((t) => t.chapterId == 'c1'), hasLength(1));
      expect(manager.tasks.first.status, DownloadTaskStatus.paused);
    },
  );

  test(
    'addTask returns true and replaces an existing failed task with the same key',
    () async {
      when(
        () => repository.getChapter(any(), any(), any(), any()),
      ).thenThrow(Exception('boom'));

      await manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'c1',
      );
      await Future.delayed(const Duration(milliseconds: 10));
      expect(manager.tasks.first.status, DownloadTaskStatus.failed);

      when(
        () => repository.getChapter(any(), any(), any(), any()),
      ).thenAnswer((_) => Completer<ChapterResult>().future);

      final result = await manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'c1',
      );

      expect(result, isTrue);
      expect(manager.tasks.where((t) => t.chapterId == 'c1'), hasLength(1));
    },
  );

  test('higher priority task is processed first', () async {
    // Use pending Completers (rather than an immediately-resolving mock,
    // as the plan's original snippet did) so tasks stay in `downloading`
    // long enough to observe: with a mock that resolves via microtasks
    // only (no real Timer/IO), the whole download chain can race ahead
    // of `Future.delayed(Duration.zero)` and flip status straight to
    // `completed` before the assertion runs, making the test flaky/wrong.
    final completers = <String, Completer<ChapterDownloadResult>>{};
    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) async => buildChapterResult());
    when(
      () => cacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((invocation) {
      final chapterId =
          invocation.namedArguments[const Symbol('chapterId')] as String;
      final completer = Completer<ChapterDownloadResult>();
      completers[chapterId] = completer;
      return completer.future;
    });

    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'low',
      mangaTitle: 'Manga',
      chapterTitle: 'low',
      priority: 0,
    );
    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'mid1',
      mangaTitle: 'Manga',
      chapterTitle: 'mid1',
      priority: 0,
    );
    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'high',
      mangaTitle: 'Manga',
      chapterTitle: 'high',
      priority: 10,
    );
    await Future.delayed(Duration.zero);
    final activeIds = manager.tasks
        .where((t) => t.status == DownloadTaskStatus.downloading)
        .map((t) => t.chapterId);
    expect(activeIds, contains('high'));
  });

  test(
    'notifies listeners synchronously when task transitions to downloading',
    () async {
      // Keep the chapter fetch pending so the task stays parked in
      // `downloading` while we assert, mirroring the real-world window
      // during which the pre-fix code failed to notify.
      final getChapterCompleter = Completer<ChapterResult>();
      when(
        () => repository.getChapter(any(), any(), any(), any()),
      ).thenAnswer((_) => getChapterCompleter.future);

      var notifiedWhileDownloading = false;
      manager.addListener(() {
        final task = manager.tasks.firstWhere(
          (t) => t.chapterId == 'c1',
          orElse: () => DownloadTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'c1',
            mangaTitle: 'Manga',
            chapterTitle: 'c1',
          ),
        );
        if (task.status == DownloadTaskStatus.downloading) {
          notifiedWhileDownloading = true;
        }
      });

      await manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'c1',
      );

      // The chapter fetch is still pending here: `getChapterCompleter`
      // has not been completed. If notifyListeners() fires when the
      // status flips to downloading, notifiedWhileDownloading must
      // already be true at this point.
      final task = manager.tasks.firstWhere((t) => t.chapterId == 'c1');
      expect(task.status, DownloadTaskStatus.downloading);
      expect(notifiedWhileDownloading, isTrue);

      // Cleanup: let the pending future resolve so it doesn't leak
      // across tests.
      getChapterCompleter.complete(buildChapterResult());
      await Future.delayed(Duration.zero);
    },
  );

  test('retryTask resets progress to 0 immediately', () async {
    // Drive the task to `partiallyFailed` with non-zero progress via the
    // normal addTask flow, then retry it and assert progress resets
    // synchronously (before any new download activity can change it).
    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) async => buildChapterResult());
    when(
      () => cacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => const ChapterDownloadResult(
        cancelled: false,
        completedImages: 0,
        failedImageIndexes: [0],
      ),
    );

    await manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'Manga',
      chapterTitle: 'c1',
    );
    await Future.delayed(const Duration(milliseconds: 10));
    final task = manager.tasks.firstWhere((t) => t.chapterId == 'c1');
    expect(task.status, DownloadTaskStatus.partiallyFailed);

    // Simulate that progress had advanced before the failure was
    // recorded (e.g. a later image failed after earlier ones succeeded).
    task.progress = 42;

    // Freeze the next repository call so the task stays in `pending`
    // (never re-enters `downloading`) long enough for the assertion.
    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) => Completer<ChapterResult>().future);

    manager.retryTask(task.key);

    expect(task.progress, 0);
  });

  test('pauseTask cancels an in-flight download and marks it paused', () async {
    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) async => buildChapterResult());
    when(
      () => cacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {
      await Future.delayed(const Duration(seconds: 1));
      return const ChapterDownloadResult(
        cancelled: true,
        completedImages: 0,
        failedImageIndexes: [],
      );
    });

    await manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'Manga',
      chapterTitle: 'c1',
    );
    await Future.delayed(const Duration(milliseconds: 50));

    final key = manager.tasks.first.key;
    manager.pauseTask(key);
    await Future.delayed(const Duration(seconds: 1));

    expect(manager.tasks.first.status, DownloadTaskStatus.paused);
  });

  test('resumeTask re-queues a paused task', () async {
    // Intentionally not awaited: pauseTask must run before addTask's
    // internal _processQueue() (which fires after an `await _persist()`)
    // flips the task to `downloading`, so it hits the `pending` branch.
    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'Manga',
      chapterTitle: 'c1',
    );
    final key = manager.tasks.first.key;
    manager.pauseTask(key);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(manager.tasks.first.status, DownloadTaskStatus.paused);

    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) async => buildChapterResult());
    when(
      () => cacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => const ChapterDownloadResult(
        cancelled: false,
        completedImages: 1,
        failedImageIndexes: [],
      ),
    );

    manager.resumeTask(key);
    await Future.delayed(const Duration(milliseconds: 50));

    expect(manager.tasks.first.status, DownloadTaskStatus.completed);
  });

  test('pauseAll pauses a pending task without cancelling anything', () async {
    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) async => buildChapterResult());
    when(
      () => cacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => Completer<ChapterDownloadResult>().future);

    for (final id in ['c1', 'c2', 'c3']) {
      manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: id,
        mangaTitle: 'Manga',
        chapterTitle: id,
      );
    }
    await Future.delayed(Duration.zero);
    // c1/c2 are already downloading (concurrency 2); c3 stays pending.
    final c3 = manager.tasks.firstWhere((t) => t.chapterId == 'c3');
    expect(c3.status, DownloadTaskStatus.pending);

    manager.pauseAll();

    final c3After = manager.tasks.firstWhere((t) => t.chapterId == 'c3');
    expect(c3After.status, DownloadTaskStatus.paused);
    expect(c3After.pausedAt, isNotNull);
  });

  test('resumeAll re-queues every paused task', () async {
    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'Manga',
      chapterTitle: 'c1',
    );
    manager.pauseTask(manager.tasks.first.key);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(manager.tasks.first.status, DownloadTaskStatus.paused);

    when(
      () => repository.getChapter(any(), any(), any(), any()),
    ).thenAnswer((_) async => buildChapterResult());
    when(
      () => cacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => const ChapterDownloadResult(
        cancelled: false,
        completedImages: 1,
        failedImageIndexes: [],
      ),
    );

    manager.resumeAll();
    await Future.delayed(const Duration(milliseconds: 50));

    expect(manager.tasks.first.status, DownloadTaskStatus.completed);
  });

  test(
    'init preserves completedImages/totalImages when resuming a downloading task, and leaves paused tasks untouched',
    () async {
      final downloadingJson = DownloadTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'c1',
        status: DownloadTaskStatus.downloading,
        progress: 40,
        totalImages: 10,
        completedImages: 4,
      ).toJson();
      final pausedJson = DownloadTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c2',
        mangaTitle: 'Manga',
        chapterTitle: 'c2',
        status: DownloadTaskStatus.paused,
        progress: 60,
        totalImages: 10,
        completedImages: 6,
      ).toJson();
      when(() => storage.read(any())).thenAnswer(
        (_) async => {
          'tasks': [downloadingJson, pausedJson],
        },
      );
      when(
        () => repository.getChapter(any(), any(), any(), any()),
      ).thenAnswer((_) => Completer<ChapterResult>().future);

      final freshManager = DownloadManager(
        repository: repository,
        cacheService: cacheService,
        storage: storage,
      );
      await freshManager.init();

      final resumed = freshManager.tasks.firstWhere(
        (t) => t.chapterId == 'c1',
      );
      // init() resets `downloading` -> `pending` and then immediately runs
      // _processQueue(), which synchronously dispatches the now-pending
      // task back to `downloading` (repository.getChapter is stubbed to
      // never resolve here, so it stays parked there for this assertion).
      // The important behavior under test is that completedImages/
      // totalImages survive the reset instead of being zeroed out.
      expect(resumed.status, DownloadTaskStatus.downloading);
      expect(resumed.completedImages, 4);
      expect(resumed.totalImages, 10);

      final stillPaused = freshManager.tasks.firstWhere(
        (t) => t.chapterId == 'c2',
      );
      expect(stillPaused.status, DownloadTaskStatus.paused);
      expect(stillPaused.completedImages, 6);
    },
  );

  test(
    'pauseTask still fully cleans up (token removed, activeCount decremented, '
    'queue reprocessed) after the finally refactor',
    () async {
      when(
        () => repository.getChapter(any(), any(), any(), any()),
      ).thenAnswer((_) async => buildChapterResult());
      when(
        () => cacheService.downloadChapter(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          images: any(named: 'images'),
          onProgress: any(named: 'onProgress'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        final chapterId =
            invocation.namedArguments[const Symbol('chapterId')] as String;
        if (chapterId == 'c2') {
          // Never resolves: c2 stays parked in `downloading` for the
          // whole test so it doesn't interfere with the activeCount
          // assertion below (which is only about c1's cleanup).
          return Completer<ChapterDownloadResult>().future;
        }
        await Future.delayed(const Duration(seconds: 1));
        return const ChapterDownloadResult(
          cancelled: true,
          completedImages: 0,
          failedImageIndexes: [],
        );
      });

      await manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'c1',
      );
      // A second task takes the other of the 2 concurrent slots so we
      // can observe activeCount go from 2 down to 1 once c1's cleanup
      // (inside the new `finally` block) runs.
      await manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c2',
        mangaTitle: 'Manga',
        chapterTitle: 'c2',
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(manager.activeCount, 2);

      final c1 = manager.tasks.firstWhere((t) => t.chapterId == 'c1');
      manager.pauseTask(c1.key);
      await Future.delayed(const Duration(seconds: 1));

      // Cleanup ran inside `finally`: status transitioned to `paused`,
      // and `_activeCount` was decremented back down (proving
      // `_activeCancelTokens.remove`/`_activeCount--`/`_processQueue()`
      // all still ran after the try/catch->finally restructuring).
      // c2 is still parked in `downloading`, so activeCount settles at
      // 1, not 0.
      expect(
        manager.tasks.firstWhere((t) => t.chapterId == 'c1').status,
        DownloadTaskStatus.paused,
      );
      expect(manager.activeCount, 1);
    },
  );

  test(
    'removeTask cancels the in-flight CancelToken for a downloading task',
    () async {
      when(
        () => repository.getChapter(any(), any(), any(), any()),
      ).thenAnswer((_) async => buildChapterResult());

      CancelToken? capturedToken;
      final downloadCompleter = Completer<ChapterDownloadResult>();
      when(
        () => cacheService.downloadChapter(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          images: any(named: 'images'),
          onProgress: any(named: 'onProgress'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) {
        capturedToken =
            invocation.namedArguments[const Symbol('cancelToken')]
                as CancelToken;
        return downloadCompleter.future;
      });

      await manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'c1',
      );
      await Future.delayed(const Duration(milliseconds: 10));

      final task = manager.tasks.firstWhere((t) => t.chapterId == 'c1');
      expect(task.status, DownloadTaskStatus.downloading);
      expect(capturedToken, isNotNull);
      expect(capturedToken!.isCancelled, isFalse);

      manager.removeTask(task.key);

      expect(capturedToken!.isCancelled, isTrue);
      expect(manager.tasks.any((t) => t.chapterId == 'c1'), isFalse);

      // Cleanup: let the pending download future resolve so it doesn't
      // leak across tests.
      downloadCompleter.complete(
        const ChapterDownloadResult(
          cancelled: true,
          completedImages: 0,
          failedImageIndexes: [],
        ),
      );
      await Future.delayed(Duration.zero);
    },
  );
}
