import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Manga18.Club source plugin (18+ adult manhwa/manga, English UI).
///
/// Site is built on the "Manga18" template (same base used by several adult
/// aggregators in the Tachiyomi/keiyoushi ecosystem). NOT a Madara theme.
///
/// URL patterns:
///   Popular : GET {base}/list-manga/{page}?order_by=views
///   Latest  : GET {base}/list-manga/{page}
///   Search  : GET {base}/list-manga/{page}?search={query}
///   Detail  : GET {base}{mangaPath}          (chapters embedded in the page)
///   Chapter : GET {base}{chapterPath}        (images are base64-encoded)
///
/// Chapter images live in an inline <script> that assigns a `slides_p_path`
/// array of base64-encoded image URLs.
class Manga18Club extends MangaSource {
  static const String sourceId = 'manga18';
  static const String _baseUrl = 'https://manga18.club';

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  @override
  String get id => sourceId;

  @override
  String get name => 'Manga18.Club';

  @override
  String get shortName => 'M18';

  @override
  String? get description => '18+ Korean/Japanese manhwa & manga (English)';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => true;

  @override
  bool get needsProxy => true;

  @override
  bool get needsCloudflare => true;

  // Cloudflare on this site enforces TLS/JA3 fingerprint binding on the
  // cf_clearance cookie, so a plain Dio request is rejected (403) even with a
  // valid cookie. Route requests through the on-device WebView engine to reuse
  // the real browser TLS fingerprint and CF session. Native-only.
  @override
  bool get usesWebViewFetch => true;

  @override
  String? get userAgent => _ua;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _ua,
        'Referer': '$_baseUrl/',
      };

  // URL opened in the native WebView to pass the Cloudflare challenge and
  // capture the cf_clearance cookie. The site home page triggers CF.
  @override
  String? get cloudflareUrl => '$_baseUrl/';

  // Locate the `slides_p_path` assignment. We only anchor on the variable
  // name; the array bounds are resolved manually (first '[' .. ',]'/']') to
  // mirror the upstream keiyoushi implementation and avoid non-greedy
  // truncation when the array spans many entries.
  static final _slidesPattern = RegExp(r'slides_p_path\s*=');

  // ====== Discovery ======

  // Genre labels are Chinese for display; values are the site's own genre
  // slugs used in the `{base}/manga-list/{slug}/{page}` URL pattern (scraped
  // from the "Browse Manga by Genres" footer + confirmed live on several
  // entries). Slug derivation: lowercase, spaces -> '-', trailing '+' dropped.
  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'views',
          choices: [
            FilterChoice(label: '人气', value: 'views'),
            FilterChoice(label: '最新', value: 'latest'),
          ],
        ),
        FilterOption(
          name: 'genre',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '动作', value: 'action'),
            FilterChoice(label: '冒险', value: 'adventure'),
            FilterChoice(label: '喜剧', value: 'comedy'),
            FilterChoice(label: '剧情', value: 'drama'),
            FilterChoice(label: '奇幻', value: 'fantasy'),
            FilterChoice(label: '恐怖', value: 'horror'),
            FilterChoice(label: '悬疑', value: 'mystery'),
            FilterChoice(label: '心理', value: 'psychological'),
            FilterChoice(label: '恋爱', value: 'romance'),
            FilterChoice(label: '校园', value: 'school-life'),
            FilterChoice(label: '科幻', value: 'sci-fi'),
            FilterChoice(label: '日常', value: 'slice-of-life'),
            FilterChoice(label: '运动', value: 'sports'),
            FilterChoice(label: '超自然', value: 'supernatural'),
            FilterChoice(label: '悲剧', value: 'tragedy'),
            FilterChoice(label: '历史', value: 'historical'),
            FilterChoice(label: '机甲', value: 'mecha'),
            FilterChoice(label: '同人', value: 'doujinshi'),
            FilterChoice(label: '性转', value: 'gender-bender'),
            FilterChoice(label: '后宫', value: 'harem'),
            FilterChoice(label: '少年', value: 'shounen'),
            FilterChoice(label: '少女', value: 'shoujo'),
            FilterChoice(label: '青年', value: 'seinen'),
            FilterChoice(label: '女性向', value: 'josei'),
            FilterChoice(label: '福利', value: 'ecchi'),
            FilterChoice(label: '耽美', value: 'shounen-ai'),
            FilterChoice(label: '百合', value: 'shojou-ai'),
            FilterChoice(label: '纯爱/BL', value: 'yaoi'),
            FilterChoice(label: '成人', value: 'adult'),
            FilterChoice(label: '成人向', value: 'mature'),
            FilterChoice(label: '情色', value: 'smut'),
            FilterChoice(label: '18+', value: '18'),
            FilterChoice(label: '无删减', value: 'uncensored'),
            FilterChoice(label: '生肉', value: 'raw'),
            FilterChoice(label: '真人', value: 'live-action'),
            FilterChoice(label: '格斗', value: 'martial-art'),
            FilterChoice(label: '韩漫', value: 'manhwa'),
            FilterChoice(label: '国漫', value: 'manhua'),
            FilterChoice(label: '单行本', value: 'one-shot'),
            FilterChoice(label: '动画', value: 'anime'),
            FilterChoice(label: '漫画', value: 'comic'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final genre = filters['genre'] ?? '';
    final sort = filters['sort'] ?? 'views';
    final url = genre.isNotEmpty
        ? '$_baseUrl/manga-list/$genre/$page'
        : '$_baseUrl/list-manga/$page';
    return FetchConfig(
      url: url,
      queryParameters: {'order_by': sort},
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseList(response as String);
  }

  // ====== Search ======

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/list-manga/$page',
      queryParameters: {'search': keyword.trim()},
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseList(response as String);
  }

  /// Shared parser for popular/latest/search list pages.
  List<MangaSummary> _parseList(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    final items = document.querySelectorAll('div.story_item');
    for (final item in items) {
      final linkEl = item.querySelector('a');
      final href = linkEl?.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final mangaId = _toPath(href);

      final title = item
              .querySelector('div.mg_info > div.mg_name a')
              ?.text
              .trim() ??
          linkEl?.attributes['title']?.trim() ??
          '';
      if (title.isEmpty) continue;

      final imgEl = item.querySelector('img');
      final coverSrc =
          imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '';
      final coverUrl = _absUrl(coverSrc);

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        headers: defaultHeaders,
      ));
    }

    return results;
  }

  // ====== Manga Info ======

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: _absUrl(mangaId),
      headers: defaultHeaders,
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final title = document.querySelector('div.detail_name > h1')?.text.trim() ??
        document.querySelector('title')?.text.trim() ??
        '';

    final coverSrc =
        document.querySelector('div.detail_avatar > img')?.attributes['src'] ??
            '';
    final coverUrl = _absUrl(coverSrc);

    // Description
    final descEls = document.querySelectorAll('div.detail_reviewContent');
    final description = descEls.isNotEmpty
        ? descEls.map((e) => e.text.trim()).where((t) => t.isNotEmpty).join('\n')
        : null;

    // Status
    MangaStatus status = MangaStatus.unknown;
    final statusText =
        _infoValue(document, 'Status')?.toLowerCase() ?? '';
    if (statusText.contains('on going') || statusText.contains('ongoing')) {
      status = MangaStatus.ongoing;
    } else if (statusText.contains('completed')) {
      status = MangaStatus.completed;
    }

    // Author (author / autor label variants)
    final author = _infoLabelValue(document, ['author', 'autor']) ?? '';

    // Tags / genres
    final tags = <String>[];
    for (final a
        in document.querySelectorAll('div.info_value > a[href*="/manga-list/"]')) {
      final t = a.text.trim();
      if (t.isNotEmpty) tags.add(t);
    }

    // Chapters (embedded in detail page). HTML lists newest-first (descending).
    final chapters = <ChapterItem>[];
    final seen = <String>{};
    for (final el in document.querySelectorAll('div.chapter_box .item')) {
      final a = el.querySelector('a');
      final href = a?.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final chapterId = _toPath(href);
      if (seen.contains(chapterId)) continue;
      seen.add(chapterId);

      final chapterTitle = a?.text.trim() ?? '';
      if (chapterTitle.isEmpty) continue;

      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: chapterTitle,
      ));
    }
    // Present oldest-first to match reader expectations.
    final orderedChapters = chapters.reversed.toList();

    final latestChapter = chapters.isNotEmpty ? chapters.first.title : null;

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: tags,
      status: status,
      latestChapter: latestChapter,
      headers: defaultHeaders,
      chapters: orderedChapters,
    );
  }

  // ====== Chapter List (embedded in manga info) ======

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // ====== Chapter Content ======

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: _absUrl(chapterId),
      headers: defaultHeaders,
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final images = <ChapterImage>[];

    final match = _slidesPattern.firstMatch(htmlStr);
    if (match != null) {
      // Take everything after the first '[' following the assignment, then up
      // to the closing bracket. Prefer ',]' (trailing-comma form used by the
      // site) and fall back to a plain ']'.
      final afterAssign = htmlStr.substring(match.end);
      final openIdx = afterAssign.indexOf('[');
      if (openIdx != -1) {
        var body = afterAssign.substring(openIdx + 1);
        final closeComma = body.indexOf(',]');
        final closePlain = body.indexOf(']');
        if (closeComma != -1) {
          body = body.substring(0, closeComma);
        } else if (closePlain != -1) {
          body = body.substring(0, closePlain);
        }
        for (final rawEntry in body.split(',')) {
          final b64 = rawEntry.replaceAll('"', '').replaceAll("'", '').trim();
          if (b64.isEmpty) continue;
          String decoded;
          try {
            decoded = utf8.decode(base64.decode(b64));
          } catch (_) {
            continue;
          }
          decoded = decoded.trim();
          if (decoded.isEmpty) continue;
          final url = decoded.startsWith('/') ? '$_baseUrl$decoded' : decoded;
          images.add(ChapterImage(
            url: url,
            headers: defaultHeaders,
          ));
        }
      }
    }

    final title =
        html_parser.parse(htmlStr).querySelector('title')?.text.trim() ?? '';

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: defaultHeaders,
      ),
      canLoadMore: false,
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return _absUrl(chapterId);
  }

  // --- Private Helpers ---

  /// Normalize a possibly-absolute href into a stable manga/chapter id.
  ///
  /// The id is a site path WITHOUT a leading slash (e.g. "manhwa/secret-class")
  /// so it can be safely embedded in a single go_router path segment. Any
  /// internal slashes are percent-encoded (`%2F`) to keep the id opaque to the
  /// router, and decoded back in [_absUrl].
  String _toPath(String href) {
    var path = href.trim();
    if (path.startsWith('http')) {
      final uri = Uri.tryParse(path);
      if (uri != null) {
        path = uri.path;
        if (uri.hasQuery) path = '$path?${uri.query}';
      }
    }
    // Drop leading slash so the id is a bare path.
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    // Drop trailing slash for consistency.
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    // Return the bare path (may contain slashes). Route helpers percent-encode
    // ids into a single go_router segment; go_router decodes back to this value
    // and _absUrl reconstructs the absolute URL from it.
    return path;
  }

  /// Turn a relative path/URL or an encoded id into an absolute URL.
  String _absUrl(String value) {
    // Decode ids produced by [_toPath] (slashes were percent-encoded).
    final v = value.trim().replaceAll('%2F', '/');
    if (v.isEmpty) return '';
    if (v.startsWith('http')) return v;
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('/')) return '$_baseUrl$v';
    return '$_baseUrl/$v';
  }

  /// Read an info row value by its label text (e.g. "Status", "Other name").
  /// Matches `div.item:contains(<label>) div.info_value`.
  String? _infoValue(dynamic document, String label) {
    for (final item in document.querySelectorAll('div.detail_listInfo div.item')) {
      if (item.text.toLowerCase().contains(label.toLowerCase())) {
        final value = item.querySelector('div.info_value')?.text.trim();
        if (value != null && value.isNotEmpty && value != 'Updating') {
          return value;
        }
      }
    }
    return null;
  }

  /// Read an info value where the label sits in `div.info_label` and the value
  /// in the sibling `div.info_value`. Accepts multiple label spellings.
  String? _infoLabelValue(dynamic document, List<String> labels) {
    for (final row in document.querySelectorAll('div.item')) {
      final labelText =
          row.querySelector('div.info_label')?.text.trim().toLowerCase() ?? '';
      final matched = labels.any((l) => labelText.contains(l.toLowerCase()));
      if (!matched) continue;
      final value = row.querySelector('div.info_value')?.text.trim();
      if (value != null && value.isNotEmpty && value != 'Updating') {
        return value;
      }
    }
    return null;
  }
}
