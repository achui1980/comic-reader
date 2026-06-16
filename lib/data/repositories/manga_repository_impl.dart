import 'dart:convert';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';

/// Implementation of MangaRepository using HTTP client and source plugins.
class MangaRepositoryImpl implements MangaRepository {
  final HttpClient _httpClient;
  final SourceRegistry _sourceRegistry;

  MangaRepositoryImpl({
    required HttpClient httpClient,
    required SourceRegistry sourceRegistry,
  })  : _httpClient = httpClient,
        _sourceRegistry = sourceRegistry;

  /// Merge source auth headers (cookies from CF bypass) into config
  /// and inject source metadata into extras for interceptors.
  FetchConfig _mergeHeaders(FetchConfig config, MangaSource source) {
    final extra = <String, dynamic>{
      'sourceId': source.id,
      'needsCloudflare': source.needsCloudflare,
      ...?config.extra,
    };
    final headers = <String, String>{
      ...?config.headers,
      ...source.extraHeaders,
    };
    return config.copyWith(headers: headers, extra: extra);
  }

  @override
  Future<List<MangaSummary>> getDiscovery(String sourceId, int page, Map<String, String> filters) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareDiscoveryFetch(page, filters);
    config = _mergeHeaders(config, source);
    final response = await _httpClient.execute(config);
    return source.parseDiscovery(response.data);
  }

  @override
  Future<List<MangaSummary>> searchManga(String sourceId, String keyword, int page, Map<String, String> filters) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareSearchFetch(keyword, page, filters);
    config = _mergeHeaders(config, source);
    final response = await _httpClient.execute(config);
    return source.parseSearch(response.data);
  }

  @override
  Future<MangaDetail> getMangaInfo(String sourceId, String mangaId) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareMangaInfoFetch(mangaId);
    config = _mergeHeaders(config, source);
    final response = await _httpClient.execute(config);
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
    config = _mergeHeaders(config, source);
    final response = await _httpClient.execute(config);
    return source.parseChapterList(response.data, mangaId);
  }

  @override
  Future<ChapterResult> getChapter(String sourceId, String mangaId, String chapterId, int page, {dynamic extra}) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareChapterFetch(mangaId, chapterId, page, extra: extra);
    config = _mergeHeaders(config, source);
    final response = await _httpClient.execute(config);
    var result = source.parseChapter(response.data, mangaId, chapterId, page);

    // Handle sources that return image page URLs needing resolution (e.g., E-Hentai)
    if (result.chapter.images.isEmpty && result.nextExtra != null) {
      final imagePageUrls = jsonDecode(result.nextExtra!) as List;
      final resolvedImages = <ChapterImage>[];
      for (final pageUrl in imagePageUrls) {
        try {
          final imgConfig = FetchConfig(url: pageUrl as String);
          final imgResponse = await _httpClient.execute(_mergeHeaders(imgConfig, source));
          final imgHtml = imgResponse.data as String;
          // Parse img#img src from the image page
          final srcMatch = RegExp(r'<img[^>]+id="img"[^>]+src="([^"]+)"').firstMatch(imgHtml);
          if (srcMatch != null) {
            resolvedImages.add(ChapterImage(url: srcMatch.group(1)!));
          }
        } catch (_) {
          // Skip failed image pages
        }
      }
      if (resolvedImages.isNotEmpty) {
        result = ChapterResult(
          chapter: Chapter(
            id: result.chapter.id,
            mangaId: result.chapter.mangaId,
            title: result.chapter.title,
            images: resolvedImages,
          ),
          canLoadMore: result.canLoadMore,
          nextPage: result.nextPage,
        );
      }
    }

    return result;
  }
}
