import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// mgread.io source plugin.
///
/// mgread.io is an English manga/manhwa/manhua aggregator built on WordPress
/// with a custom `init-manga` theme. This source uses pure HTML scraping
/// (the site's custom REST APIs require undocumented parameters and return
/// empty results for search).
///
/// - Discovery: home page manga cards.
/// - Search: `?s={keyword}&post_type=wp-manga` results page.
/// - Manga info: `/manga/{slug}/`, metadata primarily from JSON-LD, chapters
///   embedded in the same page.
/// - Chapter images: direct `https://mg.mgread.io/{postId}/{ch}/{n}.jpg` links
///   embedded in the chapter page HTML (no scrambling).
class MgRead extends MangaSource {
  static const String sourceId = 'mgread';
  static const String _baseUrl = 'https://mgread.io';

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/136.0.0.0 Safari/537.36';

  @override
  String get id => sourceId;

  @override
  String get name => 'MgRead';

  @override
  String get shortName => 'MGR';

  @override
  String? get description => 'English manga/manhwa/manhua';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => false;

  @override
  String? get userAgent => _desktopUserAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _desktopUserAgent,
        'Referer': '$_baseUrl/',
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'updated',
          choices: [
            FilterChoice(label: '最近更新', value: 'updated'),
            FilterChoice(label: '最新', value: 'new'),
            FilterChoice(label: '最早', value: 'old'),
            FilterChoice(label: '总人气', value: 'views'),
            FilterChoice(label: '日人气', value: 'views_day'),
            FilterChoice(label: '周人气', value: 'views_week'),
            FilterChoice(label: '月人气', value: 'views_month'),
            FilterChoice(label: '最高评分', value: 'rating'),
            FilterChoice(label: '最多推荐', value: 'power'),
            FilterChoice(label: '最多关注', value: 'follow'),
          ],
        ),
        FilterOption(
          name: 'genre',
          label: '类型',
          defaultValue: '',
          choices: [
            FilterChoice(label: '不限', value: ''),
            FilterChoice(label: 'Action', value: 'action'),
            FilterChoice(label: 'Adaptation', value: 'adaptation'),
            FilterChoice(label: 'Adventure', value: 'adventure'),
            FilterChoice(label: 'Anime', value: 'anime'),
            FilterChoice(label: 'Comedy', value: 'comedy'),
            FilterChoice(label: 'Cooking', value: 'cooking'),
            FilterChoice(label: 'Crime', value: 'crime'),
            FilterChoice(label: 'Drama', value: 'drama'),
            FilterChoice(label: 'Ecchi', value: 'ecchi'),
            FilterChoice(label: 'Fantasy', value: 'fantasy'),
            FilterChoice(label: 'Harem', value: 'harem'),
            FilterChoice(label: 'Historical', value: 'historical'),
            FilterChoice(label: 'Horror', value: 'horror'),
            FilterChoice(label: 'Isekai', value: 'isekai'),
            FilterChoice(label: 'Josei', value: 'josei'),
            FilterChoice(label: 'Martial Arts', value: 'martial-arts'),
            FilterChoice(label: 'Mature', value: 'mature'),
            FilterChoice(label: 'Mecha', value: 'mecha'),
            FilterChoice(label: 'Medical', value: 'medical'),
            FilterChoice(label: 'Music', value: 'music'),
            FilterChoice(label: 'Mystery', value: 'mystery'),
            FilterChoice(label: 'Romance', value: 'romance'),
            FilterChoice(label: 'School Life', value: 'school-life'),
            FilterChoice(label: 'Shoujo', value: 'shoujo'),
            FilterChoice(label: 'Shounen', value: 'shounen'),
            FilterChoice(label: 'Slice of Life', value: 'slice-of-life'),
            FilterChoice(label: 'Smut', value: 'smut'),
            FilterChoice(label: 'Sports', value: 'sports'),
            FilterChoice(label: 'Supernatural', value: 'supernatural'),
            FilterChoice(label: 'Webtoons', value: 'webtoons'),
          ],
        ),
        FilterOption(
          name: 'type',
          label: '媒介',
          defaultValue: '',
          choices: [
            FilterChoice(label: '不限', value: ''),
            FilterChoice(label: '漫画', value: 'comic'),
            FilterChoice(label: '小说', value: 'novel'),
            FilterChoice(label: '短篇', value: 'oneshot'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '状态',
          defaultValue: '',
          choices: [
            FilterChoice(label: '不限', value: ''),
            FilterChoice(label: '连载中', value: 'ongoing'),
            FilterChoice(label: '季完结', value: 'season_end'),
            FilterChoice(label: '完结', value: 'completed'),
            FilterChoice(label: '休刊', value: 'source_hiatus'),
            FilterChoice(label: '已追平', value: 'caught_up'),
            FilterChoice(label: '弃坑', value: 'dropped'),
          ],
        ),
        FilterOption(
          name: 'age_rating',
          label: '年龄分级',
          defaultValue: '',
          choices: [
            FilterChoice(label: '不限', value: ''),
            FilterChoice(label: '全年龄', value: 'all'),
            FilterChoice(label: '13+', value: '13+'),
            FilterChoice(label: '16+', value: '16+'),
            FilterChoice(label: '18+', value: '18+'),
          ],
        ),
      ];

  // --- Regex patterns ---
  static final _mangaSlugPattern =
      RegExp(r'/manga/([^/?#]+)/?(?:$|[?#])');
  static final _chapterSlugPattern =
      RegExp(r'/manga/[^/]+/(chapter-[^/?#]+)/?');

  // ====== Discovery ======

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final sort = filters['sort'] ?? 'updated';
    final genre = filters['genre'] ?? '';
    final type = filters['type'] ?? '';
    final status = filters['status'] ?? '';
    final ageRating = filters['age_rating'] ?? '';

    final hasFilter = genre.isNotEmpty ||
        type.isNotEmpty ||
        status.isNotEmpty ||
        ageRating.isNotEmpty ||
        (sort.isNotEmpty && sort != 'updated');

    // No filters and default sort: use the lightweight home page.
    if (!hasFilter) {
      return FetchConfig(
        url: '$_baseUrl/',
        headers: defaultHeaders,
      );
    }

    // Otherwise use the advanced-filter endpoint (path-based pagination).
    final query = <String, String>{};
    if (sort.isNotEmpty) query['sort'] = sort;
    if (genre.isNotEmpty) query['genre[]'] = genre;
    if (type.isNotEmpty) query['type'] = type;
    if (status.isNotEmpty) query['status'] = status;
    if (ageRating.isNotEmpty) query['age_rating'] = ageRating;

    return FetchConfig(
      url: '$_baseUrl/advanced-filter/page/$page/',
      queryParameters: query,
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseCardsFromHtml(response as String);
  }

  // ====== Search ======

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/',
      queryParameters: {
        's': keyword,
        'post_type': 'wp-manga',
      },
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseCardsFromHtml(response as String);
  }

  // ====== Manga Info ======

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/manga/$mangaId/',
      headers: defaultHeaders,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Prefer JSON-LD ComicSeries block for metadata.
    final ld = _findComicSeriesLd(document);

    String title = '';
    String? desc;
    String coverUrl = '';
    final tags = <String>[];

    if (ld != null) {
      title = _asString(ld['name']);
      desc = _cleanText(_asString(ld['description']));
      final image = ld['image'];
      if (image is Map<String, dynamic>) {
        coverUrl = _asString(image['url']);
      } else if (image is String) {
        coverUrl = image;
      }
      final genre = ld['genre'];
      if (genre is List) {
        for (final g in genre) {
          final gs = g.toString().trim();
          if (gs.isNotEmpty) tags.add(gs);
        }
      }
    }

    // Fallbacks from page HTML.
    if (title.isEmpty) {
      title = document.querySelector('h1')?.text.trim() ?? '';
    }
    if (coverUrl.isEmpty) {
      final coverEl =
          document.querySelector('img[alt^="Cover image of"]');
      coverUrl = coverEl?.attributes['src'] ?? '';
    }
    if (desc == null || desc.isEmpty) {
      final descEl = document.querySelector('#manga-description');
      final p = descEl?.querySelector('p') ?? descEl;
      final t = p?.text.trim();
      if (t != null && t.isNotEmpty) desc = _cleanText(t);
    }

    // The detail page only embeds the FIRST page of chapters (~24). Returning
    // them here would make DetailCubit treat the list as complete and skip
    // pagination entirely. Return empty chapters to force the paginated
    // `getChapterList` path, which walks `/manga/{slug}/chapter/page/{N}/`.
    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: desc,
      tags: tags,
      status: MangaStatus.unknown,
      chapters: const [],
      headers: defaultHeaders,
    );
  }

  // ====== Chapter List (paginated) ======

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    return FetchConfig(
      url: '$_baseUrl/manga/$mangaId/chapter/page/$page/',
      headers: defaultHeaders,
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final document = html_parser.parse(response as String);
    final chapters = _parseChapterItems(document, mangaId);

    // Pagination: `<ul class="uk-pagination">` with links to
    // `/manga/{slug}/chapter/page/{N}/`. Derive current and max page.
    int maxPage = 1;
    int currentPage = 1;
    final pageLinkPattern = RegExp(r'/chapter/page/(\d+)/');
    for (final a in document.querySelectorAll('.uk-pagination a')) {
      final m = pageLinkPattern.firstMatch(a.attributes['href'] ?? '');
      if (m != null) {
        final p = int.tryParse(m.group(1)!) ?? 1;
        if (p > maxPage) maxPage = p;
      }
    }
    // Active page is the pagination item marked `uk-active`.
    final activeEl = document.querySelector('.uk-pagination .uk-active');
    final curVal = int.tryParse(activeEl?.text.trim() ?? '');
    if (curVal != null) currentPage = curVal;
    if (currentPage > maxPage) maxPage = currentPage;

    final canLoadMore = chapters.isNotEmpty && currentPage < maxPage;

    return ChapterListResult(
      chapters: chapters,
      canLoadMore: canLoadMore,
      nextPage: canLoadMore ? currentPage + 1 : null,
    );
  }

  // ====== Chapter Content ======

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/manga/$mangaId/$chapterId/',
      headers: defaultHeaders,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final content = document.querySelector('#chapter-content');
    final imgEls = (content ?? document.documentElement!)
        .querySelectorAll('img');

    final images = <ChapterImage>[];
    final seen = <String>{};
    for (final el in imgEls) {
      final src = el.attributes['src'] ??
          el.attributes['data-src'] ??
          el.attributes['data-original-src'] ??
          '';
      if (src.isEmpty) continue;
      if (!src.contains('mg.mgread.io')) continue;
      if (seen.contains(src)) continue;
      seen.add(src);
      images.add(ChapterImage(
        url: src,
        headers: defaultHeaders,
      ));
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: images,
        headers: defaultHeaders,
      ),
      canLoadMore: false,
    );
  }

  // --- Private helpers ---

  /// Parse manga cards (home / search) into summaries, deduped by slug.
  ///
  /// Both layouts point at `/manga/{slug}/`, but expose title/cover
  /// differently:
  ///  - Home: title lives in the cover `<img alt="Cover image of {Title}">`.
  ///  - Search: title lives in a heading anchor (`a.uk-link-heading`), while
  ///    the image alt is a generic "Illustration: ..." string; the cover is a
  ///    `-150x150` thumbnail.
  /// A single pass over all `/manga/{slug}/` anchors aggregates the best
  /// title and cover per slug, preserving first-seen order.
  List<MangaSummary> _parseCardsFromHtml(String htmlStr) {
    final document = html_parser.parse(htmlStr);

    final order = <String>[];
    final seen = <String>{};
    final titles = <String, String>{};
    final covers = <String, String>{};

    final anchors = document.querySelectorAll('a[href*="/manga/"]');
    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('/chapter-')) continue;
      final slugMatch = _mangaSlugPattern.firstMatch(href);
      if (slugMatch == null) continue;
      final slug = slugMatch.group(1)!;
      if (slug == 'chapter') continue;

      if (seen.add(slug)) {
        order.add(slug);
      }

      // Cover: any image inside this anchor. Upgrade thumbnails to full size.
      final img = a.querySelector('img');
      if (img != null) {
        final raw = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
        final cover = _upgradeCover(raw.trim());
        if (cover.isNotEmpty) {
          covers.putIfAbsent(slug, () => cover);
        }
      }

      // Title candidates, best first:
      //  1. heading anchor text (search layout)
      //  2. image alt with "Cover image of " prefix stripped (home layout)
      //  3. plain anchor text
      final className = a.attributes['class'] ?? '';
      final anchorText = a.text.trim();
      String? candidate;
      if (className.contains('uk-link-heading') && anchorText.isNotEmpty) {
        candidate = anchorText;
      } else {
        final alt = img?.attributes['alt']?.trim() ?? '';
        final stripped = alt.replaceFirst(
            RegExp(r'^Cover image of\s+', caseSensitive: false), '');
        if (stripped.isNotEmpty &&
            !RegExp(r'^Illustration:', caseSensitive: false)
                .hasMatch(stripped)) {
          candidate = stripped;
        } else if (anchorText.isNotEmpty) {
          candidate = anchorText;
        }
      }

      if (candidate != null && candidate.isNotEmpty) {
        final existing = titles[slug];
        // Prefer a heading-derived title; otherwise take the first non-empty.
        if (existing == null || className.contains('uk-link-heading')) {
          titles[slug] = _cleanText(candidate);
        }
      }
    }

    final results = <MangaSummary>[];
    for (final slug in order) {
      final title = titles[slug] ?? '';
      final cover = covers[slug] ?? '';
      if (title.isEmpty && cover.isEmpty) continue;
      results.add(MangaSummary(
        id: slug,
        sourceId: sourceId,
        title: title,
        coverUrl: cover,
        headers: defaultHeaders,
      ));
    }

    return results;
  }

  /// Parse chapter list items from a chapter-list page document.
  ///
  /// Items live in `<div class=chapter-item>` blocks inside `#chapter-list`.
  /// The page also has a `.reading-buttons` "Read First" anchor pointing at
  /// chapter-1; that anchor is NOT inside a `.chapter-item`, so scoping to
  /// `.chapter-item` naturally excludes it. Chapters are returned in page
  /// order (newest-first, matching the site); the detail UI provides its own
  /// sort toggle.
  List<ChapterItem> _parseChapterItems(
      dom.Document document, String mangaId) {
    final chapters = <ChapterItem>[];
    final seen = <String>{};

    final scope = document.querySelector('#chapter-list') ??
        document.documentElement!;
    final items = scope.querySelectorAll('.chapter-item');
    for (final item in items) {
      final a = item.querySelector('a[href*="/chapter-"]') ??
          item.querySelector('a');
      final href = a?.attributes['href'] ?? '';
      final match = _chapterSlugPattern.firstMatch(href);
      if (match == null) continue;
      final chapterId = match.group(1)!;
      if (seen.contains(chapterId)) continue;
      seen.add(chapterId);

      final title = item.querySelector('h3')?.text.trim() ??
          a?.text.trim() ??
          chapterId;

      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: _cleanText(title),
        href: href.isNotEmpty ? href : null,
      ));
    }

    return chapters;
  }

  /// Find and decode the JSON-LD block whose @type includes ComicSeries.
  Map<String, dynamic>? _findComicSeriesLd(dom.Document document) {
    final scripts =
        document.querySelectorAll('script[type="application/ld+json"]');
    for (final s in scripts) {
      final raw = s.text.trim();
      if (raw.isEmpty) continue;
      dynamic decoded;
      try {
        decoded = json.decode(raw);
      } catch (_) {
        continue;
      }
      final candidates = <dynamic>[];
      if (decoded is List) {
        candidates.addAll(decoded);
      } else if (decoded is Map<String, dynamic>) {
        candidates.add(decoded);
        final graph = decoded['@graph'];
        if (graph is List) candidates.addAll(graph);
      }
      for (final c in candidates) {
        if (c is Map<String, dynamic> && _typeContainsSeries(c['@type'])) {
          return c;
        }
      }
    }
    return null;
  }

  bool _typeContainsSeries(dynamic type) {
    if (type is String) {
      return type.contains('ComicSeries') || type.contains('CreativeWorkSeries');
    }
    if (type is List) {
      return type.any((t) =>
          t.toString().contains('ComicSeries') ||
          t.toString().contains('CreativeWorkSeries'));
    }
    return false;
  }

  String _asString(dynamic v) => v == null ? '' : v.toString();

  /// Upgrade a `-150x150` / `-212x300` thumbnail URL to the full-size image.
  ///
  /// WordPress appends a `-{w}x{h}` suffix before the extension for generated
  /// thumbnail sizes; stripping it yields the original upload.
  String _upgradeCover(String url) {
    if (url.isEmpty) return url;
    return url.replaceFirstMapped(
        RegExp(r'-\d+x\d+(\.(?:webp|jpg|jpeg|png))', caseSensitive: false),
        (m) => m.group(1)!);
  }

  /// Unescape HTML entities and collapse whitespace.
  String _cleanText(String text) {
    if (text.isEmpty) return text;
    var t = html_parser.parseFragment(text).text ?? text;
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }
}
