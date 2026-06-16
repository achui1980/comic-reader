import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// NHentai source plugin.
/// Uses nhentai.to mirror (no Cloudflare) with zrocdn.xyz image CDN.
/// All gallery images are embedded directly in the gallery page HTML.
class NHentai extends MangaSource {
  static const String sourceId = 'nhentai';
  static const String _baseUrl = 'https://nhentai.to';
  static const String _imageCdn = 'https://zrocdn.xyz';

  @override
  String get id => sourceId;

  @override
  String get name => 'NHentai';

  @override
  String get shortName => 'NH';

  @override
  String? get description => 'English doujinshi gallery';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsCloudflare => false;

  @override
  List<FilterOption> get searchFilters => const [
        FilterOption(
          name: 'sort',
          label: 'Sort',
          defaultValue: '',
          choices: [
            FilterChoice(label: 'Recent', value: ''),
            FilterChoice(label: 'Popular Today', value: 'popular-today'),
            FilterChoice(label: 'Popular This Week', value: 'popular-week'),
            FilterChoice(label: 'Popular All Time', value: 'popular'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final sort = filters['sort'] ?? '';
    String url = '$_baseUrl/search';
    final params = <String, dynamic>{'page': '$page'};
    if (sort.isNotEmpty) {
      params['sort'] = sort;
    }
    // Default discovery: popular this week, use '*' wildcard to get results
    if (sort.isEmpty) {
      params['q'] = '*';
      params['sort'] = 'popular-week';
    } else if (!params.containsKey('q')) {
      params['q'] = '*';
    }
    return FetchConfig(url: url, queryParameters: params);
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseGalleryList(response as String);
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final sort = filters['sort'] ?? '';
    final params = <String, dynamic>{
      'q': keyword,
      'page': '$page',
    };
    if (sort.isNotEmpty) {
      params['sort'] = sort;
    }
    return FetchConfig(
      url: '$_baseUrl/search',
      queryParameters: params,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseGalleryList(response as String);
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/g/$mangaId/');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Title
    final title =
        document.querySelector('h1.title span.pretty')?.text.trim() ??
            document.querySelector('h1.title')?.text.trim() ??
            document.querySelector('h1')?.text.trim() ??
            '';

    // Cover image
    final coverEl = document.querySelector('#cover img') ??
        document.querySelector('.gallery .cover img');
    final cover = coverEl?.attributes['data-src'] ??
        coverEl?.attributes['src'] ??
        '';

    // Tags
    final tagEls = document.querySelectorAll('.tag-container');
    final tagNames = <String>[];
    final artists = <String>[];

    for (final container in tagEls) {
      final label = container.text.trim().toLowerCase();
      final tagSpans = container.querySelectorAll('span.name');

      if (label.startsWith('artists') || label.startsWith('artist')) {
        for (final span in tagSpans) {
          artists.add(span.text.trim());
        }
      } else if (label.startsWith('tags') || label.startsWith('tag')) {
        for (final span in tagSpans) {
          tagNames.add(span.text.trim());
        }
      }
    }

    // Page count from images in the gallery page
    final imageEls = document.querySelectorAll(
        '#thumbnail-container img, .thumbs img, img[data-src*="zrocdn"]');
    final pageCount = imageEls.isNotEmpty ? imageEls.length : _countPages(htmlStr);

    // Single chapter for the gallery
    final chapters = [
      ChapterItem(
        id: '1',
        mangaId: mangaId,
        title: '$pageCount pages',
      ),
    ];

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: _ensureAbsoluteUrl(cover),
      author: artists.join(', '),
      tags: tagNames,
      status: MangaStatus.completed,
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // NHentai is single-chapter per gallery
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(url: '$_baseUrl/g/$mangaId/');
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Extract all thumbnail images - convert from thumbnails to full images
    // Thumbnail URL: https://zrocdn.xyz/galleries/{media_id}/{N}t.jpg
    // Full URL:      https://zrocdn.xyz/galleries/{media_id}/{N}.jpg
    final images = <ChapterImage>[];

    // Try to find all page images
    final allImgs = document.querySelectorAll('img[data-src]');
    final pageImgs = <String>[];

    for (final img in allImgs) {
      final dataSrc = img.attributes['data-src'] ?? '';
      // Match pattern: zrocdn.xyz/galleries/{media_id}/{N}t.{ext}
      if (dataSrc.contains('zrocdn.xyz/galleries/') &&
          RegExp(r'/\d+t\.\w+$').hasMatch(dataSrc)) {
        pageImgs.add(dataSrc);
      }
    }

    // Also check non-lazy images with src
    if (pageImgs.isEmpty) {
      for (final img in document.querySelectorAll('img[src*="zrocdn.xyz"]')) {
        final src = img.attributes['src'] ?? '';
        if (src.contains('/galleries/') &&
            RegExp(r'/\d+t\.\w+$').hasMatch(src)) {
          pageImgs.add(src);
        }
      }
    }

    // Convert thumbnail URLs to full image URLs
    for (final thumbUrl in pageImgs) {
      // Replace {N}t.{ext} with {N}.{ext}
      final fullUrl = thumbUrl.replaceAllMapped(
        RegExp(r'/(\d+)t\.(\w+)$'),
        (m) => '/${m.group(1)}.${m.group(2)}',
      );
      images.add(ChapterImage(url: fullUrl));
    }

    // If we still have no images, try cover-based approach
    if (images.isEmpty) {
      final coverImg = document.querySelector('#cover img');
      final coverSrc = coverImg?.attributes['data-src'] ??
          coverImg?.attributes['src'] ??
          '';
      if (coverSrc.contains('zrocdn.xyz/galleries/')) {
        // Extract media_id from cover URL
        final mediaMatch =
            RegExp(r'galleries/(\d+)/').firstMatch(coverSrc);
        if (mediaMatch != null) {
          final mediaId = mediaMatch.group(1)!;
          final numPages = _countPages(htmlStr);
          for (var i = 1; i <= numPages; i++) {
            images.add(ChapterImage(
              url: '$_imageCdn/galleries/$mediaId/$i.jpg',
            ));
          }
        }
      }
    }

    // Title
    final title =
        document.querySelector('h1.title span.pretty')?.text.trim() ??
            document.querySelector('h1')?.text.trim() ??
            '';

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
      ),
    );
  }

  // --- Private Helpers ---

  List<MangaSummary> _parseGalleryList(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final items = document.querySelectorAll('div.gallery');
    final results = <MangaSummary>[];

    for (final item in items) {
      final linkEl = item.querySelector('a.cover') ?? item.querySelector('a');
      if (linkEl == null) continue;

      final href = linkEl.attributes['href'] ?? '';
      final mangaId = _extractGalleryId(href);
      if (mangaId == null) continue;

      final imgEl = item.querySelector('img');
      final title =
          item.querySelector('div.caption')?.text.trim() ??
              imgEl?.attributes['alt'] ??
              '';
      final cover = imgEl?.attributes['data-src'] ??
          imgEl?.attributes['src'] ??
          '';

      // Skip placeholder data URIs
      final coverUrl = cover.startsWith('data:') ? '' : cover;

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: _ensureAbsoluteUrl(coverUrl),
      ));
    }

    return results;
  }

  int _countPages(String htmlStr) {
    // Count the number of thumbnail images
    final matches = RegExp(r'zrocdn\.xyz/galleries/\d+/\d+t\.\w+').allMatches(htmlStr);
    if (matches.isNotEmpty) return matches.length;

    // Fallback: look for "N pages" text
    final pageMatch = RegExp(r'(\d+)\s*pages?').firstMatch(htmlStr);
    if (pageMatch != null) return int.tryParse(pageMatch.group(1)!) ?? 0;

    return 0;
  }

  String? _extractGalleryId(String href) {
    final match = RegExp(r'/g/(\d+)').firstMatch(href);
    return match?.group(1);
  }

  String _ensureAbsoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$_baseUrl$url';
  }
}
