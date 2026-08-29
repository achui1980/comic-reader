import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/detail/bloc/download_cubit.dart';
import 'package:comic_reader/presentation/detail/bloc/download_state.dart';

class MockDownloadManager extends Mock implements DownloadManager {}

class MockMangaRepository extends Mock implements MangaRepository {}

class MockChapterCacheService extends Mock implements ChapterCacheService {}

DownloadTask _task({
  required String chapterId,
  DownloadTaskStatus status = DownloadTaskStatus.pending,
  String sourceId = 's1',
  String mangaId = 'm1',
  int completedImages = 0,
  int totalImages = 0,
}) =>
    DownloadTask(
      sourceId: sourceId,
      mangaId: mangaId,
      chapterId: chapterId,
      mangaTitle: mangaId,
      chapterTitle: chapterId,
      status: status,
      completedImages: completedImages,
      totalImages: totalImages,
    );

void main() {
  late MockDownloadManager mockManager;
  late MockMangaRepository mockRepository;
  late MockChapterCacheService mockCacheService;
  late void Function() capturedListener;

  setUp(() {
    mockManager = MockDownloadManager();
    mockRepository = MockMangaRepository();
    mockCacheService = MockChapterCacheService();
    when(() => mockManager.tasks).thenReturn(<DownloadTask>[]);
    when(() => mockManager.addListener(any())).thenAnswer((invocation) {
      capturedListener =
          invocation.positionalArguments.first as void Function();
    });
    when(() => mockManager.removeListener(any())).thenReturn(null);
    when(() => mockManager.addTask(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          mangaTitle: any(named: 'mangaTitle'),
          chapterTitle: any(named: 'chapterTitle'),
        )).thenAnswer((_) async {});
    when(() => mockManager.pauseTask(any())).thenReturn(null);
  });

  DownloadCubit build() => DownloadCubit(
        cacheService: mockCacheService,
        repository: mockRepository,
        downloadManager: mockManager,
        sourceId: 's1',
        mangaId: 'm1',
      );

  blocTest<DownloadCubit, DownloadState>(
    'downloadChapter forwards to DownloadManager.addTask',
    build: build,
    act: (cubit) => cubit
        .downloadChapter(ChapterItem(id: 'c1', mangaId: 'm1', title: '第1章')),
    verify: (_) {
      verify(() => mockManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'c1',
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: '第1章',
          )).called(1);
    },
  );

  blocTest<DownloadCubit, DownloadState>(
    'cancelDownload calls pauseTask on the active chapter',
    build: build,
    seed: () => const DownloadState(
      chapters: {'c1': ChapterDownloadStatus.downloading},
      activeChapterId: 'c1',
    ),
    act: (cubit) => cubit.cancelDownload(),
    verify: (_) {
      verify(() => mockManager.pauseTask('s1_m1_c1')).called(1);
    },
  );

  blocTest<DownloadCubit, DownloadState>(
    'cancelDownload is a no-op when nothing is active',
    build: build,
    act: (cubit) => cubit.cancelDownload(),
    verify: (_) {
      verifyNever(() => mockManager.pauseTask(any()));
    },
  );

  blocTest<DownloadCubit, DownloadState>(
    'downloadMultiple skips chapters already cached locally',
    build: build,
    seed: () => const DownloadState(
      chapters: {'c1': ChapterDownloadStatus.cached},
    ),
    act: (cubit) => cubit.downloadMultiple([
      ChapterItem(id: 'c1', mangaId: 'm1', title: 'Ch1'),
      ChapterItem(id: 'c2', mangaId: 'm1', title: 'Ch2'),
    ]),
    verify: (_) {
      verify(() => mockManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'c2',
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: 'Ch2',
          )).called(1);
      verifyNever(() => mockManager.addTask(
            sourceId: any(named: 'sourceId'),
            mangaId: any(named: 'mangaId'),
            chapterId: 'c1',
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          ));
    },
  );

  test('checkCachedChapters queries ChapterCacheService per chapter', () async {
    when(() => mockCacheService.isChapterCached('s1', 'm1', 'c1', 1))
        .thenAnswer((_) async => true);
    when(() => mockCacheService.isChapterCached('s1', 'm1', 'c2', 1))
        .thenAnswer((_) async => false);
    final cubit = build();

    await cubit.checkCachedChapters([
      ChapterItem(id: 'c1', mangaId: 'm1', title: 'Ch1'),
      ChapterItem(id: 'c2', mangaId: 'm1', title: 'Ch2'),
    ]);

    expect(cubit.state.chapters['c1'], ChapterDownloadStatus.cached);
    expect(cubit.state.chapters['c2'], ChapterDownloadStatus.none);
  });

  blocTest<DownloadCubit, DownloadState>(
    'checkCachedChapters does not clobber paused/partiallyFailed/queued/'
    'downloading/failed statuses that reflect a live DownloadManager task',
    setUp: () {
      // Disk heuristic says "cached" (>=1 file present) for every chapter,
      // simulating partiallyFailed/paused tasks which do have some files on
      // disk already.
      when(() => mockCacheService.isChapterCached(any(), any(), any(), any()))
          .thenAnswer((_) async => true);
    },
    build: build,
    seed: () => const DownloadState(chapters: {
      'c1': ChapterDownloadStatus.paused,
      'c2': ChapterDownloadStatus.partiallyFailed,
      'c3': ChapterDownloadStatus.queued,
      'c4': ChapterDownloadStatus.downloading,
      'c5': ChapterDownloadStatus.failed,
      'c6': ChapterDownloadStatus.none,
      // c7 has no entry at all yet.
    }),
    act: (cubit) => cubit.checkCachedChapters([
      ChapterItem(id: 'c1', mangaId: 'm1', title: 'Ch1'),
      ChapterItem(id: 'c2', mangaId: 'm1', title: 'Ch2'),
      ChapterItem(id: 'c3', mangaId: 'm1', title: 'Ch3'),
      ChapterItem(id: 'c4', mangaId: 'm1', title: 'Ch4'),
      ChapterItem(id: 'c5', mangaId: 'm1', title: 'Ch5'),
      ChapterItem(id: 'c6', mangaId: 'm1', title: 'Ch6'),
      ChapterItem(id: 'c7', mangaId: 'm1', title: 'Ch7'),
    ]),
    verify: (cubit) {
      // Live-task statuses must be preserved untouched.
      expect(cubit.state.chapters['c1'], ChapterDownloadStatus.paused);
      expect(
          cubit.state.chapters['c2'], ChapterDownloadStatus.partiallyFailed);
      expect(cubit.state.chapters['c3'], ChapterDownloadStatus.queued);
      expect(cubit.state.chapters['c4'], ChapterDownloadStatus.downloading);
      expect(cubit.state.chapters['c5'], ChapterDownloadStatus.failed);
      // none/no-entry chapters are still subject to the disk heuristic.
      expect(cubit.state.chapters['c6'], ChapterDownloadStatus.cached);
      expect(cubit.state.chapters['c7'], ChapterDownloadStatus.cached);
    },
  );

  test('maps DownloadTaskStatus to ChapterDownloadStatus, including paused '
      'and partiallyFailed', () {
    final cubit = build();

    when(() => mockManager.tasks).thenReturn([
      _task(chapterId: 'c1', status: DownloadTaskStatus.pending),
      _task(chapterId: 'c2', status: DownloadTaskStatus.downloading),
      _task(chapterId: 'c3', status: DownloadTaskStatus.completed),
      _task(chapterId: 'c4', status: DownloadTaskStatus.failed),
      _task(chapterId: 'c5', status: DownloadTaskStatus.paused),
      _task(chapterId: 'c6', status: DownloadTaskStatus.partiallyFailed),
      // Task for a different manga must be ignored.
      _task(chapterId: 'c7', mangaId: 'other', status: DownloadTaskStatus.paused),
    ]);
    capturedListener();

    expect(cubit.state.chapters['c1'], ChapterDownloadStatus.queued);
    expect(cubit.state.chapters['c2'], ChapterDownloadStatus.downloading);
    expect(cubit.state.chapters['c3'], ChapterDownloadStatus.cached);
    expect(cubit.state.chapters['c4'], ChapterDownloadStatus.failed);
    expect(cubit.state.chapters['c5'], ChapterDownloadStatus.paused);
    expect(cubit.state.chapters['c6'], ChapterDownloadStatus.partiallyFailed);
    expect(cubit.state.chapters.containsKey('c7'), isFalse);
    expect(cubit.state.activeChapterId, 'c2');

    cubit.close();
  });

  test('constructor synchronously syncs state from already-in-flight tasks '
      'without waiting for a listener callback', () {
    // Tasks already exist in DownloadManager *before* the cubit is built,
    // simulating navigating back into the detail screen while a download
    // was already running in the background.
    when(() => mockManager.tasks).thenReturn([
      _task(chapterId: 'c1', status: DownloadTaskStatus.downloading),
    ]);

    final cubit = build();

    // This assertion must hold immediately after construction, without
    // ever invoking the captured listener callback.
    expect(cubit.state.chapters['c1'], ChapterDownloadStatus.downloading);
    expect(cubit.state.activeChapterId, 'c1');

    cubit.close();
  });

  test('_onManagerChanged clears stale statuses when a task disappears from '
      'DownloadManager.tasks (e.g. removed via the download drawer)', () {
    when(() => mockManager.tasks).thenReturn([
      _task(chapterId: 'c1', status: DownloadTaskStatus.paused),
      _task(chapterId: 'c2', status: DownloadTaskStatus.pending),
    ]);
    final cubit = build();
    expect(cubit.state.chapters['c1'], ChapterDownloadStatus.paused);
    expect(cubit.state.chapters['c2'], ChapterDownloadStatus.queued);

    // c1's task is removed from the manager (e.g. via
    // DownloadManager.removeTask() from the download drawer) while this
    // cubit is still alive; c2's task remains.
    when(() => mockManager.tasks).thenReturn([
      _task(chapterId: 'c2', status: DownloadTaskStatus.pending),
    ]);
    capturedListener();

    expect(cubit.state.chapters['c1'], ChapterDownloadStatus.none);
    expect(cubit.state.chapters['c2'], ChapterDownloadStatus.queued);

    cubit.close();
  });

  test('_onManagerChanged does not reset a completed task\'s chapter to '
      'none when the task is removed from DownloadManager.tasks (e.g. '
      'removeTask() called from the download drawer on an already-'
      'completed download, which does not delete files from disk)', () {
    when(() => mockManager.tasks).thenReturn([
      _task(chapterId: 'c1', status: DownloadTaskStatus.completed),
    ]);
    final cubit = build();
    expect(cubit.state.chapters['c1'], ChapterDownloadStatus.cached);

    // c1's completed task is removed from the manager (e.g. via
    // DownloadManager.removeTask() from the download drawer's long-press
    // "remove" action on a finished download) while this cubit is still
    // alive. The files are still on disk, so the chapter must remain
    // `cached`, not be reset to `none`.
    when(() => mockManager.tasks).thenReturn(<DownloadTask>[]);
    capturedListener();

    expect(cubit.state.chapters['c1'], ChapterDownloadStatus.cached);

    cubit.close();
  });

  blocTest<DownloadCubit, DownloadState>(
    '_onManagerChanged does not clear disk-based statuses set by '
    'checkCachedChapters that never had a corresponding task',
    build: build,
    seed: () =>
        const DownloadState(chapters: {'c1': ChapterDownloadStatus.cached}),
    act: (cubit) {
      when(() => mockManager.tasks).thenReturn(<DownloadTask>[]);
      capturedListener();
    },
    verify: (cubit) {
      expect(cubit.state.chapters['c1'], ChapterDownloadStatus.cached);
    },
  );

  test('close() removes the DownloadManager listener', () async {
    final cubit = build();
    await cubit.close();
    verify(() => mockManager.removeListener(any())).called(1);
  });
}
