import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/remote/cloudflare_interceptor.dart';
import 'package:comic_reader/data/sources/hitomi.dart';
import 'package:comic_reader/data/sources/jm_comic.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';
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

  /// Preflight check: HEAD-request the first image to detect CF on image CDN.
  /// Throws [CloudflareException] so the UI can prompt CF verification.
  Future<void> _preflightImageCf(MangaSource source, ChapterImage image) async {
    try {
      final preflightConfig = FetchConfig(
        url: image.url,
        headers: {
          ...?source.defaultHeaders,
          ...source.extraHeaders,
        },
        responseType: ResponseType.plain,
      );
      final merged = _mergeHeaders(preflightConfig, source);
      await _httpClient.execute(merged);
      // If we get here, image CDN is accessible — no CF block.
    } on DioException catch (e) {
      // If the interceptor already converted it to CloudflareException, rethrow
      if (e.error is CloudflareException) rethrow;
      // Manual detection for 403 without interceptor catching it
      if (e.response?.statusCode == 403) {
        final body = e.response?.data?.toString() ?? '';
        if (body.contains('cloudflare') || body.contains('Cloudflare') ||
            body.contains('cf_chl_opt') || body.contains('challenges.cloudflare.com')) {
          throw DioException(
            requestOptions: e.requestOptions,
            response: e.response,
            type: DioExceptionType.unknown,
            error: CloudflareException(
              sourceId: source.id,
              url: source.cloudflareUrl ?? image.url,
            ),
          );
        }
      }
      // Non-CF error — don't block chapter loading
      debugPrint('[_preflightImageCf] Non-CF error: $e');
    }
  }

  /// Execute a request with domain fallback for JMComic and domain discovery for Wu55Comic.
  /// If request fails with a network/timeout error, switches to next domain and retries.
  Future<Response> _executeWithFallback(
    FetchConfig config,
    MangaSource source,
    FetchConfig Function() rebuildConfig,
  ) async {
    if (source is! JmComic && source is! Wu55Comic) {
      return _httpClient.execute(config);
    }

    // For Wu55Comic: try execute, on failure attempt domain discovery + retry
    if (source is Wu55Comic) {
      try {
        return await _httpClient.execute(config);
      } catch (e) {
        debugPrint('[Wu55] Request failed: $e, trying domain discovery...');
        try {
          final discoveryConfig = source.prepareDomainDiscoveryFetch();
          final discoveryResponse = await _httpClient.execute(discoveryConfig);
          final changed = source.parseDomainDiscovery(discoveryResponse.data);
          if (changed) {
            debugPrint('[Wu55] Domain updated to: ${source.baseUrl}');
            final newConfig = rebuildConfig();
            return await _httpClient.execute(_mergeHeaders(newConfig, source));
          }
        } catch (de) {
          debugPrint('[Wu55] Domain discovery also failed: $de');
        }
        rethrow;
      }
    }

    // For JmComic: rotate through fallback domains
    final jmSource = source as JmComic;
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

    // Hitomi: nozomi returns only IDs; enrich with galleryblock HTML
    if (source is Hitomi) {
      return _enrichHitomiResults(source, response.data);
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
    config = _mergeHeaders(config, source);
    final response = await _executeWithFallback(
      config, source, () => source.prepareSearchFetch(keyword, page, filters),
    );

    // Hitomi: nozomi returns only IDs; enrich with galleryblock HTML
    if (source is Hitomi) {
      return _enrichHitomiResults(source, response.data);
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
        ggConfig = _mergeHeaders(ggConfig, source);
        final ggResponse = await _httpClient.execute(ggConfig);
        source.parseGgResponse(ggResponse.data?.toString() ?? '');
      } catch (e) {
        debugPrint('[getMangaInfo] Hitomi: Failed to fetch gg.js: $e');
      }
    }

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

    // Hitomi: fetch gg.js before chapter to determine image CDN subdomain routing
    if (source is Hitomi && source.needsGgRefresh) {
      try {
        var ggConfig = source.prepareGgFetch();
        ggConfig = _mergeHeaders(ggConfig, source);
        debugPrint('[getChapter] Hitomi: Fetching gg.js');
        final ggResponse = await _httpClient.execute(ggConfig);
        source.parseGgResponse(ggResponse.data?.toString() ?? '');
        debugPrint('[getChapter] Hitomi: gg.js updated');
      } catch (e) {
        debugPrint('[getChapter] Hitomi: Failed to fetch gg.js: $e (using fallback)');
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

    // Preflight check: if this source has a separate CF-protected image CDN,
    // test the first image URL via Dio to detect CF challenges early.
    // This triggers CloudflareException before the reader tries loading images.
    if (source.cloudflareUrl != null &&
        result.chapter.images.isNotEmpty &&
        !source.extraHeaders.containsKey('Cookie')) {
      await _preflightImageCf(source, result.chapter.images.first);
    }

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

    // Handle wu55comic encrypted images: download shards, decrypt, convert to data URIs
    // Optimized: parallel shard downloads + batch processing (3 images concurrently)
    if (source is Wu55Comic && result.chapter.images.isNotEmpty) {
      debugPrint('[getChapter] Wu55: Decrypting ${result.chapter.images.length} images...');
      final decryptedImages = List<ChapterImage?>.filled(result.chapter.images.length, null);
      const batchSize = 3;

      for (int batchStart = 0; batchStart < result.chapter.images.length; batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize).clamp(0, result.chapter.images.length);
        final futures = <Future<void>>[];

        for (int i = batchStart; i < batchEnd; i++) {
          futures.add(_decryptWu55Image(result.chapter.images[i], i, source).then((img) {
            decryptedImages[i] = img;
          }));
        }

        await Future.wait(futures);
        debugPrint('[getChapter] Wu55: Batch ${batchStart ~/ batchSize + 1} done ($batchEnd/${result.chapter.images.length})');
      }

      result = ChapterResult(
        chapter: Chapter(
          id: result.chapter.id,
          mangaId: result.chapter.mangaId,
          title: result.chapter.title,
          images: decryptedImages.map((e) => e!).toList(),
          headers: result.chapter.headers,
        ),
        canLoadMore: false,
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
          // Allow the source to return MULTIPLE images from a single page
          // (e.g. an AJAX endpoint returning all chapter images at once).
          final multi = source.parseChapterImagePage(imgHtml);
          if (multi != null) {
            resolvedImages.addAll(multi);
            continue;
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

    // Preflight: detect CF on image CDN before streaming images to reader
    if (source.cloudflareUrl != null &&
        result.chapter.images.isNotEmpty &&
        !source.extraHeaders.containsKey('Cookie')) {
      await _preflightImageCf(source, result.chapter.images.first);
    }

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

      // Phase 3: Resolve each image page URL progressively.
      // If the source returns MULTIPLE images per page (parseChapterImagePage),
      // we accumulate into a flat growing list instead of the 1:1 placeholder
      // slots, since the true image count is only known after resolving.
      final resolvedImages = List<ChapterImage>.from(placeholderImages);
      final multiImages = <ChapterImage>[];
      var multiMode = false;
      const batchSize = 5;
      for (int i = 0; i < allImagePageUrls.length; i++) {
        final pageUrl = allImagePageUrls[i];
        try {
          final imgConfig = FetchConfig(url: pageUrl as String);
          final imgResponse = await _httpClient.execute(_mergeHeaders(imgConfig, source));
          final imgHtml = imgResponse.data as String;
          final multi = source.parseChapterImagePage(imgHtml);
          if (multi != null) {
            multiMode = true;
            multiImages.addAll(multi);
            yield ChapterResult(
              chapter: Chapter(
                id: result.chapter.id,
                mangaId: result.chapter.mangaId,
                title: result.chapter.title,
                images: List<ChapterImage>.from(multiImages),
              ),
            );
            continue;
          }
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

        // Yield after every batchSize images or last image (single-image mode)
        if (!multiMode &&
            ((i + 1) % batchSize == 0 || i == allImagePageUrls.length - 1)) {
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

    // Handle wu55comic encrypted images in stream path
    // Optimized: parallel shard downloads + batch processing with progressive yield
    if (source is Wu55Comic && result.chapter.images.isNotEmpty) {
      debugPrint('[getChapterStream] Wu55: Decrypting ${result.chapter.images.length} images...');
      final decryptedImages = <ChapterImage>[];
      const batchSize = 3;

      for (int batchStart = 0; batchStart < result.chapter.images.length; batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize).clamp(0, result.chapter.images.length);
        final futures = <Future<ChapterImage>>[];

        for (int i = batchStart; i < batchEnd; i++) {
          futures.add(_decryptWu55Image(result.chapter.images[i], i, source));
        }

        final batchResults = await Future.wait(futures);
        decryptedImages.addAll(batchResults);

        // Yield progress after each batch so UI can start showing images
        yield ChapterResult(
          chapter: Chapter(
            id: result.chapter.id,
            mangaId: result.chapter.mangaId,
            title: result.chapter.title,
            images: List<ChapterImage>.from(decryptedImages),
          ),
        );
        debugPrint('[getChapterStream] Wu55: ${decryptedImages.length}/${result.chapter.images.length} decrypted');
      }
      return;
    }

    // Default: non-EH sources just yield once
    yield result;
  }

  /// Decrypt a single wu55comic image: download shards in parallel, AES decrypt, return data URI.
  Future<ChapterImage> _decryptWu55Image(ChapterImage img, int index, Wu55Comic source) async {
    if (img.scrambleType != ScrambleType.wu55) return img;

    try {
      final shardUrls = Wu55ComicDecoder.buildShardUrls(img.url);

      // Download both shards in parallel
      final responses = await Future.wait([
        _httpClient.execute(_mergeHeaders(FetchConfig(
          url: shardUrls[0],
          responseType: ResponseType.bytes,
          headers: img.headers,
        ), source)),
        _httpClient.execute(_mergeHeaders(FetchConfig(
          url: shardUrls[1],
          responseType: ResponseType.bytes,
          headers: img.headers,
        ), source)),
      ]);

      final shard0Bytes = Uint8List.fromList(responses[0].data as List<int>);
      final shard1Bytes = Uint8List.fromList(responses[1].data as List<int>);

      // Each shard is an independent AES-CBC stream
      final decoded = Wu55ComicDecoder.decodeShards([shard0Bytes, shard1Bytes]);
      final base64Data = base64Encode(decoded.imageBytes);
      final dataUri = 'data:${decoded.mimeType};base64,$base64Data';

      return ChapterImage(
        url: dataUri,
        scrambleType: decoded.needsUnscramble ? ScrambleType.wu55 : ScrambleType.none,
        wu55BookId: decoded.bookId,
        wu55PageNumber: decoded.pageNumber,
      );
    } catch (e) {
      debugPrint('[Wu55] Failed to decrypt image ${index + 1}: $e');
      return img; // fallback to original
    }
  }

  /// Hitomi: enrich nozomi ID list with galleryblock HTML to get titles and covers.
  /// Fetches galleryblock/{id}.html in parallel for each ID.
  Future<List<MangaSummary>> _enrichHitomiResults(Hitomi source, dynamic responseData) async {
    final ids = source.parseNozomiIds(responseData);
    debugPrint('[Hitomi] Enriching ${ids.length} gallery IDs with galleryblock...');

    if (ids.isEmpty) return [];

    // Fetch galleryblock HTML for each ID in parallel
    final futures = ids.map((id) async {
      try {
        var config = source.prepareGalleryBlockFetch(id);
        config = _mergeHeaders(config, source);
        final response = await _httpClient.execute(config);
        final html = response.data?.toString() ?? '';
        return source.parseGalleryBlock(html, id);
      } catch (e) {
        debugPrint('[Hitomi] Failed to fetch galleryblock for $id: $e');
        // Return a placeholder if fetch fails
        return MangaSummary(
          id: id,
          sourceId: Hitomi.sourceId,
          title: 'Gallery #$id',
          coverUrl: '',
        );
      }
    }).toList();

    final results = await Future.wait(futures);
    final summaries = results.whereType<MangaSummary>().toList();
    debugPrint('[Hitomi] Enriched ${summaries.length} items, first: ${summaries.isNotEmpty ? summaries.first.id : "none"}');
    return summaries;
  }
}
