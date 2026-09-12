import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// 我的漫画 (mycomic.com) —— Laravel + Alpine.js + Flux UI + Tailwind 的中文
/// 漫画聚合站。两个特点决定了本实现的形状：
///
/// 1. 主站在 Cloudflare 的 TLS/JA3 指纹校验后面（普通 Dio 请求直接 403 WAF 页），
///    因此走 [usesWebViewFetch]；而图片 CDN `biccam.com` 不受该校验，只需
///    `Referer` 头即可放行，走直连快速路径。
/// 2. 章节列表由 Alpine.js 客户端渲染，DOM 里只有 `<template x-for>`；真正的
///    数据以 JSON 内嵌在祖先 div 的 `x-data` 属性里，故 [parseMangaInfo] 在
///    **原始响应字符串**上做括号深度扫描提取，不依赖 DOM。
///
/// Tailwind 工具类不可作为选择器依据（类名长且随构建变化），本实现一律基于
/// 结构不变量、OG meta 与内嵌 JSON。
class MyComic extends MangaSource {
  static const String sourceId = 'mycomic';
  static const String _baseUrl = 'https://mycomic.com';
  static const String _locale = 'cn';
  static const String _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  // CDN 放行的唯一条件：实测 `Referer` 单独即可 200，UA / Cookie 都不需要。
  static const Map<String, String> _imageHeaders = {'Referer': '$_baseUrl/'};

  @override
  String get id => sourceId;

  @override
  String get name => '我的漫画';

  @override
  String get shortName => 'MYC';

  @override
  String? get description => '我的漫画 mycomic.com，中文漫画聚合站，支持题材/地区/状态筛选。';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  /// 站点整体是通用漫画站，但人气榜前列混有明确的成人作品，保守起见标记。
  @override
  bool get isAdult => true;

  @override
  bool get needsCloudflare => true;

  @override
  bool get usesWebViewFetch => true;

  @override
  String? get cloudflareUrl => '$_baseUrl/$_locale';

  @override
  String? get userAgent => _ua;

  @override
  Map<String, String>? get defaultHeaders => const {
    'User-Agent': _ua,
    'Referer': '$_baseUrl/',
  };

  /// [FilterOption.name] 直接用站点真实参数名，使请求构造只需「跳过空值后原样
  /// 透传」，无需维护映射表。空 value 代表「全部」。
  @override
  List<FilterOption> get discoveryFilters => const [
    FilterOption(
      name: 'sort',
      label: '排序',
      defaultValue: '-update',
      choices: [
        FilterChoice(label: '最近更新', value: '-update'),
        FilterChoice(label: '最高人气', value: '-views'),
      ],
    ),
    FilterOption(
      name: 'filter[tag]',
      label: '题材',
      defaultValue: '',
      choices: [
        FilterChoice(label: '全部', value: ''),
        FilterChoice(label: '魔幻', value: 'mohuan'),
        FilterChoice(label: '魔法', value: 'mofa'),
        FilterChoice(label: '热血', value: 'rexue'),
        FilterChoice(label: '冒险', value: 'maoxian'),
        FilterChoice(label: '悬疑', value: 'xuanyi'),
        FilterChoice(label: '侦探', value: 'zhentan'),
        FilterChoice(label: '爱情', value: 'aiqing'),
        FilterChoice(label: '校园', value: 'xiaoyuan'),
        FilterChoice(label: '搞笑', value: 'gaoxiao'),
        FilterChoice(label: '四格', value: 'sige'),
        FilterChoice(label: '科幻', value: 'kehuan'),
        FilterChoice(label: '神鬼', value: 'shengui'),
        FilterChoice(label: '舞蹈', value: 'wudao'),
        FilterChoice(label: '音乐', value: 'yinyue'),
        FilterChoice(label: '百合', value: 'baihe'),
        FilterChoice(label: '后宫', value: 'hougong'),
        FilterChoice(label: '机战', value: 'jizhan'),
        FilterChoice(label: '格斗', value: 'gedou'),
        FilterChoice(label: '恐怖', value: 'kongbu'),
        FilterChoice(label: '萌系', value: 'mengxi'),
        FilterChoice(label: '武侠', value: 'wuxia'),
        FilterChoice(label: '社会', value: 'shehui'),
        FilterChoice(label: '体育', value: 'tiyu'),
        FilterChoice(label: '腐女', value: 'funv'),
        FilterChoice(label: '推理', value: 'tuili'),
        FilterChoice(label: '杂志', value: 'zazhi'),
        FilterChoice(label: '历史', value: 'lishi'),
        FilterChoice(label: '耽美', value: 'danmei'),
        FilterChoice(label: '励志', value: 'lizhi'),
        FilterChoice(label: '职场', value: 'zhichang'),
        FilterChoice(label: '生活', value: 'shenghuo'),
        FilterChoice(label: '治愈', value: 'zhiyu'),
        FilterChoice(label: '伪娘', value: 'weiniang'),
        FilterChoice(label: '黑道', value: 'heidao'),
        FilterChoice(label: '战争', value: 'zhanzheng'),
        FilterChoice(label: '竞技', value: 'jingji'),
        FilterChoice(label: '美食', value: 'meishi'),
        FilterChoice(label: '宅男', value: 'zhainan'),
      ],
    ),
    FilterOption(
      name: 'filter[country]',
      label: '地区',
      defaultValue: '',
      choices: [
        FilterChoice(label: '全部', value: ''),
        FilterChoice(label: '日本', value: 'japan'),
        FilterChoice(label: '大陆', value: 'china'),
        FilterChoice(label: '港台', value: 'hongkong'),
        FilterChoice(label: '韩国', value: 'korea'),
        FilterChoice(label: '欧美', value: 'europe'),
        FilterChoice(label: '其他', value: 'other'),
      ],
    ),
    FilterOption(
      name: 'filter[end]',
      label: '状态',
      defaultValue: '',
      choices: [
        FilterChoice(label: '全部', value: ''),
        FilterChoice(label: '连载中', value: '0'),
        FilterChoice(label: '已完结', value: '1'),
      ],
    ),
  ];

  @override
  List<FilterOption> get searchFilters => const [];

  /// 参数名由调用方自带的筛选器列表决定（发现页传 [discoveryFilters]，搜索传
  /// [searchFilters]），因此这里只做「跳过空值后原样透传」。不设共享白名单：任
  /// 何一份列表新增筛选器都会自动生效，也不会让某条路径拿另一条路径的键名去过
  /// 滤——那样会静默丢参数（UI 可选但请求里没有）。
  Map<String, dynamic> _buildQuery(
    int page,
    Map<String, String> filters,
    List<FilterOption> options,
  ) {
    final query = <String, dynamic>{'page': '$page'};
    for (final option in options) {
      final value = filters[option.name];
      if (value != null && value.isNotEmpty) {
        query[option.name] = value;
      }
    }
    return query;
  }

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/$_locale/comics',
      queryParameters: _buildQuery(page, filters, discoveryFilters),
      timeout: const Duration(seconds: 60),
    );
  }

  /// 搜索与列表共用同一端点，差异仅在 `q` 参数。
  @override
  FetchConfig prepareSearchFetch(
    String keyword,
    int page,
    Map<String, String> filters,
  ) {
    return FetchConfig(
      url: '$_baseUrl/$_locale/comics',
      queryParameters: {
        'q': keyword,
        ..._buildQuery(page, filters, searchFilters),
      },
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/$_locale/comics/$mangaId',
      timeout: const Duration(seconds: 60),
    );
  }

  /// 章节已随详情页一并取得，无需额外请求。
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  @override
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) {
    return FetchConfig(
      url: '$_baseUrl/$_locale/chapters/$chapterId',
      timeout: const Duration(seconds: 60),
    );
  }

  static final RegExp _comicIdPattern = RegExp(r'/comics/(\d+)');

  @override
  List<MangaSummary> parseDiscovery(dynamic response) =>
      _parseList(response as String);

  @override
  List<MangaSummary> parseSearch(dynamic response) =>
      _parseList(response as String);

  List<MangaSummary> _parseList(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final anchor in document.querySelectorAll('a[href]')) {
      final match = _comicIdPattern.firstMatch(anchor.attributes['href'] ?? '');
      if (match == null) continue;

      // 「随机漫画」导航链接不包 img，由此滤除。
      final img = anchor.querySelector('img');
      if (img == null) continue;
      final title = (img.attributes['alt'] ?? '').trim();
      if (title.isEmpty) continue;

      final id = match.group(1)!;
      if (!seen.add(id)) continue;

      results.add(MangaSummary(
        id: id,
        sourceId: sourceId,
        title: title,
        coverUrl: (img.attributes['data-src'] ?? img.attributes['src'] ?? '')
            .trim(),
        latestChapter: _latestChapterText(anchor, title),
        headers: _imageHeaders,
      ));
    }

    return results;
  }

  /// 最新章节徽章：在卡片 `<a>` 内取所有**叶子 div**（无子元素节点），选第一个
  /// 满足「文本非空、不等于标题、长度 ≤ 20」者。长度上限用于排除简介类长文本。
  String? _latestChapterText(Element anchor, String title) {
    for (final div in anchor.querySelectorAll('div')) {
      if (div.children.isNotEmpty) continue;
      final text = div.text.trim();
      if (text.isEmpty || text == title || text.length > 20) continue;
      return text;
    }
    return null;
  }

  static const String _siteSuffixMarker = ' - MYCOMIC';

  /// 剥掉 `og:title` 的 ` - MYCOMIC - 我的漫画` 站点后缀。
  String _stripSiteSuffix(String value) {
    final text = value.trim();
    final idx = text.indexOf(_siteSuffixMarker);
    return idx > 0 ? text.substring(0, idx).trim() : text;
  }

  String? _meta(Document document, String property) {
    final element = document.querySelector('meta[property="$property"]') ??
        document.querySelector('meta[name="$property"]');
    final content = element?.attributes['content']?.trim();
    return (content == null || content.isEmpty) ? null : content;
  }

  /// 收集 href 含指定筛选参数的链接文本（去重、保持文档顺序）。
  /// 同时容错百分号编码与未编码两种形式。
  List<String> _filterLinkTexts(Document document, String parameter) {
    final encoded = 'filter%5B$parameter%5D';
    final plain = 'filter[$parameter]';
    final texts = <String>[];
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (!href.contains(encoded) && !href.contains(plain)) continue;
      final text = anchor.text.trim();
      if (text.isEmpty || texts.contains(text)) continue;
      texts.add(text);
    }
    return texts;
  }

  MangaStatus _parseStatus(Document document) {
    for (final element in document.querySelectorAll('span, div, a, p')) {
      if (element.children.isNotEmpty) continue;
      switch (element.text.trim()) {
        case '连载中':
          return MangaStatus.ongoing;
        case '已完结':
          return MangaStatus.completed;
      }
    }
    return MangaStatus.unknown;
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // 站点为 newest-first。
    final chapters = _extractChapters(htmlStr, mangaId);

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: _stripSiteSuffix(_meta(document, 'og:title') ?? ''),
      coverUrl: _meta(document, 'og:image') ?? '',
      // 必须用 og:description：页面内最长文本块是评论区广告垃圾。
      description: _meta(document, 'og:description'),
      author: _filterLinkTexts(document, 'author').join(', '),
      tags: _filterLinkTexts(document, 'tag'),
      status: _parseStatus(document),
      latestChapter: chapters.isEmpty ? null : chapters.first.title,
      headers: _imageHeaders,
      // 阅读器要 oldest-first。
      chapters: chapters.reversed.toList(),
    );
  }

  /// 提取 Alpine `x-data` 里内嵌的章节数组。实测该数组在整页中恰好出现一次，
  /// 且长篇（262 话）也一次性全部内嵌，故无需分页。
  ///
  /// 走**原始响应字符串**而非 DOM 属性：页面上有多个 `[x-data]` 元素（下拉、
  /// 排序控件都在用 Alpine），用 `chapters:` 文本 marker 定位比猜 CSS 选择器稳。
  /// 代价是 HTML 实体不会被解码——标题里的 `&amp;` 会原样带进 UI，且若站点某天
  /// 把 `x-data` 改成双引号包裹（属性值内的 `"` 变成 `&quot;`），本路径会直接
  /// `FormatException`。Task 6 拿到真实 HTML 后确认是否需要补 unescape。
  List<ChapterItem> _extractChapters(String htmlStr, String mangaId) {
    final decoded = jsonDecode(_sliceChaptersJson(htmlStr));
    if (decoded is! List) {
      throw Exception('MyComic: 内嵌章节数据不是 JSON 数组');
    }

    final items = <ChapterItem>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id == null) continue;
      items.add(ChapterItem(
        id: '$id',
        mangaId: mangaId,
        title: (entry['title'] as String?)?.trim() ?? '$id',
        href: '$_baseUrl/$_locale/chapters/$id',
      ));
    }
    return items;
  }

  static final RegExp _chaptersArrayStartPattern = RegExp(r'chapters:\s*\[');

  /// 起始符靠正则**定位**，数组边界靠引号/转义感知的括号深度扫描**切片**。
  ///
  /// **不要用正则切片。** `chapters:\s*(\[.*?\])` 在章节标题含 `]`（卷名、括注
  /// 很常见）时会静默截断成非法 JSON。用正则*定位*起始 `[` 则是安全的，而且比
  /// `indexOf('[', marker)` 更严格：后者对「`[` 与 `chapters:` 的距离」毫无约束，
  /// 站点一旦改版成 `chapters: chapterStore` / `chapters: null`，扫描器会跳到
  /// 文档任意远处抓走一个完全无关的 `[`（无关数组 → 静默 0 章节，推荐位数组 →
  /// 静默产出看起来正常的假章节），比抛错难查得多。故要求 `[` 紧跟在 `chapters:`
  /// 之后（中间只容许空白）。
  String _sliceChaptersJson(String htmlStr) {
    final match = _chaptersArrayStartPattern.firstMatch(htmlStr);
    if (match == null) {
      throw Exception('MyComic: 详情页未找到内嵌章节数组（chapters: [），站点结构可能已变更');
    }
    final start = match.end - 1;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < htmlStr.length; i++) {
      final ch = htmlStr[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (inString) {
        if (ch == '"') inString = false;
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) return htmlStr.substring(start, i + 1);
      }
    }
    throw Exception('MyComic: 内嵌章节 JSON 数组未闭合');
  }

  /// 阅读器页章节标题：`og:title` 形如「第01话 - 猎人游戏W - MYCOMIC - 我的漫画」，
  /// 先剥站点后缀，再取首个 ` - ` 之前的部分。
  String _chapterTitle(Document document) {
    final stripped = _stripSiteSuffix(_meta(document, 'og:title') ?? '');
    final idx = stripped.indexOf(' - ');
    return idx > 0 ? stripped.substring(0, idx).trim() : stripped;
  }

  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) {
    final document = html_parser.parse(response as String);
    final images = <ChapterImage>[];
    final seen = <String>{};

    for (final img in document.querySelectorAll('img.page')) {
      // lozad 懒加载：真实地址在 data-src，src 是占位图。
      final url = (img.attributes['data-src'] ?? img.attributes['src'] ?? '')
          .trim();
      // 兜底「带 page class 却拿不到章节图地址」的两种形态：既无 src 也无
      // data-src（模板漏写 / lozad 尚未注入）→ 空串；只有占位 src 而没有
      // data-src → `??` 回退到 base64 或 /img/placeholder.gif。
      // 注意国旗图标不靠这里排除，它在 `img.page` 选择器阶段就已被滤掉。
      if (url.isEmpty || !url.contains('/chapters/')) continue;
      if (!seen.add(url)) continue;
      images.add(ChapterImage(url: url, headers: _imageHeaders));
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: _chapterTitle(document),
        images: images,
        headers: _imageHeaders,
      ),
      canLoadMore: false,
    );
  }
}
