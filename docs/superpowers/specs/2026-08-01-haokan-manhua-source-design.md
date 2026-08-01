# 好看漫画（haokantxt.com）漫画源设计

## 背景

为 comic-reader 新增漫画源「好看漫画」，站点 `https://www.haokantxt.com/`。尽管域名带 `txt`，实测为图片型漫画站，底层是开源 PHP CMS **MCCMS 漫画系统**（响应头 `x-generator: Mccms comic`，模板 `/template/pc/zizhi001/`）。全站服务端渲染 HTML，编码 UTF-8，无 GBK 问题。

## 目标与范围

- 实现标准 `MangaSource` 子类，覆盖发现、搜索、详情、章节列表、章节图片五组契约。
- 零框架改动：遵循「源是纯函数」惯例，网络/cookie/CF/分页全交框架。
- 与现有 31 个源同构，参照 `manhuagui_mobile.dart`（HTML 解析）与 `mmero.dart`（防御性写法）。

非目标：不引入 charset_converter（无 GBK 需要）；不做框架级防盗链（用 `ChapterImage.headers` 即可）；不做分类 tag 动态抓取（硬编码 8 个常用）。

## 关键决策

| # | 决策点 | 取值 | 理由 |
|---|--------|------|------|
| 1 | 发现页数据源 | 纯 `/category` + 筛选器 | 唯一可无限翻页，行为与其余源一致（`/custom/*` 榜单固定 30 条不可翻页） |
| 2 | mangaId 传递 | Summary.id=slug；ChapterItem.mangaId=数字id | 双 ID 体系靠 entity 天然携带，无需组合串 |
| 3 | 详情页解析 | 优先 ld+json，DOM 兜底 | JSON 比 DOM 稳，换模板不易崩 |
| 4 | 图片防盗链 | 每张图注入 `Referer: https://www.haokantxt.com/` | 唯一硬坑，CDN 缺 Referer 返回 200+html 验证码页 |
| 5 | 18+ / 代理 | 都不 | 国内免费直连，实测无墙 |
| 6 | 方案选型 | 方案 A（标准 HTML 源） | 工作量最小、风险最低、零框架改动 |

## 架构

### 文件与注册

- 新建 `lib/data/sources/haokan_manhua.dart`，类 `HaokanManhua`，id `haokan`。
- `lib/app/di/injection.dart` register 块追加一行 `registry.register(HaokanManhua())`。
- 新建单测 `test/data/sources/haokan_manhua_test.dart`（照 mmero 惯例，零网络）。

### 元数据 getter

```
id='haokan'  name='好看漫画'  shortName='HK'  score=3.5
description='国内免费漫画站，MCCMS 系统'  href='https://www.haokantxt.com'
isAdult=false  needsProxy=false  firstPage=1
```

### 请求头

- `defaultHeaders` → `{'Referer': _baseUrl}`（主站页面本身不强制，无害且省心）。
- 图片头单独在 `ChapterImage.headers` 注入 `{'Referer': _baseUrl}`（防盗链关键）。
- UA 不设（实测无校验）。

## 五组 prepare/parse 映射

### ① Discovery（发现/浏览）— 走 `/category`

- `prepareDiscoveryFetch(page, filters)` → GET `{_baseUrl}/category/[tags/{id}]/[finish/{1|2}]/[order/{addtime|hits}]/page/{page}`
  - 路径段顺序固定 tags→finish→order→page；缺省段省略。
  - `discoveryFilters`：3 个 `FilterOption`：
    - `tags`：全部 + 热血6/冒险7/科幻8/霸总9/玄幻10/校园11/修真12/搞笑13（硬编码）
    - `finish`：全部/连载1/完结2
    - `order`：最新addtime/人气hits
- `parseDiscovery(html)` → `List<MangaSummary>`：`div.comic-item`，`a.comic-cover`→href(提取 slug)、`img`→src 封面、`span.update-badge`→状态文本、`h3>a` 或 `a[title]`→标题、`p.comic-author`→作者。列表页无数字 id，`MangaSummary.id` 只存 slug。

### ② Search（搜索）

- `prepareSearchFetch(keyword, page, _)` → GET `{_baseUrl}/search/{Uri.encodeComponent(keyword)}/{page}`（必须路径形式，`?key=` 不支持翻页）。
- `parseSearch(html)` → 同 Discovery 卡片解析（第三种 comic-item 变体，`.comic-list > div.comic-item`）。

### ③ MangaInfo（详情）

- `prepareMangaInfoFetch(slug)` → GET `{_baseUrl}/comic_{slug}.html`
- `parseMangaInfo(html, slug)` → `MangaDetail`：
  - 优先 `<script type="application/ld+json">` 拿 title/author/description/genre/status/评分/最新章节。
  - 数字 id：从 `a[data-id]` 或首章按钮 href 正则 `chapter_(\d+)_` 提取。
  - 章节：`#chapter-list .chapter-item > a`，每条 `ChapterItem(id=chapterId数字, mangaId=数字comicId, title=text, href=完整url)`。
  - 封面：ld+json 的 image 或 `.comic-cover-large img`→src。

### ④ ChapterList（章节列表）

- `prepareChapterListFetch(_, _)` → **return null**（章节内嵌详情页）。
- `parseChapterList(_, _)` → `const ChapterListResult(chapters: [])`。

### ⑤ Chapter（章节图片）

- `prepareChapterFetch(mangaId数字, chapterId, page, {extra})` → GET `{_baseUrl}/chapter_{mangaId}_{chapterId}.html`
- `parseChapter(html, ...)` → `ChapterResult`：`.comic-content img.comic-image`，每张 `ChapterImage(url: src??data-src, headers: {'Referer': _baseUrl})`，`canLoadMore: false`。
- 付费降级：若 images 为空且页面 `.buy-box` 不含 `display:none` → 抛 `Exception('该章节需要付费')`。
- 覆写 `getChapterWebUrl(mangaId, chapterId)` → `{_baseUrl}/chapter_{mangaId}_{chapterId}.html`。

## mangaId 传递链

Summary.id=slug（列表页只有 slug）→ `prepareMangaInfoFetch(slug)` 用 slug 请求详情页 → `parseMangaInfo` 从详情页解析出数字 id → 每个 `ChapterItem.mangaId` 存数字 id → `prepareChapterFetch(mangaId, ...)` 收到数字 id 直接拼章节 URL。无需组合串。

## 私有辅助

- `_baseUrl = 'https://www.haokantxt.com'`
- `_extractSlug(href)` → 正则 `comic_(.+?)\.html`
- `_extractNumericId(html)` → 正则 `chapter_(\d+)_` 或 `data-id="(\d+)"`
- `_parseCard(element)` → 复用于 discovery/search 的卡片解析（处理 comic-item 三变体：`item.matches('a') ? item.href : item.querySelector('a').href`；标题统一 `.comic-title` textContent 或 `h3>a`）
- `_map`/`_list` → 防御性 JSON 取值（照 mmero 惯例）
- ld+json 解析 → `document.querySelector('script[type="application/ld+json"]')` → `json.decode`，try-catch，失败回退 DOM

## 边界处理（防御性，不抛异常）

- 卡片缺字段 → 该字段给默认值（author=''、status=unknown），不跳过整条。
- 详情页无 ld+json → 全走 DOM 兜底。
- 数字 id 提取失败 → 章节 mangaId 回退用 slug（至少详情页可看）。
- 章节无图片 + 无付费标记 → 返回空 images（不抛）。

## 测试用例清单

文件 `test/data/sources/haokan_manhua_test.dart`，两个 group，零网络零 mock。

group 1 `HaokanManhua metadata and request builders`：
- id/name/shortName/score/isAdult 断言。
- discoveryFilters 有 tags/finish/order 三项。
- `prepareDiscoveryFetch(2, {tags:'6',finish:'2',order:'hits'})` → URL 含 `/category/tags/6/finish/2/order/hits/page/2`。
- `prepareDiscoveryFetch(1, {})` → `/category/page/1`。
- `prepareSearchFetch('恋爱', 2, {})` → 路径含 encode 后关键字 + `/2`。
- `prepareMangaInfoFetch('yirenzhixia')` → `/comic_yirenzhixia.html`。
- `prepareChapterListFetch(...)` → isNull。
- `prepareChapterFetch('13871','4992',1)` → `/chapter_13871_4992.html`。
- `getChapterWebUrl('13871','4992')` → 同上。

group 2 `HaokanManhua response parsing`：
- `parseDiscovery` 喂手写卡片 HTML → 校验 slug/title/cover。
- `parseSearch` 同上。
- `parseMangaInfo` 喂含 ld+json 的 HTML → title/author/description/数字id/章节列表。
- `parseMangaInfo` 喂无 ld+json 的 HTML → DOM 兜底仍能出 title。
- `parseChapter` 喂含 3 张 `img.comic-image` 的 HTML → 3 个 url + 每个 headers 含 Referer + canLoadMore=false。
- `parseChapter` 喂 0 图 + `.buy-box`（不含 display:none）→ 抛付费异常。
- `parseChapter` 喂畸形 HTML → 空 images 不抛。

验证命令：`flutter test test/data/sources/haokan_manhua_test.dart`（不跑全仓库，避免联网脚本与已知失败的 widget_test）。

## 风险与缓解

- 图片防盗链静默失败（200+html）→ 全局注入 Referer（已在设计中）。
- `.comic-item` 三套 DOM → `_parseCard` 统一处理。
- 无 JSON API，全靠选择器 → 换模板即崩；ld+json 优先降低详情页脆弱性。
- 付费墙是待激活死代码 → 0 图 + buy-box 可见时显式抛异常。
- tag id 无语义 → 硬编码 8 个常用，站方增删分类会漂移（可接受）。
