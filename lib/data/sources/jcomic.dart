import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// JComic (jcomic.net) data source.
///
/// Traditional Chinese manga site. HTML-based, no auth/login required.
/// Images served via AWS S3 presigned URLs behind Cloudflare protection.
class JComic extends MangaSource {
  static const String sourceId = 'jcomic';
  static const String _baseUrl = 'https://jcomic.net';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36';

  /// Prefix used to mark single-chapter manga IDs.
  static const String _singlePrefix = '__single__';

  // --- Identity ---

  @override
  String get id => sourceId;

  @override
  String get name => 'JComic';

  @override
  String get shortName => 'JC';

  @override
  String? get description => 'jcomic.net';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  String? get userAgent => _userAgent;

  @override
  Map<String, String>? get defaultHeaders => const {
        'User-Agent': _userAgent,
        'Referer': 'https://jcomic.net',
      };

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => true;

  /// Web platform loads images directly via HTML <img> (no CORS proxy)
  /// because images.jcomic.net has Cloudflare protection that requires
  /// browser cookies the proxy cannot provide.
  @override
  bool get webDirectImage => true;

  /// CF verification targets the image CDN where Cloudflare protection exists.
  /// On web: user should open images.jcomic.net in a new tab to pass CF challenge.
  /// On native: WebView opens this URL for CF cookie extraction.
  @override
  String? get cloudflareUrl => 'https://images.jcomic.net';

  /// Dynamic image headers that include CF cookie when available.
  Map<String, String> get _imageHeaders {
    final headers = <String, String>{'Referer': 'https://jcomic.net'};
    final cookie = extraHeaders['Cookie'];
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    final ua = extraHeaders['User-Agent'];
    if (ua != null && ua.isNotEmpty) {
      headers['User-Agent'] = ua;
    }
    return headers;
  }

  /// After CF verification, also register cookie with CORS proxy for web images.
  @override
  void syncExtraData(Map<String, dynamic> data) {
    super.syncExtraData(data);
    _registerCorsProxyCookie(data['cookie'] as String?);
  }

  /// Register CF cookie with the CORS proxy's __host_token for images.jcomic.net.
  void _registerCorsProxyCookie(String? cookie) {
    if (!kIsWeb || cookie == null || cookie.isEmpty) return;
    try {
      Dio().post(
        'http://localhost:9090/__host_token',
        data: {
          'host': 'images.jcomic.net',
          'token': cookie,
          'header': 'Cookie',
        },
      );
    } catch (_) {
      // Non-critical: proxy may not be running
    }
  }

  // --- Filters ---

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'category',
          label: '分類',
          defaultValue: '最近更新',
          choices: [
            FilterChoice(label: '最近更新', value: '最近更新'),
            FilterChoice(label: '隨機', value: '隨機'),
            FilterChoice(label: '全彩', value: '全彩'),
            FilterChoice(label: '長篇', value: '長篇'),
            FilterChoice(label: '單行本', value: '單行本'),
            FilterChoice(label: '同人', value: '同人'),
            FilterChoice(label: '短篇', value: '短篇'),
            FilterChoice(label: 'Cosplay', value: 'Cosplay'),
            FilterChoice(label: '歐美', value: '歐美'),
            FilterChoice(label: 'WEBTOON', value: 'WEBTOON'),
            FilterChoice(label: '圓神領域', value: '圓神領域'),
            FilterChoice(label: '碧藍幻想', value: '碧藍幻想'),
            FilterChoice(label: 'CG雜圖', value: 'CG雜圖'),
            FilterChoice(label: '英語 ENG', value: '英語 ENG'),
            FilterChoice(label: '生肉', value: '生肉'),
            FilterChoice(label: '純愛', value: '純愛'),
            FilterChoice(label: '百合花園', value: '百合花園'),
            FilterChoice(label: '耽美花園', value: '耽美花園'),
            FilterChoice(label: '偽娘哲學', value: '偽娘哲學'),
            FilterChoice(label: '後宮閃光', value: '後宮閃光'),
            FilterChoice(label: '扶他樂園', value: '扶他樂園'),
            FilterChoice(label: '姐姐系', value: '姐姐系'),
            FilterChoice(label: '妹妹系', value: '妹妹系'),
            FilterChoice(label: 'SM', value: 'SM'),
            FilterChoice(label: '性轉換', value: '性轉換'),
            FilterChoice(label: '足の恋', value: '足の恋'),
            FilterChoice(label: '重口地帶', value: '重口地帶'),
            FilterChoice(label: '人妻', value: '人妻'),
            FilterChoice(label: 'NTR', value: 'NTR'),
            FilterChoice(label: '強暴', value: '強暴'),
            FilterChoice(label: '非人類', value: '非人類'),
            FilterChoice(label: '艦隊收藏', value: '艦隊收藏'),
            FilterChoice(label: 'Love Live', value: 'Love Live'),
            FilterChoice(label: 'SAO 刀劍神域', value: 'SAO 刀劍神域'),
            FilterChoice(label: 'Fate', value: 'Fate'),
            FilterChoice(label: '東方', value: '東方'),
            FilterChoice(label: '禁書目錄', value: '禁書目錄'),
          ],
        ),
      ];

  // --- Private Helpers ---

  /// Shared parser for listing items (used by both discovery and search).
  /// Parses `<div class="row col-lg-4 col-md-6 col-xs-12">` blocks.
  List<MangaSummary> _parseListingItems(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    // Each manga card is in a div with these column classes
    final cards = document.querySelectorAll('div.col-lg-4.col-md-6.col-xs-12');

    for (final card in cards) {
      // Find the link to the manga — either /page/{id} or /eps/{id}
      final linkEl = card.querySelector('a[href^="/page/"], a[href^="/eps/"]');
      if (linkEl == null) continue;

      final href = linkEl.attributes['href'] ?? '';
      String mangaId;
      if (href.startsWith('/page/')) {
        // Single-chapter manga — use raw path as ID (no decode to avoid
        // issues with titles containing raw % characters)
        mangaId = '$_singlePrefix${href.substring('/page/'.length)}';
      } else if (href.startsWith('/eps/')) {
        // Multi-chapter manga
        mangaId = href.substring('/eps/'.length);
      } else {
        continue;
      }

      // Cover image
      final imgEl = card.querySelector('img.img-responsive');
      final coverUrl = imgEl?.attributes['src'] ?? '';

      // Title — strip trailing " (N)" image count
      final titleEl = card.querySelector('.comic-title');
      var title = titleEl?.text.trim() ?? '';
      final countSuffix = RegExp(r'\s*\(\d+\)$');
      title = title.replaceFirst(countSuffix, '');

      // Author
      final authorEl = card.querySelector('a[href^="/author/"] button') ??
          card.querySelector('a[href^="/author/"]');
      final author = authorEl?.text.trim() ?? '';

      // Update time
      final dateEl = card.querySelector('.comic-date');
      String? updateTime;
      if (dateEl != null) {
        final dateText = dateEl.text.trim();
        // Format: "最後更新: 2024-05-01 12:30"
        final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(dateText);
        if (dateMatch != null) {
          updateTime = dateMatch.group(1);
        }
      }

      if (title.isNotEmpty) {
        results.add(MangaSummary(
          id: mangaId,
          sourceId: sourceId,
          title: title,
          coverUrl: coverUrl,
          author: author,
          updateTime: updateTime,
          headers: _imageHeaders,
        ));
      }
    }

    return results;
  }

  // --- Discovery ---

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final category = filters['category'] ?? '最近更新';
    final encodedCategory = Uri.encodeComponent(category);

    return FetchConfig(
      url: '$_baseUrl/cat/$encodedCategory/$page',
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseListingItems(response as String);
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // JComic search has no pagination — page > 1 returns empty
    if (page > 1) {
      return FetchConfig(
        url: '$_baseUrl/search/${Uri.encodeComponent(keyword)}',
        headers: defaultHeaders,
        extra: {'emptyPage': true},
      );
    }
    return FetchConfig(
      url: '$_baseUrl/search/${Uri.encodeComponent(keyword)}',
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseListingItems(response as String);
  }

  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    if (mangaId.startsWith(_singlePrefix)) {
      // Single-chapter: fetch reading page directly
      final stripped = mangaId.substring(_singlePrefix.length);
      return FetchConfig(
        url: '$_baseUrl/page/$stripped',
        headers: defaultHeaders,
      );
    } else {
      // Multi-chapter: fetch episode list page
      return FetchConfig(
        url: '$_baseUrl/eps/$mangaId',
        headers: defaultHeaders,
      );
    }
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    if (mangaId.startsWith(_singlePrefix)) {
      return _parseSingleChapterInfo(document, mangaId);
    } else {
      return _parseMultiChapterInfo(document, mangaId);
    }
  }

  /// Parse manga info from the multi-chapter episode list page (/eps/{title}).
  MangaDetail _parseMultiChapterInfo(dynamic document, String mangaId) {
    // Title
    final titleEl =
        document.querySelector('.comic-title') ?? document.querySelector('h1');
    var title = titleEl?.text.trim() ?? mangaId;
    title = title.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');

    // Cover
    final coverEl = document.querySelector('img.img-responsive');
    final coverUrl = coverEl?.attributes['src'] ?? '';

    // Author
    final authorEl = document.querySelector('a[href^="/author/"] button') ??
        document.querySelector('a[href^="/author/"]');
    final author = authorEl?.text.trim() ?? '';

    // Tags — all category buttons
    final tagEls = document.querySelectorAll('a[href^="/cat/"] button');
    final tags = <String>[];
    for (final el in tagEls) {
      final text = el.text.trim();
      if (text.isNotEmpty) tags.add(text);
    }

    // Update time
    String? updateTime;
    final dateEl = document.querySelector('.comic-date');
    if (dateEl != null) {
      final dateMatch =
          RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(dateEl.text);
      if (dateMatch != null) updateTime = dateMatch.group(1);
    }

    // Chapters — each <a href="/page/{title}/{epNum}"><button>...</button></a>
    final chapters = <ChapterItem>[];

    // mangaId is the raw URL path segment (already encoded as it appears in href)
    final chapterLinks =
        document.querySelectorAll('a[href*="/page/$mangaId/"]');

    for (final a in chapterLinks) {
      final chapterHref = a.attributes['href'] ?? '';
      // Extract episode number from /page/{title}/{epNum}
      final parts = chapterHref.split('/');
      if (parts.length < 4) continue;
      final epNum = parts.last;
      if (int.tryParse(epNum) == null) continue;

      final chapterTitle =
          a.querySelector('button')?.text.trim() ?? a.text.trim();

      if (chapterTitle.isNotEmpty) {
        chapters.add(ChapterItem(
          id: epNum,
          mangaId: mangaId,
          title: chapterTitle,
        ));
      }
    }

    // Sort chapters by episode number ascending
    chapters.sort((a, b) {
      final aNum = int.tryParse(a.id) ?? 0;
      final bNum = int.tryParse(b.id) ?? 0;
      return aNum.compareTo(bNum);
    });

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      tags: tags,
      status: MangaStatus.unknown,
      updateTime: updateTime,
      headers: _imageHeaders,
      chapters: chapters,
    );
  }

  /// Parse manga info from a single-chapter reading page (/page/{title}).
  MangaDetail _parseSingleChapterInfo(dynamic document, String mangaId) {
    // Title from <h1>
    final titleEl = document.querySelector('h1');
    var title =
        titleEl?.text.trim() ?? mangaId.substring(_singlePrefix.length);
    title = title.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');

    // Cover — first comic image
    final coverEl = document.querySelector('img.img-responsive.comic-thumb');
    final coverUrl = coverEl?.attributes['src'] ?? '';

    // Author
    final authorEl = document.querySelector('a[href^="/author/"] button') ??
        document.querySelector('a[href^="/author/"]');
    final author = authorEl?.text.trim() ?? '';

    // Tags
    final tagEls = document.querySelectorAll('a[href^="/cat/"] button');
    final tags = <String>[];
    for (final el in tagEls) {
      final text = el.text.trim();
      if (text.isNotEmpty) tags.add(text);
    }

    // Fixed single chapter
    final chapters = [
      ChapterItem(
        id: '1',
        mangaId: mangaId,
        title: '全一話',
      ),
    ];

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      tags: tags,
      status: MangaStatus.unknown,
      headers: _imageHeaders,
      chapters: chapters,
    );
  }

  // --- Chapter List (embedded in manga info) ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are fully embedded in the manga info page
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    if (mangaId.startsWith(_singlePrefix)) {
      final stripped = mangaId.substring(_singlePrefix.length);
      return FetchConfig(
        url: '$_baseUrl/page/$stripped',
        headers: defaultHeaders,
      );
    } else {
      return FetchConfig(
        url: '$_baseUrl/page/$mangaId/$chapterId',
        headers: defaultHeaders,
      );
    }
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final images = <ChapterImage>[];

    // Extract all comic images from the page
    final imgEls = document.querySelectorAll('img.img-responsive.comic-thumb');
    for (final el in imgEls) {
      final src = el.attributes['src'] ?? '';
      // Filter: only S3 image URLs (images.jcomic.net), skip covers/thumbnails
      if (src.contains('images.jcomic.net')) {
        images.add(ChapterImage(
          url: src,
          headers: _imageHeaders,
        ));
      }
    }

    // Chapter title
    final titleEl = document.querySelector('h1');
    var title = titleEl?.text.trim() ?? '';
    title = title.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');

    // Also try to get from #eps element
    if (title.isEmpty) {
      final epsEl = document.querySelector('#eps');
      title = epsEl?.text.trim() ?? 'Chapter $chapterId';
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: _imageHeaders,
      ),
      canLoadMore: false,
    );
  }

  // --- Web URL ---

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    if (mangaId.startsWith(_singlePrefix)) {
      final stripped = mangaId.substring(_singlePrefix.length);
      return '$_baseUrl/page/$stripped';
    }
    return '$_baseUrl/page/$mangaId/$chapterId';
  }
}
