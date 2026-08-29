import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/data/local/category_store.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/local/library_update_service.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/home/home_screen.dart';

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

  // Empty coverUrl avoids CachedNetworkImage attempting a real network
  // fetch during the widget test (no network access in the test sandbox).
  const mangaA = MangaSummary(id: 'mA', sourceId: 'sA', title: 'Manga A', coverUrl: '');
  const mangaB = MangaSummary(id: 'mB', sourceId: 'sB', title: 'Manga B', coverUrl: '');

  setUp(() async {
    favoritesStore = MockFavoritesStore();
    updateStore = MockUpdateStore();
    categoryStore = MockCategoryStore();
    libraryUpdateService = MockLibraryUpdateService();
    historyStore = MockReadingHistoryStore();
    downloadManager = MockDownloadManager();
    repository = MockMangaRepository();

    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<FavoritesStore>(favoritesStore);
    GetIt.instance.registerSingleton<UpdateStore>(updateStore);
    GetIt.instance.registerSingleton<CategoryStore>(categoryStore);
    GetIt.instance
        .registerSingleton<LibraryUpdateService>(libraryUpdateService);
    GetIt.instance.registerSingleton<MangaRepository>(repository);
    GetIt.instance.registerSingleton<ReadingHistoryStore>(historyStore);
    GetIt.instance.registerSingleton<DownloadManager>(downloadManager);
    // Real (unregistered) registry is fine: `.get(sourceId)` just returns
    // null, which _buildMangaCard already handles (no source name shown).
    GetIt.instance.registerSingleton<SourceRegistry>(SourceRegistry());

    when(() => favoritesStore.getAll())
        .thenAnswer((_) async => [mangaA, mangaB]);
    when(() => favoritesStore.getCategoryMap())
        .thenAnswer((_) async => <String, List<String>>{});
    when(() => favoritesStore.notifier).thenReturn(ValueNotifier<int>(0));
    when(() => updateStore.getAllUpdated())
        .thenAnswer((_) async => <String>{});
    when(() => categoryStore.getAll()).thenAnswer((_) async => <Category>[]);
    when(() => downloadManager.activeCount).thenReturn(0);
  });

  /// Pumps [HomeScreen] and lets the initial async `loadFavorites()` (fired
  /// from `BlocProvider.create`) resolve. Deliberately avoids
  /// `pumpAndSettle`: cover images use `CachedNetworkImage`, and settling
  /// could hang waiting on its (mocked-offline) network attempt.
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Finder downloadSelectedButton() => find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == '下载所选',
      );

  testWidgets(
      '长按选中一部漫画后，"下载所选"按钮可用；点击后调用 downloadSelected 并显示准确的 SnackBar 文案',
      (tester) async {
    // The selected manga (sA/mA) has one unread chapter -> downloadSelected
    // should queue exactly 1 chapter, and the SnackBar must reflect that
    // real count instead of a generic "done" message.
    final chapters = [
      const ChapterItem(id: 'c1', mangaId: 'mA', title: 'Ch1'),
    ];
    when(() => repository.getChapterList('sA', 'mA', 1)).thenAnswer(
        (_) async => ChapterListResult(chapters: chapters, canLoadMore: false));
    when(() => historyStore.getReadChapters('sA', 'mA'))
        .thenAnswer((_) async => <String>{});
    when(() => downloadManager.addTask(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          mangaTitle: any(named: 'mangaTitle'),
          chapterTitle: any(named: 'chapterTitle'),
        )).thenAnswer((_) async {});

    await pumpHome(tester);

    await tester.longPress(find.text('Manga A'));
    await tester.pump();

    expect(find.text('已选 1 项'), findsOneWidget);
    final button = tester.widget<IconButton>(downloadSelectedButton());
    expect(button.onPressed, isNotNull);

    await tester.tap(downloadSelectedButton());
    // Flush the awaited downloadSelected() -> downloadUnread() chain plus
    // the SnackBar's entrance animation.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    verify(() => downloadManager.addTask(
          sourceId: 'sA',
          mangaId: 'mA',
          chapterId: 'c1',
          mangaTitle: 'Manga A',
          chapterTitle: 'Ch1',
        )).called(1);
    expect(find.text('已加入下载队列（共1章）'), findsOneWidget);
  });

  testWidgets('未选中任何漫画时（切换到空分类后点击全选），"下载所选"按钮禁用', (tester) async {
    // A category with zero matching manga: after entering selection mode,
    // switching to it and tapping "全选" (selectAll) sets `selectedKeys` to
    // an empty set while `isSelecting` stays true — the one reachable path
    // to "selecting with nothing selected" via the real production code
    // (see HomeCubit.selectAll / toggleSelection).
    when(() => categoryStore.getAll()).thenAnswer(
        (_) async => const [Category(id: 'c1', name: 'Empty', order: 0)]);

    await pumpHome(tester);

    await tester.longPress(find.text('Manga A'));
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.text('Empty'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();

    expect(find.text('已选 0 项'), findsOneWidget);
    final button = tester.widget<IconButton>(downloadSelectedButton());
    expect(button.onPressed, isNull);
  });
}
