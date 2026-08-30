import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/data/local/category_store.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/local/library_update_service.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/home/bloc/home_cubit.dart';
import 'package:comic_reader/presentation/home/bloc/home_state.dart';

class MockFavoritesStore extends Mock implements FavoritesStore {}

class MockUpdateStore extends Mock implements UpdateStore {}

class MockCategoryStore extends Mock implements CategoryStore {}

class MockLibraryUpdateService extends Mock implements LibraryUpdateService {}

class MockReadingHistoryStore extends Mock implements ReadingHistoryStore {}

class MockDownloadManager extends Mock implements DownloadManager {}

class MockMangaRepository extends Mock implements MangaRepository {}

void main() {
  late MockFavoritesStore favoritesStore;
  late MockUpdateStore updateStore;
  late MockCategoryStore categoryStore;
  late MockLibraryUpdateService libraryUpdateService;
  late MockReadingHistoryStore historyStore;
  late MockDownloadManager downloadManager;
  late MockMangaRepository repository;

  setUp(() {
    favoritesStore = MockFavoritesStore();
    updateStore = MockUpdateStore();
    categoryStore = MockCategoryStore();
    libraryUpdateService = MockLibraryUpdateService();
    historyStore = MockReadingHistoryStore();
    downloadManager = MockDownloadManager();
    repository = MockMangaRepository();
  });

  HomeCubit buildCubit() => HomeCubit(
        favoritesStore: favoritesStore,
        updateStore: updateStore,
        categoryStore: categoryStore,
        libraryUpdateService: libraryUpdateService,
        repository: repository,
        historyStore: historyStore,
        downloadManager: downloadManager,
      );

  const manga = MangaSummary(
    id: 'm1',
    sourceId: 's1',
    title: 'T',
    coverUrl: 'c',
  );
  final chapters = [
    const ChapterItem(id: 'c1', mangaId: 'm1', title: 'Ch1'),
    const ChapterItem(id: 'c2', mangaId: 'm1', title: 'Ch2'),
  ];
  // Stand-in for sources whose MangaDetail carries no embedded chapters
  // (i.e. they rely on the separate getChapterList pagination), used by
  // every test below that isn't specifically exercising the new
  // getMangaInfo-embedded-chapters path.
  const emptyMangaDetail =
      MangaDetail(id: 'm1', sourceId: 's1', title: 'T', coverUrl: 'c');

  blocTest<HomeCubit, dynamic>(
    'downloadUnread 只为未读章节调用 addTask，并返回加入队列的章节数',
    build: () {
      when(() => repository.getMangaInfo('s1', 'm1'))
          .thenAnswer((_) async => emptyMangaDetail);
      when(() => repository.getChapterList('s1', 'm1', 1)).thenAnswer(
          (_) async => ChapterListResult(chapters: chapters, canLoadMore: false));
      when(() => historyStore.getReadChapters('s1', 'm1'))
          .thenAnswer((_) async => {'c1'});
      when(() => downloadManager.addTask(
            sourceId: any(named: 'sourceId'),
            mangaId: any(named: 'mangaId'),
            chapterId: any(named: 'chapterId'),
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          )).thenAnswer((_) async => true);
      return buildCubit();
    },
    act: (cubit) => cubit.downloadUnread(manga),
    verify: (_) {
      verify(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'c2',
            mangaTitle: 'T',
            chapterTitle: 'Ch2',
          )).called(1);
      verifyNever(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'c1',
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          ));
    },
  );

  test('downloadUnread 返回实际加入队列的章节数', () async {
    when(() => repository.getMangaInfo('s1', 'm1'))
        .thenAnswer((_) async => emptyMangaDetail);
    when(() => repository.getChapterList('s1', 'm1', 1)).thenAnswer(
        (_) async => ChapterListResult(chapters: chapters, canLoadMore: false));
    when(() => historyStore.getReadChapters('s1', 'm1'))
        .thenAnswer((_) async => {'c1'});
    when(() => downloadManager.addTask(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          mangaTitle: any(named: 'mangaTitle'),
          chapterTitle: any(named: 'chapterTitle'),
        )).thenAnswer((_) async => true);
    final cubit = buildCubit();
    final count = await cubit.downloadUnread(manga);
    expect(count, 1);
  });

  test(
    'downloadUnread 只统计 addTask 真正返回true(新入队)的章节数，'
    '已存在非failed任务(addTask返回false)的未读章节不计入',
    () async {
      // Both c1 and c2 are unread, but c1 already has a live non-failed
      // task in DownloadManager (e.g. paused) so addTask silently no-ops
      // and returns false for it. Only c2's addTask call returns true.
      when(() => repository.getMangaInfo('s1', 'm1'))
          .thenAnswer((_) async => emptyMangaDetail);
      when(() => repository.getChapterList('s1', 'm1', 1)).thenAnswer(
          (_) async =>
              ChapterListResult(chapters: chapters, canLoadMore: false));
      when(() => historyStore.getReadChapters('s1', 'm1'))
          .thenAnswer((_) async => <String>{});
      when(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'c1',
            mangaTitle: 'T',
            chapterTitle: 'Ch1',
          )).thenAnswer((_) async => false);
      when(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'c2',
            mangaTitle: 'T',
            chapterTitle: 'Ch2',
          )).thenAnswer((_) async => true);

      final cubit = buildCubit();
      final count = await cubit.downloadUnread(manga);

      // 2 chapters are unread, but only 1 was actually newly queued.
      expect(count, 1);
    },
  );

  test('downloadUnread 会翻页拉取全部章节列表，并正确对比完整已读集合', () async {
    // Page 1 reports canLoadMore=true with one chapter; page 2 is the last
    // page (canLoadMore=false) with a second, unread chapter. downloadUnread
    // must keep paging (mirroring DetailCubit.loadChapters) instead of only
    // reading page 1, otherwise chapters that only exist on later pages
    // (e.g. paginated sources like MangaDex) would never be queued.
    final page1Chapters = [
      const ChapterItem(id: 'p1c1', mangaId: 'm1', title: 'Page1-Ch1'),
    ];
    final page2Chapters = [
      const ChapterItem(id: 'p2c1', mangaId: 'm1', title: 'Page2-Ch1'),
    ];
    when(() => repository.getMangaInfo('s1', 'm1'))
        .thenAnswer((_) async => emptyMangaDetail);
    when(() => repository.getChapterList('s1', 'm1', 1)).thenAnswer(
        (_) async =>
            ChapterListResult(chapters: page1Chapters, canLoadMore: true));
    when(() => repository.getChapterList('s1', 'm1', 2)).thenAnswer(
        (_) async =>
            ChapterListResult(chapters: page2Chapters, canLoadMore: false));
    // Nothing read yet, so both pages' chapters are unread.
    when(() => historyStore.getReadChapters('s1', 'm1'))
        .thenAnswer((_) async => <String>{});
    when(() => downloadManager.addTask(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          mangaTitle: any(named: 'mangaTitle'),
          chapterTitle: any(named: 'chapterTitle'),
        )).thenAnswer((_) async => true);

    final cubit = buildCubit();
    final count = await cubit.downloadUnread(manga);

    // Both pages must have been fetched.
    verify(() => repository.getChapterList('s1', 'm1', 1)).called(1);
    verify(() => repository.getChapterList('s1', 'm1', 2)).called(1);
    // The chapter that only exists on page 2 must still be queued.
    verify(() => downloadManager.addTask(
          sourceId: 's1',
          mangaId: 'm1',
          chapterId: 'p2c1',
          mangaTitle: 'T',
          chapterTitle: 'Page2-Ch1',
        )).called(1);
    verify(() => downloadManager.addTask(
          sourceId: 's1',
          mangaId: 'm1',
          chapterId: 'p1c1',
          mangaTitle: 'T',
          chapterTitle: 'Page1-Ch1',
        )).called(1);
    expect(count, 2);
  });

  test(
    'downloadUnread 优先使用 getMangaInfo 返回的内嵌章节列表，'
    '跳过 getChapterList 分页(修复 prepareChapterListFetch 返回null的源永远无未读章节的bug)',
    () async {
      // Simulates a source like bazuo whose prepareChapterListFetch always
      // returns null: getChapterList degenerates to an empty result, but
      // getMangaInfo's MangaDetail carries the real embedded chapter list.
      final embeddedChapters = [
        const ChapterItem(id: 'e1', mangaId: 'm1', title: 'E1'),
        const ChapterItem(id: 'e2', mangaId: 'm1', title: 'E2'),
        const ChapterItem(id: 'e3', mangaId: 'm1', title: 'E3'),
      ];
      when(() => repository.getMangaInfo('s1', 'm1')).thenAnswer(
        (_) async => MangaDetail(
          id: 'm1',
          sourceId: 's1',
          title: 'T',
          coverUrl: 'c',
          chapters: embeddedChapters,
        ),
      );
      when(() => repository.getChapterList('s1', 'm1', any())).thenAnswer(
          (_) async => const ChapterListResult(chapters: [], canLoadMore: false));
      when(() => historyStore.getReadChapters('s1', 'm1'))
          .thenAnswer((_) async => {'e1'});
      when(() => downloadManager.addTask(
            sourceId: any(named: 'sourceId'),
            mangaId: any(named: 'mangaId'),
            chapterId: any(named: 'chapterId'),
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          )).thenAnswer((_) async => true);

      final cubit = buildCubit();
      final count = await cubit.downloadUnread(manga);

      // e2 and e3 are unread among the 3 embedded chapters; e1 is read.
      expect(count, 2);
      verify(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'e2',
            mangaTitle: 'T',
            chapterTitle: 'E2',
          )).called(1);
      verify(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'e3',
            mangaTitle: 'T',
            chapterTitle: 'E3',
          )).called(1);
      verifyNever(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'e1',
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          ));
      // The pagination fallback must be skipped entirely since getMangaInfo
      // already returned a non-empty embedded chapter list.
      verifyNever(() => repository.getChapterList(any(), any(), any()));
    },
  );

  test('downloadUnread 在 getChapterList 抛出异常时不崩溃，返回0', () async {
    when(() => repository.getMangaInfo('s1', 'm1')).thenAnswer(
        (_) async => const MangaDetail(id: 'm1', sourceId: 's1', title: 'T', coverUrl: 'c'));
    when(() => repository.getChapterList('s1', 'm1', 1))
        .thenThrow(Exception('network error'));

    final cubit = buildCubit();
    final count = await cubit.downloadUnread(manga);

    expect(count, 0);
    verifyNever(() => downloadManager.addTask(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          mangaTitle: any(named: 'mangaTitle'),
          chapterTitle: any(named: 'chapterTitle'),
        ));
  });

  test('downloadUnread 在 getReadChapters 抛出异常时不崩溃，返回0', () async {
    when(() => repository.getMangaInfo('s1', 'm1'))
        .thenAnswer((_) async => emptyMangaDetail);
    when(() => repository.getChapterList('s1', 'm1', 1)).thenAnswer(
        (_) async => ChapterListResult(chapters: chapters, canLoadMore: false));
    when(() => historyStore.getReadChapters('s1', 'm1'))
        .thenThrow(Exception('storage error'));

    final cubit = buildCubit();
    final count = await cubit.downloadUnread(manga);

    expect(count, 0);
    verifyNever(() => downloadManager.addTask(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          mangaTitle: any(named: 'mangaTitle'),
          chapterTitle: any(named: 'chapterTitle'),
        ));
  });

  // Two mangas from different sources. mangaA's id deliberately contains an
  // underscore ('m_1') to stress-test the `key.split('_')` parsing in
  // `downloadSelected` — sourceId must come from `parts.first` and mangaId
  // from `parts.sublist(1).join('_')`, otherwise this manga would fail to
  // match against `state.favorites` and silently download nothing for it.
  const mangaA = MangaSummary(
    id: 'm_1',
    sourceId: 's1',
    title: 'MangaA',
    coverUrl: 'c',
  );
  const mangaB = MangaSummary(
    id: 'm2',
    sourceId: 's2',
    title: 'MangaB',
    coverUrl: 'c',
  );
  final chaptersA = [
    const ChapterItem(id: 'ca1', mangaId: 'm_1', title: 'A-Ch1'),
    const ChapterItem(id: 'ca2', mangaId: 'm_1', title: 'A-Ch2'),
  ];
  final chaptersB = [
    const ChapterItem(id: 'cb1', mangaId: 'm2', title: 'B-Ch1'),
  ];

  blocTest<HomeCubit, dynamic>(
    'downloadSelected 为所有选中漫画的未读章节调用 addTask（且正确解析含下划线的mangaId）',
    build: () {
      when(() => repository.getMangaInfo('s1', 'm_1'))
          .thenAnswer((_) async => emptyMangaDetail);
      when(() => repository.getMangaInfo('s2', 'm2'))
          .thenAnswer((_) async => emptyMangaDetail);
      when(() => repository.getChapterList('s1', 'm_1', 1)).thenAnswer(
          (_) async =>
              ChapterListResult(chapters: chaptersA, canLoadMore: false));
      when(() => repository.getChapterList('s2', 'm2', 1)).thenAnswer(
          (_) async =>
              ChapterListResult(chapters: chaptersB, canLoadMore: false));
      // mangaA: 'ca1' already read, 'ca2' unread.
      when(() => historyStore.getReadChapters('s1', 'm_1'))
          .thenAnswer((_) async => {'ca1'});
      // mangaB: nothing read yet, 'cb1' unread.
      when(() => historyStore.getReadChapters('s2', 'm2'))
          .thenAnswer((_) async => <String>{});
      when(() => downloadManager.addTask(
            sourceId: any(named: 'sourceId'),
            mangaId: any(named: 'mangaId'),
            chapterId: any(named: 'chapterId'),
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          )).thenAnswer((_) async => true);
      return buildCubit();
    },
    seed: () => const HomeState(
      favorites: [mangaA, mangaB],
      selectedKeys: {'s1_m_1', 's2_m2'},
    ),
    act: (cubit) => cubit.downloadSelected(),
    verify: (_) {
      // mangaA's unread chapter downloaded exactly once.
      verify(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm_1',
            chapterId: 'ca2',
            mangaTitle: 'MangaA',
            chapterTitle: 'A-Ch2',
          )).called(1);
      // mangaA's already-read chapter must never be downloaded.
      verifyNever(() => downloadManager.addTask(
            sourceId: 's1',
            mangaId: 'm_1',
            chapterId: 'ca1',
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          ));
      // mangaB's unread chapter downloaded exactly once — proves the second
      // selected manga is also processed, not just the first.
      verify(() => downloadManager.addTask(
            sourceId: 's2',
            mangaId: 'm2',
            chapterId: 'cb1',
            mangaTitle: 'MangaB',
            chapterTitle: 'B-Ch1',
          )).called(1);
    },
  );

  test('downloadSelected 返回所有选中漫画累加的未读章节总数', () async {
    when(() => favoritesStore.getAll())
        .thenAnswer((_) async => [mangaA, mangaB]);
    when(() => updateStore.getAllUpdated())
        .thenAnswer((_) async => <String>{});
    when(() => categoryStore.getAll()).thenAnswer((_) async => []);
    when(() => favoritesStore.getCategoryMap())
        .thenAnswer((_) async => <String, List<String>>{});
    when(() => repository.getMangaInfo('s1', 'm_1'))
        .thenAnswer((_) async => emptyMangaDetail);
    when(() => repository.getMangaInfo('s2', 'm2'))
        .thenAnswer((_) async => emptyMangaDetail);
    when(() => repository.getChapterList('s1', 'm_1', 1)).thenAnswer(
        (_) async =>
            ChapterListResult(chapters: chaptersA, canLoadMore: false));
    when(() => repository.getChapterList('s2', 'm2', 1)).thenAnswer(
        (_) async =>
            ChapterListResult(chapters: chaptersB, canLoadMore: false));
    // mangaA: 'ca1' already read, 'ca2' unread -> 1 chapter queued.
    when(() => historyStore.getReadChapters('s1', 'm_1'))
        .thenAnswer((_) async => {'ca1'});
    // mangaB: nothing read yet -> 'cb1' queued -> 1 chapter queued.
    when(() => historyStore.getReadChapters('s2', 'm2'))
        .thenAnswer((_) async => <String>{});
    when(() => downloadManager.addTask(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          mangaTitle: any(named: 'mangaTitle'),
          chapterTitle: any(named: 'chapterTitle'),
        )).thenAnswer((_) async => true);

    final cubit = buildCubit();
    await cubit.loadFavorites();
    // Select both manga via the public selection API rather than reaching
    // into Cubit.emit (protected) — mirrors how the UI actually drives this.
    cubit.enterSelectionMode('s1', 'm_1');
    cubit.toggleSelection('s2', 'm2');

    final total = await cubit.downloadSelected();

    expect(total, 2); // 1 (mangaA's ca2) + 1 (mangaB's cb1)
  });

  blocTest<HomeCubit, dynamic>(
    'downloadSelected 中一个漫画拉取章节失败时，不影响其它漫画继续下载',
    build: () {
      // mangaA's chapter fetch fails entirely.
      when(() => repository.getMangaInfo('s1', 'm_1'))
          .thenAnswer((_) async => emptyMangaDetail);
      when(() => repository.getMangaInfo('s2', 'm2'))
          .thenAnswer((_) async => emptyMangaDetail);
      when(() => repository.getChapterList('s1', 'm_1', 1))
          .thenThrow(Exception('network error'));
      when(() => repository.getChapterList('s2', 'm2', 1)).thenAnswer(
          (_) async =>
              ChapterListResult(chapters: chaptersB, canLoadMore: false));
      when(() => historyStore.getReadChapters('s2', 'm2'))
          .thenAnswer((_) async => <String>{});
      when(() => downloadManager.addTask(
            sourceId: any(named: 'sourceId'),
            mangaId: any(named: 'mangaId'),
            chapterId: any(named: 'chapterId'),
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          )).thenAnswer((_) async => true);
      return buildCubit();
    },
    seed: () => const HomeState(
      favorites: [mangaA, mangaB],
      selectedKeys: {'s1_m_1', 's2_m2'},
    ),
    act: (cubit) => cubit.downloadSelected(),
    verify: (_) {
      // mangaB must still be processed despite mangaA's failure.
      verify(() => downloadManager.addTask(
            sourceId: 's2',
            mangaId: 'm2',
            chapterId: 'cb1',
            mangaTitle: 'MangaB',
            chapterTitle: 'B-Ch1',
          )).called(1);
    },
  );
}
