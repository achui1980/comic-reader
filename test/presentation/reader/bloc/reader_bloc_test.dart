import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/settings_store.dart' as settings;
import 'package:comic_reader/data/translation/models/page_translation.dart';
import 'package:comic_reader/data/translation/translation_pipeline.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _MockMangaRepository extends Mock implements MangaRepository {}

class _MockReadingHistoryStore extends Mock implements ReadingHistoryStore {}

class _MockSettingsStore extends Mock implements settings.SettingsStore {}

class _MockTranslationPipeline extends Mock implements TranslationPipeline {}

void main() {
  late _MockMangaRepository repository;
  late _MockReadingHistoryStore readingHistoryStore;
  late _MockSettingsStore settingsStore;
  late _MockTranslationPipeline translationPipeline;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const HistoryEntry(
      sourceId: '',
      mangaId: '',
      mangaTitle: '',
      coverUrl: '',
      chapterId: '',
      chapterTitle: '',
      page: 0,
      timestamp: '',
    ));
  });

  setUp(() {
    repository = _MockMangaRepository();
    readingHistoryStore = _MockReadingHistoryStore();
    settingsStore = _MockSettingsStore();
    translationPipeline = _MockTranslationPipeline();

    // ReaderBloc falls back to GetIt.instance<TranslationPipeline>() when no
    // translationPipeline is passed explicitly (see buildBloc() below), so
    // register the mock for every test regardless of which builder is used.
    if (GetIt.instance.isRegistered<TranslationPipeline>()) {
      GetIt.instance.unregister<TranslationPipeline>();
    }
    GetIt.instance.registerSingleton<TranslationPipeline>(translationPipeline);

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
    when(
      () => readingHistoryStore.addHistory(any()),
    ).thenAnswer((_) async {});
  });

  tearDown(() {
    if (GetIt.instance.isRegistered<TranslationPipeline>()) {
      GetIt.instance.unregister<TranslationPipeline>();
    }
  });

  ReaderBloc buildBloc() => ReaderBloc(
        repository: repository,
        readingHistoryStore: readingHistoryStore,
        settingsStore: settingsStore,
      );

  const samplePageTranslation = PageTranslation(
    sourceId: 'copy',
    mangaId: 'manga',
    chapterId: 'c1',
    pageIndex: 0,
    regions: [],
    translatedAt: 0,
  );

  // A minimal valid 1x1 transparent PNG, so `img.decodeImage()` in
  // ReaderBloc._drainTranslationQueue succeeds instead of throwing a
  // RangeError on an empty buffer.
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
    '42YAAAAASUVORK5CYII=',
  );

  Future<Uint8List> fakeLoadImageBytes({
    required ChapterImage image,
    String? sourceId,
    String? mangaId,
    String? chapterId,
    int? imageIndex,
  }) async =>
      onePixelPng;

  ReaderBloc buildBlocWithTranslation() => ReaderBloc(
        repository: repository,
        readingHistoryStore: readingHistoryStore,
        settingsStore: settingsStore,
        translationPipeline: translationPipeline,
        loadImageBytes: fakeLoadImageBytes,
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
          // _cleanErrorMessage strips the "Exception: " prefix.
          .having((s) => s.errorMessage, 'errorMessage', contains('boom')),
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

  group('Translation', () {
    const chapterOne = ChapterItem(id: 'c1', mangaId: 'manga', title: 'Ch 1');

    ReaderState seedState({List<ChapterImage>? images}) {
      return ReaderState(
        sourceId: 'copy',
        mangaId: 'manga',
        chapterId: chapterOne.id,
        chapterList: const [chapterOne],
        images: images ?? const [ChapterImage(url: 'a')],
      );
    }

    blocTest<ReaderBloc, ReaderState>(
      'enabling translation immediately queues the current page',
      build: () {
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).thenAnswer((_) async => samplePageTranslation);
        return buildBlocWithTranslation();
      },
      seed: seedState,
      act: (bloc) => bloc.add(const TranslateChapterToggled(enabled: true)),
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.translationEnabled, isTrue);
        expect(
          bloc.state.pageTranslations[0]?.status,
          PageTranslationStatus.done,
        );
        expect(
          bloc.state.pageTranslations[0]?.translation,
          samplePageTranslation,
        );
      },
    );

    blocTest<ReaderBloc, ReaderState>(
      'disabling translation clears queued-but-not-started pages without '
      'cancelling the in-flight one',
      build: () {
        final completer = Completer<PageTranslation>();
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).thenAnswer((_) => completer.future);
        addTearDown(() {
          if (!completer.isCompleted) completer.complete(samplePageTranslation);
        });
        return buildBlocWithTranslation();
      },
      seed: () => seedState(
        images: const [ChapterImage(url: 'a'), ChapterImage(url: 'b')],
      ),
      act: (bloc) async {
        bloc.add(const TranslateChapterToggled(enabled: true)); // page 0: loading, blocked
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TranslatePageRequested(pageIndex: 1)); // queued, not started
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TranslateChapterToggled(enabled: false));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(
          bloc.state.pageTranslations[0]?.status,
          PageTranslationStatus.loading,
        );
        expect(bloc.state.pageTranslations.containsKey(1), isFalse);
      },
    );
  });
}
