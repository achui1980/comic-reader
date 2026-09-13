# MyComic（mycomic.com）数据源 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **实施后勘误（本文是计划时快照，按本仓惯例不回写正文）。** 实现阶段拿到真实 HTML 做离线验收，推翻了本文以下四处内容；正文里那几段可直接复制的实现代码**已被判为缺陷，不要照抄**。**一切以 `lib/data/sources/mycomic.dart` 与 `test/data/sources/mycomic_test.dart` 为准**：
>
> 1. **状态解析**：本文给出的 `querySelectorAll('span, div, a, p')` 叶子扫描是缺陷 —— 页脚的 `filter[end]` 筛选链接文本恰好也是「连载中」/「已完结」且是叶子 `<a>`，无徽章的作品会被误判成 ongoing。最终实现锚定 `[data-flux-badge]`。
> 2. **章节数组定位**：本文的 `indexOf('chapters:')` + `indexOf('[', marker)` 对两者距离毫无约束，站点改成 `chapters: null` 之类时会跳到远处抓走无关数组（静默产出假章节）。最终实现用锚定正则 `chapters:\s*\[`。
> 3. **章节标题来源**：不是 og:title 剥后缀 + ` - ` 切分。主路径是 `application/ld+json` 里 BreadcrumbList 的末项；og:title 只作回退，且**不做 ` - ` 切分**（作品名自带 ` - ` 时会被截断）。
> 4. **阅读器页夹具的 og:title**：本文写作 `第01话 - 猎人游戏W - MYCOMIC - 我的漫画`，实抓为 `猎人游戏W - MYCOMIC - 我的漫画`，**不含章节名**。

**Goal:** 为 comic-reader 新增 `mycomic.com`（我的漫画）漫画源，支持发现/筛选、搜索、详情、章节列表与章节图片，并在双平台绕过 Cloudflare TLS 指纹校验。

**Architecture:** 单文件源插件 `lib/data/sources/mycomic.dart`，遵循框架的 prepare/parse 分离契约（源不触碰网络）。主站请求走 WebView-fetch（native）/ curl-impersonate（web）绕过 Cloudflare；图片 CDN `biccam.com` 直连，仅靠 `Referer` 头放行。章节列表不额外发请求——从详情页 `x-data` 属性内嵌的 JSON 中用「引号/转义感知的括号深度扫描」提取。

**Tech Stack:** Dart / Flutter；`package:html`（DOM 解析）；`dart:convert`（jsonDecode）；`flutter_test`（离线夹具单测）。

**Spec:** `docs/superpowers/specs/2026-09-12-mycomic-source-design.md`

---

## 前置阅读（实现者必读）

1. 契约基类：`lib/data/sources/manga_source.dart`
2. 最接近的参考实现（Cloudflare + WebView fetch）：`lib/data/sources/manga18_club.dart`
3. 测试风格护标：`test/data/sources/copy_manga_test.dart`

**关键框架事实（已核实，不要重新推导）：**

- `FetchConfig.queryParameters` 的值在本仓惯例中一律用 **String**（护标 `copy_manga_test.dart` 断言 `'offset'` 为 `'0'`）。
- `queryParameters` 在 WebView-fetch 路径同样生效（`lib/data/remote/http_client.dart` 的 `_resolveUrl()` 会合并进 URL），`filter[tag]` 会被编码为 `filter%5Btag%5D`。
- **不要设 `extra['renderMode']`**。它会让 WebView 返回渲染后 HTML，而本源需要的章节 JSON 只存在于服务端原始 HTML 的 `x-data` 属性中。
- **不要 override `batchDelay`**。已核实全仓 `lib/` 内无消费方（仅基类定义 + 文档提及），它是死配置。
- **不要 override `cloudflarePageTitles`**。基类默认 `['Just a moment...']` 恰好匹配本站的挑战页标题。
- 章节图片与封面**不经过 `HttpClient`**（由 `ExtendedImage` / `manga_cover_image.dart` 直接加载），所以 CDN 直连自动成立；代价是 `Referer` 必须写进 `ChapterImage.headers` / `MangaSummary.headers` / `MangaDetail.headers` **三处**，漏一处即 403。

**验证命令（全程只用这两条，不跑全仓 `flutter test`）：**

```bash
flutter test test/data/sources/mycomic_test.dart
flutter analyze lib/data/sources/mycomic.dart
```

> 为何不跑全仓：`AGENTS.md` 记载 `test/verify_*.dart` 是手动联网脚本、`test/widget_test.dart` 现状即失败，全仓结果无法作为通过判据。

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/data/sources/mycomic.dart` | 创建 | 源插件全部逻辑（元数据、平台配置、筛选器、prepare/parse、章节 JSON 提取） |
| `test/data/sources/mycomic_test.dart` | 创建 | 离线 HTML 夹具单测，覆盖 8 个非显然陷阱 |
| `lib/app/di/injection.dart` | 修改（import 区 + 第 207 行后） | 注册源 |
| `tools/run_web.sh` | 修改（`CURL_IMPERSONATE_HOSTS` 默认值） | web 端把 `mycomic.com` 加入 curl-impersonate 名单 |
| `AGENTS.md` | 修改（第 122 行） | 更正 extra 注入点的文件指向 |

单文件是本仓 40 个源的既定模式（`manga18_club.dart` 473 行），不做拆分。

---

### Task 1: 源骨架 —— 元数据、平台配置、筛选器、请求构造器

本任务建立可编译的骨架：所有 `parse*` 先以 `UnimplementedError` 占位（Dart 抽象类必须全部实现才能编译，测试才跑得起来），Task 2–4 逐个替换。

**Files:**
- Create: `lib/data/sources/mycomic.dart`
- Test: `test/data/sources/mycomic_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/data/sources/mycomic_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/mycomic.dart';

void main() {
  late MyComic source;

  setUp(() {
    source = MyComic();
  });

  group('MyComic metadata', () {
    test('exposes stable identity', () {
      expect(source.id, 'mycomic');
      expect(source.name, '我的漫画');
      expect(source.shortName, 'MYC');
      expect(source.href, 'https://mycomic.com');
      expect(source.isAdult, isTrue);
    });

    test('enables the cloudflare webview-fetch path', () {
      expect(source.needsCloudflare, isTrue);
      expect(source.usesWebViewFetch, isTrue);
      expect(source.cloudflareUrl, 'https://mycomic.com/cn');
      expect(source.defaultHeaders?['Referer'], 'https://mycomic.com/');
      expect(source.defaultHeaders?['User-Agent'], contains('Chrome/124.0.0.0'));
    });

    test('exposes four discovery filters using the site parameter names', () {
      expect(source.discoveryFilters, hasLength(4));
      expect(
        source.discoveryFilters.map((f) => f.name),
        ['sort', 'filter[tag]', 'filter[country]', 'filter[end]'],
      );
      expect(source.searchFilters, isEmpty);
    });

    test('tag filter starts with an "all" choice and covers 38 slugs', () {
      final tag =
          source.discoveryFilters.firstWhere((f) => f.name == 'filter[tag]');
      expect(tag.choices.first.value, '');
      expect(tag.choices, hasLength(39));
      expect(
        tag.choices.map((c) => c.value),
        containsAll(<String>['mohuan', 'baihe', 'danmei', 'zazhi']),
      );
    });
  });

  group('MyComic request builders', () {
    test('discovery omits empty filter values', () {
      final config = source.prepareDiscoveryFetch(1, const {});
      expect(config.url, 'https://mycomic.com/cn/comics');
      expect(config.method, HttpMethod.get);
      expect(config.queryParameters, {'page': '1'});
    });

    test('discovery passes through non-empty filters verbatim', () {
      final config = source.prepareDiscoveryFetch(3, const {
        'sort': '-views',
        'filter[tag]': 'baihe',
        'filter[country]': '',
        'filter[end]': '1',
      });
      expect(config.queryParameters, {
        'page': '3',
        'sort': '-views',
        'filter[tag]': 'baihe',
        'filter[end]': '1',
      });
    });

    test('search reuses the comics endpoint with a q parameter', () {
      final config = source.prepareSearchFetch('猎人', 2, const {});
      expect(config.url, 'https://mycomic.com/cn/comics');
      expect(config.queryParameters?['q'], '猎人');
      expect(config.queryParameters?['page'], '2');
    });

    test('manga info targets the numeric comic id', () {
      final config = source.prepareMangaInfoFetch('55355');
      expect(config.url, 'https://mycomic.com/cn/comics/55355');
    });

    test('chapter list needs no extra request', () {
      expect(source.prepareChapterListFetch('55355', 1), isNull);
      expect(source.parseChapterList('', '55355').chapters, isEmpty);
    });

    test('chapter targets the numeric chapter id', () {
      final config = source.prepareChapterFetch('55355', '818144', 1);
      expect(config.url, 'https://mycomic.com/cn/chapters/818144');
      expect(config.timeout, const Duration(seconds: 60));
    });
  });
}
```

注意 `HttpMethod` 来自 `core/models/fetch_config.dart`，**不**由 `entities.dart` 导出，故上面显式导入了它。本任务还用不到 `entities.dart`（`MangaStatus` / `ScrambleType` 从 Task 3 起才需要），先不导入以免 unused import。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/sources/mycomic_test.dart`
Expected: 编译失败，`Error: Couldn't resolve the package 'comic_reader' ... mycomic.dart` 或 `Target of URI doesn't exist`。

- [ ] **Step 3: 写最小实现**

创建 `lib/data/sources/mycomic.dart`：

```dart
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
  static const String _ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// CDN 放行的唯一条件：实测 `Referer` 单独即可 200，UA / Cookie 都不需要。
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

  static const List<String> _filterKeys = [
    'sort',
    'filter[tag]',
    'filter[country]',
    'filter[end]',
  ];

  Map<String, dynamic> _buildQuery(int page, Map<String, String> filters) {
    final query = <String, dynamic>{'page': '$page'};
    for (final key in _filterKeys) {
      final value = filters[key];
      if (value != null && value.isNotEmpty) {
        query[key] = value;
      }
    }
    return query;
  }

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/$_locale/comics',
      queryParameters: _buildQuery(page, filters),
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
        ..._buildQuery(page, filters),
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

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    throw UnimplementedError('parseDiscovery');
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    throw UnimplementedError('parseSearch');
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
```

此时 `dart:convert`、`html_parser`、`Document` 三个导入尚未使用，`flutter analyze` 会报 unused import。Task 2–4 会用上它们；本步骤先**注释掉**这三行以保持 analyze 干净，Task 2 起逐步取消注释。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/sources/mycomic_test.dart`
Expected: PASS（10 个 test 全绿）

Run: `flutter analyze lib/data/sources/mycomic.dart`
Expected: `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add lib/data/sources/mycomic.dart test/data/sources/mycomic_test.dart
git commit -m "feat: 新增 mycomic 源骨架（元数据、Cloudflare 配置、筛选器与请求构造）"
```

---

### Task 2: 列表解析（发现与搜索共用）

**判定规则（结构不变量，不赌 Tailwind 类名）：** 遍历所有 `a[href]`，同时满足 ①`href` 匹配 `/comics/(\d+)`，②该 `<a>` 内含 `<img>` 且其 `alt` 非空。导航栏的「随机漫画」链接用 Alpine `:href` 绑定且不包 `img`，被条件 ② 自然滤除。

**Files:**
- Modify: `lib/data/sources/mycomic.dart`
- Test: `test/data/sources/mycomic_test.dart`

- [ ] **Step 1: 写失败测试**

在 `test/data/sources/mycomic_test.dart` 的 `main()` 内、`group('MyComic request builders', ...)` 之后追加：

```dart
  group('MyComic list parsing', () {
    test('keeps only real cards and drops the random-comic nav anchor', () {
      final results = source.parseDiscovery(_listFixture);

      expect(results, hasLength(2));

      expect(results[0].id, '55355');
      expect(results[0].sourceId, 'mycomic');
      expect(results[0].title, '猎人游戏W');
      expect(results[0].coverUrl, 'https://biccam.com/comics/55355-9e7018.jpg');
      expect(results[0].latestChapter, '第07话');
      expect(results[0].headers?['Referer'], 'https://mycomic.com/');

      expect(results[1].id, '40001');
      expect(results[1].title, '测试漫画');
      // data-src 优先于占位 src
      expect(results[1].coverUrl, 'https://biccam.com/comics/40001-aa11bb.jpg');
      // 该卡片的 <a> 内没有叶子 div，取不到最新章节
      expect(results[1].latestChapter, isNull);
    });

    test('parseSearch shares the list parser', () {
      expect(source.parseSearch(_listFixture), hasLength(2));
    });
  });
```

并在文件**末尾**（`main()` 之后，遵循 `copy_manga_test.dart` 的夹具位置惯例）追加：

```dart
/// 列表页夹具：1 个导航「随机漫画」锚点（无 img，须被滤除）+ 2 张真卡片。
const String _listFixture = '''
<html><body>
  <nav>
    <a href="https://mycomic.com/cn/comics/12345"
       :href="comicUrl({id: Math.floor(Math.random() * maxComicId)})">随机漫画</a>
  </nav>
  <div class="grid grid-cols-3 md:grid-cols-6">
    <div class="group relative">
      <a href="https://mycomic.com/cn/comics/55355">
        <img src="https://biccam.com/comics/55355-9e7018.jpg" alt="猎人游戏W">
        <div class="absolute inset-x-0 bottom-0"><div>第07话</div></div>
      </a>
      <div class="mt-2 text-center"><div data-flux-subheading>猎人游戏W</div></div>
    </div>
    <div class="group relative">
      <a href="https://mycomic.com/cn/comics/40001">
        <img src="https://biccam.com/img/placeholder.gif"
             data-src="https://biccam.com/comics/40001-aa11bb.jpg" alt="测试漫画">
      </a>
    </div>
  </div>
</body></html>
''';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/sources/mycomic_test.dart`
Expected: 2 个新 test FAIL，报 `UnimplementedError: parseDiscovery`

- [ ] **Step 3: 写最小实现**

在 `lib/data/sources/mycomic.dart` 中取消 `import 'package:html/parser.dart' as html_parser;` 与 `import 'package:html/dom.dart';` 的注释，并把 `parseDiscovery` / `parseSearch` 两个占位替换为：

```dart
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/sources/mycomic_test.dart`
Expected: PASS（12 个 test 全绿）

Run: `flutter analyze lib/data/sources/mycomic.dart`
Expected: `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add lib/data/sources/mycomic.dart test/data/sources/mycomic_test.dart
git commit -m "feat: mycomic 列表解析，按结构不变量滤除随机漫画导航链接"
```

---

### Task 3: 详情解析 —— OG meta + 内嵌章节 JSON 括号扫描

两个非显然陷阱：

1. **简介必须取 `og:description`。** 详情页内「最长文本块」全是评论区的色情/外送茶广告垃圾（实测多条 200–1300 字），任何「取最长文本」的启发式都会中招。
2. **章节 JSON 必须用括号深度扫描，不能用正则。** `chapters:\s*(\[.*?\])` 在章节标题含 `]`（卷名、括注很常见）时会静默截断成非法 JSON。

**Files:**
- Modify: `lib/data/sources/mycomic.dart`
- Test: `test/data/sources/mycomic_test.dart`

- [ ] **Step 1: 写失败测试**

在 `main()` 内追加：

```dart
  group('MyComic manga info parsing', () {
    test('takes the description from og:description, not the comment spam', () {
      final detail = source.parseMangaInfo(_detailFixture, '55355');

      expect(detail.id, '55355');
      expect(detail.sourceId, 'mycomic');
      expect(detail.title, '猎人游戏W');
      expect(detail.coverUrl, 'https://biccam.com/comics/55355-9e7018.jpg');
      expect(detail.description, '被卷入死亡游戏的少年们的故事。');
      expect(detail.description, isNot(contains('外送茶')));
      expect(detail.author, '某作者');
      expect(detail.tags, ['百合', '职场']);
      expect(detail.status, MangaStatus.ongoing);
      expect(detail.headers?['Referer'], 'https://mycomic.com/');
    });

    test('reverses the site newest-first order to oldest-first', () {
      final detail = source.parseMangaInfo(_detailFixture, '55355');

      // latestChapter 取反转前的首项
      expect(detail.latestChapter, '第07话');
      expect(detail.chapters.map((c) => c.id), ['818144', '818149', '818150']);
      expect(detail.chapters.first.title, '第01话');
      expect(detail.chapters.first.mangaId, '55355');
      expect(
        detail.chapters.first.href,
        'https://mycomic.com/cn/chapters/818144',
      );
    });

    test('does not truncate titles containing "]" or escaped quotes', () {
      final detail = source.parseMangaInfo(_trickyChaptersFixture, '999');

      expect(detail.chapters, hasLength(2));
      expect(detail.chapters.map((c) => c.title), ['第"零"话', '卷1 [完] 特别篇']);
      expect(detail.latestChapter, '卷1 [完] 特别篇');
    });

    test('decodes unicode-escaped titles', () {
      final detail = source.parseMangaInfo(_escapedChaptersFixture, '888');
      expect(detail.chapters.single.title, '第07话');
    });

    test('throws when the embedded chapter payload is gone', () {
      expect(
        () => source.parseMangaInfo(_noChaptersFixture, '777'),
        throwsA(isA<Exception>()),
      );
    });

    test('accepts a legitimately empty chapter array', () {
      final detail = source.parseMangaInfo(_emptyChaptersFixture, '666');
      expect(detail.chapters, isEmpty);
      expect(detail.latestChapter, isNull);
      expect(detail.title, '未上架作品');
    });
  });
```

在文件末尾追加夹具（`_trickyChaptersFixture` / `_escapedChaptersFixture` 含反斜杠，必须用 **raw** 字符串 `r'''`，否则 Dart 会先把 `\u7b2c` 当成自己的转义）：

```dart
/// 详情页夹具：OG meta + 状态徽章 + 作者/题材筛选链接 + x-data 内嵌章节 JSON
/// + 一段评论区垃圾长文本（用于证明简介不是「取最长文本」）。
const String _detailFixture = '''
<html><head>
  <meta property="og:title" content="猎人游戏W - MYCOMIC - 我的漫画">
  <meta property="og:description" content="被卷入死亡游戏的少年们的故事。">
  <meta property="og:image" content="https://biccam.com/comics/55355-9e7018.jpg">
</head><body>
  <span class="badge">连载中</span>
  <a href="/cn/comics?filter%5Bauthor%5D=%E6%9F%90%E4%BD%9C%E8%80%85">某作者</a>
  <a href="/cn/comics?filter%5Btag%5D=baihe">百合</a>
  <a href="/cn/comics?filter%5Btag%5D=zhichang">职场</a>
  <a href="/cn/chapters/818150">开始阅读</a>
  <div x-data='{
    chapters: [{"id":818150,"title":"第07话"},{"id":818149,"title":"第06话"},{"id":818144,"title":"第01话"}],
    decending: true,
    toggleSorting() { this.decending = !this.decending }
  }'>
    <template x-for="chapter in chapters"><a :href="chapterUrl(chapter)"></a></template>
  </div>
  <div class="comments">
    <p>【外送茶】加LINE看照片，全套服務，市區叫小姐外送到府，價格實在，安全可靠，歡迎老闆來電諮詢，我們有各種類型的妹妹可以挑選，保證真人實照，不滿意可換人，二十四小時營業，全台都有服務點，還可以指定時間地點，先看照片再決定，不用先付訂金，見面滿意再付款，絕不強迫消費。</p>
  </div>
</body></html>
''';

/// 标题含 `]` 与转义引号——正则方案 `\[.*?\]` 会在这里静默截断。
const String _trickyChaptersFixture = r'''
<html><head>
  <meta property="og:title" content="括号试炼 - MYCOMIC - 我的漫画">
</head><body>
  <div x-data='{
    chapters: [{"id":11,"title":"卷1 [完] 特别篇"},{"id":10,"title":"第\"零\"话"}],
    decending: true
  }'></div>
</body></html>
''';

/// 原始 HTML 里章节标题是 unicode 转义的，交由 jsonDecode 原生处理。
const String _escapedChaptersFixture = r'''
<html><head>
  <meta property="og:title" content="转义试炼 - MYCOMIC - 我的漫画">
</head><body>
  <div x-data='{ chapters: [{"id":818150,"title":"\u7b2c07\u8bdd"}] }'></div>
</body></html>
''';

/// 站点改版移除内嵌章节 —— 必须显式抛错，不能静默返回空。
const String _noChaptersFixture = '''
<html><head>
  <meta property="og:title" content="改版了 - MYCOMIC - 我的漫画">
</head><body><div x-data='{ decending: true }'></div></body></html>
''';

/// 合法的空章节表（尚未上架的作品）。
const String _emptyChaptersFixture = '''
<html><head>
  <meta property="og:title" content="未上架作品 - MYCOMIC - 我的漫画">
</head><body><div x-data='{ chapters: [], decending: true }'></div></body></html>
''';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/sources/mycomic_test.dart`
Expected: 6 个新 test FAIL，报 `UnimplementedError: parseMangaInfo`

- [ ] **Step 3: 写最小实现**

在 `lib/data/sources/mycomic.dart` 中取消 `import 'dart:convert';` 的注释，并把 `parseMangaInfo` 占位替换为：

```dart
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

  /// 从**原始响应字符串**（不经 DOM，避免 HTML 实体解码干扰）提取 Alpine
  /// `x-data` 里内嵌的章节数组。实测该数组在整页中恰好出现一次，且长篇
  /// （262 话）也一次性全部内嵌，故无需分页。
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

  /// 引号/转义感知的括号深度扫描。
  ///
  /// **不要改回正则。** `chapters:\s*(\[.*?\])` 在章节标题含 `]`（卷名、括注
  /// 很常见）时会静默截断成非法 JSON。
  String _sliceChaptersJson(String htmlStr) {
    final marker = htmlStr.indexOf('chapters:');
    if (marker < 0) {
      throw Exception('MyComic: 详情页未找到内嵌章节数据（chapters:），站点结构可能已变更');
    }
    final start = htmlStr.indexOf('[', marker);
    if (start < 0) {
      throw Exception('MyComic: chapters: 之后未找到 JSON 数组起始符');
    }

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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/sources/mycomic_test.dart`
Expected: PASS（18 个 test 全绿）

Run: `flutter analyze lib/data/sources/mycomic.dart`
Expected: `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add lib/data/sources/mycomic.dart test/data/sources/mycomic_test.dart
git commit -m "feat: mycomic 详情解析，OG meta 取简介并用括号扫描提取内嵌章节 JSON"
```

---

### Task 4: 章节图片解析

两个陷阱：前 3 张图用 `src`、其余用 lozad 懒加载的 `data-src`（`src` 是占位 gif）；页面里还混着 `biccam.com/img/flags/*.png` 国旗图标。

**Files:**
- Modify: `lib/data/sources/mycomic.dart`
- Test: `test/data/sources/mycomic_test.dart`

- [ ] **Step 1: 写失败测试**

在 `main()` 内追加：

```dart
  group('MyComic chapter parsing', () {
    test('prefers data-src, keeps order, and drops non-page images', () {
      final result = source.parseChapter(_chapterFixture, '55355', '818144', 1);

      expect(result.canLoadMore, isFalse);
      expect(result.chapter.id, '818144');
      expect(result.chapter.mangaId, '55355');
      expect(result.chapter.title, '第01话');
      expect(result.chapter.images.map((i) => i.url), [
        'https://biccam.com/chapters/818144/1-03ef91.jpg',
        'https://biccam.com/chapters/818144/2-1a2b3c.jpg',
        'https://biccam.com/chapters/818144/3-4d5e6f.jpg',
      ]);
    });

    test('every image carries the CDN Referer and no scrambling', () {
      final result = source.parseChapter(_chapterFixture, '55355', '818144', 1);

      expect(result.chapter.images, isNotEmpty);
      for (final image in result.chapter.images) {
        expect(image.headers?['Referer'], 'https://mycomic.com/');
        expect(image.scrambleType, ScrambleType.none);
      }
      expect(result.chapter.headers?['Referer'], 'https://mycomic.com/');
    });
  });
```

在文件末尾追加夹具：

```dart
/// 阅读器夹具：国旗图标 + 首图仅 src + 两张 lozad 懒加载（data-src 真实、
/// src 为占位）。
const String _chapterFixture = '''
<html><head>
  <meta property="og:title" content="第01话 - 猎人游戏W - MYCOMIC - 我的漫画">
</head><body>
  <img class="flag" src="https://biccam.com/img/flags/cn.png">
  <img class="page w-full mx-auto"
       src="https://biccam.com/chapters/818144/1-03ef91.jpg">
  <img class="page w-full mx-auto lozad"
       src="data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=="
       data-src="https://biccam.com/chapters/818144/2-1a2b3c.jpg">
  <img class="page w-full mx-auto lozad"
       src="https://biccam.com/img/placeholder.gif"
       data-src="https://biccam.com/chapters/818144/3-4d5e6f.jpg">
</body></html>
''';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/sources/mycomic_test.dart`
Expected: 2 个新 test FAIL，报 `UnimplementedError: parseChapter`

- [ ] **Step 3: 写最小实现**

把 `parseChapter` 占位替换为：

```dart
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
      // 排除国旗图标与 base64 占位图。
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/sources/mycomic_test.dart`
Expected: PASS（20 个 test 全绿）

Run: `flutter analyze lib/data/sources/mycomic.dart`
Expected: `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add lib/data/sources/mycomic.dart test/data/sources/mycomic_test.dart
git commit -m "feat: mycomic 章节图片解析，data-src 优先并过滤国旗与占位图"
```

---

### Task 5: 接线、web 端绕过配置与文档更正

本任务无新增测试（注册与 shell 配置不在单测覆盖范围），验证靠 `flutter analyze` 与人工核对。

**Files:**
- Modify: `lib/app/di/injection.dart`（import 区 + 第 207 行后）
- Modify: `tools/run_web.sh`（`CURL_IMPERSONATE_HOSTS` 默认值）
- Modify: `AGENTS.md:122`

- [ ] **Step 1: 注册源**

在 `lib/app/di/injection.dart` 的源导入区加一行（放在第 45 行 `manwaye.dart` 之后，与相邻导入同风格）：

```dart
import 'package:comic_reader/data/sources/mycomic.dart';
```

在 `registry.register(...)` 块的末行（当前第 207 行 `registry.register(Manwaye());`）之后追加：

```dart
  registry.register(MyComic());
```

- [ ] **Step 2: web 端加入 curl-impersonate 名单**

`tools/run_web.sh` 的 `CURL_IMPERSONATE_HOSTS` 默认值，把 `mycomic.com` 追加到末尾。**不要加 `biccam.com`**——CDN 需保持直连快速路径。

改前：
```sh
CURL_IMPERSONATE_HOSTS="${CURL_IMPERSONATE_HOSTS:-manga18.club,api.comick.dev,vymanga.net,weebcentral.com,www.mangago.me}"
```
改后：
```sh
CURL_IMPERSONATE_HOSTS="${CURL_IMPERSONATE_HOSTS:-manga18.club,api.comick.dev,vymanga.net,weebcentral.com,www.mangago.me,mycomic.com}"
```

- [ ] **Step 3: 更正 AGENTS.md 的 extra 注入点**

`AGENTS.md` 第 122 行称注入发生在 `manga_repository_impl.dart` 的 `_mergeHeaders`，实际在 `lib/data/repositories/fetch_pipeline.dart:21-37` 的 `FetchPipeline.mergeHeaders()`（前者 grep 零命中）。把该行中的

```
`_mergeHeaders` in the repository injects `useWebViewFetch`/`cloudflareUrl` into `extra`;
```

替换为

```
`FetchPipeline.mergeHeaders()` (`lib/data/repositories/fetch_pipeline.dart:21-37`) injects `useWebViewFetch`/`cloudflareUrl` into `extra`;
```

- [ ] **Step 4: 验证**

Run:
```bash
flutter analyze lib/data/sources/mycomic.dart lib/app/di/injection.dart
flutter test test/data/sources/mycomic_test.dart
bash -n tools/run_web.sh
rg -n "mycomic" lib/app/di/injection.dart tools/run_web.sh
```
Expected:
- analyze：`No issues found!`
- test：20 个 test 全绿
- `bash -n`：无输出（语法正确）
- rg：命中 3 处（injection 的 import 与 register、run_web.sh 的 hosts 行）

- [ ] **Step 5: 提交**

```bash
git add lib/app/di/injection.dart tools/run_web.sh AGENTS.md
git commit -m "feat: 注册 mycomic 源并把 mycomic.com 加入 web 端 impersonate 名单

顺带更正 AGENTS.md 中 extra 注入点的文件指向（fetch_pipeline.dart）。"
```

---

### Task 6: 联网人工验收（可选，需真实设备/浏览器）

自动化测试全为离线夹具，站点真实行为需人工过一遍。

- [ ] **Step 1: 起 native 应用并核对四条路径**

Run: `flutter run -d macos`（或 `-d <android-device>`）

依次核对：
1. 设置页能看到「我的漫画 / MYC」，且在成人源过滤开启时表现符合预期。
2. 发现页首屏有 30 张封面且**封面能显示**（封面能显示 = `MangaSummary.headers` 的 Referer 生效）。
3. 切换「题材=百合」「状态=已完结」后结果变化，翻到第 2 页仍有数据。
4. 搜索「猎人」有结果；进详情页看到简介（**不是评论区广告文本**）、作者、标签、状态、完整章节列表；进阅读器图片能加载。

- [ ] **Step 2: 记录 Cloudflare 限流表现**

已知风险：实测无延迟连发 5 个详情页请求会触发 403 + `Just a moment...` 挑战页，且会持续一段时间。基类默认 `cloudflarePageTitles` 能识别该页并交由框架处理，但**没有真正的节流手段**（`batchDelay` 已核实是死配置）。单本阅读不受影响；若批量下载出现 403，记录现象但**不在本计划范围内修复**。

- [ ] **Step 3: web 端抽验（需 curl-impersonate）**

前置：`brew install lexiforest/tap/curl-impersonate`

Run: `./tools/run_web.sh`
核对：发现页能出结果（说明 CORS 代理对 `mycomic.com` 走了 impersonate），且封面/章节图片能加载（说明 `biccam.com` 走了直连）。

若本机无 curl-impersonate，跳过本步并在验收说明中注明「web 端未验证」。

---

## 完成判据

- [ ] `flutter test test/data/sources/mycomic_test.dart` 全绿（20 个 test）
- [ ] `flutter analyze lib/data/sources/mycomic.dart lib/app/di/injection.dart` 输出 `No issues found!`
- [ ] spec 的 8 个测试用例逐条有对应 test：#1→Task 2、#2/#3/#4a/#4b→Task 3、#5→Task 3、#6/#8→Task 4、#7→Task 1
- [ ] `registry.register(MyComic())` 已在 `injection.dart`
- [ ] `mycomic.com` 已在 `run_web.sh` 的 `CURL_IMPERSONATE_HOSTS`，`biccam.com` **不在**
- [ ] 运行 `graphify update .` 刷新知识图谱（AGENTS.md 要求，改代码后执行，AST-only 无 API 开销）
