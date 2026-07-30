import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/hitomi.dart';
import 'package:comic_reader/data/sources/jm_comic.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'fetch_pipeline.dart';
import 'wu55_chapter_decryptor.dart';

/// Handles the chapter image fetch/pagination/decryption pipeline shared by
/// [getChapter] (bulk) and [getChapterStream] (progressive) in
/// MangaRepositoryImpl. Was `MangaRepositoryImpl.getChapter` /
/// `.getChapterStream`; extracted verbatim, then partially deduped (see
/// `_expandPicaPages` / `_resolveWu55Images`).
///
/// The E-Hentai-style image-page resolution loop is intentionally NOT
/// merged into a single shared implementation: the two original methods
/// have a real (not just cosmetic) behavioral difference on resolution
/// failure -- `getChapter` silently *omits* unresolved images from the
/// result list, while `getChapterStream` leaves a placeholder
/// `ChapterImage(url: '')` at that index and progressively yields every 5
/// images. Unifying them would have to pick one semantics and thereby
/// change the other call site's observable behavior, so each keeps its own
/// private resolver (`_resolveEhentaiImagesForGetChapter` /
/// `_resolveEhentaiImagesForStream`).
class ChapterImagePipeline {
  final HttpClient _httpClient;
  final FetchPipeline _pipeline;
  final Wu55ChapterDecryptor _wu55Decryptor;

  ChapterImagePipeline(this._httpClient, this._pipeline, this._wu55Decryptor);

  Future<ChapterResult> getChapter(
    String mangaId,
    String chapterId,
    int page,
    MangaSource source, {
    dynamic extra,
  }) async {
    // Use source.firstPage for initial page (E-Hentai is 0-based)
    final effectivePage = page == 1 ? source.firstPage : page;

    // JMC: fetch scramble_id before loading chapter to determine correct unscramble threshold
    if (source is JmComic) {
      try {
        var scrambleConfig = source.prepareScrambleFetch(chapterId);
        scrambleConfig = _pipeline.mergeHeaders(scrambleConfig, source);
        debugPrint('[getChapter] JMC: Fetching scramble_id for chapter $chapterId');
        final scrambleResponse = await _pipeline.executeWithFallback(
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
        ggConfig = _pipeline.mergeHeaders(ggConfig, source);
        debugPrint('[getChapter] Hitomi: Fetching gg.js');
        final ggResponse = await _httpClient.execute(ggConfig);
        source.parseGgResponse(ggResponse.data?.toString() ?? '');
        debugPrint('[getChapter] Hitomi: gg.js updated');
      } catch (e) {
        debugPrint('[getChapter] Hitomi: Failed to fetch gg.js: $e (using fallback)');
      }
    }

    var config = source.prepareChapterFetch(mangaId, chapterId, effectivePage, extra: extra);
    config = _pipeline.mergeHeaders(config, source);
    debugPrint('[getChapter] Fetching: ${config.url} params=${config.queryParameters}');
    final response = await _pipeline.executeWithFallback(
      config, source, () => source.prepareChapterFetch(mangaId, chapterId, effectivePage, extra: extra),
    );
    debugPrint('[getChapter] Response type: ${response.data.runtimeType}, length: ${response.data.toString().length}');
    var result = source.parseChapter(response.data, mangaId, chapterId, effectivePage);
    debugPrint('[getChapter] parseChapter result: images=${result.chapter.images.length}, nextExtra=${result.nextExtra != null ? "has ${jsonDecode(result.nextExtra!).length} urls" : "null"}, canLoadMore=${result.canLoadMore}');

    // Preflight check: if this source has a separate CF-protected image CDN,
    // test the first image URL via Dio to detect CF challenges early.
    // This triggers CloudflareException before the reader tries loading images.
    //
    // Skip for WebView-fetch sources: their document requests already bypass CF
    // via the headless webview, and image requests go straight to a separate CDN
    // subdomain (loaded by the reader's ExtendedImage, not HttpClient). Routing an
    // image URL through the in-page fetch() would fail with a cross-origin CORS
    // error (the CDN sends no Access-Control-Allow-Origin header), so preflighting
    // it here is both unnecessary and harmful.
    if (source.cloudflareUrl != null &&
        !source.usesWebViewFetch &&
        result.chapter.images.isNotEmpty &&
        !source.extraHeaders.containsKey('Cookie')) {
      await _pipeline.preflightImageCf(source, result.chapter.images.first);
    }

    // Handle sources with paginated image lists (e.g., PicaComic returns ~40 images per API page)
    // If images were returned directly AND there are more pages, fetch all remaining pages
    if (result.chapter.images.isNotEmpty && result.canLoadMore && result.nextPage != null) {
      final allImages = await _expandPicaPages(
        source, mangaId, chapterId, result.chapter.images, result.canLoadMore, result.nextPage, extra,
      );
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
      List<ChapterImage> decryptedImages = const [];
      var batchNum = 0;
      await for (final partial in _resolveWu55Images(result.chapter.images, source)) {
        decryptedImages = partial;
        batchNum++;
        debugPrint('[getChapter] Wu55: Batch $batchNum done (${decryptedImages.length}/${result.chapter.images.length})');
      }

      result = ChapterResult(
        chapter: Chapter(
          id: result.chapter.id,
          mangaId: result.chapter.mangaId,
          title: result.chapter.title,
          images: decryptedImages,
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
        final nextResponse = await _httpClient.execute(_pipeline.mergeHeaders(nextConfig, source));
        result = source.parseChapter(nextResponse.data, mangaId, chapterId, currentPage);
        if (result.nextExtra != null) {
          final moreUrls = jsonDecode(result.nextExtra!) as List;
          allImagePageUrls.addAll(moreUrls);
        }
        canLoadMore = result.canLoadMore;
      }

      // Now resolve each image page URL to the actual image src
      final resolvedImages = await _resolveEhentaiImagesForGetChapter(allImagePageUrls, source);
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

  Stream<ChapterResult> getChapterStream(
    String mangaId,
    String chapterId,
    int page,
    MangaSource source, {
    dynamic extra,
  }) async* {
    final effectivePage = page == 1 ? source.firstPage : page;

    // Phase 1: Initial fetch
    final config = source.prepareChapterFetch(mangaId, chapterId, effectivePage, extra: extra);
    final response = await _httpClient.execute(_pipeline.mergeHeaders(config, source));
    var result = source.parseChapter(response.data, mangaId, chapterId, effectivePage);

    // Preflight: detect CF on image CDN before streaming images to reader
    if (source.cloudflareUrl != null &&
        !source.usesWebViewFetch &&
        result.chapter.images.isNotEmpty &&
        !source.extraHeaders.containsKey('Cookie')) {
      await _pipeline.preflightImageCf(source, result.chapter.images.first);
    }

    // Handle JMC source multi-page images (same as getChapter)
    if (result.chapter.images.isNotEmpty && result.canLoadMore && result.nextPage != null) {
      final allImages = await _expandPicaPages(
        source, mangaId, chapterId, result.chapter.images, result.canLoadMore, result.nextPage, extra,
      );
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
        final nextResponse = await _httpClient.execute(_pipeline.mergeHeaders(nextConfig, source));
        result = source.parseChapter(nextResponse.data, mangaId, chapterId, currentPage);
        if (result.nextExtra != null) {
          final moreUrls = jsonDecode(result.nextExtra!) as List;
          allImagePageUrls.addAll(moreUrls);
        }
        canLoadMore = result.canLoadMore;
      }

      final totalCount = allImagePageUrls.length;
      debugPrint('[getChapterStream] Total pages to resolve: $totalCount');

      // Phase 3: Resolve each image page URL progressively, yielding partial
      // results as they come in (see class doc for why this isn't shared
      // with the getChapter EH resolver).
      await for (final partial in _resolveEhentaiImagesForStream(allImagePageUrls, source)) {
        yield ChapterResult(
          chapter: Chapter(
            id: result.chapter.id,
            mangaId: result.chapter.mangaId,
            title: result.chapter.title,
            images: partial,
          ),
        );
      }
      return;
    }

    // Handle wu55comic encrypted images in stream path
    // Optimized: parallel shard downloads + batch processing with progressive yield
    if (source is Wu55Comic && result.chapter.images.isNotEmpty) {
      debugPrint('[getChapterStream] Wu55: Decrypting ${result.chapter.images.length} images...');
      await for (final partial in _resolveWu55Images(result.chapter.images, source)) {
        yield ChapterResult(
          chapter: Chapter(
            id: result.chapter.id,
            mangaId: result.chapter.mangaId,
            title: result.chapter.title,
            images: partial,
          ),
        );
        debugPrint('[getChapterStream] Wu55: ${partial.length}/${result.chapter.images.length} decrypted');
      }
      return;
    }

    // Default: non-EH sources just yield once
    yield result;
  }

  /// Fetches remaining paginated image pages (e.g. PicaComic's ~40
  /// images-per-API-page) and returns the fully accumulated image list.
  /// Shared verbatim by [getChapter] and [getChapterStream] -- their
  /// pagination-expansion loops were byte-for-byte identical.
  Future<List<ChapterImage>> _expandPicaPages(
    MangaSource source,
    String mangaId,
    String chapterId,
    List<ChapterImage> initialImages,
    bool canLoadMoreInitial,
    int? nextPageInitial,
    dynamic extra,
  ) async {
    final allImages = List<ChapterImage>.from(initialImages);
    var canLoadMore = canLoadMoreInitial;
    var nextPage = nextPageInitial;
    while (canLoadMore && nextPage != null) {
      final nextConfig = source.prepareChapterFetch(mangaId, chapterId, nextPage, extra: extra);
      final nextResponse = await _httpClient.execute(_pipeline.mergeHeaders(nextConfig, source));
      final nextResult = source.parseChapter(nextResponse.data, mangaId, chapterId, nextPage);
      allImages.addAll(nextResult.chapter.images);
      canLoadMore = nextResult.canLoadMore;
      nextPage = nextResult.nextPage;
    }
    return allImages;
  }

  /// Decrypts wu55comic-encrypted [images] in batches of 3 (parallel shard
  /// download + decrypt per batch), emitting the progressively-growing
  /// decrypted list after each batch. Order is preserved because
  /// `Future.wait` resolves in list order and batches are processed
  /// sequentially. Shared by [getChapter] (which only consumes the final
  /// emission) and [getChapterStream] (which yields every emission to the
  /// reader for progressive display).
  Stream<List<ChapterImage>> _resolveWu55Images(
    List<ChapterImage> images,
    Wu55Comic source,
  ) async* {
    final decrypted = <ChapterImage>[];
    const batchSize = 3;
    for (int batchStart = 0; batchStart < images.length; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize).clamp(0, images.length);
      final futures = <Future<ChapterImage>>[];
      for (int i = batchStart; i < batchEnd; i++) {
        futures.add(_wu55Decryptor.decrypt(images[i], i, source));
      }
      final batchResults = await Future.wait(futures);
      decrypted.addAll(batchResults);
      yield List<ChapterImage>.from(decrypted);
    }
  }

  /// getChapter's E-Hentai-style image-page resolver: silently *omits*
  /// images whose page failed to resolve (verbatim from the original
  /// `getChapter` body).
  Future<List<ChapterImage>> _resolveEhentaiImagesForGetChapter(
    List<dynamic> allImagePageUrls,
    MangaSource source,
  ) async {
    final resolvedImages = <ChapterImage>[];
    debugPrint('[getChapter] Resolving ${allImagePageUrls.length} image page URLs...');
    if (allImagePageUrls.isNotEmpty) {
      debugPrint('[getChapter] First URL to resolve: ${allImagePageUrls.first}');
    }
    for (int i = 0; i < allImagePageUrls.length; i++) {
      final pageUrl = allImagePageUrls[i];
      try {
        final imgConfig = FetchConfig(url: pageUrl as String);
        final imgResponse = await _httpClient.execute(_pipeline.mergeHeaders(imgConfig, source));
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
    return resolvedImages;
  }

  /// getChapterStream's E-Hentai-style image-page resolver: keeps a
  /// placeholder `ChapterImage(url: '')` for pages that failed to resolve
  /// and yields the progressively-growing list every 5 images (or
  /// immediately for "multi" pages), verbatim from the original
  /// `getChapterStream` body.
  Stream<List<ChapterImage>> _resolveEhentaiImagesForStream(
    List<dynamic> allImagePageUrls,
    MangaSource source,
  ) async* {
    // Yield initial state: placeholder images (empty URLs) for total count
    final placeholderImages = List<ChapterImage>.generate(
      allImagePageUrls.length,
      (_) => const ChapterImage(url: ''),
    );
    yield List<ChapterImage>.from(placeholderImages);

    final resolvedImages = List<ChapterImage>.from(placeholderImages);
    final multiImages = <ChapterImage>[];
    var multiMode = false;
    const batchSize = 5;
    for (int i = 0; i < allImagePageUrls.length; i++) {
      final pageUrl = allImagePageUrls[i];
      try {
        final imgConfig = FetchConfig(url: pageUrl as String);
        final imgResponse = await _httpClient.execute(_pipeline.mergeHeaders(imgConfig, source));
        final imgHtml = imgResponse.data as String;
        final multi = source.parseChapterImagePage(imgHtml);
        if (multi != null) {
          multiMode = true;
          multiImages.addAll(multi);
          yield List<ChapterImage>.from(multiImages);
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
        yield List<ChapterImage>.from(resolvedImages);
      }
    }
  }
}
