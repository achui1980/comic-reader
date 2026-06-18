import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/jm_comic.dart';
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
      ...?source.defaultHeaders,
      ...?config.headers,
      ...source.extraHeaders,
    };
    return config.copyWith(headers: headers, extra: extra);
  }

  /// Execute a request with domain fallback for JMComic.
  /// If request fails with a network/timeout error, switches to next domain and retries.
  Future<Response> _executeWithFallback(
    FetchConfig config,
    MangaSource source,
    FetchConfig Function() rebuildConfig,
  ) async {
    if (source is! JmComic) {
      return _httpClient.execute(config);
    }

    final jmSource = source;
    Object? lastError;

    for (int attempt = 0; attempt <= jmSource.maxDomainRetries; attempt++) {
      try {
        final effectiveConfig = attempt == 0 ? config : _mergeHeaders(rebuildConfig(), source);
        return await _httpClient.execute(effectiveConfig);
      } on DioException catch (e) {
        lastError = e;
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          debugPrint('[JMC Fallback] Domain failed (${e.type}), switching to next domain...');
          jmSource.switchToNextDomain();
          continue;
        }
        // Non-timeout errors (e.g., 403) — also try next domain
        if (e.response?.statusCode == 403 || e.response?.statusCode == 502 || e.response?.statusCode == 503) {
          debugPrint('[JMC Fallback] HTTP ${e.response?.statusCode}, switching domain...');
          jmSource.switchToNextDomain();
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('All JMC domains exhausted');
  }

  @override
  Future<List<MangaSummary>> getDiscovery(String sourceId, int page, Map<String, String> filters) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareDiscoveryFetch(page, filters);
    config = _mergeHeaders(config, source);
    debugPrint('[getDiscovery] Fetching page=$page url=${config.url} params=${config.queryParameters}');
    final response = await _executeWithFallback(
      config, source, () => source.prepareDiscoveryFetch(page, filters),
    );
    final results = source.parseDiscovery(response.data);
    debugPrint('[getDiscovery] page=$page returned ${results.length} items${results.isNotEmpty ? ", first: ${results.first.id}" : ""}');
    return results;
  }

  @override
  Future<List<MangaSummary>> searchManga(String sourceId, String keyword, int page, Map<String, String> filters) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareSearchFetch(keyword, page, filters);
    config = _mergeHeaders(config, source);
    final response = await _executeWithFallback(
      config, source, () => source.prepareSearchFetch(keyword, page, filters),
    );
    return source.parseSearch(response.data);
  }

  @override
  Future<MangaDetail> getMangaInfo(String sourceId, String mangaId) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    var config = source.prepareMangaInfoFetch(mangaId);
    config = _mergeHeaders(config, source);
    final response = await _executeWithFallback(
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
    config = _mergeHeaders(config, source);
    final response = await _executeWithFallback(
      config, source, () => source.prepareChapterListFetch(mangaId, page)!,
    );
    return source.parseChapterList(response.data, mangaId);
  }

  @override
  Future<ChapterResult> getChapter(String sourceId, String mangaId, String chapterId, int page, {dynamic extra}) async {
    final source = _sourceRegistry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    // Use source.firstPage for initial page (E-Hentai is 0-based)
    final effectivePage = page == 1 ? source.firstPage : page;

    // JMC: fetch scramble_id before loading chapter to determine correct unscramble threshold
    if (source is JmComic) {
      try {
        var scrambleConfig = source.prepareScrambleFetch(chapterId);
        scrambleConfig = _mergeHeaders(scrambleConfig, source);
        debugPrint('[getChapter] JMC: Fetching scramble_id for chapter $chapterId');
        final scrambleResponse = await _executeWithFallback(
          scrambleConfig, source, () => source.prepareScrambleFetch(chapterId),
        );
        final responseText = scrambleResponse.data?.toString() ?? '';
        source.parseScrambleResponse(responseText);
        debugPrint('[getChapter] JMC: scramble_id updated');
      } catch (e) {
        debugPrint('[getChapter] JMC: Failed to fetch scramble_id: $e (using default)');
      }
    }

    var config = source.prepareChapterFetch(mangaId, chapterId, effectivePage, extra: extra);
    config = _mergeHeaders(config, source);
    debugPrint('[getChapter] Fetching: ${config.url} params=${config.queryParameters}');
    final response = await _executeWithFallback(
      config, source, () => source.prepareChapterFetch(mangaId, chapterId, effectivePage, extra: extra),
    );
    debugPrint('[getChapter] Response type: ${response.data.runtimeType}, length: ${response.data.toString().length}');
    var result = source.parseChapter(response.data, mangaId, chapterId, effectivePage);
    debugPrint('[getChapter] parseChapter result: images=${result.chapter.images.length}, nextExtra=${result.nextExtra != null ? "has ${jsonDecode(result.nextExtra!).length} urls" : "null"}, canLoadMore=${result.canLoadMore}');

    // Handle sources with paginated image lists (e.g., PicaComic returns ~40 images per API page)
    // If images were returned directly AND there are more pages, fetch all remaining pages
    if (result.chapter.images.isNotEmpty && result.canLoadMore && result.nextPage != null) {
      final allImages = List<ChapterImage>.from(result.chapter.images);
      var canLoadMore = result.canLoadMore;
      var nextPage = result.nextPage;
      while (canLoadMore && nextPage != null) {
        debugPrint('[getChapter] Loading additional page $nextPage...');
        final nextConfig = source.prepareChapterFetch(mangaId, chapterId, nextPage, extra: extra);
        final nextResponse = await _httpClient.execute(_mergeHeaders(nextConfig, source));
        final nextResult = source.parseChapter(nextResponse.data, mangaId, chapterId, nextPage);
        allImages.addAll(nextResult.chapter.images);
        canLoadMore = nextResult.canLoadMore;
        nextPage = nextResult.nextPage;
      }
      debugPrint('[getChapter] Total images after all pages: ${allImages.length}');
      result = ChapterResult(
        chapter: Chapter(
          id: result.chapter.id,
          mangaId: result.chapter.mangaId,
          title: result.chapter.title,
          images: allImages,
        ),
      );
    }

    // Handle sources that return image page URLs needing resolution (e.g., E-Hentai)
    // Collect ALL thumbnail pages first, then resolve all image page URLs
    if (result.chapter.images.isEmpty && result.nextExtra != null) {
      var allImagePageUrls = List<dynamic>.from(jsonDecode(result.nextExtra!));
      debugPrint('[getChapter] Starting multi-page resolution. Initial URLs: ${allImagePageUrls.length}');

      // If there are more thumbnail pages, fetch them all
      var currentPage = effectivePage;
      var canLoadMore = result.canLoadMore;
      while (canLoadMore && result.nextPage != null) {
        currentPage = result.nextPage!;
        final nextConfig = source.prepareChapterFetch(mangaId, chapterId, currentPage, extra: extra);
        final nextResponse = await _httpClient.execute(_mergeHeaders(nextConfig, source));
        result = source.parseChapter(nextResponse.data, mangaId, chapterId, currentPage);
        if (result.nextExtra != null) {
          final moreUrls = jsonDecode(result.nextExtra!) as List;
          allImagePageUrls.addAll(moreUrls);
        }
        canLoadMore = result.canLoadMore;
      }

      // Now resolve each image page URL to the actual image src
      final resolvedImages = <ChapterImage>[];
      debugPrint('[getChapter] Resolving ${allImagePageUrls.length} image page URLs...');
      if (allImagePageUrls.isNotEmpty) {
        debugPrint('[getChapter] First URL to resolve: ${allImagePageUrls.first}');
      }
      for (int i = 0; i < allImagePageUrls.length; i++) {
        final pageUrl = allImagePageUrls[i];
        try {
          final imgConfig = FetchConfig(url: pageUrl as String);
          final imgResponse = await _httpClient.execute(_mergeHeaders(imgConfig, source));
          final imgHtml = imgResponse.data as String;
          if (i == 0) {
            debugPrint('[getChapter] First image page HTML length: ${imgHtml.length}');
            debugPrint('[getChapter] First image page contains img#img: ${imgHtml.contains('id="img"')}');
          }
          // Parse img#img src from the image page (handle src before or after id)
          String? imgSrc;
          final srcMatch1 = RegExp(r'<img[^>]+id="img"[^>]+src="([^"]+)"').firstMatch(imgHtml);
          if (srcMatch1 != null) {
            imgSrc = srcMatch1.group(1);
          } else {
            final srcMatch2 = RegExp(r'<img[^>]+src="([^"]+)"[^>]+id="img"').firstMatch(imgHtml);
            if (srcMatch2 != null) {
              imgSrc = srcMatch2.group(1);
            }
          }
          if (imgSrc != null && imgSrc.isNotEmpty) {
            resolvedImages.add(ChapterImage(
              url: imgSrc,
              headers: source.defaultHeaders != null
                  ? Map<String, String>.from(source.defaultHeaders!)
                  : null,
            ));
          }
        } catch (e) {
          debugPrint('[EH-Resolve] Failed to resolve image page [$i] $pageUrl: $e');
          if (i == 0) {
            debugPrint('[EH-Resolve] First failure stack: ${StackTrace.current.toString().split('\n').take(5).join('\n')}');
          }
        }
      }
      debugPrint('[EH-Resolve] Resolved ${resolvedImages.length}/${allImagePageUrls.length} images');
      if (resolvedImages.isNotEmpty) {
        debugPrint('[EH-Resolve] First image: ${resolvedImages.first.url}');
        result = ChapterResult(
          chapter: Chapter(
            id: result.chapter.id,
            mangaId: result.chapter.mangaId,
            title: result.chapter.title,
            images: resolvedImages,
          ),
        );
      }
    }

    return result;
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

    final effectivePage = page == 1 ? source.firstPage : page;

    // Phase 1: Initial fetch
    final config = source.prepareChapterFetch(mangaId, chapterId, effectivePage, extra: extra);
    final response = await _httpClient.execute(_mergeHeaders(config, source));
    var result = source.parseChapter(response.data, mangaId, chapterId, effectivePage);

    // Handle JMC source multi-page images (same as getChapter)
    if (result.chapter.images.isNotEmpty && result.canLoadMore && result.nextPage != null) {
      final allImages = List<ChapterImage>.from(result.chapter.images);
      var canLoadMore = result.canLoadMore;
      var nextPage = result.nextPage;
      while (canLoadMore && nextPage != null) {
        final nextConfig = source.prepareChapterFetch(mangaId, chapterId, nextPage, extra: extra);
        final nextResponse = await _httpClient.execute(_mergeHeaders(nextConfig, source));
        final nextResult = source.parseChapter(nextResponse.data, mangaId, chapterId, nextPage);
        allImages.addAll(nextResult.chapter.images);
        canLoadMore = nextResult.canLoadMore;
        nextPage = nextResult.nextPage;
      }
      yield ChapterResult(
        chapter: Chapter(
          id: result.chapter.id,
          mangaId: result.chapter.mangaId,
          title: result.chapter.title,
          images: allImages,
        ),
      );
      return;
    }

    // Handle EH-style: images empty + nextExtra has image page URLs
    if (result.chapter.images.isEmpty && result.nextExtra != null) {
      var allImagePageUrls = List<dynamic>.from(jsonDecode(result.nextExtra!));
      debugPrint('[getChapterStream] Starting progressive resolution. Initial URLs: ${allImagePageUrls.length}');

      // Phase 2: Collect all thumbnail pages
      var currentPage = effectivePage;
      var canLoadMore = result.canLoadMore;
      while (canLoadMore && result.nextPage != null) {
        currentPage = result.nextPage!;
        final nextConfig = source.prepareChapterFetch(mangaId, chapterId, currentPage, extra: extra);
        final nextResponse = await _httpClient.execute(_mergeHeaders(nextConfig, source));
        result = source.parseChapter(nextResponse.data, mangaId, chapterId, currentPage);
        if (result.nextExtra != null) {
          final moreUrls = jsonDecode(result.nextExtra!) as List;
          allImagePageUrls.addAll(moreUrls);
        }
        canLoadMore = result.canLoadMore;
      }

      final totalCount = allImagePageUrls.length;
      debugPrint('[getChapterStream] Total pages to resolve: $totalCount');

      // Yield initial state: placeholder images (empty URLs) for total count
      final placeholderImages = List<ChapterImage>.generate(
        totalCount,
        (_) => const ChapterImage(url: ''),
      );
      yield ChapterResult(
        chapter: Chapter(
          id: result.chapter.id,
          mangaId: result.chapter.mangaId,
          title: result.chapter.title,
          images: placeholderImages,
        ),
      );

      // Phase 3: Resolve each image page URL progressively
      final resolvedImages = List<ChapterImage>.from(placeholderImages);
      const batchSize = 5;
      for (int i = 0; i < allImagePageUrls.length; i++) {
        final pageUrl = allImagePageUrls[i];
        try {
          final imgConfig = FetchConfig(url: pageUrl as String);
          final imgResponse = await _httpClient.execute(_mergeHeaders(imgConfig, source));
          final imgHtml = imgResponse.data as String;
          String? imgSrc;
          final srcMatch1 = RegExp(r'<img[^>]+id="img"[^>]+src="([^"]+)"').firstMatch(imgHtml);
          if (srcMatch1 != null) {
            imgSrc = srcMatch1.group(1);
          } else {
            final srcMatch2 = RegExp(r'<img[^>]+src="([^"]+)"[^>]+id="img"').firstMatch(imgHtml);
            if (srcMatch2 != null) {
              imgSrc = srcMatch2.group(1);
            }
          }
          if (imgSrc != null && imgSrc.isNotEmpty) {
            resolvedImages[i] = ChapterImage(
              url: imgSrc,
              headers: source.defaultHeaders != null
                  ? Map<String, String>.from(source.defaultHeaders!)
                  : null,
            );
          }
        } catch (e) {
          debugPrint('[EH-Stream] Failed to resolve image page [$i] $pageUrl: $e');
        }

        // Yield after every batchSize images or last image
        if ((i + 1) % batchSize == 0 || i == allImagePageUrls.length - 1) {
          yield ChapterResult(
            chapter: Chapter(
              id: result.chapter.id,
              mangaId: result.chapter.mangaId,
              title: result.chapter.title,
              images: List<ChapterImage>.from(resolvedImages),
            ),
          );
        }
      }
      return;
    }

    // Default: non-EH sources just yield once
    yield result;
  }
}
