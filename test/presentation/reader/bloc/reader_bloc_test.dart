import 'package:bloc_test/bloc_test.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/settings_store.dart' as settings;
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
}
