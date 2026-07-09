import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// VyManga (vymanga.net) — English aggregator manga site (Laravel backend).
///
/// Sits behind Cloudflare's interactive JS challenge (Managed Challenge),
/// identical in nature to Weeb Central: the detail/chapter pages return a
/// 403 "Just a moment..." challenge that curl-impersonate cannot solve on
/// its own (it can fake the TLS fingerprint but cannot execute the JS to
/// obtain `cf_clearance`). Therefore native routes requests through the
/// WebView fetch channel (see [usesWebViewFetch] + [cloudflareUrl]); web
/// relies on curl-impersonate in `tools/cors_proxy.js` combined with a
/// manually pasted `cf_clearance` cookie.
///
/// Endpoints:
/// - Search/discover: GET /search?q=<kw>&page=<n>   (HTTP 200, no CF)
/// - Detail:          GET /manga/{slug}              (CF challenge)
/// - Chapter images:  GET /manga/{slug}/{chapter}    (CF challenge, guessed)
///
/// NOTE: The detail and chapter selectors below are best-effort guesses made
/// while the pages were unreachable offline (403). They MUST be verified
/// against real HTML captured on a native device/emulator (which passes CF
/// via WebView) and refined. The search selectors are verified and correct.
class VyMangaSource extends MangaSource {
  static const String sourceId = 'vymanga';

  static const String _baseUrl = 'https://vymanga.net';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36';

  @override
  String get id => sourceId;

  @override
  String get name => 'VyManga';

  @override
  String get shortName => 'VY';

  @override
  String? get description => 'English manga aggregator (vymanga.net).';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  String? get userAgent => _ua;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _ua,
        'Referer': '$_baseUrl/',
      };

  @override
  bool get needsProxy => true;

  @override
  bool get needsCloudflare => true;

  @override
  bool get usesWebViewFetch => true;

  @override
  String? get cloudflareUrl => '$_baseUrl/';

  // --- Helpers ---------------------------------------------------------------

  /// Extract the manga slug from a `/manga/{slug}` href.
  static String _slugFromMangaHref(String href) {
    final match = RegExp(r'/manga/([^/?#]+)').firstMatch(href);
    return match?.group(1) ?? '';
  }

  /// Prefer lazy-loaded `data-src` over the placeholder `src`.
  static String _imgUrl(dom.Element? img) {
    if (img == null) return '';
    final dataSrc = img.attributes['data-src'];
    if (dataSrc != null && dataSrc.isNotEmpty) return dataSrc;
    return img.attributes['src'] ?? '';
  }

  // --- Discovery -------------------------------------------------------------
  // No dedicated list endpoint verified yet (/manga-list is 404); reuse the
  // search endpoint with an empty keyword as a stopgap.

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    return _searchConfig('', page);
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) =>
      _parseCards(response as String);

  // --- Search ----------------------------------------------------------------

  FetchConfig _searchConfig(String keyword, int page) {
    return FetchConfig(
      url: '$_baseUrl/search',
      queryParameters: {
        'q': keyword,
        'page': '$page',
      },
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return _searchConfig(keyword, page);
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) =>
      _parseCards(response as String);

  /// Parse the `div.comic-item` cards returned by the search page. These
  /// selectors are verified against live HTML.
  List<MangaSummary> _parseCards(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    for (final item in document.querySelectorAll('.comic-item')) {
      final link = item.querySelector('a[href*="/manga/"]');
      final href = link?.attributes['href'] ?? '';
      final mangaId = _slugFromMangaHref(href);
      if (mangaId.isEmpty) continue;

      final coverUrl = _imgUrl(item.querySelector('img'));

      String title = item.querySelector('.comic-title')?.text.trim() ?? '';
      if (title.isEmpty) {
        title = link?.attributes['title']?.trim() ?? '';
      }
      if (title.isEmpty) continue;

      // Latest chapter (e.g. "Chapter 12 : Name"); take the first tray-item.
      final latest = item.querySelector('.tray-item')?.text.trim();

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        latestChapter: (latest != null && latest.isNotEmpty) ? latest : null,
      ));
    }

    return results;
  }

  // --- Manga Info ------------------------------------------------------------
  // GUESSED selectors — verify against real detail HTML captured via WebView.

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/manga/$mangaId',
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final document = html_parser.parse(response as String);

    // Title: main heading on the detail page.
    final title = document.querySelector('.title, h1')?.text.trim() ?? '';

    // Cover: first significant image (prefer data-src).
    final coverUrl = _imgUrl(
      document.querySelector('.content-thumb img, .comic-cover img, img'),
    );

    String author = '';
    final tags = <String>[];
    MangaStatus status = MangaStatus.unknown;

    // Metadata rows are typically "<label>: <value>" blocks.
    for (final row in document.querySelectorAll('.author, p, li, div')) {
      final text = row.text.trim();
      final lower = text.toLowerCase();
      if (author.isEmpty && lower.startsWith('author')) {
        author = row
            .querySelectorAll('a')
            .map((e) => e.text.trim())
            .where((s) => s.isNotEmpty)
            .join(', ');
        if (author.isEmpty) {
          author = text.replaceFirst(RegExp(r'^[Aa]uthor\s*:?\s*'), '').trim();
        }
      } else if (lower.startsWith('status')) {
        if (lower.contains('ongoing')) {
          status = MangaStatus.ongoing;
        } else if (lower.contains('complete')) {
          status = MangaStatus.completed;
        }
      } else if (lower.startsWith('genre') || lower.startsWith('tag')) {
        tags.addAll(row
            .querySelectorAll('a')
            .map((e) => e.text.trim())
            .where((s) => s.isNotEmpty));
      }
    }

    final description = document
        .querySelector('.summary, .content, .description, p.pre-line')
        ?.text
        .trim();

    // Chapters are embedded in the detail page for this site.
    final chapters = _parseChapterItems(document, mangaId);

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      description: description,
      tags: tags,
      status: status,
      chapters: chapters,
    );
  }

  /// Parse chapter anchors from the detail document. GUESSED selectors.
  List<ChapterItem> _parseChapterItems(dom.Document document, String mangaId) {
    final items = <ChapterItem>[];
    final seen = <String>{};

    for (final a in document.querySelectorAll('a[href*="/manga/"]')) {
      final href = a.attributes['href'] ?? '';
      // A chapter URL has a segment after the slug: /manga/{slug}/{chapter}.
      final match =
          RegExp(r'/manga/[^/?#]+/([^/?#]+)').firstMatch(href);
      final chapterId = match?.group(1);
      if (chapterId == null || chapterId.isEmpty) continue;
      if (!seen.add(chapterId)) continue;

      final title = a.text.trim();
      items.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: title.isEmpty ? chapterId : title,
        href: '$_baseUrl/manga/$mangaId/$chapterId',
      ));
    }

    // Site lists newest-first; reverse to oldest-first for the reader.
    return items.reversed.toList();
  }

  // --- Chapter List ----------------------------------------------------------
  // Chapters are embedded in the detail page, so no separate fetch.

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) =>
      const ChapterListResult(chapters: []);

  // --- Chapter Content -------------------------------------------------------
  // GUESSED selectors — verify against real chapter HTML captured via WebView.

  @override
  FetchConfig prepareChapterFetch(
      String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/manga/$mangaId/$chapterId',
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final document = html_parser.parse(response as String);
    final images = <ChapterImage>[];

    // Reader images are typically lazy-loaded within a container.
    for (final img in document
        .querySelectorAll('.chapter-img, .reading-content img, img.lozad')) {
      final url = _imgUrl(img);
      if (url.isEmpty || url.contains('blank.gif')) continue;
      images.add(ChapterImage(
        url: url,
        headers: const {'Referer': '$_baseUrl/'},
      ));
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: images,
      ),
      canLoadMore: false,
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/manga/$mangaId/$chapterId';
  }
}
