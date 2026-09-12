# 我的漫画（mycomic.com）漫画源设计

## 背景

为 comic-reader 新增漫画源「我的漫画」，站点 `https://mycomic.com/cn`。技术栈为 **Laravel + Alpine.js + Flux UI + Tailwind**，与仓库内已有的 MCCMS 系（`haokan_manhua`、`51manga`）无任何同族关系，需全新实现。

两个决定实现形态的特征：

1. **主站受 Cloudflare TLS/JA3 指纹校验保护。** 普通 `curl` 访问返回 403 + `Attention Required!` WAF 拦截页（非 JS challenge），`server: cloudflare`。这正是 `AGENTS.md`「Cloudflare / TLS Fingerprint Sources」一节描述的场景，解法已有先例（`manga18_club`）。
2. **章节列表由 Alpine.js 客户端渲染，但数据内嵌于服务端 HTML。** DOM 里只有 `<template x-for="chapter in chapters">`，真实章节数组以 JSON 形式写在祖先 `div` 的 `x-data` 属性中。因此无需执行 JS，但也无法靠解析 `<a>` 标签取章节。

## 目标与范围

- 实现标准 `MangaSource` 子类，覆盖发现、搜索、详情、章节列表、章节图片五组契约。
- 遵循「源是纯函数」惯例：`prepare*` 只造 `FetchConfig`，`parse*` 只做纯解析，不产生额外网络请求，**不改动框架代码**。
- 在 `tools/run_web.sh` 的 curl-impersonate 名单中加入主站主机名，使 web 平台可用。
- 新增离线单元测试覆盖四个非显然的解析陷阱。

非目标：不引入新依赖（`html` 已在 `pubspec.yaml`，`dart:convert` 为 SDK 自带）；不实现登录（站点匿名可读全站）；不做题材 slug 动态抓取（硬编码实测到的 38 个）；不暴露受众 `filter[audience]` 与年份 `filter[year]` 两组筛选。

## 侦察结论（已实测验证）

侦察通过真实 Chrome（`--remote-debugging-port=9222`）+ chrome-devtools MCP 完成，因为本机未安装 curl-impersonate 且裸 curl 被 WAF 拦截。

### URL 方案

locale `cn` 是**路径段**而非查询参数：

| 功能 | URL |
|---|---|
| 发现 / 资料库 | `/cn/comics?page=N` |
| 搜索 | `/cn/comics?q=<关键词>&page=N` |
| 详情 | `/cn/comics/<comicId>` |
| 章节 | `/cn/chapters/<chapterId>` |

- **搜索与发现复用同一端点。** 页面上两个 form 的 `action` 均为 `/cn/comics`，`method=get`，唯一输入框 `name="q"`。
- `comicId` / `chapterId` 均为**纯数字**，不含斜杠，对 `routes.dart` 的 `Uri.encodeComponent` 路由天然安全。无需 `manga18_club` 那套 `_toPath`/`_absUrl` 路径编码工具。
- `chapterId` 独立于 `comicId`，拼章节 URL 只需 `chapterId`。
- 发现页每页 **30 条**，总页数上千（实测 `page=1845` 仍有数据）。

### 筛选参数词汇表

| 组 | 参数名 | 取值 |
|---|---|---|
| 排序 | `sort` | `-update`（最近更新）、`-views`（最高人气） |
| 连载状态 | `filter[end]` | `0`（连载中）、`1`（已完结） |
| 地区 | `filter[country]` | `japan` `china` `hongkong` `korea` `europe` `other` |
| 题材 | `filter[tag]` | 38 个拼音 slug（见下） |
| 受众（不暴露） | `filter[audience]` | `shaonv` `shaonian` `qingnian` `ertong` `tongyong` |
| 年份（不暴露） | `filter[year]` | `2018`–`2026` |
| 作者（不暴露） | `filter[author]` | URL 编码的作者名 |

题材 slug 全集（38）：`mohuan` `mofa` `rexue` `maoxian` `xuanyi` `zhentan` `aiqing` `xiaoyuan` `gaoxiao` `sige` `kehuan` `shengui` `wudao` `yinyue` `baihe` `hougong` `jizhan` `gedou` `kongbu` `mengxi` `wuxia` `shehui` `lishi` `danmei` `lizhi` `zhichang` `shenghuo` `zhiyu` `weiniang` `heidao` `zhanzheng` `jingji` `tiyu` `meishi` `funv` `zhainan` `tuili` `zazhi`

参数名含方括号，URL 中实际为 `filter%5Btag%5D` 形式。已验证 `queryParameters` 在 WebView-fetch 路径上同样生效（`http_client.dart:140-156` 的 `_resolveUrl()` 用 `queryParametersAll` 合并后 `uri.replace`），因此可放心交给框架编码。

### 选择器策略：不依赖 Tailwind 工具类

站点用 Tailwind，类名冗长且随构建易变（如 `div.grid.grid-cols-3.md:grid-cols-6...`）。设计一律改用**结构不变量、meta 标签、内嵌 JSON**。

### 列表卡片

```html
<div class="group relative"><a href="https://mycomic.com/cn/comics/55355">
  <img src="https://biccam.com/comics/55355-9e7018.jpg" alt="猎人游戏W">
  <div class="...gradient...">第07话</div>
</a><div class="mt-2 text-center"><div data-flux-subheading>猎人游戏W</div></div></div>
```

**陷阱：导航栏的「随机漫画」链接也匹配 `/comics/\d+`**（`:href="comicUrl({id: Math.floor(Math.random()*maxComicId)})"`）。若不过滤会多出一条脏数据。

标题优先取 `img` 的 `alt`（与 `data-flux-subheading` 内容相同但更稳）。

### 详情页

**页面无 `<h1>`。** 最稳的元数据来源是 OG meta 标签：

| 字段 | 来源 |
|---|---|
| 标题 | `og:title`，需剥离 ` - MYCOMIC - 我的漫画` 后缀 |
| 简介 | `og:description` |
| 封面 | `og:image` |
| 状态 | 叶子元素文本 `连载中` / `已完结` |
| 作者 | `a[href*="filter%5Bauthor%5D"]` 的文本 |
| 标签 | `a[href*="filter%5Btag%5D"]` 的文本 |

**严重陷阱：页面内「最长文本块」全是评论区的色情/外送茶广告垃圾**（多条 200–1300 字）。绝不能用最长文本启发式取简介，必须用 `og:description`。

`<body>` 的 `x-data` 中另有全局常量 `cdnUrl: 'https://biccam.com'`、`maxComicId: 55355`、`locale: 'cn'`。

### 章节数据（内嵌 JSON）

服务端原始 HTML 中的形式（**单引号包裹的属性**，故 JSON 内的 `"` 可字面出现）：

```html
<div x-data='{
  chapters: [{"id":818150,"title":"\u7b2c07\u8bdd"},{"id":818149,...}],
  decending: true,
  toggleSorting() {...}
```

实测结论：

- `chapters:` 在整页中**恰好出现 1 次**（7 话 / 32 话 / 262 话 / 6 卷四部作品均为 1 次）。
- **无多分组**（不存在单行本/番外分开的情况），**无章节分页**，262 话长篇也一次性全量内嵌。
- 数组元素 key **恰好只有 `["id","title"]`**，`id` 为 int，`title` 为 unicode 转义中文。
- 排序为 **newest-first**（首元素 `{id:818150,title:"第07话"}`，末元素 `{id:818144,title:"第01话"}`）。

页面上有 68 个 `a[href*="/chapters/"]`，大部分是「开始阅读」按钮和推荐位噪声，**不可用于取章节列表**。

### 阅读器页

- 图片元素 `img.page`（完整 class `page w-full mx-auto`；懒加载的额外带 `lozad`）。
- **前 3 张只有 `src`，其余在 `data-src`**（lozad 懒加载，`src` 是占位图）。
- URL 格式 `https://biccam.com/chapters/<chapterId>/<页码>-<hash>.jpg`，页码从 1 递增，hash 每图不同且不可预测（故无法合成 URL，必须解析页面）。
- **无扰码**，普通 jpg。
- 页内 39 个 `img` 中混有国旗图标 `biccam.com/img/flags/*.png`，靠 `.page` class 与 URL 含 `/chapters/` 双重过滤。

### 图片 CDN 防盗链

对 `https://biccam.com/chapters/818144/1-03ef91.jpg` 实测：

| 请求头 | 结果 |
|---|---|
| 无 | 403（响应体 3 字节） |
| 仅 `User-Agent` | 403 |
| 仅 `Referer: https://mycomic.com/` | **200，208517 字节** |
| `Referer` + `UA` | 200 |

**CDN 只需 `Referer`**，不需要 UA 或 cookie；且 **CDN 不受 Cloudflare 指纹校验**（裸 curl 即可 200）。封面同理。

### Cloudflare 限流行为

无延迟连发 5 个详情页请求后，后续请求返回 403 + `<title>Just a moment...</title>`（~6.1 KB JS challenge 页），触发后持续一段时间（1.2 s 间隔仍被拦，4–5 s 间隔部分恢复）。正常详情页为 200、~280–320 KB。

基类默认 `cloudflarePageTitles = ['Just a moment...']` 正好匹配此挑战页，**无需 override**。

> **注意：`batchDelay` 无法用于缓解限流。** `rg batchDelay` 全仓仅命中基类定义（`manga_source.dart:48`）与两份文档，**`lib/` 内无任何消费方**，override 它不产生任何效果。本设计不使用它。

## 设计

### 平台配置与 Cloudflare 绕过

新文件 `lib/data/sources/mycomic.dart`：

```dart
class MyComic extends MangaSource {
  static const String sourceId = 'mycomic';
  static const String _baseUrl = 'https://mycomic.com';
  static const String _locale = 'cn';
  static const String _ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  @override String get id => sourceId;
  @override String get name => '我的漫画';
  @override String get shortName => 'MYC';
  @override double get score => 4.0;
  @override String? get href => _baseUrl;
  @override bool get isAdult => true;

  @override bool get needsCloudflare => true;
  @override bool get usesWebViewFetch => true;
  @override String? get cloudflareUrl => '$_baseUrl/$_locale';
  @override String? get userAgent => _ua;
  @override Map<String, String>? get defaultHeaders =>
      {'User-Agent': _ua, 'Referer': '$_baseUrl/'};
}
```

`isAdult => true`：站点整体是通用漫画站，但人气榜前列混有明确的成人作品，保守起见标记。

双平台绕过分工：

- **native**：`usesWebViewFetch => true` 使 `FetchPipeline.mergeHeaders()`（`fetch_pipeline.dart:21-37`）注入 `extra['useWebViewFetch']` 与 `extra['cloudflareUrl']`，`HttpClient` 转由常驻 headless `flutter_inappwebview` 的 page-context `fetch()` 发请求，复用真实 WebKit TLS 指纹。
- **web**：`tools/run_web.sh:17` 的 `CURL_IMPERSONATE_HOSTS` 默认值追加 `mycomic.com`，令 CORS 代理对该主机改用 curl-impersonate。

**不设 `extra['renderMode']`。** 该开关（`http_client.dart:84`）会让 WebView 以顶层文档加载并返回**渲染后** HTML，而本源的章节 JSON 只存在于**服务端原始 HTML** 的 `x-data` 属性中——渲染后 DOM 里只剩 Alpine 展开的 `<template>`。默认的 in-page fetch 拿到的才是原始 HTML，正是所需。

### CDN 直连（无需框架改动）

`FetchPipeline.mergeHeaders()` 是无条件注入的，**没有按主机名的网关**，所以 `AGENTS.md` 所述「把 CDN 子域排除在 WebView-fetch 路径外」在配置层面并不存在开关。但这不构成问题：

`chapter_image_pipeline.dart:101-106` 明确说明**章节图片由阅读器的 `ExtendedImage` 加载，而非 `HttpClient`**（走 in-page fetch 反而会因 CDN 无 CORS 头而失败）；封面同理由 `manga_cover_image.dart` 加载。因此图片请求根本不经过注入路径，CDN 直连自动成立。

**唯一前提**：必须把 `Referer` 写进 `ChapterImage.headers`、`MangaSummary.headers`、`MangaDetail.headers`，否则 CDN 返回 403。

附带效果：图片 CF 预检 `preflightImageCf()` 在 `chapter_image_pipeline.dart:107-108` 被 `!source.usesWebViewFetch` 守卫，本源会跳过预检——正是期望行为。

### 发现与搜索

两者共用端点 `$_baseUrl/$_locale/comics`，差异仅在参数：

```dart
prepareDiscoveryFetch(page, filters) →
  url: '$_baseUrl/$_locale/comics'
  queryParameters: {'page': page, ...非空筛选项}

prepareSearchFetch(keyword, page, filters) →
  url: '$_baseUrl/$_locale/comics'
  queryParameters: {'q': keyword, 'page': page}
```

`FilterOption.name` **直接用站点真实参数名**（`sort`、`filter[tag]`、`filter[country]`、`filter[end]`），使 `prepareDiscoveryFetch` 只需「跳过空值后原样透传」，无需维护映射表。空 `defaultValue` 代表「全部」，构造 `queryParameters` 时必须跳过空值。

`discoveryFilters` 四组：

| name | label | choices |
|---|---|---|
| `sort` | 排序 | 最近更新 `-update`（默认）、最高人气 `-views` |
| `filter[tag]` | 题材 | 全部 `` + 38 个 slug |
| `filter[country]` | 地区 | 全部 `` / 日本 `japan` / 大陆 `china` / 港台 `hongkong` / 韩国 `korea` / 欧美 `europe` / 其他 `other` |
| `filter[end]` | 状态 | 全部 `` / 连载中 `0` / 已完结 `1` |

`searchFilters` 留空（`const []`）。

题材 38 项的 `value → label` 映射（实现时以站点筛选 UI 文本为准逐一核对；下表为基准清单）：

| value | label | value | label | value | label |
|---|---|---|---|---|---|
| `mohuan` | 魔幻 | `wudao` | 舞蹈 | `lishi` | 历史 |
| `mofa` | 魔法 | `yinyue` | 音乐 | `danmei` | 耽美 |
| `rexue` | 热血 | `baihe` | 百合 | `lizhi` | 励志 |
| `maoxian` | 冒险 | `hougong` | 后宫 | `zhichang` | 职场 |
| `xuanyi` | 悬疑 | `jizhan` | 机战 | `shenghuo` | 生活 |
| `zhentan` | 侦探 | `gedou` | 格斗 | `zhiyu` | 治愈 |
| `aiqing` | 爱情 | `kongbu` | 恐怖 | `weiniang` | 伪娘 |
| `xiaoyuan` | 校园 | `mengxi` | 萌系 | `heidao` | 黑道 |
| `gaoxiao` | 搞笑 | `wuxia` | 武侠 | `zhanzheng` | 战争 |
| `sige` | 四格 | `shehui` | 社会 | `jingji` | 竞技 |
| `kehuan` | 科幻 | `tiyu` | 体育 | `meishi` | 美食 |
| `shengui` | 神鬼 | `funv` | 腐女 | `zhainan` | 宅男 |
| `tuili` | 推理 | `zazhi` | 杂志 | | |


### 列表解析 `_parseList(String html) → List<MangaSummary>`

`parseDiscovery` 与 `parseSearch` 均委派至此。

判定规则（结构不变量，非 Tailwind 类）——遍历 `a[href]`，同时满足：

1. `href` 匹配 `/comics/(\d+)`
2. 该 `<a>` 内含 `<img>` 且其 `alt` 非空

「随机漫画」导航链接用 Alpine `:href` 绑定且不包 `img`，被条件 2 自然滤除。这比赌 `div.group.relative` 类名稳。结果按 comic id 去重并保持文档顺序。

| 字段 | 取法 |
|---|---|
| `id` | 正则捕获的数字 |
| `title` | `img` 的 `alt` |
| `coverUrl` | `img` 的 `data-src ?? src` |
| `latestChapter` | 见下方确定性规则，取不到为 `null` |
| `headers` | `{'Referer': '$_baseUrl/'}` |

`latestChapter` 的确定性规则（消除「尽力取」的歧义）：在该 `<a>` 内取所有**叶子 `div`**（无子元素节点的 div），选第一个满足「`text.trim()` 非空、且不等于 `title`、且长度 ≤ 20」者；无匹配则为 `null`。长度上限用于排除简介类长文本。

### 详情解析 `parseMangaInfo`

按上文「详情页」表格取 OG meta 与筛选链接文本。作者/标签选择器同时容错百分号编码与未编码两种形式（`filter%5Bauthor%5D` 与 `filter[author]`）。

`prepareChapterListFetch` 返回 `null`，`parseChapterList` 返回 `const ChapterListResult(chapters: [])`——章节已随详情页一并取得。

章节顺序处理（框架惯例）：站点为 newest-first，故

- `latestChapter` = 反转**前**的首个章节标题
- `MangaDetail.chapters` = 反转**后**的 oldest-first 列表（供阅读器顺序播放）

`MangaDetail.headers` 同样带 `Referer` 以便封面加载。

### 章节 JSON 提取 `_extractChapters`

在**原始响应字符串**上操作，不经 DOM（避免 HTML 实体解码干扰）。

**不使用正则。** `chapters:\s*(\[.*?\])` 这类写法在章节标题含 `]`（卷名、括注很常见）时会静默截断。改用引号/转义感知的括号深度扫描：

```
idx   = html.indexOf('chapters:')          // 找不到 → 抛 Exception
start = html.indexOf('[', idx)             // 找不到 → 抛 Exception
逐字符扫描，维护 depth / inString / escaped：
  escaped        → 清标志，跳过
  '\'            → 置 escaped
  inString       → 仅 '"' 可退出字符串态；括号一律忽略
  '"'            → 进入字符串态
  '[' → depth++ ; ']' → depth-- ，归零即为匹配尾
未找到匹配尾 → 抛 Exception
jsonDecode(html.substring(start, end + 1)) as List
```

`\u7b2c` 这类 unicode 转义由 `jsonDecode` 原生处理，无需手工解码。

每个元素映射为：

```dart
ChapterItem(
  id: '${e['id']}',
  mangaId: mangaId,
  title: e['title'] as String,
  href: '$_baseUrl/$_locale/chapters/${e['id']}',
)
```

失败策略：**找不到 `chapters:` → 抛带源名的 `Exception`**（属于站点改版，应显式暴露）；**找到但数组为空 → 合法返回空列表**（可能是尚未上架的作品）。

### 章节图片 `prepareChapterFetch` / `parseChapter`

请求 `$_baseUrl/$_locale/chapters/$chapterId`，显式 `timeout: const Duration(seconds: 60)`（与 `manga18_club` 一致）。

解析 `img.page`，每张取 **`data-src` 优先、回退 `src`**，并要求 URL 含 `/chapters/` 以排除国旗图标与占位图。每张：

```dart
ChapterImage(
  url: url,
  headers: {'Referer': '$_baseUrl/'},   // CDN 放行的唯一条件
)
```

`scrambleType` 用默认 `ScrambleType.none`（无扰码）。章节标题取 `og:title` 剥后缀，缺失时回退空串。`ChapterResult.canLoadMore: false`（无章节内分页）。

### 接线

- `lib/app/di/injection.dart`：`import` + 在 `registry.register(...)` 块中加 `registry.register(MyComic())`。
- `tools/run_web.sh:17`：`CURL_IMPERSONATE_HOSTS` 默认值追加 `mycomic.com`。**`biccam.com` 不加**——CDN 需保持直连快速路径。

### 文档更正（附带）

`AGENTS.md` 称 extra 注入在 `manga_repository_impl.dart`，实际在 `lib/data/repositories/fetch_pipeline.dart:21-37`（前者 grep 零命中）。顺手改正这一处指向。

## 测试

新增 `test/data/sources/mycomic_test.dart`，纯离线 HTML 夹具、无网络，全部经**公开方法**验证（`parseDiscovery` / `parseSearch` / `parseMangaInfo` / `parseChapter` / `prepareDiscoveryFetch`）：

| # | 用例 | 断言 |
|---|---|---|
| 1 | 列表：2 张真卡片 + 1 个无 `img` 的随机漫画锚点 | 恰好 2 条；id/标题/封面正确 |
| 2 | 章节 JSON 正常用例 | id、标题、顺序（newest-first→oldest-first 反转）正确 |
| 3 | 章节 JSON 标题含 `]` 与转义引号 | **不被截断**（方案「正则」在此失效） |
| 4a | 缺 `chapters:` | 抛 `Exception` |
| 4b | `chapters: []` | 返回空列表，不抛错 |
| 5 | 详情夹具含一段 500 字评论区垃圾文本 | `description` 等于 `og:description` |
| 6 | 章节图片：首图仅 `src`、后续 `data-src` + 占位 `src`、混入国旗 `img` | 取值正确、顺序保持、国旗被过滤 |
| 7 | 筛选：空值与设值两种情形 | 空值被跳过；设值时 `filter[tag]` 出现在 `queryParameters` |
| 8 | 章节图片 headers | 每张 `ChapterImage.headers` 含 `Referer` |

验证命令：`flutter test test/data/sources/mycomic_test.dart` 与 `flutter analyze lib/data/sources/mycomic.dart`。

> 不跑全仓 `flutter test`：`AGENTS.md` 记载 `test/verify_*.dart` 是手动联网脚本、`test/widget_test.dart` 现状即失败，全仓跑无法作为通过判据。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| Cloudflare 对连续请求限流（实测 5 连发即触发） | 基类默认 `cloudflarePageTitles` 已能识别挑战页并交由框架处理；`batchDelay` 证实无效故不采用；批量场景（如下载）若出现 403 需后续单独处理 |
| Tailwind 类名随构建变化 | 选择器一律基于结构不变量、OG meta、内嵌 JSON |
| 站点改版移除 `x-data` 内嵌章节 | `_extractChapters` 显式抛错而非静默返回空，便于定位 |
| web 平台需 curl-impersonate 二进制 | `brew install lexiforest/tap/curl-impersonate`；native 平台不受影响 |
| 题材中文 label 若照抄有误 | 实现时从站点筛选 UI 逐一核对，不靠拼音反推 |
