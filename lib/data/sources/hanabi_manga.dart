import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Supabase project this source authenticates against.
const String _hanabiSupabaseUrl = 'https://uhkvqrxmcapgtpspglrp.supabase.co';
const String _hanabiAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoa3ZxcnhtY2FwZ3Rwc3BnbHJwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5NjgzMjksImV4cCI6MjA3OTU0NDMyOX0.uuHr888lp14ObW5eWowJrHPJGgQf3sF2l7NPmFN84g4';
const String _hanabiCookieName = 'sb-uhkvqrxmcapgtpspglrp-auth-token';
const int _hanabiCookieChunkSize = 3180;

/// Builds the Supabase SSR session cookie value that hanabimanga.com's
/// server-side API routes require. The site's `/api/*` routes only read
/// the session from this Cookie header — an `Authorization: Bearer` header
/// is silently ignored by the server.
///
/// If the JSON-encoded, base64'd payload exceeds [_hanabiCookieChunkSize]
/// characters, it is split across multiple same-name cookies suffixed
/// `.0`, `.1`, etc. (matching `@supabase/ssr`'s own chunking behavior),
/// joined into a single `Cookie:` header value with `; ` separators.
String buildHanabiSessionCookie({
  required String accessToken,
  required String refreshToken,
  required int expiresIn,
  required int expiresAt,
  required Map<String, dynamic> user,
}) {
  final payload = jsonEncode({
    'access_token': accessToken,
    'token_type': 'bearer',
    'expires_in': expiresIn,
    'expires_at': expiresAt,
    'refresh_token': refreshToken,
    'user': user,
  });
  final encoded = 'base64-${base64Encode(utf8.encode(payload))}';

  if (encoded.length <= _hanabiCookieChunkSize) {
    return '$_hanabiCookieName=$encoded';
  }

  final parts = <String>[];
  for (var i = 0; i < encoded.length; i += _hanabiCookieChunkSize) {
    final end = (i + _hanabiCookieChunkSize < encoded.length)
        ? i + _hanabiCookieChunkSize
        : encoded.length;
    parts.add('$_hanabiCookieName.${parts.length}=${encoded.substring(i, end)}');
  }
  return parts.join('; ');
}

/// Extracts the `application/ld+json` block with `"@type":"Book"` from a
/// hanabimanga.com comic detail page. Returns null if not found.
Map<String, dynamic>? extractHanabiBookLdJson(String html) {
  const marker = '<script type="application/ld+json">';
  var searchStart = 0;
  while (true) {
    final start = html.indexOf(marker, searchStart);
    if (start == -1) return null;
    final contentStart = start + marker.length;
    final end = html.indexOf('</script>', contentStart);
    if (end == -1) return null;
    final jsonStr = html.substring(contentStart, end);
    searchStart = end + '</script>'.length;
    if (!jsonStr.contains('"@type":"Book"')) continue;
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }
}

/// Extracts the full chapter list embedded in a hanabimanga.com comic
/// detail page's Next.js RSC flight payload. The data is present as a
/// backslash-escaped JSON string (e.g. `\"chapters\":[...]`) rather than
/// literal JSON, because it is nested inside a `self.__next_f.push([1,"..."])`
/// script tag. Square brackets themselves are NOT escaped, so the array's
/// extent can be found by simple bracket-depth counting; only the quotes
/// inside need unescaping before `jsonDecode`.
List<Map<String, dynamic>> extractHanabiChapters(String html) {
  const marker = r'\"chapters\":[';
  final markerIndex = html.indexOf(marker);
  if (markerIndex == -1) return const [];

  final arrayStart = markerIndex + marker.length - 1; // index of '['
  var depth = 0;
  var i = arrayStart;
  for (; i < html.length; i++) {
    final ch = html[i];
    if (ch == '[') depth++;
    if (ch == ']') {
      depth--;
      if (depth == 0) {
        i++; // move past the closing ']'
        break;
      }
    }
  }

  final rawArray = html.substring(arrayStart, i);
  final unescaped = rawArray.replaceAll(r'\"', '"');
  final decoded = jsonDecode(unescaped) as List<dynamic>;
  return decoded.cast<Map<String, dynamic>>();
}

/// HanabiManga (花火漫画) source plugin.
///
/// - Login: direct Supabase Auth REST calls (no WebView needed).
/// - Session: the server only trusts a hand-built Supabase SSR cookie
///   (see [buildHanabiSessionCookie]), stored via the generic
///   [MangaSource.extraHeaders]/[MangaSource.syncExtraData] mechanism.
/// - Chapter list: embedded in the comic detail page HTML itself (see
///   [extractHanabiChapters]); [prepareChapterListFetch] returns null.
/// - Image descrambling: handled out-of-band by `HanabiChapterDecryptor`
///   (see hanabi_chapter_decryptor.dart), which is invoked from
///   `ChapterImagePipeline` after [parseChapter] returns
///   `ScrambleType.hanabi` images.
class HanabiManga extends MangaSource {
  static const String sourceId = 'hanabi_manga';
  static const String _baseUrl = 'https://web.hanabimanga.com';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  @override
  String get id => sourceId;

  @override
  String get name => '花火漫画';

  @override
  String get shortName => '花火';

  @override
  String? get description => '需要登录账号才能使用，仅支持免费/普通章节';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get requiresLogin => true;

  @override
  String? get loginDescription => '使用花火漫画账号登录后即可阅读免费章节';

  @override
  bool get isAuthenticated =>
      extraHeaders.containsKey('Cookie') &&
      _expiresAt != null &&
      DateTime.now().toUtc().isBefore(_expiresAt!);

  @override
  void syncExtraData(Map<String, dynamic> data) {
    super.syncExtraData(data);
    final accessToken = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final expiresAt = data['expiresAt'] as int?;
    if (accessToken != null) _accessToken = accessToken;
    if (refreshToken != null) _refreshToken = refreshToken;
    if (expiresAt != null) {
      _expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
        isUtc: true,
      );
    }
  }

  @override
  FetchConfig buildSignInRequest(String email, String password) {
    return FetchConfig(
      url: '$_hanabiSupabaseUrl/auth/v1/token?grant_type=password',
      method: HttpMethod.post,
      headers: const {
        'apikey': _hanabiAnonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
  }

  @override
  Map<String, dynamic>? parseSignIn(dynamic response) {
    final data = response is String
        ? jsonDecode(response) as Map<String, dynamic>
        : response as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    final expiresIn = data['expires_in'] as int?;
    final expiresAt = data['expires_at'] as int?;
    final user = data['user'] as Map<String, dynamic>?;
    if (accessToken == null ||
        refreshToken == null ||
        expiresAt == null ||
        user == null) {
      return null;
    }
    final cookie = buildHanabiSessionCookie(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn ?? 3600,
      expiresAt: expiresAt,
      user: user,
    );
    return {
      'cookie': cookie,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt,
    };
  }

  @override
  bool get needsSessionRefresh {
    if (_expiresAt == null) return false;
    return DateTime.now()
        .toUtc()
        .isAfter(_expiresAt!.subtract(const Duration(minutes: 5)));
  }

  @override
  FetchConfig buildRefreshRequest() {
    return FetchConfig(
      url: '$_hanabiSupabaseUrl/auth/v1/token?grant_type=refresh_token',
      method: HttpMethod.post,
      headers: const {
        'apikey': _hanabiAnonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'refresh_token': _refreshToken}),
    );
  }

  @override
  List<FilterOption> get discoveryFilters => const [
    FilterOption(
      name: 'category',
      label: '分类',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '推理', value: 'mystery'),
        FilterChoice(label: '后宫', value: 'harem'),
        FilterChoice(label: '科幻', value: 'scifi'),
        FilterChoice(label: '百合', value: 'yuri'),
        FilterChoice(label: '恐怖', value: 'horror'),
        FilterChoice(label: '恋爱', value: 'romance'),
        FilterChoice(label: '音乐', value: 'music'),
        FilterChoice(label: '校园', value: 'school'),
        FilterChoice(label: '穿越', value: 'isekai'),
        FilterChoice(label: '战斗', value: 'battle'),
        FilterChoice(label: '运动', value: 'sports'),
        FilterChoice(label: '武侠', value: 'wuxia'),
        FilterChoice(label: '奇幻', value: 'fantasy'),
        FilterChoice(label: '惊悚', value: 'thriller'),
        FilterChoice(label: '搞笑', value: 'comedy'),
        FilterChoice(label: '日常', value: 'slice-of-life'),
        FilterChoice(label: '悬疑', value: 'suspense'),
        FilterChoice(label: '冒险', value: 'adventure'),
        FilterChoice(label: '历史', value: 'history'),
        FilterChoice(label: '乙女', value: 'otome'),
        FilterChoice(label: '美食', value: 'gourmet'),
        FilterChoice(label: '职场', value: 'workplace'),
        FilterChoice(label: '玄幻', value: 'xuanhuan'),
        FilterChoice(label: '机战', value: 'mecha'),
        FilterChoice(label: '魔幻', value: 'magic'),
        FilterChoice(label: '伪娘', value: 'femboy'),
      ],
    ),
    FilterOption(
      name: 'sort',
      label: '排序',
      defaultValue: '',
      choices: [
        FilterChoice(label: '推荐', value: ''),
        FilterChoice(label: '评分', value: 'rating'),
        FilterChoice(label: '最近更新', value: 'updated'),
        FilterChoice(label: '最新上架', value: 'created'),
      ],
    ),
    FilterOption(
      name: 'region',
      label: '分区',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '日漫', value: 'jp'),
        FilterChoice(label: '韩漫', value: 'kr'),
        FilterChoice(label: '美漫', value: 'us'),
        FilterChoice(label: '其他', value: 'others'),
      ],
    ),
    FilterOption(
      name: 'status',
      label: '状态',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '连载中', value: 'serializing'),
        FilterChoice(label: '已完结', value: 'finished'),
      ],
    ),
  ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final category = filters['category'] ?? 'all';
    final sort = filters['sort'] ?? '';
    final region = filters['region'] ?? 'all';
    final status = filters['status'] ?? 'all';

    final query = <String, String>{'page': '$page'};
    if (category != 'all') query['category'] = category;
    if (sort.isNotEmpty) query['sort'] = sort;
    if (region != 'all') query['region'] = region;
    if (status != 'all') query['status'] = status;

    final queryString = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return FetchConfig(url: '$_baseUrl/zh-CN/browse?$queryString');
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final document = html_parser.parse(response as String);
    final links = document.querySelectorAll('a[href*="/comic/"]');
    final idPattern = RegExp(r'/comic/(\d+)');
    final seen = <String>{};
    final results = <MangaSummary>[];

    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      final match = idPattern.firstMatch(href);
      if (match == null) continue;
      final id = match.group(1)!;
      if (!seen.add(id)) continue;

      final img = link.querySelector('img');
      final coverUrl = img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';
      final title = (link.querySelector('h3')?.text.trim().isNotEmpty ?? false)
          ? link.querySelector('h3')!.text.trim()
          : (link.querySelector('h2')?.text.trim().isNotEmpty ?? false)
              ? link.querySelector('h2')!.text.trim()
              : (img?.attributes['alt'] ?? '').trim();
      if (title.isEmpty) continue;

      results.add(
        MangaSummary(id: id, sourceId: sourceId, title: title, coverUrl: coverUrl, author: ''),
      );
    }
    return results;
  }

  @override
  FetchConfig prepareSearchFetch(String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_hanabiSupabaseUrl/rest/v1/rpc/search_comics_pgroonga',
      method: HttpMethod.post,
      headers: const {
        'apikey': _hanabiAnonKey,
        'Content-Type': 'application/json',
        'Content-Profile': 'public',
      },
      body: jsonEncode({
        'search_term': keyword,
        'page_number': page,
        'items_per_page': 24,
      }),
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final list = response is String
        ? jsonDecode(response) as List<dynamic>
        : response as List<dynamic>;
    return list.map((item) {
      final map = item as Map<String, dynamic>;
      return MangaSummary(
        id: '${map['id']}',
        sourceId: sourceId,
        title: map['title'] as String? ?? '',
        coverUrl: map['cover_url'] as String? ?? '',
        author: '',
        altTitles:
            (map['aliases'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                const [],
        chapterCount: map['chapters_count'] as int?,
      );
    }).toList();
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/zh-CN/comic/$mangaId');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final book = extractHanabiBookLdJson(htmlStr) ?? const <String, dynamic>{};

    final title = book['name'] as String? ?? '';
    final altTitles =
        (book['alternateName'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final authors = (book['author'] as List<dynamic>?)
            ?.map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        const <String>[];
    final coverUrl = book['image'] as String? ?? '';
    final description = book['description'] as String?;
    final tags =
        (book['genre'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            const <String>[];

    var status = MangaStatus.unknown;
    final metaMatch =
        RegExp(r'<meta name="description" content="([^"]*)"').firstMatch(htmlStr);
    final metaContent = metaMatch?.group(1) ?? '';
    if (metaContent.contains('已完结')) {
      status = MangaStatus.completed;
    } else if (metaContent.contains('连载中')) {
      status = MangaStatus.ongoing;
    }

    final rawChapters = extractHanabiChapters(htmlStr);
    final chapters = rawChapters.map((c) {
      final idx = c['idx'] as int;
      final chapterTitle = c['title'] as String? ?? '第$idx话';
      return ChapterItem(id: 'chapter-$idx', mangaId: mangaId, title: chapterTitle);
    }).toList();

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: authors.join(', '),
      tags: tags,
      altTitles: altTitles,
      status: status,
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) =>
      const ChapterListResult(chapters: []);

  @override
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) {
    return FetchConfig(url: '$_baseUrl/api/reader/comic/$mangaId/$chapterId');
  }

  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) {
    final data = response is String
        ? jsonDecode(response) as Map<String, dynamic>
        : response as Map<String, dynamic>;
    final chapterMeta = data['chapter'] as Map<String, dynamic>;
    final title = chapterMeta['title'] as String? ?? chapterId;

    final scrambleInfo =
        (data['metadata'] as Map<String, dynamic>?)?['scrambleInfo'] as Map<String, dynamic>?;
    final ticket = scrambleInfo?['ticket'] as String?;
    final nonce = scrambleInfo?['nonce'] as String?;
    final cols = scrambleInfo?['cols'] as int?;
    final rows = scrambleInfo?['rows'] as int?;

    final pages = data['pages'] as List<dynamic>;
    final images = pages.map((p) {
      final pageMap = p as Map<String, dynamic>;
      final url = pageMap['url'] as String;
      if (ticket != null && nonce != null && cols != null && rows != null) {
        return ChapterImage(
          url: url,
          scrambleType: ScrambleType.hanabi,
          hanabiTicket: ticket,
          hanabiNonce: nonce,
          hanabiCols: cols,
          hanabiRows: rows,
        );
      }
      return ChapterImage(url: url);
    }).toList();

    return ChapterResult(
      chapter: Chapter(id: chapterId, mangaId: mangaId, title: title, images: images),
    );
  }
}
