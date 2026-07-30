import 'package:bloc_test/bloc_test.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/settings_store.dart' as settings;
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMangaRepository extends Mock implements MangaRepository {}

class _MockReadingHistoryStore extends Mock implements ReadingHistoryStore {}

class _MockSettingsStore extends Mock implements settings.SettingsStore {}

void main() {
  late _MockMangaRepository repository;
  late _MockReadingHistoryStore readingHistoryStore;
  late _MockSettingsStore settingsStore;

  setUp(() {
    repository = _MockMangaRepository();
    readingHistoryStore = _MockReadingHistoryStore();
    settingsStore = _MockSettingsStore();

    when(() => settingsStore.load()).thenAnswer(
      (_) async => const settings.AppSettings(
        layoutMode: settings.LayoutMode.horizontal,
        readingDirection: settings.ReadingDirection.ltr,
      ),
    );
    when(
      () => readingHistoryStore.markChapterRead(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => readingHistoryStore.saveProgress(any(), any(), any(), any()),
    ).thenAnswer((_) async {});
  });

  ReaderBloc buildBloc() => ReaderBloc(
        repository: repository,
        readingHistoryStore: readingHistoryStore,
        settingsStore: settingsStore,
      );

  blocTest<ReaderBloc, ReaderState>(
    'emits error when chapter stream errors before first batch',
    build: () {
      when(
        () => repository.getChapterStream('copy', 'manga', 'chapter', 1),
      ).thenAnswer((_) => Stream.error(Exception('boom')));
      return buildBloc();
    },
    act: (bloc) => bloc.add(
      const LoadChapter(sourceId: 'copy', mangaId: 'manga', chapterId: 'chapter'),
    ),
    skip: 1,
    wait: const Duration(milliseconds: 10),
    expect: () => [
      isA<ReaderState>().having((s) => s.status, 'status', ReaderStatus.loading),
      isA<ReaderState>()
          .having((s) => s.status, 'status', ReaderStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', contains('Exception: boom')),
    ],
  );

  blocTest<ReaderBloc, ReaderState>(
    'emits error when chapter stream completes before first batch',
    build: () {
      when(
        () => repository.getChapterStream('copy', 'manga', 'chapter', 1),
      ).thenAnswer((_) => const Stream.empty());
      return buildBloc();
    },
    act: (bloc) => bloc.add(
      const LoadChapter(sourceId: 'copy', mangaId: 'manga', chapterId: 'chapter'),
    ),
    skip: 1,
    wait: const Duration(milliseconds: 10),
    expect: () => [
      isA<ReaderState>().having((s) => s.status, 'status', ReaderStatus.loading),
      isA<ReaderState>()
          .having((s) => s.status, 'status', ReaderStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', '未能加载章节内容'),
    ],
  );

  group('PrefetchNextChapter', () {
    const chapterOne = ChapterItem(id: 'c1', mangaId: 'manga', title: 'Ch 1');
    const chapterTwo = ChapterItem(id: 'c2', mangaId: 'manga', title: 'Ch 2');

    ReaderState seedState({
      List<ChapterItem> chapterList = const [chapterOne],
      List<ChapterImage> images = const [],
    }) {
      return ReaderState(
        sourceId: 'copy',
        mangaId: 'manga',
        chapterId: chapterOne.id,
        chapterList: chapterList,
        images: images,
      );
    }

    void stubNextChapterFetch() {
      when(() => repository.getChapter('copy', 'manga', 'c2', 1)).thenAnswer(
        (_) async => const ChapterResult(
          chapter: Chapter(
            id: 'c2',
            mangaId: 'manga',
            title: 'Ch 2',
            images: [],
          ),
        ),
      );
    }

    blocTest<ReaderBloc, ReaderState>(
      'does not fetch when there is no next chapter to prefetch',
      build: buildBloc,
      seed: () => seedState(chapterList: const [chapterOne]),
      act: (bloc) => bloc.add(const PrefetchNextChapter()),
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verifyNever(() => repository.getChapter(any(), any(), any(), any()));
      },
    );

    blocTest<ReaderBloc, ReaderState>(
      'fetches the next chapter once when one is available',
      build: () {
        stubNextChapterFetch();
        return buildBloc();
      },
      seed: () => seedState(chapterList: const [chapterOne, chapterTwo]),
      act: (bloc) => bloc.add(const PrefetchNextChapter()),
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verify(() => repository.getChapter('copy', 'manga', 'c2', 1))
            .called(1);
      },
    );

    blocTest<ReaderBloc, ReaderState>(
      'does not refetch the same chapter twice',
      build: () {
        stubNextChapterFetch();
        return buildBloc();
      },
      seed: () => seedState(chapterList: const [chapterOne, chapterTwo]),
      act: (bloc) {
        bloc.add(const PrefetchNextChapter());
        bloc.add(const PrefetchNextChapter());
      },
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verify(() => repository.getChapter('copy', 'manga', 'c2', 1))
            .called(1);
      },
    );

    blocTest<ReaderBloc, ReaderState>(
      'PageChanged near the end of the chapter triggers a prefetch',
      build: () {
        stubNextChapterFetch();
        return buildBloc();
      },
      seed: () => seedState(
        chapterList: const [chapterOne, chapterTwo],
        images: const [
          ChapterImage(url: 'a'),
          ChapterImage(url: 'b'),
          ChapterImage(url: 'c'),
        ],
      ),
      act: (bloc) => bloc.add(const PageChanged(1)),
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verify(() => repository.getChapter('copy', 'manga', 'c2', 1))
            .called(1);
      },
    );

    blocTest<ReaderBloc, ReaderState>(
      'PageChanged far from the end of the chapter does not trigger a prefetch',
      build: buildBloc,
      seed: () => seedState(
        chapterList: const [chapterOne, chapterTwo],
        images: const [
          ChapterImage(url: 'a'),
          ChapterImage(url: 'b'),
          ChapterImage(url: 'c'),
        ],
      ),
      act: (bloc) => bloc.add(const PageChanged(0)),
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verifyNever(() => repository.getChapter(any(), any(), any(), any()));
      },
    );
  });
}
