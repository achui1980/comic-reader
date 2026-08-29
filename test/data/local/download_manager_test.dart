import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
}
