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

  blocTest<HomeCubit, dynamic>(
    'downloadUnread 只为未读章节调用 addTask',
    build: () {
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
          )).thenAnswer((_) async {});
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
          )).thenAnswer((_) async {});
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
}
