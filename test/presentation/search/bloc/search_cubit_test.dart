import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/search/bloc/search_cubit.dart';
import 'package:comic_reader/presentation/search/bloc/search_state.dart';

class MockMangaRepository extends Mock implements MangaRepository {}

/// Minimal source used only for its identity metadata in the registry.
/// The cubit never calls prepare*/parse* on it (the repository is mocked),
/// so those throw.
class _FakeSource extends MangaSource {
  _FakeSource({
    required this.fakeId,
    this.fakeIsAdult = false,
    this.fakeFirstPage = 1,
  });

  final String fakeId;
  final bool fakeIsAdult;
  final int fakeFirstPage;

  @override
  String get id => fakeId;
  @override
  String get name => 'Source $fakeId';
  @override
  String get shortName => fakeId;
  @override
  String? get description => 'fake $fakeId';
  @override
  double get score => 1.0;
  @override
  String? get href => 'https://$fakeId.test';
  @override
  bool get isAdult => fakeIsAdult;
  @override
  int get firstPage => fakeFirstPage;

  @override
  FetchConfig prepareSearchFetch(
          String keyword, int page, Map<String, String> filters) =>
      throw UnimplementedError();
  @override
  List<MangaSummary> parseSearch(dynamic response) =>
      throw UnimplementedError();
  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) =>
      throw UnimplementedError();
  @override
  List<MangaSummary> parseDiscovery(dynamic response) =>
      throw UnimplementedError();
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) =>
      throw UnimplementedError();
  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) =>
      throw UnimplementedError();
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) =>
      throw UnimplementedError();
  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) =>
      throw UnimplementedError();
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
          {dynamic extra}) =>
      throw UnimplementedError();
  @override
  ChapterResult parseChapter(
          dynamic response, String mangaId, String chapterId, int page) =>
      throw UnimplementedError();
}

MangaSummary _summary(String id, String sourceId, String title,
        {String author = ''}) =>
    MangaSummary(
      id: id,
      sourceId: sourceId,
      title: title,
      coverUrl: 'https://$sourceId.test/$id.jpg',
      author: author,
    );

void main() {
  late MockMangaRepository repo;
  late SourceRegistry registry;

  setUp(() {
    repo = MockMangaRepository();
    registry = SourceRegistry();
  });

  SearchCubit buildCubit() =>
      SearchCubit(repository: repo, registry: registry);

  group('searchAll fan-out', () {
    test('empty keyword is a no-op', () async {
      registry.register(_FakeSource(fakeId: 'a'));
      final cubit = buildCubit();
      await cubit.searchAll('   ');
      expect(cubit.state.status, SearchStatus.initial);
      expect(cubit.state.slices, isEmpty);
      verifyNever(() => repo.searchManga(any(), any(), any(), any()));
    });

    test('errors when there are no enabled sources', () async {
      final cubit = buildCubit();
      await cubit.searchAll('naruto');
      expect(cubit.state.status, SearchStatus.error);
      expect(cubit.state.aggregateMode, isTrue);
      expect(cubit.state.slices, isEmpty);
    });

    test('fans out to every enabled source and populates a slice each',
        () async {
      registry.register(_FakeSource(fakeId: 'a'));
      registry.register(_FakeSource(fakeId: 'b'));
      when(() => repo.searchManga('a', 'q', 1, {}))
          .thenAnswer((_) async => [_summary('a1', 'a', 'Alpha')]);
      when(() => repo.searchManga('b', 'q', 1, {}))
          .thenAnswer((_) async => [_summary('b1', 'b', 'Beta')]);

      final cubit = buildCubit();
      await cubit.searchAll('q');

      expect(cubit.state.aggregateMode, isTrue);
      expect(cubit.state.status, SearchStatus.loaded);
      expect(cubit.state.slices.keys, containsAll(<String>['a', 'b']));
      expect(cubit.state.slices['a']!.status, SearchStatus.loaded);
      expect(cubit.state.slices['a']!.results.single.id, 'a1');
      expect(cubit.state.slices['b']!.results.single.id, 'b1');
      verify(() => repo.searchManga('a', 'q', 1, {})).called(1);
      verify(() => repo.searchManga('b', 'q', 1, {})).called(1);
    });

    test('respects per-source firstPage', () async {
      registry.register(_FakeSource(fakeId: 'a', fakeFirstPage: 0));
      when(() => repo.searchManga('a', 'q', 0, {}))
          .thenAnswer((_) async => [_summary('a1', 'a', 'Alpha')]);

      final cubit = buildCubit();
      await cubit.searchAll('q');

      expect(cubit.state.slices['a']!.currentPage, 0);
      verify(() => repo.searchManga('a', 'q', 0, {})).called(1);
    });
  });

  group('single-source failure does not block others', () {
    test('one source throwing marks only its slice as error', () async {
      registry.register(_FakeSource(fakeId: 'a'));
      registry.register(_FakeSource(fakeId: 'b'));
      when(() => repo.searchManga('a', 'q', 1, {}))
          .thenThrow(Exception('boom'));
      when(() => repo.searchManga('b', 'q', 1, {}))
          .thenAnswer((_) async => [_summary('b1', 'b', 'Beta')]);

      final cubit = buildCubit();
      await cubit.searchAll('q');

      // Overall still settles as loaded.
      expect(cubit.state.status, SearchStatus.loaded);
      expect(cubit.state.slices['a']!.status, SearchStatus.error);
      expect(cubit.state.slices['a']!.errorMessage, contains('boom'));
      expect(cubit.state.slices['a']!.hasMore, isFalse);
      // The healthy source is unaffected.
      expect(cubit.state.slices['b']!.status, SearchStatus.loaded);
      expect(cubit.state.slices['b']!.results.single.id, 'b1');
    });

    test('retrySource re-runs a failed slice', () async {
      registry.register(_FakeSource(fakeId: 'a'));
      var call = 0;
      when(() => repo.searchManga('a', 'q', 1, {})).thenAnswer((_) async {
        call++;
        if (call == 1) throw Exception('boom');
        return [_summary('a1', 'a', 'Alpha')];
      });

      final cubit = buildCubit();
      await cubit.searchAll('q');
      expect(cubit.state.slices['a']!.status, SearchStatus.error);

      await cubit.retrySource('a');
      expect(cubit.state.slices['a']!.status, SearchStatus.loaded);
      expect(cubit.state.slices['a']!.results.single.id, 'a1');
      expect(cubit.state.slices['a']!.errorMessage, isNull);
    });
  });

  group('dedupedAggregatedResults', () {
    test('collapses same work surfaced by multiple sources', () async {
      registry.register(_FakeSource(fakeId: 'a'));
      registry.register(_FakeSource(fakeId: 'b'));
      // Same normalized title (full-width vs half-width + case) across sources.
      when(() => repo.searchManga('a', 'q', 1, {})).thenAnswer(
          (_) async => [_summary('a1', 'a', 'ＯＮＥ ＰＩＥＣＥ')]);
      when(() => repo.searchManga('b', 'q', 1, {}))
          .thenAnswer((_) async => [_summary('b1', 'b', 'one piece')]);

      final cubit = buildCubit();
      await cubit.searchAll('q');

      final deduped = cubit.dedupedAggregatedResults;
      expect(deduped, hasLength(1));
      // First source in enabled order (a) wins.
      expect(deduped.single.sourceId, 'a');
    });

    test('keeps distinct works from different sources', () async {
      registry.register(_FakeSource(fakeId: 'a'));
      registry.register(_FakeSource(fakeId: 'b'));
      when(() => repo.searchManga('a', 'q', 1, {}))
          .thenAnswer((_) async => [_summary('a1', 'a', 'Alpha')]);
      when(() => repo.searchManga('b', 'q', 1, {}))
          .thenAnswer((_) async => [_summary('b1', 'b', 'Beta')]);

      final cubit = buildCubit();
      await cubit.searchAll('q');

      expect(cubit.dedupedAggregatedResults, hasLength(2));
    });

    test('same title but different author are NOT collapsed', () async {
      registry.register(_FakeSource(fakeId: 'a'));
      registry.register(_FakeSource(fakeId: 'b'));
      when(() => repo.searchManga('a', 'q', 1, {})).thenAnswer(
          (_) async => [_summary('a1', 'a', 'Title', author: 'Author X')]);
      when(() => repo.searchManga('b', 'q', 1, {})).thenAnswer(
          (_) async => [_summary('b1', 'b', 'Title', author: 'Author Y')]);

      final cubit = buildCubit();
      await cubit.searchAll('q');

      expect(cubit.dedupedAggregatedResults, hasLength(2));
    });
  });

  group('loadMoreSource', () {
    test('appends next page results for a single slice', () async {
      registry.register(_FakeSource(fakeId: 'a'));
      when(() => repo.searchManga('a', 'q', 1, {}))
          .thenAnswer((_) async => [_summary('a1', 'a', 'One')]);
      when(() => repo.searchManga('a', 'q', 2, {}))
          .thenAnswer((_) async => [_summary('a2', 'a', 'Two')]);

      final cubit = buildCubit();
      await cubit.searchAll('q');
      await cubit.loadMoreSource('a');

      final slice = cubit.state.slices['a']!;
      expect(slice.results.map((m) => m.id), ['a1', 'a2']);
      expect(slice.currentPage, 2);
      expect(slice.hasMore, isTrue);
    });

    test('duplicate next page stops pagination (hasMore=false)', () async {
      registry.register(_FakeSource(fakeId: 'a'));
      when(() => repo.searchManga('a', 'q', 1, {}))
          .thenAnswer((_) async => [_summary('a1', 'a', 'One')]);
      // Server returns the same item again → treated as no new content.
      when(() => repo.searchManga('a', 'q', 2, {}))
          .thenAnswer((_) async => [_summary('a1', 'a', 'One')]);

      final cubit = buildCubit();
      await cubit.searchAll('q');
      await cubit.loadMoreSource('a');

      final slice = cubit.state.slices['a']!;
      expect(slice.results, hasLength(1));
      expect(slice.hasMore, isFalse);
    });
  });

  group('adult gating via registry.enabled', () {
    test('adult source is excluded until unlocked', () async {
      registry.register(_FakeSource(fakeId: 'safe'));
      registry.register(_FakeSource(fakeId: 'adult', fakeIsAdult: true));
      when(() => repo.searchManga(any(), any(), any(), any()))
          .thenAnswer((_) async => const []);

      final cubit = buildCubit();
      await cubit.searchAll('q');

      // Locked: only the safe source gets a slice.
      expect(cubit.state.slices.keys, ['safe']);
      verifyNever(() => repo.searchManga('adult', any(), any(), any()));
    });

    test('adult source included once unlocked', () async {
      registry.register(_FakeSource(fakeId: 'safe'));
      registry.register(_FakeSource(fakeId: 'adult', fakeIsAdult: true));
      registry.setAdultUnlocked(true);
      when(() => repo.searchManga(any(), any(), any(), any()))
          .thenAnswer((_) async => const []);

      final cubit = buildCubit();
      await cubit.searchAll('q');

      expect(cubit.state.slices.keys, containsAll(<String>['safe', 'adult']));
    });
  });
}
