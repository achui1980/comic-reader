import 'dart:convert';
import 'dart:typed_data';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/manwaye_image_decoder.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// 漫蛙漫画 / MANWA — https://manwari.cc
///
/// The site's previous domain (manwaye.cc) now 301-redirects here; Dio does
/// not automatically follow the redirect for the POST discovery request, so
/// the base URL must track whatever domain the site is currently live on.
///
/// Pure JSON-API source: every endpoint returns JSON, so there is no HTML
/// parsing at all. The site has no Cloudflare / TLS-fingerprint check, needs no
/// cookies or login for free chapters, and its image CDN serves bytes without a
/// Referer.
///
/// Endpoint map:
///   discovery    POST /api/cate/                              (JSON body)
///   search       GET  /api/search?type=mh&keyword=…
///   manga info   GET  /api/comic/{id}
///   chapters     GET  /api/comic/{id}/chapters                (all in one call)
///   images       GET  /api/comic/image/{cid}?page=&page_size=&image_source=
class Manwaye extends MangaSource {
  static const String sourceId = 'manwaye';
  static const String _baseUrl = 'https://manwari.cc';

  /// Chapter image CDN. `window.IMAGE_SOURCES` on the reader page labels this
  /// one 高速源 (fastest); the documented alternates are `https://mwtuwu.cc`
  /// (稳定源) and `https://101.35.11.30:36661` (备用源). Two further entries are
  /// VIP-only and ship with an empty url.
  static const String _imageSource = 'https://tu.mwzu.cc';

  static const int _discoveryPageSize = 36;
  static const int _searchPageSize = 20;
  static const int _imagePageSize = 100;

  @override
  String get id => sourceId;

  @override
  String get name => '漫蛙漫画';

  @override
  String get shortName => 'MW';

  @override
  String? get description => 'MANWA 漫蛙，JSON API 站点，韩漫/条漫为主';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  /// Mixed-content site: the front page is mainstream 少年/恋爱 manga, but the
  /// catalogue has explicit 19r / 无码 sections and adult tags appear on
  /// ordinary works, so the whole source is gated behind the 18+ switch.
  @override
  bool get isAdult => true;

  @override
  bool get needsProxy => false;

  @override
  Map<String, String>? get defaultHeaders => const {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
        'Referer': '$_baseUrl/',
        'Accept': 'application/json, text/plain, */*',
      };

  /// Every image on this site — covers and chapter pages alike — is stored
  /// AES-256-CBC encrypted. See [ManwayeImageDecoder] for the payload format and
  /// why the transform is safe to apply repeatedly.
  @override
  bool get transformsImageBytes => true;

  @override
  Uint8List transformImageBytes(Uint8List bytes) =>
      ManwayeImageDecoder.decodeImageBytes(bytes);

  // ---------------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------------

  /// Every choice below mirrors a real `data-value` from the `/cate/` page and
  /// was verified to change the server-side result set.
  ///
  /// The site's UI also has a 类型向 (一般向/BL向/TL向/GL向/禁漫) selector backed by a
  /// `typeId` field, but that is purely a client-side cookie: `cate.js` only
  /// declares `typeId` under `requestParams.video`, and posting any `typeId` for
  /// `category: comic` returns a byte-identical list. It is deliberately omitted
  /// rather than shipped as a filter that silently does nothing.
  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '更新', value: '0'),
            FilterChoice(label: '新作', value: '1'),
            FilterChoice(label: '热门', value: '3'),
          ],
        ),
        FilterOption(
          name: 'tag',
          label: '题材',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '热血', value: '热血'),
            FilterChoice(label: '玄幻', value: '玄幻'),
            FilterChoice(label: '恋爱', value: '恋爱'),
            FilterChoice(label: '冒险', value: '冒险'),
            FilterChoice(label: '古风', value: '古风'),
            FilterChoice(label: '都市', value: '都市'),
            FilterChoice(label: '穿越', value: '穿越'),
            FilterChoice(label: '奇幻', value: '奇幻'),
            FilterChoice(label: '搞笑', value: '搞笑'),
            FilterChoice(label: '少男', value: '少男'),
            FilterChoice(label: '战斗', value: '战斗'),
            FilterChoice(label: '重生', value: '重生'),
            FilterChoice(label: '逆袭', value: '逆袭'),
            FilterChoice(label: '爆笑', value: '爆笑'),
            FilterChoice(label: '少年', value: '少年'),
            FilterChoice(label: '后宫', value: '后宫'),
            FilterChoice(label: '系统', value: '系统'),
            FilterChoice(label: 'BL', value: 'BL'),
            FilterChoice(label: '韩漫', value: '韩漫'),
            FilterChoice(label: '完整版', value: '完整版'),
            FilterChoice(label: '19r', value: '19r'),
            FilterChoice(label: '台版', value: '台版'),
          ],
        ),
        FilterOption(
          name: 'areaId',
          label: '地区',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '韩国', value: '2'),
            FilterChoice(label: '日漫', value: '3'),
            FilterChoice(label: '国漫', value: '4'),
            FilterChoice(label: '台漫', value: '5'),
            FilterChoice(label: '其他', value: '6'),
            FilterChoice(label: '未分类', value: '1'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '状态',
          defaultValue: '-1',
          choices: [
            FilterChoice(label: '全部', value: '-1'),
            FilterChoice(label: '连载中', value: '0'),
            FilterChoice(label: '已完结', value: '1'),
          ],
        ),
        FilterOption(
          name: 'day',
          label: '更新日',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '周一', value: '1'),
            FilterChoice(label: '周二', value: '2'),
            FilterChoice(label: '周三', value: '3'),
            FilterChoice(label: '周四', value: '4'),
            FilterChoice(label: '周五', value: '5'),
            FilterChoice(label: '周六', value: '6'),
            FilterChoice(label: '周日', value: '7'),
          ],
        ),
        FilterOption(
          name: 'level',
          label: '画质',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '普通', value: '1'),
            FilterChoice(label: 'VIP无码', value: '2'),
          ],
        ),
      ];

  /// `/api/search` accepts exactly one of `keyword` / `author` / `tags`, so the
  /// field to match on is exposed as a filter instead of three search modes.
  @override
  List<FilterOption> get searchFilters => const [
        FilterOption(
          name: 'field',
          label: '搜索',
          defaultValue: 'keyword',
          choices: [
            FilterChoice(label: '标题', value: 'keyword'),
            FilterChoice(label: '作者', value: 'author'),
            FilterChoice(label: '标签', value: 'tags'),
          ],
        ),
      ];

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    // `cate.js` posts to "/api" + location.pathname, so /cate/ -> /api/cate/.
    // The `video` / `novel` keys must be present (as empty objects) even for a
    // comic query — the endpoint reads requestParams[category] by name.
    final body = {
      'page': {'page': page, 'pageSize': _discoveryPageSize},
      'category': 'comic',
      'sort': _int(filters['sort'], 0),
      'comic': {
        'status': _int(filters['status'], -1),
        'day': _int(filters['day'], 0),
        'tag': filters['tag'] ?? '',
        'level': _int(filters['level'], 0),
        'areaId': _int(filters['areaId'], 0),
      },
      'video': const <String, dynamic>{},
      'novel': const <String, dynamic>{},
    };

    return FetchConfig(
      url: '$_baseUrl/api/cate/',
      method: HttpMethod.post,
      headers: {...?defaultHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    // Paging past the end returns `list: []` with the full `total` intact, which
    // the framework treats as "no more pages".
    return _listData(response)
        .map(_summaryFromCateItem)
        .whereType<MangaSummary>()
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    var field = filters['field'] ?? 'keyword';
    if (field != 'keyword' && field != 'author' && field != 'tags') {
      field = 'keyword';
    }

    return FetchConfig(
      url: '$_baseUrl/api/search',
      headers: defaultHeaders,
      queryParameters: {
        // Literal 'mh' is required; a numeric type is rejected with
        // "This search type is not supported yet".
        'type': 'mh',
        'page': page,
        'pageSize': _searchPageSize,
        field: keyword,
      },
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _listData(response)
        .map(_summaryFromSearchItem)
        .whereType<MangaSummary>()
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Manga info
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/api/comic/$mangaId',
      headers: defaultHeaders,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final data = _dataMap(response);
    if (data == null) throw Exception('漫蛙：无法解析漫画信息 ($mangaId)');

    final alias = _str(data['alias']);

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: _str(data['title']),
      coverUrl: _str(data['cover']),
      description: _nullIfEmpty(_str(data['intro'])),
      author: _str(data['author']),
      tags: _splitTags(data['tags']),
      altTitles: alias.isEmpty ? const [] : [alias],
      status: _status(data['status']),
      latestChapter: _nullIfEmpty(_str(data['cName'])),
      updateTime: _nullIfEmpty(_str(data['editTime'])),
      // Chapters come from the dedicated /chapters endpoint, so this stays
      // empty and the framework calls prepareChapterListFetch.
    );
  }

  // ---------------------------------------------------------------------------
  // Chapter list
  // ---------------------------------------------------------------------------

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // The endpoint is unpaginated — it returns every chapter in one response —
    // so only the first page ever issues a request.
    if (page > firstPage) return null;
    return FetchConfig(
      url: '$_baseUrl/api/comic/$mangaId/chapters',
      headers: defaultHeaders,
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final chapters = <ChapterItem>[];
    for (final raw in _listData(response)) {
      final cid = _str(raw['id']);
      if (cid.isEmpty || cid == '0') continue;

      var title = _str(raw['title']);
      if (title.isEmpty) title = '第$cid话';
      // Surface the paywall in the list so it is visible before opening.
      if (raw['isVip'] == true) title = '$title 🔒';

      chapters.add(ChapterItem(
        id: cid,
        mangaId: mangaId,
        title: title,
        href: '$_baseUrl/comic/$mangaId/$cid',
      ));
    }

    // Already ordered by sortId upstream, but sort defensively.
    return ChapterListResult(chapters: chapters, canLoadMore: false);
  }

  // ---------------------------------------------------------------------------
  // Chapter content
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/api/comic/image/$chapterId',
      headers: defaultHeaders,
      queryParameters: {
        'page': page,
        'page_size': _imagePageSize,
        'image_source': _imageSource,
      },
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final data = _dataMap(response);

    final images = <ChapterImage>[];
    final rawImages = data?['images'];
    if (rawImages is List) {
      for (final entry in rawImages) {
        // Items are `{"url": "..."}`; tolerate a bare string too.
        final url = entry is Map
            ? _str(entry['url'])
            : (entry is String ? entry.trim() : '');
        if (url.isEmpty) continue;
        // Absolute CDN URLs, plain .jpg, no scrambling, no Referer needed.
        images.add(ChapterImage(url: url));
      }
    }

    if (images.isEmpty && page <= firstPage) {
      throw Exception('漫蛙：该章节无图片，可能需要 VIP 或已下架');
    }

    // pagination: {current_page, page_size, total, total_pages}
    final pagination = data?['pagination'];
    var canLoadMore = false;
    int? nextPage;
    if (pagination is Map) {
      final current = _int(pagination['current_page'], page);
      final totalPages = _int(pagination['total_pages'], 1);
      if (current < totalPages) {
        canLoadMore = true;
        nextPage = current + 1;
      }
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: images,
      ),
      canLoadMore: canLoadMore,
      nextPage: nextPage,
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    // The API URL is not human-readable; the reader page is.
    return '$_baseUrl/comic/$mangaId/$chapterId';
  }

  // ---------------------------------------------------------------------------
  // Item mappers
  //
  // The two list endpoints return DIFFERENT shapes and must not share a parser:
  //   /api/cate/   -> cover in `pic`, no `id` (must be cut out of `url`)
  //   /api/search  -> cover in `cover`, numeric `id` present
  // ---------------------------------------------------------------------------

  MangaSummary? _summaryFromCateItem(Map<String, dynamic> item) {
    final id = _idFromUrl(_str(item['url']));
    if (id == null) return null;

    return MangaSummary(
      id: id,
      sourceId: sourceId,
      title: _str(item['title']),
      coverUrl: _str(item['pic']),
      author: _str(item['author']),
      description: _nullIfEmpty(_str(item['intro'])),
    );
  }

  MangaSummary? _summaryFromSearchItem(Map<String, dynamic> item) {
    var id = _str(item['id']);
    if (id.isEmpty || id == '0') {
      id = _idFromUrl(_str(item['url'])) ?? '';
    }
    if (id.isEmpty) return null;

    final alias = _str(item['alias']);

    return MangaSummary(
      id: id,
      sourceId: sourceId,
      title: _str(item['title']),
      coverUrl: _str(item['cover']),
      author: _str(item['author']),
      altTitles: alias.isEmpty ? const [] : [alias],
      updateTime: _nullIfEmpty(_str(item['editTime'])),
      description: _nullIfEmpty(_str(item['description'])),
    );
  }

  /// `"/comic/1903"` -> `"1903"`.
  String? _idFromUrl(String url) {
    final match = RegExp(r'/comic/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  // ---------------------------------------------------------------------------
  // Response helpers
  //
  // Dio decodes application/json into a Map, but the web CORS proxy can hand
  // back a raw String, so both are accepted.
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _asMap(dynamic response) {
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return response.cast<String, dynamic>();
    if (response is String) {
      if (response.trim().isEmpty) return null;
      try {
        final decoded = jsonDecode(response);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// The `data` object of an envelope response.
  Map<String, dynamic>? _dataMap(dynamic response) {
    final root = _asMap(response);
    if (root == null) return null;
    final data = root['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  /// The `data.list` array of an envelope response.
  List<Map<String, dynamic>> _listData(dynamic response) {
    final list = _dataMap(response)?['list'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  static String _str(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  static String? _nullIfEmpty(String value) => value.isEmpty ? null : value;

  static int _int(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  /// `status`: 0 = 连载中, 1 = 已完结.
  static MangaStatus _status(dynamic value) {
    switch (_int(value, -1)) {
      case 0:
        return MangaStatus.ongoing;
      case 1:
        return MangaStatus.completed;
      default:
        return MangaStatus.unknown;
    }
  }

  /// `tags` is a comma-separated string, e.g. `"韩漫,19r,完整版"`.
  static List<String> _splitTags(dynamic value) {
    final raw = _str(value);
    if (raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
