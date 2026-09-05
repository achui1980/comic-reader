import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/detail/bloc/detail_cubit.dart';
import 'package:comic_reader/presentation/detail/bloc/detail_state.dart';

class MockMangaRepository extends Mock implements MangaRepository {}

class MockFavoritesStore extends Mock implements FavoritesStore {}

class MockReadingHistoryStore extends Mock implements ReadingHistoryStore {}

void main() {
  late MockMangaRepository mockRepository;
  late MockFavoritesStore mockFavoritesStore;
  late MockReadingHistoryStore mockHistoryStore;

  const sourceId = 's1';
  const mangaId = 'm1';

  ChapterItem chapter(String id) =>
      ChapterItem(id: id, mangaId: mangaId, title: 'Chapter $id');

  setUp(() {
    mockRepository = MockMangaRepository();
    mockFavoritesStore = MockFavoritesStore();
    mockHistoryStore = MockReadingHistoryStore();
  });

  DetailCubit build() => DetailCubit(
        repository: mockRepository,
        favoritesStore: mockFavoritesStore,
        historyStore: mockHistoryStore,
        sourceId: sourceId,
        mangaId: mangaId,
      );

  group('loadChapters', () {
    blocTest<DetailCubit, DetailState>(
      'sets chaptersError and resets pagination to retry page 1 when the '
      'very first page fails',
      build: build,
      act: (cubit) => cubit.loadChapters(),
      setUp: () {
        when(() => mockRepository.getChapterList(sourceId, mangaId, 1))
            .thenThrow(Exception('network down'));
      },
      expect: () => [
        // chaptersLoading: true, error cleared
        isA<DetailState>()
            .having((s) => s.chaptersLoading, 'chaptersLoading', true)
            .having((s) => s.chaptersError, 'chaptersError', isNull),
        // failure: error set, pagination reset so retry starts at page 1
        isA<DetailState>()
            .having((s) => s.chaptersLoading, 'chaptersLoading', false)
            .having((s) => s.chaptersError, 'chaptersError', isNotNull)
            .having((s) => s.canLoadMoreChapters, 'canLoadMoreChapters', true)
            .having((s) => s.chapterPage, 'chapterPage', 0)
            .having((s) => s.chapters, 'chapters', isEmpty),
      ],
    );

    blocTest<DetailCubit, DetailState>(
      'keeps already-fetched chapters and correct pagination when a later '
      'page fails mid-pagination',
      build: build,
      act: (cubit) => cubit.loadChapters(),
      setUp: () {
        when(() => mockRepository.getChapterList(sourceId, mangaId, 1))
            .thenAnswer((_) async => ChapterListResult(
                  chapters: [chapter('c1')],
                  canLoadMore: true,
                ));
        when(() => mockRepository.getChapterList(sourceId, mangaId, 2))
            .thenThrow(Exception('page 2 failed'));
      },
      expect: () => [
        // chaptersLoading: true, error cleared
        isA<DetailState>()
            .having((s) => s.chaptersLoading, 'chaptersLoading', true)
            .having((s) => s.chaptersError, 'chaptersError', isNull),
        // page 1 succeeded, emitted immediately
        isA<DetailState>()
            .having((s) => s.chapters.length, 'chapters.length', 1)
            .having((s) => s.chaptersLoading, 'chaptersLoading', true)
            .having((s) => s.canLoadMoreChapters, 'canLoadMoreChapters', true)
            .having((s) => s.chapterPage, 'chapterPage', 1),
        // page 2 failed: chapter 1 preserved, pagination state left as-is
        // so a retry continues from page 2, not from scratch
        isA<DetailState>()
            .having((s) => s.chapters.length, 'chapters.length', 1)
            .having((s) => s.chaptersLoading, 'chaptersLoading', false)
            .having((s) => s.chaptersError, 'chaptersError', isNotNull)
            .having((s) => s.canLoadMoreChapters, 'canLoadMoreChapters', true)
            .having((s) => s.chapterPage, 'chapterPage', 1),
      ],
    );

    blocTest<DetailCubit, DetailState>(
      'clears a previous chaptersError when called again',
      build: build,
      seed: () => const DetailState(chaptersError: 'previous failure'),
      act: (cubit) => cubit.loadChapters(),
      setUp: () {
        when(() => mockRepository.getChapterList(sourceId, mangaId, 1))
            .thenAnswer((_) async => const ChapterListResult(
                  chapters: [],
                  canLoadMore: false,
                ));
      },
      expect: () => [
        // loading starts, error cleared immediately
        isA<DetailState>()
            .having((s) => s.chaptersLoading, 'chaptersLoading', true)
            .having((s) => s.chaptersError, 'chaptersError', isNull),
        // page 1 emit and the final post-loop emit produce an identical
        // state here (canLoadMore is false from the start), so Cubit's
        // Equatable-based dedup collapses them into a single emission.
        isA<DetailState>()
            .having((s) => s.chaptersLoading, 'chaptersLoading', false)
            .having((s) => s.chaptersError, 'chaptersError', isNull),
      ],
    );
  });

  group('loadMoreChapters', () {
    blocTest<DetailCubit, DetailState>(
      'retries the failed page, clears chaptersError, and appends new '
      'chapters on success',
      build: build,
      seed: () => DetailState(
        chapters: [chapter('c1')],
        canLoadMoreChapters: true,
        chapterPage: 1,
        chaptersError: 'page 2 failed',
      ),
      act: (cubit) => cubit.loadMoreChapters(),
      setUp: () {
        when(() => mockRepository.getChapterList(sourceId, mangaId, 2))
            .thenAnswer((_) async => ChapterListResult(
                  chapters: [chapter('c2')],
                  canLoadMore: false,
                ));
      },
      expect: () => [
        // loading starts, error cleared immediately
        isA<DetailState>()
            .having((s) => s.chaptersLoading, 'chaptersLoading', true)
            .having((s) => s.chaptersError, 'chaptersError', isNull),
        // success: new chapter appended after the existing one
        isA<DetailState>()
            .having((s) => s.chapters.map((c) => c.id).toList(),
                'chapter ids', ['c1', 'c2'])
            .having((s) => s.chaptersLoading, 'chaptersLoading', false)
            .having((s) => s.chaptersError, 'chaptersError', isNull)
            .having((s) => s.canLoadMoreChapters, 'canLoadMoreChapters', false)
            .having((s) => s.chapterPage, 'chapterPage', 2),
      ],
      verify: (_) {
        verify(() => mockRepository.getChapterList(sourceId, mangaId, 2))
            .called(1);
      },
    );

    blocTest<DetailCubit, DetailState>(
      'sets chaptersError again and keeps existing chapters when the retry '
      'itself fails',
      build: build,
      seed: () => DetailState(
        chapters: [chapter('c1')],
        canLoadMoreChapters: true,
        chapterPage: 1,
      ),
      act: (cubit) => cubit.loadMoreChapters(),
      setUp: () {
        when(() => mockRepository.getChapterList(sourceId, mangaId, 2))
            .thenThrow(Exception('still down'));
      },
      expect: () => [
        isA<DetailState>()
            .having((s) => s.chaptersLoading, 'chaptersLoading', true)
            .having((s) => s.chaptersError, 'chaptersError', isNull),
        isA<DetailState>()
            .having((s) => s.chapters.length, 'chapters.length', 1)
            .having((s) => s.chaptersLoading, 'chaptersLoading', false)
            .having((s) => s.chaptersError, 'chaptersError', isNotNull)
            .having((s) => s.chapterPage, 'chapterPage', 1),
      ],
    );

    blocTest<DetailCubit, DetailState>(
      'does nothing when canLoadMoreChapters is false',
      build: build,
      seed: () => DetailState(
        chapters: [chapter('c1')],
        canLoadMoreChapters: false,
        chapterPage: 1,
      ),
      act: (cubit) => cubit.loadMoreChapters(),
      expect: () => [],
      verify: (_) {
        verifyNever(() => mockRepository.getChapterList(any(), any(), any()));
      },
    );
  });
}
