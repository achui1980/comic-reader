import 'dart:convert';
import 'dart:math';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/utils/js_unpacker.dart';
import 'package:comic_reader/core/utils/lz_string.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class ManhuaGuiMobile extends MangaSource {
  static const String sourceId = 'mhgm';
  static const String _baseUrl = 'https://m.manhuagui.com';

  static const String _mobileUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 '
      'Mobile/15E148 Safari/604.1';

  /// Weighted CDN hostnames for image delivery
  static const Map<String, double> _cdnWeights = {
    'eu': 5,
    'eu1': 5,
    'us': 1,
    'us1': 1,
    'us2': 1,
    'us3': 1,
    'i': 0.1,
  };

  final _random = Random();

  /// Resolve a potentially relative URL to an absolute one
  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$_baseUrl$url';
  }

  @override
  String get id => sourceId;

  @override
  String get name => '漫画柜mobile';

  @override
  String get shortName => 'MHGM';

  @override
  bool get isAdult => true;

  @override
  String? get description => '需要代理，频繁访问会封IP';

  @override
  double get score => 5.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => true;

  @override
  String? get userAgent => _mobileUA;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _mobileUA,
        'Referer': _baseUrl,
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'type',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '连载', value: 'lianzai'),
            FilterChoice(label: '完结', value: 'wanjie'),
            FilterChoice(label: '日本', value: 'japan'),
            FilterChoice(label: '港台', value: 'hongkong'),
            FilterChoice(label: '其他', value: 'other'),
            FilterChoice(label: '欧美', value: 'europe'),
            FilterChoice(label: '内地', value: 'china'),
            FilterChoice(label: '韩国', value: 'korea'),
            FilterChoice(label: '热血', value: 'rexue'),
            FilterChoice(label: '冒险', value: 'maoxian'),
            FilterChoice(label: '魔幻', value: 'mohuan'),
            FilterChoice(label: '神鬼', value: 'shengui'),
            FilterChoice(label: '搞笑', value: 'gaoxiao'),
            FilterChoice(label: '萌系', value: 'mengxi'),
            FilterChoice(label: '爱情', value: 'aiqing'),
            FilterChoice(label: '科幻', value: 'kehuan'),
            FilterChoice(label: '魔法', value: 'mofa'),
            FilterChoice(label: '格斗', value: 'gedou'),
            FilterChoice(label: '武侠', value: 'wuxia'),
            FilterChoice(label: '机战', value: 'jizhan'),
            FilterChoice(label: '战争', value: 'zhanzheng'),
            FilterChoice(label: '竞技', value: 'jingji'),
            FilterChoice(label: '体育', value: 'tiyu'),
            FilterChoice(label: '校园', value: 'xiaoyuan'),
            FilterChoice(label: '生活', value: 'shenghuo'),
            FilterChoice(label: '励志', value: 'lizhi'),
            FilterChoice(label: '历史', value: 'lishi'),
            FilterChoice(label: '伪娘', value: 'weiniang'),
            FilterChoice(label: '宅男', value: 'zhainan'),
            FilterChoice(label: '腐女', value: 'funv'),
            FilterChoice(label: '耽美', value: 'danmei'),
            FilterChoice(label: '百合', value: 'baihe'),
            FilterChoice(label: '后宫', value: 'hougong'),
            FilterChoice(label: '治愈', value: 'zhiyu'),
            FilterChoice(label: '美食', value: 'meishi'),
            FilterChoice(label: '推理', value: 'tuili'),
            FilterChoice(label: '悬疑', value: 'xuanyi'),
            FilterChoice(label: '恐怖', value: 'kongbu'),
            FilterChoice(label: '四格', value: 'sige'),
            FilterChoice(label: '职场', value: 'zhichang'),
            FilterChoice(label: '侦探', value: 'zhentan'),
            FilterChoice(label: '社会', value: 'shehui'),
            FilterChoice(label: '音乐', value: 'yinyue'),
            FilterChoice(label: '舞蹈', value: 'wudao'),
            FilterChoice(label: '杂志', value: 'zazhi'),
            FilterChoice(label: '黑道', value: 'heidao'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: '',
          choices: [
            FilterChoice(label: '添加时间', value: ''),
            FilterChoice(label: '更新时间', value: 'update'),
            FilterChoice(label: '浏览次数', value: 'view'),
          ],
        ),
      ];

  @override
  List<FilterOption> get searchFilters => const [
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: '',
          choices: [
            FilterChoice(label: '添加时间', value: ''),
            FilterChoice(label: '更新时间', value: '1'),
            FilterChoice(label: '浏览次数', value: '2'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final type = filters['type'] ?? '';
    final sort = filters['sort'] ?? '';

    final path = type.isNotEmpty ? '/list/$type/' : '/list/';
    return FetchConfig(
      url: '$_baseUrl$path',
      headers: {'User-Agent': _mobileUA},
      queryParameters: {
        'page': '$page',
        'catid': '0',
        'ajax': '1',
        if (sort.isNotEmpty) 'order': sort,
      },
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parseFragment(htmlStr);

    final items = document.querySelectorAll('li > a');
    final results = <MangaSummary>[];

    for (final item in items) {
      final href = item.attributes['href'] ?? '';
      final mangaId = _extractMangaIdFromHref(href);
      if (mangaId == null) continue;

      final titleEl = item.querySelector('h3');
      final title = titleEl?.text.trim() ?? '';

      final imgEl = item.querySelector('div.thumb img');
      final cover = imgEl?.attributes['data-src'] ??
          imgEl?.attributes['src'] ??
          '';
      final fullCover = _resolveUrl(cover);

      final ddElements = item.querySelectorAll('dl > dd');
      String author = '';
      String? latest;
      String? updateTime;
      if (ddElements.isNotEmpty) author = ddElements[0].text.trim();
      if (ddElements.length >= 3) latest = ddElements[2].text.trim();
      if (ddElements.length >= 4) updateTime = ddElements[3].text.trim();

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: fullCover,
        author: author,
        latestChapter: latest,
        updateTime: updateTime,
      ));
    }

    return results;
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final sort = filters['sort'] ?? '';
    final sortSuffix = sort.isNotEmpty ? '_o$sort' : '';

    if (page <= 1) {
      return FetchConfig(
        url: '$_baseUrl/s/${Uri.encodeComponent(keyword)}$sortSuffix.html',
        headers: {'User-Agent': _mobileUA},
      );
    }

    // Page > 1 uses POST with form data
    return FetchConfig(
      url: '$_baseUrl/s/${Uri.encodeComponent(keyword)}$sortSuffix.html',
      method: HttpMethod.post,
      headers: {
        'User-Agent': _mobileUA,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'page=$page&ajax=1&order=$sort',
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parseFragment(htmlStr);

    final items = document.querySelectorAll('li > a');
    // Also try the detail list format
    final detailItems = document.querySelectorAll('ul#detail > li > a');
    final allItems = items.isNotEmpty ? items : detailItems;

    final results = <MangaSummary>[];

    for (final item in allItems) {
      final href = item.attributes['href'] ?? '';
      final mangaId = _extractMangaIdFromHref(href);
      if (mangaId == null) continue;

      final titleEl = item.querySelector('h3');
      final title = titleEl?.text.trim() ?? '';

      final imgEl = item.querySelector('div.thumb img');
      final cover = imgEl?.attributes['data-src'] ??
          imgEl?.attributes['src'] ??
          '';
      final fullCover = _resolveUrl(cover);

      final ddElements = item.querySelectorAll('dl > dd');
      String author = '';
      String? latest;
      String? updateTime;
      if (ddElements.isNotEmpty) author = ddElements[0].text.trim();
      if (ddElements.length >= 3) latest = ddElements[2].text.trim();
      if (ddElements.length >= 4) updateTime = ddElements[3].text.trim();

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: fullCover,
        author: author,
        latestChapter: latest,
        updateTime: updateTime,
      ));
    }

    return results;
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/comic/$mangaId/',
      headers: {'User-Agent': _mobileUA},
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Try to extract numeric bid from script
    final bidMatch =
        RegExp(r'\{\s*bid:(\d+),').firstMatch(htmlStr);
    if (bidMatch != null) {
      // We can use the bid as the mangaId if needed
      mangaId = bidMatch.group(1) ?? mangaId;
    }

    // Status
    var status = MangaStatus.unknown;
    final statusEl = document.querySelector('div.book-detail div.thumb i');
    if (statusEl != null) {
      final statusText = statusEl.text.trim();
      if (statusText.contains('连载')) {
        status = MangaStatus.ongoing;
      } else if (statusText.contains('完结')) {
        status = MangaStatus.completed;
      }
    }

    // Title
    final titleEl = document.querySelector('div.main-bar > h1') ??
        document.querySelector('div.book-title > h1');
    final title = titleEl?.text.trim() ?? '';

    // Cover
    final coverEl = document.querySelector('div.book-detail div.thumb img') ??
        document.querySelector('div.book-cover img');
    final cover = coverEl?.attributes['data-src'] ??
        coverEl?.attributes['src'] ??
        '';
    final fullCover = _resolveUrl(cover);

    // Metadata from cont-list dl
    final dlElements = document.querySelectorAll('div.cont-list dl');
    final authors = <String>[];
    final tags = <String>[];
    String? updateTime;

    for (final dl in dlElements) {
      final dt = dl.querySelector('dt');
      final label = dt?.text.trim() ?? '';
      final ddLinks = dl.querySelectorAll('dd a');

      if (label.contains('作者')) {
        for (final a in ddLinks) {
          final authorName = a.text.trim();
          if (authorName.isNotEmpty) authors.add(authorName);
        }
      } else if (label.contains('类型') || label.contains('类别')) {
        for (final a in ddLinks) {
          final tag = a.text.trim();
          if (tag.isNotEmpty) tags.add(tag);
        }
      } else if (label.contains('更新')) {
        final dd = dl.querySelector('dd');
        updateTime = dd?.text.trim();
      }
    }

    // Chapters
    var chapters = <ChapterItem>[];

    // Check for error/audit page - chapters hidden in __VIEWSTATE
    final errorAudit = document.querySelector('#erroraudit_show');
    final viewState = document.querySelector('#__VIEWSTATE');

    if (errorAudit != null && viewState != null) {
      final compressed = viewState.attributes['value'] ?? '';
      if (compressed.isNotEmpty) {
        final decompressed = LZString.decompressFromBase64(compressed);
        if (decompressed != null && decompressed.isNotEmpty) {
          final chapterDoc = html_parser.parseFragment(decompressed);
          chapters = _parseChapterElements(chapterDoc, mangaId);
        }
      }
    }

    // Normal chapter list
    if (chapters.isEmpty) {
      final chapterList = document.querySelector('#chapterList');
      if (chapterList != null) {
        chapters = _parseChapterElements(chapterList, mangaId);
      }
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: fullCover,
      author: authors.join(', '),
      tags: tags,
      status: status,
      updateTime: updateTime,
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are parsed from manga info page
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    // Chapter list is parsed within parseMangaInfo
    return const ChapterListResult(chapters: []);
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/comic/$mangaId/$chapterId.html',
      headers: {'User-Agent': _mobileUA},
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;

    // Find the packed eval script
    final evalPattern = RegExp(
      r'window\["\\x65\\x76\\x61\\x6c"\]\((.+?)\)\s*[\n<]',
      dotAll: true,
    );
    var evalMatch = evalPattern.firstMatch(htmlStr);

    // Alternative: look for the packed function directly
    String? packedScript;
    if (evalMatch != null) {
      packedScript = evalMatch.group(1);
    } else {
      packedScript = JsUnpacker.findPackedScript(htmlStr);
    }

    if (packedScript == null) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    // Unpack the script
    final unpacked = JsUnpacker.unpack(packedScript);
    if (unpacked == null) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    // Extract JSON data from SMH.reader({...}).preInit();
    final readerPattern = RegExp(r'SMH\.reader\(({.*})\)\.preInit', dotAll: true);
    final readerMatch = readerPattern.firstMatch(unpacked);

    if (readerMatch == null) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    final jsonStr = readerMatch.group(1)!;
    Map<String, dynamic> readerData;
    try {
      readerData = json.decode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    final chapterTitle = readerData['chapterTitle'] as String? ?? '';
    final imagePaths = (readerData['images'] as List?)?.cast<String>() ?? [];
    final sl = readerData['sl'] as Map<String, dynamic>?;

    // Build SL query params
    String slParams = '';
    if (sl != null) {
      slParams = sl.entries.map((e) => '${e.key}=${e.value}').join('&');
    }

    // Select CDN hostname and build image URLs
    final hostname = _selectCdnHost();
    final imageHeaders = {'Referer': _baseUrl};
    final images = imagePaths.map((path) {
      final url = slParams.isNotEmpty
          ? 'https://$hostname.hamreus.com$path?$slParams'
          : 'https://$hostname.hamreus.com$path';
      return ChapterImage(url: url, headers: imageHeaders);
    }).toList();

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: chapterTitle,
        images: images,
      ),
    );
  }

  // --- Private helpers ---

  /// Extract manga ID from href like "/comic/12345/"
  String? _extractMangaIdFromHref(String href) {
    final match = RegExp(r'/comic/(\d+)').firstMatch(href);
    return match?.group(1);
  }

  /// Parse chapter elements from an HTML fragment
  List<ChapterItem> _parseChapterElements(Node container, String mangaId) {
    final chapters = <ChapterItem>[];
    final links = (container is Element)
        ? container.querySelectorAll('ul > li > a')
        : (container as DocumentFragment).querySelectorAll('ul > li > a');

    for (final link in links) {
      final chapterHref = link.attributes['href'] ?? '';
      final chapterIdMatch =
          RegExp(r'/comic/\d+/(\d+)').firstMatch(chapterHref);
      if (chapterIdMatch == null) continue;

      final chId = chapterIdMatch.group(1)!;
      final chTitle = link.text.trim();

      chapters.add(ChapterItem(
        id: chId,
        mangaId: mangaId,
        title: chTitle,
        href: '$_baseUrl$chapterHref',
      ));
    }

    return chapters;
  }

  /// Select a CDN hostname based on weights
  String _selectCdnHost() {
    double totalWeight = 0;
    for (final w in _cdnWeights.values) {
      totalWeight += w;
    }

    double randomVal = _random.nextDouble() * totalWeight;
    for (final entry in _cdnWeights.entries) {
      randomVal -= entry.value;
      if (randomVal <= 0) return entry.key;
    }
    return 'eu'; // fallback
  }
}
