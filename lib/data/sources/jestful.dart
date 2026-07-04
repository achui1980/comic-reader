import 'dart:convert';
import 'dart:math';

import 'package:html/parser.dart' as html_parser;
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/manga.dart';
import 'package:comic_reader/domain/entities/chapter.dart';
import 'package:comic_reader/domain/entities/plugin_info.dart';

/// JestFul (jestful.net) — Japanese raw manga reader.
///
/// Site quirks handled here:
/// - List/search cards use `div.thumb-wrapper`; covers are lazy-loaded via
///   the `data-bg` attribute (not `src`).
/// - Manga IDs are URL slugs derived from `hwms-{slug}.html`.
/// - The chapter list is loaded via AJAX from a `*.lstc?slug={slug}` endpoint.
/// - Chapter images are loaded via AJAX from a `*.iog?cid={cid}` endpoint,
///   where `cid` is a numeric id only found inside the chapter HTML page.
///   This forces a two-fetch flow: the chapter HTML page is fetched first to
///   extract the cid, then the `.iog` page is resolved via the framework's
///   E-Hentai-style `nextExtra` indirection. Since `.iog` returns MANY images
///   in one response, [parseChapterImagePage] is overridden.
class Jestful extends MangaSource {
  static const String sourceId = 'jestful';
  static const String _baseUrl = 'https://jestful.net';

  static const String _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

  static final Random _random = Random();

  /// Generates a random lowercase-alphanumeric string of [n] chars.
  /// The site ignores the random prefix of `.lstc`/`.iog` URLs.
  static String _randomStr(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      Iterable.generate(
        n,
        (_) => chars.codeUnitAt(_random.nextInt(chars.length)),
      ),
    );
  }

  @override
  String get id => sourceId;

  @override
  String get name => 'JestFul';

  @override
  String get shortName => 'JF';

  @override
  String? get description => '日语生肉 raw 漫画';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => false;

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;

  @override
  String? get userAgent => _mobileUserAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _mobileUserAgent,
        'Referer': '$_baseUrl/',
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'genre',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: 'Action', value: 'Action'),
            FilterChoice(label: 'Adult', value: 'Adult'),
            FilterChoice(label: 'Adventure', value: 'Adventure'),
            FilterChoice(label: 'Comedy', value: 'Comedy'),
            FilterChoice(label: 'Drama', value: 'Drama'),
            FilterChoice(label: 'Ecchi', value: 'Ecchi'),
            FilterChoice(label: 'Fantasy', value: 'Fantasy'),
            FilterChoice(label: 'Gender Bender', value: 'Gender Bender'),
            FilterChoice(label: 'Harem', value: 'Harem'),
            FilterChoice(label: 'Historical', value: 'Historical'),
            FilterChoice(label: 'Horror', value: 'Horror'),
            FilterChoice(label: 'Mature', value: 'Mature'),
            FilterChoice(label: 'Mecha', value: 'Mecha'),
            FilterChoice(label: 'Mystery', value: 'Mystery'),
            FilterChoice(label: 'Psychological', value: 'Psychological'),
            FilterChoice(label: 'Romance', value: 'Romance'),
            FilterChoice(label: 'School Life', value: 'School Life'),
            FilterChoice(label: 'Sci-fi', value: 'Sci-fi'),
            FilterChoice(label: 'Seinen', value: 'Seinen'),
            FilterChoice(label: 'Shoujo', value: 'Shoujo'),
            FilterChoice(label: 'Shounen', value: 'Shounen'),
            FilterChoice(label: 'Shounen Ai', value: 'Shounen Ai'),
            FilterChoice(label: 'Slice of Life', value: 'Slice of Life'),
            FilterChoice(label: 'Sports', value: 'Sports'),
            FilterChoice(label: 'Supernatural', value: 'Supernatural'),
            FilterChoice(label: 'Tragedy', value: 'Tragedy'),
            FilterChoice(label: 'Yuri', value: 'Yuri'),
            FilterChoice(label: 'Demons', value: 'Demons'),
            FilterChoice(label: 'Josei', value: 'Josei'),
            FilterChoice(label: 'Magic', value: 'Magic'),
            FilterChoice(label: 'Super Power', value: 'Super Power'),
            FilterChoice(label: 'Smut', value: 'Smut'),
            FilterChoice(label: 'Yaoi', value: 'Yaoi'),
            FilterChoice(label: 'Isekai', value: 'Isekai'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'last_update',
          choices: [
            FilterChoice(label: '最近更新', value: 'last_update'),
            FilterChoice(label: '人气', value: 'views'),
          ],
        ),
      ];

  // --- Discovery ---

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final genre = filters['genre'] ?? '';

    if (genre.isNotEmpty) {
      // Genre pages: /manga-list-genre-{Genre}.html (with pagination query)
      return FetchConfig(
        url: '$_baseUrl/manga-list-genre-$genre.html',
        queryParameters: {
          'listType': 'pagination',
          'page': page.toString(),
        },
        headers: defaultHeaders,
      );
    }

    return FetchConfig(
      url: '$_baseUrl/manga-list.html',
      queryParameters: {
        'listType': 'pagination',
        'sort': filters['sort'] ?? 'last_update',
        'sort_type': 'DESC',
        'page': page.toString(),
      },
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseCards(response as String);
  }

  /// Parse manga cards from list/search pages.
  /// Each card is a `div.thumb-wrapper` with an `a[href^="hwms-"]`, a
  /// lazy-loaded cover in `div.img-in-ratio[data-bg]`, and a title in
  /// `h3.title-thumb`.
  List<MangaSummary> _parseCards(String html) {
    final document = html_parser.parse(html);
    final wrappers = document.querySelectorAll('div.thumb-wrapper');
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final wrapper in wrappers) {
      final link = wrapper.querySelector('a[href^="hwms-"]');
      final href = link?.attributes['href'] ?? '';
      final slug = _slugFromHwms(href);
      if (slug.isEmpty || seen.contains(slug)) continue;
      seen.add(slug);

      // Cover: lazy-loaded via data-bg on the ratio container.
      final coverEl = wrapper.querySelector('div.img-in-ratio');
      final coverUrl = (coverEl?.attributes['data-bg'] ??
              coverEl?.attributes['data-src'] ??
              '')
          .trim();

      // Title lives in a sibling `.series-title h3`, but querying from the
      // document scope via the same slug is unreliable, so look it up on the
      // parent card (thumb-wrapper's parent contains series-title).
      String title = wrapper.querySelector('h3.title-thumb')?.text.trim() ?? '';
      if (title.isEmpty) {
        final parent = wrapper.parent;
        title =
            parent?.querySelector('h3.title-thumb')?.text.trim() ?? '';
      }
      if (title.isEmpty) {
        // Fall back to the alt text / title attribute if present.
        title = link?.attributes['title']?.trim() ?? '';
      }
      if (title.isEmpty) continue;

      final latest = wrapper.querySelector('a[href^="bsaq-"]')?.text.trim();

      results.add(MangaSummary(
        id: slug,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        latestChapter: (latest == null || latest.isEmpty) ? null : latest,
        headers: defaultHeaders,
      ));
    }

    return results;
  }

  /// Extracts the slug from an `hwms-{slug}.html` href.
  String _slugFromHwms(String href) {
    var s = href.trim();
    final slash = s.lastIndexOf('/');
    if (slash != -1) s = s.substring(slash + 1);
    if (!s.startsWith('hwms-')) return '';
    s = s.substring('hwms-'.length);
    if (s.endsWith('.html')) s = s.substring(0, s.length - '.html'.length);
    return s;
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/manga-list.html',
      queryParameters: {'name': keyword},
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseCards(response as String);
  }

  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/hwms-$mangaId.html',
      headers: defaultHeaders,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final html = response as String;
    final document = html_parser.parse(html);

    final title = document.querySelector('ul.manga-info h3')?.text.trim() ?? '';

    // Cover — pagespeed may replace src with a placeholder and put the real
    // URL in data-pagespeed-lazy-src.
    final coverEl = document.querySelector('div.info-cover img.thumbnail');
    final coverUrl = (coverEl?.attributes['data-pagespeed-lazy-src'] ??
            coverEl?.attributes['src'] ??
            '')
        .trim();

    // Genres — take anchor TEXT (some hrefs contain '/').
    final tags = document
        .querySelectorAll("ul.manga-info a[href^='manga-list-genre-']")
        .map((a) => a.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // Status
    MangaStatus status = MangaStatus.unknown;
    if (document.querySelector("ul.manga-info a[href*='manga-completed']") !=
        null) {
      status = MangaStatus.completed;
    } else if (document
            .querySelector("ul.manga-info a[href*='manga-incomplete']") !=
        null) {
      status = MangaStatus.ongoing;
    }

    // Description — the <p> immediately after the <h3>Description</h3>.
    String? description;
    for (final h3 in document.querySelectorAll('h3')) {
      if (h3.text.trim() == 'Description') {
        var sibling = h3.nextElementSibling;
        while (sibling != null && sibling.localName != 'p') {
          sibling = sibling.nextElementSibling;
        }
        final text = sibling?.text.trim();
        if (text != null && text.isNotEmpty) description = text;
        break;
      }
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: '',
      tags: tags,
      status: status,
      chapters: const [],
      headers: defaultHeaders,
    );
  }

  // --- Chapter List ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are loaded via AJAX from a *.lstc?slug={slug} endpoint.
    return FetchConfig(
      url: '$_baseUrl/${_randomStr(25)}.lstc',
      queryParameters: {'slug': mangaId},
      headers: {
        ...?defaultHeaders,
        'Referer': '$_baseUrl/hwms-$mangaId.html',
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final html = response as String;
    final document = html_parser.parse(html);

    final links = document.querySelectorAll('a.chapter');
    final chapters = <ChapterItem>[];
    final seen = <String>{};

    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      var chapterId = href.trim();
      final slash = chapterId.lastIndexOf('/');
      if (slash != -1) chapterId = chapterId.substring(slash + 1);
      if (!chapterId.startsWith('bsaq-')) continue;
      if (chapterId.endsWith('.html')) {
        chapterId = chapterId.substring(0, chapterId.length - '.html'.length);
      }
      if (seen.contains(chapterId)) continue;
      seen.add(chapterId);

      final title =
          (link.attributes['title'] ?? link.text).trim();

      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: title.isEmpty ? chapterId : title,
      ));
    }

    return ChapterListResult(chapters: chapters);
  }

  // --- Chapter Content ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // page == firstPage: fetch the chapter HTML page to extract the numeric
    // cid. The framework then resolves images via the nextExtra indirection.
    return FetchConfig(
      url: '$_baseUrl/$chapterId.html',
      headers: defaultHeaders,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final html = response as String;

    // Extract numeric chapter id (cid) from `load_image(<cid>, ...)`.
    final match = RegExp(r'load_image\((\d+)').firstMatch(html);
    final cid = match?.group(1);

    final title = _titleFromChapterId(chapterId);

    if (cid == null) {
      // Could not resolve cid — return empty; nothing more to do.
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: title,
          images: const [],
          headers: defaultHeaders,
        ),
      );
    }

    // Empty images + nextExtra triggers the framework's indirection flow.
    // The resolver uses FetchConfig(url: pageUrl) with NO query params, so
    // the cid must be embedded directly in the URL query string.
    final iogUrl = '$_baseUrl/${_randomStr(25)}.iog?cid=$cid';

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: const [],
        headers: defaultHeaders,
      ),
      nextExtra: jsonEncode([iogUrl]),
    );
  }

  /// Parses the `.iog` image-resolution page, which returns MANY images at
  /// once as `img.chapter-img` elements.
  @override
  List<ChapterImage>? parseChapterImagePage(dynamic response) {
    final html = response as String;
    final document = html_parser.parse(html);

    final imgs = document.querySelectorAll('img.chapter-img');
    final images = <ChapterImage>[];

    for (final img in imgs) {
      final src = (img.attributes['src'] ??
              img.attributes['data-src'] ??
              '')
          .trim();
      if (src.isEmpty) continue;
      images.add(ChapterImage(url: src, headers: defaultHeaders));
    }

    return images;
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/$chapterId.html';
  }

  /// Derives a human-readable title from a `bsaq-{slug}-chapter-{N}` id.
  String _titleFromChapterId(String chapterId) {
    final match = RegExp(r'-chapter-([\d.]+)$').firstMatch(chapterId);
    if (match != null) return 'Chapter ${match.group(1)}';
    return chapterId;
  }
}
