import 'package:flutter/foundation.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/hitomi.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'chapter_image_pipeline.dart';
import 'fetch_pipeline.dart';
import 'hitomi_enrichment.dart';
import 'wu55_chapter_decryptor.dart';

/// Implementation of MangaRepository using HTTP client and source plugins.
class MangaRepositoryImpl implements MangaRepository {
  final HttpClient _httpClient;
  final SourceRegistry _sourceRegistry;
  late final FetchPipeline _pipeline = FetchPipeline(_httpClient);
  late final Wu55ChapterDecryptor _wu55Decryptor = Wu55ChapterDecryptor(_httpClient, _pipeline);
  late final ChapterImagePipeline _chapterPipeline =
      ChapterImagePipeline(_httpClient, _pipeline, _wu55Decryptor);

  MangaRepositoryImpl({
    required HttpClient httpClient,
    required SourceRegistry sourceRegistry,
  })  : _httpClient = httpClient,
        _sourceRegistry = sourceRegistry;

  @override
  Future<List<MangaSummary>> getDiscovery(String sourceId, int page, Map<String, String> filters) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareDiscoveryFetch(page, filters);
    config = _pipeline.mergeHeaders(config, source);
    debugPrint('[getDiscovery] Fetching page=$page url=${config.url} params=${config.queryParameters}');
    final response = await _pipeline.executeWithFallback(
      config, source, () => source.prepareDiscoveryFetch(page, filters),
    );

    // Hitomi: nozomi returns only IDs; enrich with galleryblock HTML
    if (source is Hitomi) {
      return enrichHitomiResults(_httpClient, _pipeline, source, response.data);
    }

    final results = source.parseDiscovery(response.data);
    debugPrint('[getDiscovery] page=$page returned ${results.length} items${results.isNotEmpty ? ", first: ${results.first.id}" : ""}');
    return results;
  }

  @override
  Future<List<MangaSummary>> searchManga(String sourceId, String keyword, int page, Map<String, String> filters) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareSearchFetch(keyword, page, filters);
    config = _pipeline.mergeHeaders(config, source);
    final response = await _pipeline.executeWithFallback(
      config, source, () => source.prepareSearchFetch(keyword, page, filters),
    );

    // Hitomi: nozomi returns only IDs; enrich with galleryblock HTML
    if (source is Hitomi) {
      return enrichHitomiResults(_httpClient, _pipeline, source, response.data);
    }

    return source.parseSearch(response.data);
  }

  @override
  Future<MangaDetail> getMangaInfo(String sourceId, String mangaId) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    // Hitomi: ensure gg.js is loaded before parsing manga info (needed for cover URL)
    if (source is Hitomi && source.needsGgRefresh) {
      try {
        var ggConfig = source.prepareGgFetch();
        ggConfig = _pipeline.mergeHeaders(ggConfig, source);
        final ggResponse = await _httpClient.execute(ggConfig);
        source.parseGgResponse(ggResponse.data?.toString() ?? '');
      } catch (e) {
        debugPrint('[getMangaInfo] Hitomi: Failed to fetch gg.js: $e');
      }
    }

    var config = source.prepareMangaInfoFetch(mangaId);
    config = _pipeline.mergeHeaders(config, source);
    final response = await _pipeline.executeWithFallback(
      config, source, () => source.prepareMangaInfoFetch(mangaId),
    );
    return source.parseMangaInfo(response.data, mangaId);
  }

  @override
  Future<ChapterListResult> getChapterList(String sourceId, String mangaId, int page) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareChapterListFetch(mangaId, page);
    if (config == null) {
      return const ChapterListResult(chapters: []);
    }
    config = _pipeline.mergeHeaders(config, source);
    final response = await _pipeline.executeWithFallback(
      config, source, () => source.prepareChapterListFetch(mangaId, page)!,
    );
    return source.parseChapterList(response.data, mangaId);
  }

  @override
  Future<ChapterResult> getChapter(String sourceId, String mangaId, String chapterId, int page, {dynamic extra}) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');
    return _chapterPipeline.getChapter(mangaId, chapterId, page, source, extra: extra);
  }

  @override
  Stream<ChapterResult> getChapterStream(
    String sourceId,
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) async* {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) {
      throw Exception('Source not found: $sourceId');
    }
    yield* _chapterPipeline.getChapterStream(mangaId, chapterId, page, source, extra: extra);
  }
}
