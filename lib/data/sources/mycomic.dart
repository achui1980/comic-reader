// Task 3 会用到以下导入（详情页 `x-data` 内嵌 JSON 解析），尚无引用者，先注释以
// 保持 `flutter analyze` 干净：
// import 'dart:convert';

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

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    throw UnimplementedError('parseMangaInfo');
  }

  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) {
    throw UnimplementedError('parseChapter');
  }
}
