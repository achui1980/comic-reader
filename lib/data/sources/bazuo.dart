import 'dart:convert';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Bazuo (manga.bazuo.link) data source.
///
/// A Telegram-WebApp style aggregator that exposes three kinds of endpoints:
///
/// * Static chunked JSON for the "latest" feed and per-category listings
///   (`/mini-data/latest.json`, `/mini-data/categories/<slug>.json`), paginated
///   by appending `-<page>` to the filename. Chunk size is 180.
/// * A dynamic search/ranking endpoint (`/api/search.js`) driven by
///   `mode=rankings&period=…` (offset/limit paging) or `q=…` (no paging).
/// * A per-comic detail JSON (`/data/comics/<id>.json.js`) that embeds BOTH the
///   chapter list AND every chapter's page URLs.
///
/// Note: the site serves `/api/search` and `/data/comics/<id>.json` as 307
/// redirects to the `.js` variants. We always request the final `.js` URL
/// directly so the web CORS proxy never has to follow a redirect.
class Bazuo extends MangaSource {
  static const String sourceId = 'bazuo';
  static const String _siteBase = 'https://manga.bazuo.link';
  static const String _appBase = '$_siteBase/manga-app';

  /// Cache-buster the site's own frontend sends along. Harmless if stale, but
  /// keeping it in sync with the deployed app avoids serving an older CDN copy.
  static const String _appVersion = '20260813-reader-origin-v1';

  /// Number of items per chunk in the static JSON files. Mirrors the site's
  /// `REMOTE_LIST_CHUNK_SIZE`, and is reused as the ranking page size.
  static const int _chunkSize = 180;

  /// Maps a display category name to its static JSON filename slug.
  /// Mirrors the site's `CATEGORY_FILE_MAP`. Categories absent from this map
  /// (e.g. 国漫, which has 0 items) have no static listing file.
  static const Map<String, String> _categorySlugs = {
    '同人志': 'doujin',
    '单行本': 'danxingben',
    '韩漫': 'hanman',
    '3D漫画': '3d',
    'AI图集': 'ai',
    'CG画集': 'cg',
    'Cosplay': 'cosplay',
  };

  static const Map<String, String> _apiHeaders = {
    'Referer': '$_appBase/',
    'Accept': 'application/json, text/plain, */*',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  };

  /// The image CDN (img5.qy0.ru) is referer-checked; without it some hosts
  /// answer with an HTML interstitial that fails to decode as an image.
  static const Map<String, String> _imageHeaders = {
    'Referer': '$_siteBase/',
  };

  @override
  String get id => sourceId;

  @override
  String get name => 'Bazuo 漫画';

  @override
  String get shortName => 'BZ';

  @override
  String? get description => '聚合站，支持分类与日/周/月/年榜';

  @override
  double get score => 4.0;

  @override
  String? get href => '$_appBase/';

  /// The catalogue is overwhelmingly doujin / hanman / CG material.
  @override
  bool get isAdult => true;

  @override
  Map<String, String>? get defaultHeaders => _apiHeaders;

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'latest',
          choices: [
            FilterChoice(label: '最新', value: 'latest'),
            FilterChoice(label: '日榜', value: 'day'),
            FilterChoice(label: '周榜', value: 'week'),
            FilterChoice(label: '月榜', value: 'month'),
            FilterChoice(label: '年榜', value: 'year'),
          ],
        ),
        FilterOption(
          name: 'category',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '同人志', value: '同人志'),
            FilterChoice(label: '单行本', value: '单行本'),
            FilterChoice(label: '韩漫', value: '韩漫'),
            FilterChoice(label: '3D漫画', value: '3D漫画'),
            FilterChoice(label: 'AI图集', value: 'AI图集'),
            FilterChoice(label: 'CG画集', value: 'CG画集'),
            FilterChoice(label: 'Cosplay', value: 'Cosplay'),
          ],
        ),
      ];

  // --- Discovery ---

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final sort = filters['sort'] ?? 'latest';
    final category = filters['category'] ?? '';

    // Rankings: a dynamic endpoint with offset/limit paging. It accepts an
    // optional category filter, passed as the display name (not the slug).
    if (sort != 'latest') {
      final offset = (page - 1) * _chunkSize;
      return FetchConfig(
        url: '$_appBase/api/search.js'
            '?mode=rankings'
            '&period=${Uri.encodeQueryComponent(sort)}'
            '&category=${Uri.encodeQueryComponent(category)}'
            '&offset=$offset'
            '&limit=$_chunkSize',
        headers: _apiHeaders,
      );
    }

    // Latest / per-category static JSON. Page 1 is the bare filename; later
    // pages append "-<page>" before the extension.
    final String path;
    if (category.isEmpty) {
      path = page <= 1 ? 'latest.json' : 'latest-$page.json';
    } else {
      // An unknown category has no static file; fall back to the latest feed
      // rather than requesting a URL that is guaranteed to 404.
      final slug = _categorySlugs[category];
      if (slug == null) {
        path = page <= 1 ? 'latest.json' : 'latest-$page.json';
      } else {
        path = page <= 1 ? '$slug.json' : '$slug-$page.json';
      }
    }

    final dir = category.isEmpty || !_categorySlugs.containsKey(category)
        ? 'mini-data'
        : 'mini-data/categories';

    return FetchConfig(
      url: '$_appBase/$dir/$path?v=$_appVersion',
      headers: _apiHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseItems(response);
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // The search endpoint has no offset/page parameter; it returns a single
    // capped result set. Mirror the site's own limit.
    return FetchConfig(
      url: '$_appBase/api/search.js'
          '?q=${Uri.encodeQueryComponent(keyword)}'
          '&limit=120'
          '&v=$_appVersion',
      headers: _apiHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseItems(response);
  }

  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: _detailUrl(mangaId), headers: _apiHeaders);
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final map = _asMap(response);
    if (map == null) {
      return MangaDetail(
        id: mangaId,
        sourceId: sourceId,
        title: mangaId,
        coverUrl: '',
      );
    }

    final tags = _stringList(map['tags']);
    final latestChapter = map['latestChapterTitle'] as String?;

    final chapters = <ChapterItem>[];
    final rawChapters = map['chapters'];
    if (rawChapters is List) {
      for (final raw in rawChapters) {
        if (raw is! Map) continue;
        final chapterId = raw['id']?.toString() ?? '';
        if (chapterId.isEmpty) continue;
        chapters.add(ChapterItem(
          id: chapterId,
          mangaId: mangaId,
          title: raw['title']?.toString() ?? chapterId,
        ));
      }
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: map['title'] as String? ?? mangaId,
      coverUrl: map['cover'] as String? ?? '',
      description: map['description'] as String?,
      author: map['author'] as String? ?? '',
      tags: tags,
      altTitles: _stringList(map['titleAliases']),
      status: _resolveStatus(map, chapters.length),
      latestChapter: latestChapter,
      chapters: chapters,
      headers: _imageHeaders,
    );
  }

  // --- Chapter List (embedded in the detail response) ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // Page URLs live inside the detail JSON, so re-fetch it and pick the
    // matching chapter in [parseChapter].
    return FetchConfig(url: _detailUrl(mangaId), headers: _apiHeaders);
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final map = _asMap(response);
    final images = <ChapterImage>[];
    String title = '';

    final rawChapters = map?['chapters'];
    if (rawChapters is List) {
      Map? target;
      for (final raw in rawChapters) {
        if (raw is Map && raw['id']?.toString() == chapterId) {
          target = raw;
          break;
        }
      }
      // Single-chapter works sometimes use a localized id (e.g. "正文"); if the
      // requested id is absent, fall back to the only chapter available.
      target ??= rawChapters.length == 1 && rawChapters.first is Map
          ? rawChapters.first as Map
          : null;

      if (target != null) {
        title = target['title']?.toString() ?? '';
        final pages = target['pages'];
        if (pages is List) {
          for (final p in pages) {
            final src = p is Map ? p['src']?.toString() : p?.toString();
            if (src == null || src.isEmpty) continue;
            images.add(ChapterImage(url: src, headers: _imageHeaders));
          }
        }
      }
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: _imageHeaders,
      ),
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_appBase/?comic=${Uri.encodeQueryComponent(mangaId)}'
        '&chapter=${Uri.encodeQueryComponent(chapterId)}';
  }

  // --- Helpers ---

  /// Detail JSON URL. IDs may contain CJK characters and dashes
  /// (e.g. `hanman-飞机杯女神连线中-414a40f0`), so they must be percent-encoded.
  String _detailUrl(String mangaId) =>
      '$_appBase/data/comics/${Uri.encodeComponent(mangaId)}.json.js'
      '?v=$_appVersion';

  /// The three list endpoints (latest, category, rankings/search) all wrap
  /// their payload in an `items` array, so one parser covers them all.
  List<MangaSummary> _parseItems(dynamic response) {
    final map = _asMap(response);
    final items = map?['items'];
    if (items is! List) return const [];

    final results = <MangaSummary>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final itemId = raw['id']?.toString() ?? '';
      if (itemId.isEmpty) continue;

      final cover = (raw['cover'] as String?)?.trim();
      final firstPage = (raw['firstPageSrc'] as String?)?.trim();

      results.add(MangaSummary(
        id: itemId,
        sourceId: sourceId,
        title: raw['title']?.toString() ?? itemId,
        coverUrl: (cover != null && cover.isNotEmpty)
            ? cover
            : (firstPage ?? ''),
        author: raw['author']?.toString() ?? '',
        altTitles: _stringList(raw['titleAliases']),
        latestChapter: raw['latestChapterTitle'] as String?,
        chapterCount: _asInt(raw['chapterCount']),
        popularityText: raw['category'] as String?,
        headers: _imageHeaders,
      ));
    }
    return results;
  }

  /// Accepts either a decoded Map or a raw JSON string, since the fetch
  /// pipeline may hand back either depending on the response content type.
  Map<String, dynamic>? _asMap(dynamic response) {
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return response.cast<String, dynamic>();
    if (response is String) {
      if (response.isEmpty) return null;
      try {
        final decoded = jsonDecode(response);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// The API exposes no explicit status field. Grouped multi-chapter series
  /// (韩漫 catalogues) keep receiving new episodes, while single-chapter
  /// doujin/CG uploads are complete by nature.
  MangaStatus _resolveStatus(Map<String, dynamic> map, int chapterCount) {
    final tags = _stringList(map['tags']);
    if (tags.contains('目录汇总')) return MangaStatus.ongoing;
    final grouping = map['workGrouping'];
    if (grouping is Map && grouping['mode'] != null) return MangaStatus.ongoing;
    if (chapterCount <= 1) return MangaStatus.completed;
    return MangaStatus.unknown;
  }
}
