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
}
