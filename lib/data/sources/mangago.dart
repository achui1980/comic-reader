import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Mangago (mangago.me) — English aggregator manga/manhwa/manhua site.
///
/// Sits behind Cloudflare, so requests are routed through the WebView-fetch
/// channel on native (see [usesWebViewFetch]) and through curl-impersonate on
/// web (see `tools/run_web.sh`).
///
/// The full list of image URLs for a chapter is stored in an encrypted
/// `var imgsrcs='...'` blob in the reader page HTML. The decryption is a fixed
/// AES-128-CBC (ZeroPadding) with hardcoded key/IV — the same for every chapter
/// — so we reproduce it in Dart ([_decryptImgsrcs]) and get all image URLs from
/// a single bare-chapter request, rather than rendering each `pg-N` page.
///
/// Endpoints:
/// - Discovery (latest): GET /list/latest/all/{page}/
/// - Discovery (filtered): GET /genre/{genre}/{page}/?f=&o=&sortby=&e=
/// - Search:             GET /r/l_search/?name=<kw>&page=<n>
/// - Detail:             GET /read-manga/{slug}/           (chapters embedded)
/// - Reader page:        GET /read-manga/{slug}/{chapterId}/
class Mangago extends MangaSource {
  static const String sourceId = 'mangago';

  static const String _baseUrl = 'https://www.mangago.me';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36';

  @override
  String get id => sourceId;

  @override
  String get name => 'Mangago';

  @override
  String get shortName => 'Mangago';

  @override
  String? get description =>
      'English manga/manhwa/manhua aggregator (mangago.me).';

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

  /// Extract the manga slug from a `/read-manga/{slug}/...` href.
  static String _slugFromHref(String href) {
    final match = RegExp(r'/read-manga/([^/]+)/').firstMatch(href);
    return match?.group(1) ?? '';
  }

  /// Extract the stable chapter id (the middle path segment(s) between the
  /// slug and the trailing `pg-N/`) from a reader href.
  ///
  /// e.g. `/read-manga/jinx/uu/br_chapter-128596/pg-1/` -> `uu/br_chapter-128596`
  ///      `/read-manga/jinx/mkk/mk_v-1-chapter-1/`      -> `mkk/mk_v-1-chapter-1`
  static String _chapterIdFromHref(String href) {
    // Strip origin if present.
    var rel = href;
    final schemeIdx = rel.indexOf('/read-manga/');
    if (schemeIdx > 0) rel = rel.substring(schemeIdx);
    final match = RegExp(r'/read-manga/[^/]+/(.+?)/?$').firstMatch(rel);
    var id = match?.group(1) ?? '';
    // Drop a trailing pg-N segment if present.
    id = id.replaceAll(RegExp(r'/pg-\d+/?$'), '');
    return id;
  }

  // AES-128-CBC key/IV used by the site to encrypt the `imgsrcs` blob. These
  // are global constants baked into the obfuscated chapter.js and are identical
  // for every chapter. The framework auto-injects the WebView-fetch /
  // Cloudflare `extra` for every request (see `usesWebViewFetch`), so sources
  // do not need to set it manually.
  static final _imgKey =
      encrypt.Key.fromBase16('e11adc3949ba59abbe56e057f20f883e');
  static final _imgIv =
      encrypt.IV.fromBase16('1234567890abcdef1234567890abcdef');

  // --- Filters ---------------------------------------------------------------
  // Genres exclude when "hide adult" is selected. These are mangago's own genre
  // names (used verbatim in the /genre/<Name>/ path and the e= exclude param).
  static const List<String> _adultGenres = [
    'Adult',
    'Mature',
    'Smut',
    'Yaoi',
    'Yuri',
    'Bara',
    'Doujinshi',
    'Ecchi',
  ];

  static const List<FilterChoice> _genreChoices = [
    FilterChoice(label: '全部', value: ''),
    FilterChoice(label: '动作', value: 'Action'),
    FilterChoice(label: '冒险', value: 'Adventure'),
    FilterChoice(label: '喜剧', value: 'Comedy'),
    FilterChoice(label: '剧情', value: 'Drama'),
    FilterChoice(label: '奇幻', value: 'Fantasy'),
    FilterChoice(label: '恋爱', value: 'Romance'),
    FilterChoice(label: '恐怖', value: 'Horror'),
    FilterChoice(label: '悬疑', value: 'Mystery'),
    FilterChoice(label: '科幻', value: 'Sci-fi'),
    FilterChoice(label: '历史', value: 'Historical'),
    FilterChoice(label: '少女', value: 'Shoujo'),
    FilterChoice(label: '少年', value: 'Shounen'),
    FilterChoice(label: '女性向', value: 'Josei'),
    FilterChoice(label: '青年', value: 'Seinen'),
    FilterChoice(label: '后宫', value: 'Harem'),
    FilterChoice(label: '校园', value: 'School Life'),
    FilterChoice(label: '日常', value: 'Slice Of Life'),
    FilterChoice(label: '运动', value: 'Sports'),
    FilterChoice(label: '超自然', value: 'Supernatural'),
    FilterChoice(label: '心理', value: 'Psychological'),
    FilterChoice(label: '武术', value: 'Martial Arts'),
    FilterChoice(label: '机甲', value: 'Mecha'),
    FilterChoice(label: '悲剧', value: 'Tragedy'),
    FilterChoice(label: '性转换', value: 'Gender Bender'),
    FilterChoice(label: '短篇', value: 'One Shot'),
    FilterChoice(label: '同人', value: 'Doujinshi'),
    FilterChoice(label: '网漫', value: 'Webtoons'),
    FilterChoice(label: '男男BL', value: 'Yaoi'),
    FilterChoice(label: '百合GL', value: 'Yuri'),
    FilterChoice(label: '少年爱', value: 'Shounen Ai'),
    FilterChoice(label: '少女爱', value: 'Shoujo Ai'),
    FilterChoice(label: '成人', value: 'Adult'),
    FilterChoice(label: '重口味', value: 'Mature'),
    FilterChoice(label: '情色', value: 'Smut'),
    FilterChoice(label: '卖肉', value: 'Ecchi'),
    FilterChoice(label: '熊男同', value: 'Bara'),
  ];

  static const List<FilterOption> _filters = [
    FilterOption(
      name: 'genre',
      label: '分类',
      defaultValue: '',
      choices: _genreChoices,
    ),
    FilterOption(
      name: 'sortby',
      label: '排序',
      defaultValue: '',
      choices: [
        FilterChoice(label: '最新更新', value: ''),
        FilterChoice(label: '浏览量', value: 'view'),
        FilterChoice(label: '人气', value: 'comment_count'),
        FilterChoice(label: '创建时间', value: 'create_date'),
        FilterChoice(label: '更新时间', value: 'update_date'),
      ],
    ),
    FilterOption(
      name: 'status',
      label: '状态',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '仅完结', value: 'finished'),
        FilterChoice(label: '仅连载', value: 'ongoing'),
      ],
    ),
    FilterOption(
      name: 'adult',
      label: '18+内容',
      defaultValue: 'hide',
      choices: [
        FilterChoice(label: '隐藏成人', value: 'hide'),
        FilterChoice(label: '显示全部', value: 'show'),
        FilterChoice(label: '仅看成人', value: 'only'),
      ],
    ),
  ];

  @override
  List<FilterOption> get discoveryFilters => _filters;

  // --- Discovery -------------------------------------------------------------
  // With no filters (all defaults) discovery uses the "latest updates" listing;
  // otherwise it uses the /genre/ advanced listing endpoint.

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    // Fast path: when the caller passes no filters at all (e.g. the initial
    // discovery load before the user touches the filter UI), use the plain
    // "latest" listing — original behaviour with the richest metadata.
    if (filters.isEmpty) {
      return FetchConfig(
        url: '$_baseUrl/list/latest/all/$page/',
        extra: const {'renderMode': true},
        timeout: const Duration(seconds: 60),
      );
    }

    final genre = (filters['genre'] ?? '').trim();
    final sortby = (filters['sortby'] ?? '').trim();
    final status = (filters['status'] ?? 'all').trim();
    final adult = (filters['adult'] ?? 'hide').trim();

    // Also stay on the latest listing when every filter is left at a neutral
    // value that the genre endpoint cannot express better (no genre, default
    // sort, all statuses, adult shown -> no exclusions needed).
    final neutral =
        genre.isEmpty && sortby.isEmpty && status == 'all' && adult == 'show';
    if (neutral) {
      return FetchConfig(
        url: '$_baseUrl/list/latest/all/$page/',
        extra: const {'renderMode': true},
        timeout: const Duration(seconds: 60),
      );
    }

    // Resolve the effective genre. "Only adult" forces the Adult genre when the
    // user hasn't picked one.
    var effectiveGenre = genre;
    if (adult == 'only' && effectiveGenre.isEmpty) {
      effectiveGenre = 'Adult';
    }
    final genrePath = effectiveGenre.isEmpty ? 'all' : effectiveGenre;

    // Status -> f (include Completed) / o (include Ongoing).
    String f;
    String o;
    switch (status) {
      case 'finished':
        f = '1';
        o = '0';
        break;
      case 'ongoing':
        f = '0';
        o = '1';
        break;
      default:
        f = '1';
        o = '1';
    }

    // Adult -> exclude list (only meaningful when hiding adult content).
    final exclude = adult == 'hide' ? _adultGenres.join(',') : '';

    return FetchConfig(
      url: '$_baseUrl/genre/$genrePath/$page/',
      queryParameters: {
        'f': f,
        'o': o,
        'sortby': sortby,
        'e': exclude,
      },
      extra: const {'renderMode': true},
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) =>
      _parseListData(response as String);

  // --- Search ----------------------------------------------------------------

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/r/l_search/',
      queryParameters: {
        'name': keyword,
        'page': '$page',
      },
      extra: const {'renderMode': true},
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) =>
      _parseListData(response as String);

  /// The latest listing and search results share the same
  /// `ul#search_list li > div.box` markup; the /genre/ advanced listing uses a
  /// different `.pic_list .updatesli` markup with lazy-loaded covers. We try the
  /// search-list layout first and fall back to the genre layout.
  List<MangaSummary> _parseListData(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    for (final li in document.querySelectorAll('#search_list li')) {
      final coverLink = li.querySelector('a.thm-effect[href*="/read-manga/"]') ??
          li.querySelector('a[href*="/read-manga/"]');
      final href = coverLink?.attributes['href'] ?? '';
      final mangaId = _slugFromHref(href);
      if (mangaId.isEmpty) continue;

      // Cover image (direct src, not lazy-loaded).
      final img = coverLink?.querySelector('img') ?? li.querySelector('img');
      final coverUrl = img?.attributes['src'] ?? '';

      // Title: prefer the info-row heading, fall back to the link title attr.
      String title = li.querySelector('.row-1 h2 a')?.text.trim() ?? '';
      if (title.isEmpty) {
        title = coverLink?.attributes['title']?.trim() ?? '';
      }
      if (title.isEmpty) {
        title = img?.attributes['alt']?.trim() ?? '';
      }
      if (title.isEmpty) continue;

      // Author: text after the "Author:" label in .row-3.
      final author = _labelledText(li.querySelector('.row-3'), 'Author');

      // Update date: text after the "Update Date:" label in .row-5.
      final updateTime = _labelledText(li.querySelector('.row-5'), 'Update');

      // Latest chapter: first chapter link in .row-5.
      final latestChapter =
          li.querySelector('.row-5 a.chico')?.text.trim();

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        author: author,
        latestChapter:
            (latestChapter != null && latestChapter.isNotEmpty)
                ? latestChapter
                : null,
        updateTime: updateTime.isNotEmpty ? updateTime : null,
      ));
    }

    // Fall back to the /genre/ advanced-listing layout.
    if (results.isEmpty) {
      results.addAll(_parseGenreListData(document));
    }

    return results;
  }

  /// Parse the `.pic_list .updatesli` markup used by the /genre/ listing.
  ///
  /// Covers are lazy-loaded (`data-src`); the info block (`.new_info`) carries
  /// no author/update fields, so only id/title/cover are available.
  List<MangaSummary> _parseGenreListData(dom.Document document) {
    final results = <MangaSummary>[];

    for (final li in document.querySelectorAll('.updatesli')) {
      final coverLink = li.querySelector('a.thm-effect[href*="/read-manga/"]') ??
          li.querySelector('a[href*="/read-manga/"]');
      final href = coverLink?.attributes['href'] ?? '';
      final mangaId = _slugFromHref(href);
      if (mangaId.isEmpty) continue;

      // Cover: prefer the lazy-loaded data-src over the placeholder src.
      final img = coverLink?.querySelector('img') ?? li.querySelector('img');
      var coverUrl = img?.attributes['data-src'] ?? '';
      if (coverUrl.isEmpty) coverUrl = img?.attributes['src'] ?? '';

      // Title: the `span.title a` text, falling back to the link/img attrs.
      String title = li.querySelector('.title a')?.text.trim() ??
          li.querySelector('.title')?.text.trim() ??
          '';
      if (title.isEmpty) {
        title = coverLink?.attributes['title']?.trim() ?? '';
      }
      if (title.isEmpty) {
        title = img?.attributes['alt']?.trim() ?? '';
      }
      if (title.isEmpty) continue;

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
      ));
    }

    return results;
  }

  /// Return the text of [element] with a leading `<span>`-style label removed.
  ///
  /// mangago info rows look like `<span class="blue">Author: </span>Name`, so
  /// we take the element's full text and strip everything up to and including
  /// the label keyword + a following colon.
  static String _labelledText(dom.Element? element, String label) {
    if (element == null) return '';
    final full = element.text.trim();
    final regex = RegExp('$label[^:]*:\\s*', caseSensitive: false);
    final match = regex.firstMatch(full);
    if (match == null) return full;
    // Take text after the label, and cut at a following label if any.
    var rest = full.substring(match.end).trim();
    // Some rows concatenate multiple label:value pairs; cut at next capitalised
    // "Xxx:" label to avoid bleeding into the next field.
    final next = RegExp(r'\s+[A-Z][a-zA-Z ]*:\s').firstMatch(rest);
    if (next != null) rest = rest.substring(0, next.start).trim();
    return rest;
  }

  // --- Manga Info ------------------------------------------------------------
  // Chapters are embedded in the detail page (#chapter_table).

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/read-manga/$mangaId/',
      extra: const {'renderMode': true},
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final document = html_parser.parse(response as String);

    final title = document.querySelector('h1')?.text.trim() ?? '';

    final coverImg = document.querySelector('#information .left.cover img') ??
        document.querySelector('img[src*="coverlink"]');
    final coverUrl = coverImg?.attributes['src'] ?? '';

    final description = document.querySelector('.manga_summary')?.text.trim();

    String author = '';
    final tags = <String>[];
    MangaStatus status = MangaStatus.unknown;

    for (final row in document.querySelectorAll('.manga_right table tr')) {
      final label = row.querySelector('label')?.text.trim().toLowerCase() ?? '';
      if (label.contains('status')) {
        final s = row.querySelector('span')?.text.trim().toLowerCase() ??
            row.text.toLowerCase();
        if (s.contains('ongoing')) {
          status = MangaStatus.ongoing;
        } else if (s.contains('complete')) {
          status = MangaStatus.completed;
        }
      } else if (label.contains('author')) {
        author = row
            .querySelectorAll('a[href*="l_search"]')
            .map((e) => e.text.trim())
            .where((s) => s.isNotEmpty)
            .join(', ');
        if (author.isEmpty) {
          author = row
              .querySelectorAll('a')
              .map((e) => e.text.trim())
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
      } else if (label.contains('genre')) {
        tags.addAll(row
            .querySelectorAll('a[href*="/genre/"]')
            .map((e) => e.text.trim())
            .where((s) => s.isNotEmpty));
      }
    }

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

  // --- Chapter List ----------------------------------------------------------
  // Chapters are embedded in the detail page; re-fetch the same page for the
  // dedicated chapter-list request.

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    if (page > firstPage) return null;
    return FetchConfig(
      url: '$_baseUrl/read-manga/$mangaId/',
      extra: const {'renderMode': true},
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final document = html_parser.parse(response as String);
    return ChapterListResult(
      chapters: _parseChapterItems(document, mangaId),
    );
  }

  /// Parse the `#chapter_table` chapter anchors into oldest-first order.
  List<ChapterItem> _parseChapterItems(dom.Document document, String mangaId) {
    final items = <ChapterItem>[];
    final anchors =
        document.querySelectorAll('#chapter_table a.chico[href*="/read-manga/"]');
    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      final chapterId = _chapterIdFromHref(href);
      if (chapterId.isEmpty) continue;

      String title = a.querySelector('b')?.text.trim() ?? '';
      if (title.isEmpty) title = a.text.trim();

      items.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        href: '$_baseUrl/read-manga/$mangaId/$chapterId/',
      ));
    }
    // Site lists newest-first; reverse to oldest-first for the reader.
    return items.reversed.toList();
  }

  // --- Chapter Content -------------------------------------------------------
  // The full chapter's image URLs are in an encrypted `var imgsrcs='...'` blob
  // in any reader page. We fetch the bare chapter URL once and decrypt the
  // whole chapter. Note: some chapters (e.g. oneshots) have no `pg-N` segment,
  // so we must NOT append `pg-1/` (that 404s); the bare URL works for all.

  @override
  FetchConfig prepareChapterFetch(
      String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/read-manga/$mangaId/$chapterId/',
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final html = response as String;
    final images = <ChapterImage>[];

    for (final url in _decryptImgsrcs(html)) {
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

  /// Decrypt the `var imgsrcs='...'` blob from a reader page into the full,
  /// ordered list of image URLs for the chapter.
  ///
  /// The blob is a Base64 AES-128-CBC (ZeroPadding) ciphertext. After decrypt
  /// the plaintext is a comma-separated URL list; a trailing `"1"`/`"2"` flag
  /// and any `cspiclink` placeholder entries are dropped.
  static List<String> _decryptImgsrcs(String html) {
    final match = RegExp(
      '''var\\s+imgsrcs\\s*=\\s*['"]([^'"]+)['"]''',
    ).firstMatch(html);
    final cipher = match?.group(1);
    if (cipher == null || cipher.isEmpty) return const [];

    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_imgKey, mode: encrypt.AESMode.cbc, padding: null),
      );
      final bytes = encrypter.decryptBytes(
        encrypt.Encrypted.fromBase64(cipher),
        iv: _imgIv,
      );
      // Strip ZeroPadding (trailing 0x00 bytes).
      var end = bytes.length;
      while (end > 0 && bytes[end - 1] == 0) {
        end--;
      }
      final text = utf8.decode(bytes.sublist(0, end), allowMalformed: true);

      final parts = text.split(',');
      if (parts.isNotEmpty && (parts.last == '1' || parts.last == '2')) {
        parts.removeLast();
      }
      return parts
          .where((p) => p.startsWith('http') && !p.contains('cspiclink'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/read-manga/$mangaId/$chapterId/';
  }
}
