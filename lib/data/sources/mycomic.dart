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
///
///    **仅 [usesWebViewFetch] 还不够**：本站的 Cloudflare 部署连**页面内的
///    `fetch()` 也会重新挑战** —— 在已通过挑战、cookie 齐备的页面上下文里发出的
///    in-page fetch 依旧返回 403（真机 macOS 实测：`WebView fetch returned status
///    403`）。故四条请求路径一律带 `extra: {'renderMode': true}`，改走
///    `fetchRendered` 的**顶层导航**路径：把目标 URL 当真实页面加载，再取
///    `document.documentElement.outerHTML`。该失败模式与这条逃生舱的原委见
///    `lib/data/remote/webview_fetcher_native.dart` 里 `fetchRendered` 的 doc，
///    开关判定在 `lib/data/remote/http_client.dart` 的 `renderMode`。
/// 2. 章节列表由 Alpine.js 客户端渲染，DOM 里只有 `<template x-for>`；真正的
///    数据以 JSON 内嵌在祖先 div 的 `x-data` 属性里，故 [parseMangaInfo] 从该
///    **DOM 属性**取值后做引号感知的括号深度扫描提取。
///
///    渲染后取 DOM 属性是安全的：Alpine.js **不会移除** `x-data` 属性，渲染前后
///    该属性都在，唯一的差别是属性的**引号形态**（原始 HTML 单引号包裹、值内 `"`
///    原样；`outerHTML` 双引号包裹、值内 `"` 转义成 `&quot;`）——
///    而这恰恰是必须走 DOM 而非原始字符串的理由，详见 [_extractChapters]。
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
      extra: const {'renderMode': true},
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
      extra: const {'renderMode': true},
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/$_locale/comics/$mangaId',
      extra: const {'renderMode': true},
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
      extra: const {'renderMode': true},
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

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  /// 最新章节徽章：在卡片 `<a>` 内取所有**叶子 div**（无子元素节点），选第一个
  /// 满足「文本非空、不等于标题、长度 ≤ 20」者。长度上限用于排除简介类长文本。
  ///
  /// 判长度**之前必须折叠空白**，返回值也用折叠后的文本：站点上已完结作品的角标
  /// 不是单行章节名，而是「章节名 + `[完]`」两行结构，HTML 缩进会让原始文本长达
  /// 80 余字符，未折叠时全部撞上 `> 20` 守卫（实测真实列表页 30 张卡片有 13 张因此
  /// 丢了 latestChapter）。折叠后 `短篇 [完]` 只有 6 字符，而简介折叠后仍 > 20，
  /// 所以阈值本身依旧有效。
  String? _latestChapterText(Element anchor, String title) {
    for (final div in anchor.querySelectorAll('div')) {
      if (div.children.isNotEmpty) continue;
      final text = div.text.replaceAll(_whitespacePattern, ' ').trim();
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

  /// 连载状态：**必须**锚定 Flux 的 `[data-flux-badge]` 徽章，不能全文档扫描。
  ///
  /// 页脚的状态筛选链接 `?filter[end]=0` / `=1` 文本恰好也是「连载中」/「已完结」，
  /// 而且是叶子 `<a>`，任何「扫全文档叶子元素、取顶序首个命中」的写法都会撞上它们。
  /// 有徽章的作品判对纯属侥幸（真徽章在文档顶序上早于页脚，两份真实详情页——连载中
  /// 与已完结——均如此；不写死具体偏移，它会随站点每次改版漂移，且代码里也没有任何
  /// 依赖该数值的常量）；**没有徽章**的作品则会命中页脚更靠前的「连载中」而被误判成
  /// ongoing，本应是 unknown。
  ///
  /// 折叠空白只是**与 [_latestChapterText] 保持一致的防御性归一化**，不是这里的必需
  /// 品：实测真徽章文本 `\n        连载中\n    ` 单靠 `trim()` 就已干净（`trim` 后
  /// 恰好 3 字符），而 `连载中` / `已完结` 都无内部空白，折叠前后完全相同。保留它是因为
  /// 徽章文本形态由 Flux 组件决定、改版后可能夹进内部空白，成本又可忽略。
  /// 属性选择器已把范围收窄到详情页上唯一的那个徽章，无需再加叶子元素守卫。
  MangaStatus _parseStatus(Document document) {
    for (final element in document.querySelectorAll('[data-flux-badge]')) {
      switch (element.text.replaceAll(_whitespacePattern, ' ').trim()) {
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
    final document = html_parser.parse(response as String);

    // 站点为 newest-first。
    final chapters = _extractChapters(document, mangaId);

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

  /// 只做**定位**：挑出属性值含 `chapters:` 的那个 `x-data`。
  ///
  static const String _chaptersKeyMarker = 'chapters:';

  /// 只做**定位**：挑出属性值含 `chapters:` 的那个 `x-data`。
  ///
  /// 这里用宽松的文本 marker 而不是 [_chaptersArrayStartPattern]，是为了把职责分开
  /// —— 本方法负责「哪个元素」，[_sliceChaptersJson] 负责「值合不合法」。若站点改版
  /// 成 `chapters: chapterStore`，本方法照样选中该元素，随后由 [_sliceChaptersJson]
  /// 抛出它自己那条更精确的错误；反过来（这里就用严格正则）会让那条守卫变成死代码。
  ///
  /// 找不到时**必须抛错**，不能静默返回空章节表：后者会让详情页看起来正常、只是
  /// 一章都没有，比抛错难查得多。与 [_sliceChaptersJson] 的失败语义保持一致。
  String _chaptersXData(Document document) {
    for (final element in document.querySelectorAll('[x-data]')) {
      final value = element.attributes['x-data'] ?? '';
      if (value.contains(_chaptersKeyMarker)) return value;
    }
    throw Exception('MyComic: 详情页未找到内嵌章节数据（x-data 里的 chapters:），站点结构可能已变更');
  }

  /// 提取 Alpine `x-data` 里内嵌的章节数组。实测该数组在整页中恰好出现一次，
  /// 且长篇（262 话）也一次性全部内嵌，故无需分页。
  ///
  /// 走 **DOM 属性**而非原始响应字符串，这是正确性的必要条件、不是风格取舍：本源
  /// 线上走 renderMode（见类级 doc），拿到的是 `document.documentElement.outerHTML`，
  /// 而浏览器序列化属性时一律用**双引号**包裹属性值，于是值内原本的 `"` 全部变成
  /// `&quot;`（真站实抓 `chapters: [{&quot;id&quot;:818150,...`）——
  /// 把这样的原始串直接喂 `jsonDecode` 必抛 `FormatException`。
  /// `package:html` 解析属性值时会把 `&quot;` 解码回 `"`，故走 DOM 属性对**两种
  /// 引号形态都成立**：服务端下发的原始 HTML 用单引号包裹、值内 `"` 原样，此时实体
  /// 解码是恒等操作，行为与改动前完全相同（既有的一众原始串夹具即为此作证）。
  ///
  /// 页面上有多个 `[x-data]` 元素（真站渲染后详情页 30 个，下拉、排序控件都在用
  /// Alpine），所以由 [_chaptersXData] **遍历**挑出含 `chapters:` 的那一个 ——
  /// 既保住了原先「用文本 marker 定位比猜 CSS 选择器稳」的性质，又顺带解决了实体
  /// 解码问题。
  List<ChapterItem> _extractChapters(Document document, String mangaId) {
    final decoded = jsonDecode(_sliceChaptersJson(_chaptersXData(document)));
    if (decoded is! List) {
      throw Exception('MyComic: 内嵌章节数据不是 JSON 数组');
    }

    final items = <ChapterItem>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id == null) continue;
      // 用类型**检查**而非 `as String?` 强转：后者只容忍 null，遇到非字符串
      // （`"title":123`）会抛 TypeError，而 [parseMangaInfo] 全程无 try/catch，
      // 整个详情页会因此加载失败。退化成 id 才是这里本来的意图。
      final rawTitle = entry['title'];
      items.add(ChapterItem(
        id: '$id',
        mangaId: mangaId,
        title: rawTitle is String ? rawTitle.trim() : '$id',
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

  /// 阅读器页章节标题：主路径是 `application/ld+json` 里 BreadcrumbList 的末项。
  ///
  /// **不能用 `og:title`**：实测阅读器页的 `og:title` 只有 `猎人游戏W - MYCOMIC -
  /// 我的漫画`，压根不含章节名，走它会让所有章节都显示同一个作品名（`Chapter.title`
  /// 驱动阅读器顶部标题栏与连续阅读的章节分界标签，等于无法区分章节）。页面上也没有
  /// h1/h2/h3 或任何可见章节标题元素，`<title>` 同样不含章节名。
  ///
  /// 取 breadcrumb **末项**（`position` 最大者）的 `name`，因为它是**纯章节名**
  /// `第01话`；LD-JSON 顶层还有个同名 `name` 字段，值是 `作品名 - 章节名` 复合格式，
  /// 用它就得多押一层分隔符假设，故不用。
  ///
  /// 保留 `og:title` 作为回退：站点裁掉结构化数据时，退化成作品名总比空标题好
  /// （空串会让 UI 出现无名章节）。回退**只剥站点后缀，不再按 ` - ` 二次切分**：
  /// 既然 og:title 里压根没有章节名可切（见上），那次切分就只剩害处 —— 作品名自带
  /// ` - ` 时（`Re - Zero 从零开始`）会被截成 `Re`，让「作品名总比空标题好」这条
  /// 唯一理由反过来不成立。
  String _chapterTitle(Document document) {
    final fromBreadcrumb = _breadcrumbLeafName(document);
    if (fromBreadcrumb != null) return fromBreadcrumb;

    return _stripSiteSuffix(_meta(document, 'og:title') ?? '');
  }

  /// 取 `application/ld+json` 里 `itemListElement` 中 `position` 最大那项的 `name`。
  ///
  /// `<script>` 在 `package:html` 里是 raw text element，`script.text` 返回未解码
  /// HTML 实体的原始文本，正是 `jsonDecode` 要的。整段用 try/catch 包住：站点塞进
  /// 非法 JSON 时只能让本方法返回 null 走回退，不能把整个 [parseChapter] 带崩。
  ///
  /// **没有任何一项带合法 `position` 时返回 null，绝不退化成取列表首项**：
  /// `itemListElement` 是有序列表、根节点在前叶子在后，首项是站点级根节点（实测真站
  /// 该位置的值是 `漫画资料库`），拿它当 `Chapter.title` 比回退到 og:title 的作品名
  /// （`猎人游戏W`）严格更糟。而 `position` 是 schema.org `BreadcrumbList` 对
  /// `ListItem` 的必填属性，全缺即畸形数据 —— 对畸形数据「弃」而非「猜」，与上面
  /// try/catch 的取向一致。
  String? _breadcrumbLeafName(Document document) {
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      Object? decoded;
      try {
        decoded = jsonDecode(script.text);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) continue;

      final list = decoded['itemListElement'];
      if (list is! List || list.isEmpty) continue;

      Map<dynamic, dynamic>? leaf;
      num? leafPosition;
      for (final entry in list) {
        if (entry is! Map) continue;
        final position = entry['position'];
        final value = position is num ? position : null;
        if (value != null && (leafPosition == null || value > leafPosition)) {
          leaf = entry;
          leafPosition = value;
        }
      }
      if (leaf == null) continue;

      final name = leaf['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    }
    return null;
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
      // 按 data-src → src 取值：实测阅读器页前几张（3 张）图把真实地址直接写在
      // src 上、根本没有 data-src，第 4 张起才是 lozad 懒加载（data-src 才是真实
      // 地址、src 是占位图）。两条分支都是承载性路径，不是「主路径 + 兜底」——
      // 删掉 `?? src` 会让每章前几页静默消失。
      final url = (img.attributes['data-src'] ?? img.attributes['src'] ?? '')
          .trim();
      // 两条守卫兜住「带 page class 却拿不到章节图地址」的两种残缺形态：既无 src
      // 也无 data-src（模板漏写 / lozad 尚未注入）→ 空串，被 isEmpty 拦；lozad
      // 元素只有占位 src 却缺 data-src → `??` 取到 base64 或 /img/placeholder.gif，
      // 被 `/chapters/` 拦。后者仅指这一种缺 data-src 的形态，取到 src 本身并不
      // 意味着坏数据。
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
