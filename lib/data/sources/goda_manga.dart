import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// GodaManga (GoDa漫画) source plugin.
/// Uses the APP API (appgb3.baozimh.com) which serves SSR HTML pages.
/// This is a mirror/alternative domain for baozimh (包子漫画).
class GodaManga extends MangaSource {
  static const String sourceId = 'godamanga';
  static const String _baseUrl = 'https://appgb3.baozimh.com/baozimhapp';
  static const String _coverCdn = 'https://s.baozicdn.com/baozimhapp/cover';
  static const String _webUrl = 'https://godamh.com';

  static const String _appUserAgent = 'baozimh_android/1.0.31/gb/adset';

  @override
  String get id => sourceId;

  @override
  String get name => 'GoDa漫画';

  @override
  String get shortName => 'GoDa';

  @override
  String? get description => '国漫/日漫/韩漫 (包子漫画APP线路)';

  @override
  double get score => 4.0;

  @override
  String? get href => _webUrl;

  @override
  String? get userAgent => _appUserAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _appUserAgent,
        'Referer': '$_baseUrl/',
      };

  @override
  bool get needsCloudflare => false;

  @override
  List<FilterOption> get discoveryFilters => const [
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
          name: 'type',
          label: '类型',
          defaultValue: 'all',
          choices: [
            FilterChoice(label: '全部', value: 'all'),
            FilterChoice(label: '恋爱', value: 'lianai'),
            FilterChoice(label: '纯爱', value: 'chunai'),
            FilterChoice(label: '古风', value: 'gufeng'),
            FilterChoice(label: '异能', value: 'yineng'),
            FilterChoice(label: '悬疑', value: 'xuanyi'),
            FilterChoice(label: '剧情', value: 'juqing'),
            FilterChoice(label: '科幻', value: 'kehuan'),
            FilterChoice(label: '奇幻', value: 'qihuan'),
            FilterChoice(label: '玄幻', value: 'xuanhuan'),
            FilterChoice(label: '穿越', value: 'chuanyue'),
            FilterChoice(label: '冒险', value: 'maoxian'),
            FilterChoice(label: '推理', value: 'tuili'),
            FilterChoice(label: '武侠', value: 'wuxia'),
            FilterChoice(label: '格斗', value: 'gedou'),
            FilterChoice(label: '战争', value: 'zhanzheng'),
            FilterChoice(label: '热血', value: 'rexue'),
            FilterChoice(label: '搞笑', value: 'gaoxiao'),
            FilterChoice(label: '大女主', value: 'danvzhu'),
            FilterChoice(label: '都市', value: 'dushi'),
            FilterChoice(label: '总裁', value: 'zongcai'),
            FilterChoice(label: '后宫', value: 'hougong'),
            FilterChoice(label: '日常', value: 'richang'),
            FilterChoice(label: '韩漫', value: 'hanman'),
            FilterChoice(label: '少年', value: 'shaonian'),
            FilterChoice(label: '其它', value: 'qita'),
          ],
        ),
        FilterOption(
          name: 'state',
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
  static final _chapterUrlPattern =
      RegExp(r'/comic/chapter/([^/]+)/([0-9]+)_([0-9]+)(?:_([0-9]+))?\.html');
  static final _fullTimePattern =
      RegExp(r'([0-9]{4})年([0-9]{2})月([0-9]{2})日');
  // Extract slug from onclick="send_app_msg('call_page', ['comic', 'slug'])"
  static final _onclickSlugPattern =
      RegExp(r"send_app_msg\('call_page',\s*\['comic',\s*'([^']+)'\]\)");

  /// Matches chapter onclick: send_app_msg('call_page', ['chapter', 'slug', section, chapter])
  static final _onclickChapterPattern = RegExp(
      r"send_app_msg\('call_page',\s*\['chapter',\s*'([^']+)',\s*([0-9]+),\s*([0-9]+)\]\)");

  // ====== Discovery ======

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final type = filters['type'] ?? 'all';
    final region = filters['region'] ?? 'all';
    final state = filters['state'] ?? 'all';

    return FetchConfig(
      url: '$_baseUrl/classify',
      headers: defaultHeaders,
      queryParameters: {
        'type': type,
        'region': region,
        'state': state,
        'filter': '*',
        'page': '$page',
        'limit': '36',
      },
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final results = <MangaSummary>[];
    // Each comic card is within .classify-items .comics-card
    final cards = document.querySelectorAll('.classify-items .comics-card');

    for (final card in cards) {
      // Extract slug from onclick attribute: send_app_msg('call_page', ['comic', 'slug'])
      final posterEl = card.querySelector('.comics-card__poster');
      final onclick = posterEl?.attributes['onclick'] ?? '';
      final slugMatch = _onclickSlugPattern.firstMatch(onclick);
      if (slugMatch == null) continue;
      final slug = slugMatch.group(1)!;

      // Cover image - use data-src (lazy load), fallback to src
      final imgEl = card.querySelector('img');
      final coverSrc =
          imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '';
      final coverUrl = (coverSrc.isNotEmpty &&
              !coverSrc.contains('default_cover'))
          ? coverSrc
          : '$_coverCdn/$slug.jpg?w=285&h=380&q=100';

      // Title - from aria-label on poster or h3
      final title = posterEl?.attributes['aria-label'] ??
          card.querySelector('.comics-card__title h3')?.text.trim() ??
          card.querySelector('.comics-card__title')?.text.trim() ??
          '';

      // Author (in small.tags area)
      final author =
          card.querySelector('small.tags')?.text.trim() ??
          card.querySelector('.tags')?.text.trim() ??
          '';

      if (title.isNotEmpty) {
        results.add(MangaSummary(
          id: slug,
          sourceId: sourceId,
          title: title,
          coverUrl: coverUrl,
          author: author,
          headers: defaultHeaders,
        ));
      }
    }

    return results;
  }

  // ====== Search ======

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search',
      queryParameters: {'q': keyword, 'page': '$page'},
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final results = <MangaSummary>[];
    // Search results use .comics-card structure
    final cards = document.querySelectorAll('.comics-card');

    for (final card in cards) {
      final posterEl = card.querySelector('.comics-card__poster');
      final onclick = posterEl?.attributes['onclick'] ?? '';
      final slugMatch = _onclickSlugPattern.firstMatch(onclick);
      if (slugMatch == null) continue;
      final slug = slugMatch.group(1)!;

      final imgEl = card.querySelector('img');
      final coverSrc =
          imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '';
      final coverUrl = (coverSrc.isNotEmpty &&
              !coverSrc.contains('default_cover'))
          ? coverSrc
          : '$_coverCdn/$slug.jpg?w=285&h=380&q=100';

      final title = posterEl?.attributes['aria-label'] ??
          card.querySelector('.comics-card__title h3')?.text.trim() ??
          card.querySelector('.comics-card__title')?.text.trim() ??
          '';

      final author =
          card.querySelector('small.tags')?.text.trim() ??
          card.querySelector('.tags')?.text.trim() ??
          '';

      if (title.isNotEmpty) {
        results.add(MangaSummary(
          id: slug,
          sourceId: sourceId,
          title: title,
          coverUrl: coverUrl,
          author: author,
          headers: defaultHeaders,
        ));
      }
    }

    return results;
  }

  // ====== Manga Info ======

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/comic/$mangaId',
      headers: defaultHeaders,
      // Large pages (500KB+) with all chapters embedded need longer timeout
      timeout: const Duration(seconds: 120),
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Title - from .comics-detail__title or page title
    final title =
        document.querySelector('.comics-detail__title')?.text.trim() ??
            document.querySelector('title')?.text.trim() ??
            '';

    // Cover
    final coverEl = document.querySelector('.comics-detail__info amp-img') ??
        document.querySelector('.comics-detail__info img') ??
        document.querySelector('.l-content amp-img') ??
        document.querySelector('.l-content img');
    final coverSrc = coverEl?.attributes['src'] ?? '';
    final coverUrl = coverSrc.isNotEmpty
        ? coverSrc
        : '$_coverCdn/$mangaId.jpg?w=285&h=380&q=100';

    // Author
    final author =
        document.querySelector('.comics-detail__author')?.text.trim() ??
            document.querySelector('.supporting-text .author')?.text.trim() ??
            '';

    // Description
    final description =
        document.querySelector('.comics-detail__desc')?.text.trim() ??
            document.querySelector('.lb-none')?.text.trim();

    // Tags & Status
    final tagEls = document.querySelectorAll('.tag-list .tag');
    final tags = <String>[];
    MangaStatus status = MangaStatus.unknown;

    for (final el in tagEls) {
      final text = el.text.trim();
      if (text == '連載中' || text == '连载中') {
        status = MangaStatus.ongoing;
      } else if (text == '已完結' || text == '已完结') {
        status = MangaStatus.completed;
      } else if (text.isNotEmpty) {
        tags.add(text);
      }
    }

    // Update time
    String? updateTime;
    final timeEl = document.querySelector('.supporting-text em');
    if (timeEl != null) {
      updateTime = _parseUpdateTime(timeEl.text.trim());
    }

    // Latest chapter
    final latestEl = document.querySelector('.supporting-text a');
    final latestChapter = latestEl?.text.trim();

    // Chapters - from chapter list sections
    // The chapters use onclick="send_app_msg('call_page', ['chapter', slug, section, chapter])"
    // on <div class="comics-chapters__item"> elements (not <a> tags)
    final chapters = <ChapterItem>[];

    final chapterEls = document.querySelectorAll('.comics-chapters__item');

    final seenIds = <String>{};
    for (final el in chapterEls) {
      final onclick = el.attributes['onclick'] ?? '';
      final match = _onclickChapterPattern.firstMatch(onclick);
      if (match == null) continue;

      // match.group(1) = slug (may differ from mangaId with hash suffix)
      final section = match.group(2) ?? '0';
      final chapter = match.group(3) ?? '0';
      final chapterId = '${section}_$chapter';

      if (seenIds.contains(chapterId)) continue;
      seenIds.add(chapterId);

      final chapterTitle = el.querySelector('span')?.text.trim() ??
          el.text.trim();

      if (chapterTitle.isNotEmpty) {
        chapters.add(ChapterItem(
          id: chapterId,
          mangaId: mangaId,
          title: chapterTitle,
        ));
      }
    }

    // Sort by chapter index numerically (oldest first)
    // The HTML has two sections: a "latest" section (descending, ~25 items)
    // followed by a "full list" section (ascending). Simple reverse doesn't work
    // because dedup preserves insertion order across both sections.
    chapters.sort((a, b) {
      final aParts = a.id.split('_');
      final bParts = b.id.split('_');
      final aSection = int.tryParse(aParts[0]) ?? 0;
      final bSection = int.tryParse(bParts[0]) ?? 0;
      if (aSection != bSection) return aSection.compareTo(bSection);
      final aChapter = int.tryParse(aParts.length > 1 ? aParts[1] : '0') ?? 0;
      final bChapter = int.tryParse(bParts.length > 1 ? bParts[1] : '0') ?? 0;
      return aChapter.compareTo(bChapter);
    });
    final orderedChapters = chapters;

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
      updateTime: updateTime,
      headers: defaultHeaders,
      chapters: orderedChapters,
    );
  }

  // ====== Chapter List (embedded in manga info) ======

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are embedded in manga info page
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
    // chapterId format: "section_chapter" (e.g., "0_1")
    // For multi-page chapters, page > 1 appends: _{page}.html

    String url;
    if (page > 1) {
      url = '$_baseUrl/comic/chapter/$mangaId/${chapterId}_$page.html';
    } else {
      url = '$_baseUrl/comic/chapter/$mangaId/$chapterId.html';
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

    // Extract images from data-src attributes on img.comic-contain__item
    final imageEls = document.querySelectorAll('img.comic-contain__item');
    final images = <ChapterImage>[];

    for (final el in imageEls) {
      final src = el.attributes['data-src'] ?? el.attributes['src'] ?? '';
      if (src.isNotEmpty && !src.contains('pixel.gif')) {
        images.add(ChapterImage(
          url: src,
          headers: defaultHeaders,
        ));
      }
    }

    // Fallback: try amp-img or any img in .comic-contain
    if (images.isEmpty) {
      final fallbackEls = document.querySelectorAll(
          '.comic-contain amp-img, .comic-contain img');
      for (final el in fallbackEls) {
        final src = el.attributes['data-src'] ??
            el.attributes['src'] ??
            '';
        if (src.isNotEmpty &&
            !src.contains('pixel.gif') &&
            !src.contains('loading')) {
          images.add(ChapterImage(
            url: src,
            headers: defaultHeaders,
          ));
        }
      }
    }

    // Check for multi-page chapter (next page link)
    bool canLoadMore = false;
    int? nextPage;

    final nextLinks = document.querySelectorAll('.next_chapter a, a.nextBtn');
    for (final a in nextLinks) {
      final nextHref = a.attributes['href'] ?? '';
      final match = _chapterUrlPattern.firstMatch(nextHref);
      if (match != null) {
        final pageSlot = match.group(4);
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
    final title = document.querySelector('.header .title')?.text.trim() ?? '';

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

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_webUrl/comic/$mangaId/$chapterId';
  }

  // --- Private Helpers ---

  /// Parse update time from various formats
  String? _parseUpdateTime(String text) {
    if (text.isEmpty) return null;

    // "2026年06月15日" format
    final fullMatch = _fullTimePattern.firstMatch(text);
    if (fullMatch != null) {
      return '${fullMatch.group(1)}-${fullMatch.group(2)}-${fullMatch.group(3)}';
    }

    // "今天 更新" or "今天更新"
    if (text.contains('今天')) {
      final now = DateTime.now();
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }

    return null;
  }
}
