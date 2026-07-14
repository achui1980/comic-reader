import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Weeb Central (weebcentral.com) — English aggregator manga/manhwa site.
///
/// SSR + HTMX site sitting behind Cloudflare's TLS/JA3 fingerprint check,
/// so it must route requests through the WebView fetch channel on native
/// (see [usesWebViewFetch]) and through curl-impersonate on web.
///
/// Endpoints (all HTMX fragments):
/// - Quick search:  POST /search/simple?location=main   (body: text=<kw>)
/// - Search/browse: GET  /search/data?limit=32&offset=<n>&text=<kw>&...
/// - Detail:        GET  /series/{ULID}/{slug}
/// - Chapter list:  GET  /series/{ULID}/full-chapter-list
/// - Chapter images:GET  /chapters/{ULID}/images?is_prev=False&current_page=1&reading_style=long_strip
class WeebCentral extends MangaSource {
  static const String sourceId = 'weebcentral';

  static const String _baseUrl = 'https://weebcentral.com';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36';

  /// Page size used by the /search/data endpoint.
  static const int _pageSize = 32;

  @override
  String get id => sourceId;

  @override
  String get name => 'Weeb Central';

  @override
  String get shortName => 'Weeb';

  @override
  String? get description =>
      'English manga/manhwa/manhua aggregator (weebcentral.com).';

  @override
  bool get isAdult => true;

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

  // --- Filters ---------------------------------------------------------------
  // These map to the /search/data advanced-search form fields. Discovery and
  // search share the same set. A value of '' means "don't send this param"
  // (i.e. the site's own default applies).

  static const List<FilterOption> _filters = [
    FilterOption(
      name: 'sort',
      label: '排序',
      defaultValue: 'Best Match',
      choices: [
        FilterChoice(label: '最佳匹配', value: 'Best Match'),
        FilterChoice(label: '字母顺序', value: 'Alphabet'),
        FilterChoice(label: '人气', value: 'Popularity'),
        FilterChoice(label: '订阅数', value: 'Subscribers'),
        FilterChoice(label: '最近添加', value: 'Recently Added'),
        FilterChoice(label: '最新更新', value: 'Latest Updates'),
      ],
    ),
    FilterOption(
      name: 'order',
      label: '顺序',
      defaultValue: 'Descending',
      choices: [
        FilterChoice(label: '降序', value: 'Descending'),
        FilterChoice(label: '升序', value: 'Ascending'),
      ],
    ),
    FilterOption(
      name: 'included_type',
      label: '类型',
      defaultValue: '',
      choices: [
        FilterChoice(label: '全部', value: ''),
        FilterChoice(label: '日漫', value: 'Manga'),
        FilterChoice(label: '韩漫', value: 'Manhwa'),
        FilterChoice(label: '国漫', value: 'Manhua'),
        FilterChoice(label: '欧美漫', value: 'OEL'),
      ],
    ),
    FilterOption(
      name: 'included_status',
      label: '状态',
      defaultValue: '',
      choices: [
        FilterChoice(label: '全部', value: ''),
        FilterChoice(label: '连载中', value: 'Ongoing'),
        FilterChoice(label: '已完结', value: 'Complete'),
        FilterChoice(label: '休刊', value: 'Hiatus'),
        FilterChoice(label: '已取消', value: 'Canceled'),
      ],
    ),
    FilterOption(
      name: 'official',
      label: '官方',
      defaultValue: 'Any',
      choices: [
        FilterChoice(label: '任意', value: 'Any'),
        FilterChoice(label: '仅官方', value: 'True'),
        FilterChoice(label: '非官方', value: 'False'),
      ],
    ),
    FilterOption(
      name: 'adult',
      label: '成人 (18+)',
      defaultValue: 'Any',
      choices: [
        FilterChoice(label: '任意', value: 'Any'),
        FilterChoice(label: '仅成人', value: 'True'),
        FilterChoice(label: '隐藏成人', value: 'False'),
      ],
    ),
  ];

  @override
  List<FilterOption> get discoveryFilters => _filters;

  @override
  List<FilterOption> get searchFilters => _filters;

  // --- Helpers ---------------------------------------------------------------

  /// Extract a ULID from a `/series/{ULID}` or `/chapters/{ULID}` href.
  static String _idFromHref(String href, String segment) {
    final match =
        RegExp('/$segment/([0-9A-Za-z]+)').firstMatch(href);
    return match?.group(1) ?? '';
  }

  /// Pick a cover URL from a `<picture>` element: prefer the webp `source`
  /// srcset, fall back to the `img[src]`.
  static String _coverFromPicture(dom.Element? picture) {
    if (picture == null) return '';
    final source = picture.querySelector('source');
    final srcset = source?.attributes['srcset'];
    if (srcset != null && srcset.isNotEmpty) {
      // srcset may be "url 1x, url2 2x" — take the first URL.
      return srcset.split(',').first.trim().split(' ').first.trim();
    }
    final img = picture.querySelector('img');
    return img?.attributes['src'] ?? '';
  }

  // --- Discovery -------------------------------------------------------------
  // Discovery reuses the /search/data endpoint with an empty keyword.

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    return _searchDataConfig('', page, filters);
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) =>
      _parseSearchData(response as String);

  // --- Search ----------------------------------------------------------------

  FetchConfig _searchDataConfig(
      String keyword, int page, Map<String, String> filters) {
    final offset = (page - firstPage) * _pageSize;
    final query = <String, dynamic>{
      'limit': '$_pageSize',
      'offset': '$offset',
      'sort': filters['sort'] ?? 'Best Match',
      'order': filters['order'] ?? 'Descending',
      'official': filters['official'] ?? 'Any',
      'adult': filters['adult'] ?? 'Any',
      'display_mode': 'Full Display',
      'text': keyword,
    };

    // Multi-select params on the site; we expose a single choice each. Only
    // send them when a concrete (non-"All") value is picked.
    final type = filters['included_type'] ?? '';
    if (type.isNotEmpty) query['included_type'] = type;
    final status = filters['included_status'] ?? '';
    if (status.isNotEmpty) query['included_status'] = status;

    return FetchConfig(
      url: '$_baseUrl/search/data',
      queryParameters: query,
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return _searchDataConfig(keyword, page, filters);
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) =>
      _parseSearchData(response as String);

  List<MangaSummary> _parseSearchData(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    for (final article in document.querySelectorAll('article')) {
      final coverLink = article.querySelector('a[href*="/series/"]');
      final href = coverLink?.attributes['href'] ?? '';
      final mangaId = _idFromHref(href, 'series');
      if (mangaId.isEmpty) continue;

      final coverUrl = _coverFromPicture(article.querySelector('picture'));

      // Title: the linked title in the right-hand info section.
      String title = '';
      final titleLink =
          article.querySelector('a.line-clamp-1[href*="/series/"]') ??
              article.querySelector('a[href*="/series/"] .line-clamp-1');
      if (titleLink != null) {
        title = titleLink.text.trim();
      }
      if (title.isEmpty) {
        // Fallback: cover image alt (strips trailing " cover").
        final alt = article.querySelector('img')?.attributes['alt'] ?? '';
        title = alt.replaceAll(RegExp(r'\s*cover$', caseSensitive: false), '')
            .trim();
      }
      if (title.isEmpty) continue;

      // Author: <strong>Author(s):</strong> ... <span><a>Name</a></span>
      String author = '';
      for (final div in article.querySelectorAll('div')) {
        final strong = div.querySelector('strong');
        if (strong != null && strong.text.contains('Author')) {
          author = div
              .querySelectorAll('span a')
              .map((e) => e.text.trim())
              .where((s) => s.isNotEmpty)
              .join(', ');
          break;
        }
      }

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        author: author,
      ));
    }

    return results;
  }

  // --- Manga Info ------------------------------------------------------------

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/series/$mangaId',
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final document = html_parser.parse(response as String);

    final title =
        document.querySelector('h1.text-2xl.font-bold')?.text.trim() ?? '';
    final coverUrl = _coverFromPicture(document.querySelector('picture'));

    String author = '';
    final tags = <String>[];
    MangaStatus status = MangaStatus.unknown;

    for (final li in document.querySelectorAll('li')) {
      final strong = li.querySelector('strong');
      if (strong == null) continue;
      final label = strong.text.trim();
      if (label.startsWith('Author')) {
        author = li
            .querySelectorAll('span a')
            .map((e) => e.text.trim())
            .where((s) => s.isNotEmpty)
            .join(', ');
      } else if (label.startsWith('Tag')) {
        tags.addAll(li
            .querySelectorAll('span a')
            .map((e) => e.text.trim())
            .where((s) => s.isNotEmpty));
      } else if (label.startsWith('Status')) {
        final s = li.querySelector('a')?.text.trim().toLowerCase() ?? '';
        if (s.contains('ongoing')) {
          status = MangaStatus.ongoing;
        } else if (s.contains('complete')) {
          status = MangaStatus.completed;
        }
      }
    }

    final description =
        document.querySelector('p.whitespace-pre-wrap')?.text.trim();

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      description: description,
      tags: tags,
      status: status,
      chapters: const [],
    );
  }

  // --- Chapter List ----------------------------------------------------------
  // Full chapter list lives at a dedicated endpoint (detail page only embeds
  // the latest ~9 chapters).

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    if (page > firstPage) return null;
    return FetchConfig(
      url: '$_baseUrl/series/$mangaId/full-chapter-list',
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final document = html_parser.parse(response as String);
    final items = <ChapterItem>[];

    for (final a in document.querySelectorAll('a[href*="/chapters/"]')) {
      final href = a.attributes['href'] ?? '';
      final chapterId = _idFromHref(href, 'chapters');
      if (chapterId.isEmpty) continue;

      // Chapter name: first inner span text (e.g. "Chapter 450").
      String title = '';
      final grow = a.querySelector('span.grow') ?? a;
      final span = grow.querySelector('span');
      if (span != null) {
        title = span.text.trim();
      }
      if (title.isEmpty) title = a.text.trim();

      items.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        href: '$_baseUrl/chapters/$chapterId',
      ));
    }

    // Site lists newest-first; reverse to oldest-first for the reader.
    return ChapterListResult(chapters: items.reversed.toList());
  }

  // --- Chapter Content -------------------------------------------------------

  @override
  FetchConfig prepareChapterFetch(
      String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/chapters/$chapterId/images',
      queryParameters: {
        'is_prev': 'False',
        'current_page': '1',
        'reading_style': 'long_strip',
      },
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final document = html_parser.parse(response as String);
    final images = <ChapterImage>[];

    for (final img in document.querySelectorAll('section img[src]')) {
      final url = img.attributes['src'] ?? '';
      if (url.isEmpty) continue;
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
    return '$_baseUrl/chapters/$chapterId';
  }
}
