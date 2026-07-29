import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/repositories/manga_repository_impl.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class MockHttpClient extends Mock implements HttpClient {}

/// Minimal concrete source used to exercise the repository pipeline without
/// touching the network. It is neither JmComic nor Wu55Comic, so the
/// repository takes the plain `_httpClient.execute(config)` path (single call).
class _FakeSource extends MangaSource {
  _FakeSource({
    this.fakeDefaultHeaders,
    this.fakeNeedsCloudflare = false,
    this.fakeUsesWebViewFetch = false,
    this.fakeCloudflareUrl,
  });

  final Map<String, String>? fakeDefaultHeaders;
  final bool fakeNeedsCloudflare;
  final bool fakeUsesWebViewFetch;
  final String? fakeCloudflareUrl;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake Source';
  @override
  String get shortName => 'FK';
  @override
  String? get description => 'fake source for tests';
  @override
  double get score => 1.0;
  @override
  String? get href => 'https://fake.test';

  @override
  Map<String, String>? get defaultHeaders => fakeDefaultHeaders;
  @override
  bool get needsCloudflare => fakeNeedsCloudflare;
  @override
  bool get usesWebViewFetch => fakeUsesWebViewFetch;
  @override
  String? get cloudflareUrl => fakeCloudflareUrl;

  @override
  FetchConfig prepareSearchFetch(
    String keyword,
    int page,
    Map<String, String> filters,
  ) {
    return FetchConfig(
      url: 'https://fake.test/search?q=$keyword&page=$page',
      headers: const {'X-Config-Header': 'from-config'},
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return const [
      MangaSummary(
        id: 'm1',
        sourceId: 'fake',
        title: 'Fake Manga',
        coverUrl: 'https://fake.test/cover.jpg',
      ),
    ];
  }

  // Remaining prepare*/parse* pairs are unused in these tests.
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
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) =>
      throw UnimplementedError();
  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) =>
      throw UnimplementedError();
}

Response<dynamic> _okResponse(dynamic data) => Response<dynamic>(
      requestOptions: RequestOptions(path: ''),
      data: data,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const FetchConfig(url: ''));
  });

  late MockHttpClient httpClient;
  late SourceRegistry registry;

  setUp(() {
    httpClient = MockHttpClient();
    registry = SourceRegistry();
  });

  MangaRepositoryImpl buildRepo() =>
      MangaRepositoryImpl(httpClient: httpClient, sourceRegistry: registry);

  group('searchManga dispatch', () {
    test('returns parseSearch result and calls execute exactly once',
        () async {
      registry.register(_FakeSource());
      when(() => httpClient.execute(any()))
          .thenAnswer((_) async => _okResponse('<html/>'));

      final repo = buildRepo();
      final results = await repo.searchManga('fake', 'naruto', 1, {});

      expect(results, hasLength(1));
      expect(results.first.id, 'm1');
      expect(results.first.sourceId, 'fake');
      verify(() => httpClient.execute(any())).called(1);
    });

    test('throws when source is not found', () async {
      final repo = buildRepo();
      expect(
        () => repo.searchManga('does-not-exist', 'x', 1, {}),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('_mergeHeaders injection (verified via captured FetchConfig)', () {
    test('injects sourceId + needsCloudflare and merges headers', () async {
      registry.register(
        _FakeSource(
          fakeDefaultHeaders: const {'X-Default': 'from-source'},
          fakeNeedsCloudflare: true,
        ),
      );
      when(() => httpClient.execute(any()))
          .thenAnswer((_) async => _okResponse('<html/>'));

      final repo = buildRepo();
      await repo.searchManga('fake', 'q', 1, {});

      final captured =
          verify(() => httpClient.execute(captureAny())).captured.single
              as FetchConfig;

      expect(captured.extra?['sourceId'], 'fake');
      expect(captured.extra?['needsCloudflare'], true);
      // usesWebViewFetch is false here → no webview keys injected.
      expect(captured.extra?.containsKey('useWebViewFetch'), false);
      // source.defaultHeaders and config.headers both present.
      expect(captured.headers?['X-Default'], 'from-source');
      expect(captured.headers?['X-Config-Header'], 'from-config');
    });

    test('injects webview-fetch extras when usesWebViewFetch + cloudflareUrl',
        () async {
      registry.register(
        _FakeSource(
          fakeUsesWebViewFetch: true,
          fakeCloudflareUrl: 'https://fake.test/cf',
        ),
      );
      when(() => httpClient.execute(any()))
          .thenAnswer((_) async => _okResponse('<html/>'));

      final repo = buildRepo();
      await repo.searchManga('fake', 'q', 1, {});

      final captured =
          verify(() => httpClient.execute(captureAny())).captured.single
              as FetchConfig;

      expect(captured.extra?['useWebViewFetch'], true);
      expect(captured.extra?['cloudflareUrl'], 'https://fake.test/cf');
    });
  });
}
