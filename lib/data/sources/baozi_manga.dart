import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// BaoziManga (包子漫画) source plugin.
/// Uses JSON API for discovery, HTML scraping for search/manga info/chapters.
/// Chapter images are served from www.twmanga.com with paginated HTML pages.
class BaoziManga extends MangaSource {
  static const String sourceId = 'baozimh';
  static const String _baseUrl = 'https://www.baozimh.com';
  static const String _chapterBaseUrl = 'https://www.twmanga.com';
  static const String _coverCdn = 'https://static-tw.baozimh.com/cover';

  static const String _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 15_4_1 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';

  @override
  String get id => sourceId;

  @override
  String get name => '包子漫画';

  @override
  String get shortName => 'BZM';

  @override
  String? get description => '国漫/日漫/韩漫';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  String? get userAgent => _mobileUserAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _mobileUserAgent,
        'Referer': '$_baseUrl/',
      };

  @override
  bool get needsCloudflare => false;

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'type',
          label: '分类',
          defaultValue: 'all',
          choices: [
            FilterChoice(label: '全部', value: 'all'),
            FilterChoice(label: '恋爱', value: '恋爱'),
            FilterChoice(label: '纯爱', value: '纯爱'),
            FilterChoice(label: '古风', value: '古风'),
            FilterChoice(label: '异能', value: '异能'),
            FilterChoice(label: '悬疑', value: '悬疑'),
            FilterChoice(label: '剧情', value: '剧情'),
            FilterChoice(label: '科幻', value: '科幻'),
            FilterChoice(label: '奇幻', value: '奇幻'),
            FilterChoice(label: '玄幻', value: '玄幻'),
            FilterChoice(label: '穿越', value: '穿越'),
            FilterChoice(label: '冒险', value: '冒险'),
            FilterChoice(label: '推理', value: '推理'),
            FilterChoice(label: '武侠', value: '武侠'),
            FilterChoice(label: '格斗', value: '格斗'),
            FilterChoice(label: '战争', value: '战争'),
            FilterChoice(label: '热血', value: '热血'),
            FilterChoice(label: '搞笑', value: '搞笑'),
            FilterChoice(label: '大女主', value: '大女主'),
            FilterChoice(label: '都市', value: '都市'),
            FilterChoice(label: '总裁', value: '总裁'),
            FilterChoice(label: '后宫', value: '后宫'),
            FilterChoice(label: '日常', value: '日常'),
            FilterChoice(label: '韩漫', value: '韩漫'),
            FilterChoice(label: '少年', value: '少年'),
            FilterChoice(label: '其它', value: '其它'),
          ],
        ),
        FilterOption(
          name: 'region',
          label: '地区',
          defaultValue: 'all',
          choices: [
            FilterChoice(label: '全部', value: 'all'),
            FilterChoice(label: '国漫', value: 'cn'),
            FilterChoice(label: '日本', value: 'jp'),
            FilterChoice(label: '韩国', value: 'kr'),
            FilterChoice(label: '欧美', value: 'en'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '状态',
          defaultValue: 'all',
          choices: [
            FilterChoice(label: '全部', value: 'all'),
            FilterChoice(label: '连载中', value: 'serial'),
            FilterChoice(label: '已完结', value: 'pub'),
          ],
        ),
      ];

  // --- Regex patterns ---
  static final _mangaIdPattern = RegExp(r'/comic/([^/?]+)');
  static final _slotPattern =
      RegExp(r'section_slot=([0-9]+)&(?:amp;)?chapter_slot=([0-9]+)');
  static final _slotHtmlPattern =
      RegExp(r'/comic/chapter/([^/]+)/([0-9]+)_([0-9]+)(?:_([0-9]+))?\.html');
  static final _hourTimePattern = RegExp(r'([0-9]+)小时前');
  static final _fullTimePattern = RegExp(r'([0-9]{4})年([0-9]{2})月([0-9]{2})日');

  // ====== Discovery ======

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final type = filters['type'] ?? 'all';
    final region = filters['region'] ?? 'all';
    final status = filters['status'] ?? 'all';

    return FetchConfig(
      url: '$_baseUrl/api/bzmhq/amp_comic_list',
      method: HttpMethod.post,
      headers: {
        ...?defaultHeaders,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'type': type,
        'region': region,
        'state': status,
        'filter': '*',
        'page': '$page',
        'limit': '36',
        'language': 'cn',
        '__amp_source_origin': _baseUrl,
      },
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    // Response is JSON with { items: [...], next: "..." }
    Map<String, dynamic> data;
    if (response is String) {
      try {
        data = json.decode(response) as Map<String, dynamic>;
      } catch (_) {
        return [];
      }
    } else if (response is Map<String, dynamic>) {
      data = response;
    } else {
      return [];
    }

    final items = data['items'] as List<dynamic>? ?? [];
    return items.map((item) {
      final map = item as Map<String, dynamic>;
      final comicId = map['comic_id'] as String? ?? '';
      final title = map['name'] as String? ?? '';
      final author = map['author'] as String? ?? '';
      final topicImg = map['topic_img'] as String? ?? '';

      return MangaSummary(
        id: comicId,
        sourceId: sourceId,
        title: title,
        coverUrl: topicImg.isNotEmpty ? '$_coverCdn/$topicImg' : '',
        author: author,
      );
    }).toList();
  }

  // ====== Search ======

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search',
      queryParameters: {'q': keyword},
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final results = <MangaSummary>[];
    final cards = document.querySelectorAll('.classify-items > div');

    for (final card in cards) {
      // Extract link and manga ID
      final linkEl = card.querySelector('.comics-card__poster');
      final href = linkEl?.attributes['href'] ?? '';
      final idMatch = _mangaIdPattern.firstMatch(href);
      if (idMatch == null) continue;
      final mangaId = idMatch.group(1)!;

      // Cover image
      final imgEl = card.querySelector('.comics-card__poster > amp-img') ??
          card.querySelector('.comics-card__poster img');
      final coverRaw = imgEl?.attributes['src'] ?? '';
      final coverUrl = _cleanUrl(coverRaw);

      // Title
      final title = card
              .querySelector('.comics-card__info .comics-card__title')
              ?.text
              .trim() ??
          '';

      // Author
      final author =
          card.querySelector('.comics-card__info .tags')?.text.trim() ?? '';

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

  // ====== Manga Info ======

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/comic/$mangaId');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Title
    final title = document
            .querySelector('.comics-detail__title')
            ?.text
            .trim() ??
        '';

    // Cover
    final coverEl =
        document.querySelector('.comics-detail .l-content amp-img') ??
            document.querySelector('.comics-detail .l-content img');
    final coverRaw = coverEl?.attributes['src'] ?? '';
    final coverUrl = _cleanUrl(coverRaw);

    // Author
    final author = document
            .querySelector('.comics-detail__author')
            ?.text
            .trim() ??
        '';

    // Tags
    final tagEls = document.querySelectorAll(
        '.comics-detail .tag-list .tag');
    final tags = <String>[];
    for (final el in tagEls) {
      final text = el.text.trim();
      if (text.isNotEmpty && text != '连载中' && text != '已完结' &&
          text != '連載中' && text != '已完結') {
        tags.add(text);
      }
    }

    // Status
    MangaStatus status = MangaStatus.unknown;
    final allTags = tagEls.map((e) => e.text.trim()).toList();
    if (allTags.contains('连载中') || allTags.contains('連載中')) {
      status = MangaStatus.ongoing;
    } else if (allTags.contains('已完结') || allTags.contains('已完結')) {
      status = MangaStatus.completed;
    }

    // Latest chapter & update time
    final latestEl = document.querySelector(
        '.supporting-text > div:not(.tag-list) a');
    final latestChapter = latestEl?.text.trim();
    final updateTimeEl = document.querySelector(
        '.supporting-text > div:not(.tag-list) em');
    final updateTime = _parseUpdateTime(updateTimeEl?.text.trim() ?? '');

    // Chapters - collect from multiple possible containers
    final chapterEls = [
      ...document.querySelectorAll('#chapter-items > div'),
      ...document.querySelectorAll('#chapters_other_list > div'),
      ...document.querySelectorAll('.l-content .pure-g > div.comics-chapters'),
    ];

    final chapters = <ChapterItem>[];
    for (final div in chapterEls) {
      final aEl = div.querySelector('a');
      final chapterHref = aEl?.attributes['href'] ?? '';

      // chapter links use: /user/page_direct?comic_id=X&section_slot=N&chapter_slot=N
      final slotMatch = _slotPattern.firstMatch(chapterHref);
      if (slotMatch == null) continue;

      final sectionSlot = slotMatch.group(1) ?? '0';
      final chapterSlot = slotMatch.group(2) ?? '0';
      final chapterId = '${sectionSlot}_$chapterSlot';
      final chapterTitle = div.querySelector('span')?.text.trim() ??
          aEl?.text.trim() ??
          'Chapter';

      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: chapterTitle,
      ));
    }

    // Reverse to get chronological order (oldest first)
    final reversedChapters = chapters.reversed.toList();

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      tags: tags,
      status: status,
      latestChapter: latestChapter,
      updateTime: updateTime,
      chapters: reversedChapters,
    );
  }

  // ====== Chapter List (not used - chapters embedded in manga info) ======

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are embedded in manga info page, no separate fetch needed
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // ====== Chapter Content ======

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // chapterId format: "sectionSlot_chapterSlot"
    // URL: {chapterBase}/comic/chapter/{mangaId}/{sectionSlot}_{chapterSlot}.html
    // For multi-page chapters, page > 1 appends: _{page}.html
    // (e.g., 0_1.html for page 1, or 0_1_2.html for page 2)

    String url;
    if (page > 1) {
      url = '$_chapterBaseUrl/comic/chapter/$mangaId/${chapterId}_$page.html';
    } else {
      url = '$_chapterBaseUrl/comic/chapter/$mangaId/$chapterId.html';
    }

    return FetchConfig(
      url: url,
      headers: defaultHeaders,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Extract images from comic content area
    final imageEls = document.querySelectorAll(
        '.comic-contain > div:not(#div_top_ads):not(.mobadsq) amp-img');
    final images = <ChapterImage>[];

    for (final el in imageEls) {
      final src = el.attributes['src'] ?? el.attributes['data-src'] ?? '';
      if (src.isNotEmpty && !src.contains('default_cover')) {
        images.add(ChapterImage(
          url: src,
          headers: defaultHeaders,
        ));
      }
    }

    // If amp-img selector didn't work, try regular img tags
    if (images.isEmpty) {
      final imgEls = document.querySelectorAll(
          '.comic-contain > div:not(#div_top_ads):not(.mobadsq) img');
      for (final el in imgEls) {
        final src = el.attributes['src'] ?? el.attributes['data-src'] ?? '';
        if (src.isNotEmpty && !src.contains('default_cover')) {
          images.add(ChapterImage(
            url: src,
            headers: defaultHeaders,
          ));
        }
      }
    }

    // Check for multi-page chapter by looking at next_chapter links
    // The link URL pattern: /comic/chapter/{mangaId}/{sectionSlot}_{chapterSlot}_{pageSlot}.html
    bool canLoadMore = false;
    int? nextPage;

    final nextLinks = document.querySelectorAll('div.next_chapter a');
    for (final a in nextLinks) {
      final nextHref = a.attributes['href'] ?? '';
      final slotHtmlMatch = _slotHtmlPattern.firstMatch(nextHref);
      if (slotHtmlMatch != null) {
        final pageSlot = slotHtmlMatch.group(4);
        if (pageSlot != null && pageSlot.isNotEmpty) {
          final nextPageNum = int.tryParse(pageSlot);
          if (nextPageNum != null && nextPageNum > page) {
            canLoadMore = true;
            nextPage = nextPageNum;
            break;
          }
        }
      }
    }

    // Chapter title
    final title = document
            .querySelector('.comic-chapter .header .title')
            ?.text
            .trim() ??
        document.querySelector('.header .l-content .title')?.text.trim() ??
        '';

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: defaultHeaders,
      ),
      canLoadMore: canLoadMore,
      nextPage: nextPage,
    );
  }

  // --- Private Helpers ---

  /// Remove query string parameters from image URLs (tracking params etc.)
  String _cleanUrl(String url) {
    if (url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    // Return just scheme + host + path (strip query params)
    return uri.replace(query: '').toString().replaceAll('?', '');
  }

  /// Parse update time from various formats used by baozimh
  String? _parseUpdateTime(String text) {
    if (text.isEmpty) return null;

    // "2024年03月15日" format
    final fullMatch = _fullTimePattern.firstMatch(text);
    if (fullMatch != null) {
      return '${fullMatch.group(1)}-${fullMatch.group(2)}-${fullMatch.group(3)}';
    }

    // "N小时前" format
    final hourMatch = _hourTimePattern.firstMatch(text);
    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1)!) ?? 0;
      final now = DateTime.now().subtract(Duration(hours: hours));
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }

    // "今天 更新" format
    if (text.contains('今天')) {
      final now = DateTime.now();
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }

    return null;
  }
}
