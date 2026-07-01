import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// E-Hentai source plugin.
/// HTML-based gallery viewer. Uses paginated thumbnail approach
/// with image page URLs stored as extras for lazy resolution.
class EHentai extends MangaSource {
  static const String sourceId = 'ehentai';
  static const String _baseUrl = 'https://e-hentai.org';

  @override
  String get id => sourceId;

  @override
  bool get isAdult => true;

  @override
  String get name => 'E-Hentai';

  @override
  String get shortName => 'EH';

  @override
  String? get description => 'E-Hentai Galleries (may require cookies for some content)';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => true;

  @override
  int get firstPage => 0;

  @override
  bool get needsCloudflare => false;

  @override
  Map<String, String>? get defaultHeaders => const {
    'Referer': 'https://e-hentai.org',
    'Cookie': 'nw=1',
  };

  @override
  String? get injectedJavaScript => '''
    (function() {
      var cookies = document.cookie;
      if (cookies) {
        window.flutter_inappwebview.callHandler('onData', JSON.stringify({cookie: cookies}));
      }
    })();
  ''';

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'category',
          label: 'Category',
          defaultValue: '0',
          choices: [
            FilterChoice(label: 'All', value: '0'),
            FilterChoice(label: 'Doujinshi', value: '2'),
            FilterChoice(label: 'Manga', value: '4'),
            FilterChoice(label: 'Artist CG', value: '8'),
            FilterChoice(label: 'Game CG', value: '16'),
            FilterChoice(label: 'Image Set', value: '32'),
            FilterChoice(label: 'Cosplay', value: '64'),
            FilterChoice(label: 'Non-H', value: '256'),
            FilterChoice(label: 'Western', value: '512'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final category = filters['category'] ?? '0';
    final params = <String, dynamic>{
      'page': '$page',
    };
    if (category != '0') {
      // E-Hentai uses f_cats as a bitmask of EXCLUDED categories
      // Total = 1023, to show only one category: 1023 - categoryValue
      final catVal = int.tryParse(category) ?? 0;
      params['f_cats'] = '${1023 - catVal}';
    }
    return FetchConfig(
      url: _baseUrl,
      queryParameters: params,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseGalleryList(response as String);
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: _baseUrl,
      queryParameters: {
        'f_search': keyword,
        'page': '$page',
      },
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseGalleryList(response as String);
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    // mangaId format: "gid_token"
    final parts = mangaId.split('_');
    final gid = parts.isNotEmpty ? parts[0] : mangaId;
    final token = parts.length > 1 ? parts[1] : '';
    return FetchConfig(url: '$_baseUrl/g/$gid/$token/');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Title
    final title = document.querySelector('#gn')?.text.trim() ??
        document.querySelector('#gj')?.text.trim() ??
        '';

    // Cover
    String cover = '';
    final coverDiv = document.querySelector('#gd1 div');
    if (coverDiv != null) {
      final style = coverDiv.attributes['style'] ?? '';
      final urlMatch = RegExp(r'url\(([^)]+)\)').firstMatch(style);
      if (urlMatch != null) {
        cover = urlMatch.group(1) ?? '';
      }
    }
    if (cover.isEmpty) {
      // Fallback to first thumbnail
      final thumbEl = document.querySelector('.gdtm img') ??
          document.querySelector('.gdtl img');
      cover = thumbEl?.attributes['src'] ?? '';
    }

    // Tags
    final tags = <String>[];
    final tagRows = document.querySelectorAll('#taglist tr');
    for (final row in tagRows) {
      final tagLinks = row.querySelectorAll('td:last-child div a');
      for (final link in tagLinks) {
        final tag = link.text.trim();
        if (tag.isNotEmpty) tags.add(tag);
      }
    }

    // Uploader
    final uploader =
        document.querySelector('#gdn a')?.text.trim() ?? '';

    // Posted date
    String? updateTime;
    final infoRows = document.querySelectorAll('#gdd tr');
    for (final row in infoRows) {
      final label = row.querySelector('.gdt1')?.text ?? '';
      if (label.contains('Posted')) {
        updateTime = row.querySelector('.gdt2')?.text.trim();
        break;
      }
    }

    // Page count
    String? pageCount;
    for (final row in infoRows) {
      final label = row.querySelector('.gdt1')?.text ?? '';
      if (label.contains('Length')) {
        final text = row.querySelector('.gdt2')?.text.trim() ?? '';
        final match = RegExp(r'(\d+)').firstMatch(text);
        pageCount = match?.group(1);
        break;
      }
    }

    // Single chapter for the gallery
    final chapters = [
      ChapterItem(
        id: '1',
        mangaId: mangaId,
        title: '${pageCount ?? '?'} pages',
      ),
    ];

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: cover,
      description: 'Uploader: $uploader',
      author: uploader,
      tags: tags,
      status: MangaStatus.completed,
      updateTime: updateTime,
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Single chapter per gallery
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    final parts = mangaId.split('_');
    final gid = parts.isNotEmpty ? parts[0] : mangaId;
    final token = parts.length > 1 ? parts[1] : '';

    // If extra contains image page URLs from a previous fetch, fetch one
    if (extra != null && extra is String && extra.isNotEmpty) {
      try {
        final imagePageUrls = jsonDecode(extra) as List;
        if (page < imagePageUrls.length) {
          final imagePageUrl = imagePageUrls[page] as String;
          return FetchConfig(url: imagePageUrl);
        }
      } catch (_) {
        // Fall through to gallery page fetch
      }
    }

    // Fetch gallery thumbnail page (p=0 based)
    return FetchConfig(
      url: '$_baseUrl/g/$gid/$token/',
      queryParameters: {
        'p': '$page',
        'inline_set': 'ts_l', // large thumbnails
      },
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Check if this is an image page (has img#img)
    final fullImg = document.querySelector('#img');
    if (fullImg != null) {
      final imgSrc = fullImg.attributes['src'] ?? '';
      if (imgSrc.isNotEmpty) {
        return ChapterResult(
          chapter: Chapter(
            id: chapterId,
            mangaId: mangaId,
            title: '',
            images: [ChapterImage(url: imgSrc)],
          ),
          canLoadMore: true,
          nextPage: page + 1,
        );
      }
    }

    // This is a gallery thumbnail page - extract image page links
    final imagePageLinks = <String>[];

    // Try different thumbnail modes:
    // - Large thumbnails: #gdt.gt200 > a (direct children of gdt)
    // - Normal large: .gdtl a
    // - Medium: .gdtm a
    var thumbContainers = document.querySelectorAll('#gdt > a');
    if (thumbContainers.isEmpty) {
      thumbContainers = document.querySelectorAll('.gdtl a');
    }
    if (thumbContainers.isEmpty) {
      thumbContainers = document.querySelectorAll('.gdtm a');
    }

    for (final link in thumbContainers) {
      final href = link.attributes['href'] ?? '';
      if (href.contains('/s/')) {
        imagePageLinks.add(href);
      }
    }

    // Check if there are more thumbnail pages
    final paginationLinks = document.querySelectorAll('.ptt td a');
    var hasMoreThumbPages = false;

    for (final link in paginationLinks) {
      final href = link.attributes['href'] ?? '';
      final pMatch = RegExp(r'[?&]p=(\d+)').firstMatch(href);
      if (pMatch != null) {
        final p = int.tryParse(pMatch.group(1)!) ?? 0;
        if (p > page) {
          hasMoreThumbPages = true;
          break;
        }
      }
    }

    // Store image page URLs for sequential fetching
    // Return empty images with extra data pointing to image pages
    // The caller will re-fetch with extra containing these URLs
    if (imagePageLinks.isNotEmpty) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
        canLoadMore: hasMoreThumbPages,
        nextPage: hasMoreThumbPages ? page + 1 : null,
        nextExtra: jsonEncode(imagePageLinks),
      );
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: const [],
      ),
    );
  }

  // --- Private Helpers ---

  List<MangaSummary> _parseGalleryList(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    // Try extended mode table
    final rows = document.querySelectorAll('table.itg.gltc tr');
    if (rows.length > 1) {
      // Skip header row
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        final summary = _parseTableRow(row);
        if (summary != null) results.add(summary);
      }
      if (results.isNotEmpty) return results;
    }

    // Try compact mode
    final compactRows = document.querySelectorAll('table.itg.gltc tbody tr');
    for (final row in compactRows) {
      final summary = _parseTableRow(row);
      if (summary != null) results.add(summary);
    }
    if (results.isNotEmpty) return results;

    // Try thumbnail mode (div-based)
    final thumbDivs = document.querySelectorAll('.itg.gld div.gl1t');
    for (final div in thumbDivs) {
      final linkEl = div.querySelector('a');
      final href = linkEl?.attributes['href'] ?? '';
      final mangaId = _extractMangaId(href);
      if (mangaId == null) continue;

      final imgEl = div.querySelector('img');
      final cover = imgEl?.attributes['data-src'] ??
          imgEl?.attributes['src'] ??
          '';
      final title = imgEl?.attributes['title'] ??
          div.querySelector('.glink')?.text.trim() ??
          '';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: cover,
      ));
    }
    if (results.isNotEmpty) return results;

    // Fallback: try any table with gallery links
    final allRows = document.querySelectorAll('table.itg tr');
    for (final row in allRows) {
      final summary = _parseTableRow(row);
      if (summary != null) results.add(summary);
    }

    return results;
  }

  MangaSummary? _parseTableRow(dynamic row) {
    // Cover image
    final coverEl = row.querySelector('.gl1c img') ??
        row.querySelector('.gl2c img') ??
        row.querySelector('img');
    final cover = coverEl?.attributes['data-src'] ??
        coverEl?.attributes['src'] ??
        '';

    // Title and link
    final titleEl = row.querySelector('.glink') ??
        row.querySelector('.gl3c a') ??
        row.querySelector('.gl4c a');
    final title = titleEl?.text.trim() ?? '';

    // Find the gallery link
    final linkEl = row.querySelector('a[href*="/g/"]');
    if (linkEl == null) return null;

    final href = linkEl.attributes['href'] ?? '';
    final mangaId = _extractMangaId(href);
    if (mangaId == null) return null;

    if (title.isEmpty && cover.isEmpty) return null;

    return MangaSummary(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: cover,
    );
  }

  /// Extract mangaId from URL like https://e-hentai.org/g/GID/TOKEN/
  /// Returns "GID_TOKEN" as the mangaId
  String? _extractMangaId(String href) {
    final match = RegExp(r'/g/(\d+)/([a-f0-9]+)').firstMatch(href);
    if (match == null) return null;
    final gid = match.group(1)!;
    final token = match.group(2)!;
    return '${gid}_$token';
  }
}
