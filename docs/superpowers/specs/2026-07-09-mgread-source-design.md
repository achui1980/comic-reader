# mgread.io 数据源设计

日期: 2026-07-09
项目: comic-reader

## 1. 概述

为 comic-reader 增加 mgread.io 数据源。mgread.io 是一个英文漫画聚合站
(manga / manhwa / manhua)，基于 WordPress + 自定义主题 `init-manga`。

采用纯 HTML 解析方案（不使用站点自定义 REST API，因其 search 接口需要未知
参数、返回空）。使用 `package:html` 的 `html_parser` 解析（与
`baozi_manga.dart` 一致）。

## 2. 基本信息

| 字段 | 值 |
|------|-----|
| `id` | `mgread` |
| `name` | `MgRead` |
| `shortName` | `MGR` |
| `description` | `English manga/manhwa/manhua` |
| `score` | `4.0` |
| `href` | `https://mgread.io` |
| `isAdult` | `false` |
| `needsCloudflare` | `false` |

- User-Agent 使用桌面 Chrome UA。
- `defaultHeaders` 带 `Referer: https://mgread.io/`。

## 3. URL 结构

- 首页 / 发现: `https://mgread.io/`
- 详情: `https://mgread.io/manga/{slug}/`  (mangaId = slug)
- 章节: `https://mgread.io/manga/{slug}/chapter-{N}/`  (chapterId = `chapter-{N}`)
- 搜索: `https://mgread.io/?s={keyword}&post_type=wp-manga`
- 图片直链: `https://mg.mgread.io/{postId}/{chapterNum}/{imgNum}.jpg`

## 4. 各功能 prepare/parse 实现

### Discovery（首页发现）
- `prepareDiscoveryFetch(page, filters)` → `GET https://mgread.io/`
  （第一版只做首页，分页后续扩展）
- `parseDiscovery` → 解析首页漫画卡片，提取 `/manga/{slug}/` 链接 → id=slug，
  img → cover，alt/heading → title。按 slug 去重。
- `discoveryFilters` 第一版留空。

### Search（搜索）
- `prepareSearchFetch(keyword, page, filters)` →
  `GET https://mgread.io/?s={keyword}&post_type=wp-manga`
- `parseSearch` → 解析 `<article uk-grid>` 卡片，提取 slug/title/cover，
  按 slug 去重。

### MangaInfo（详情）
- `prepareMangaInfoFetch(mangaId)` → `GET https://mgread.io/manga/{slug}/`
- `parseMangaInfo`:
  - 优先解析页面里的 JSON-LD（`<script type="application/ld+json">`，
    `@type` 含 `ComicSeries` / `CreativeWorkSeries`）：取 name、description、
    image.url(cover)、genre(tags)。
  - 回退：`<h1>` 取标题；`#manga-description p` 取简介；封面 img。
  - description 含 HTML 实体（`&#8217;` `&hellip;` 等），需 unescape。
  - 章节列表内嵌详情页，同时解析（见下）。

### 章节列表（内嵌详情页）
- `prepareChapterListFetch` → **返回 null**（章节内嵌）
- `parseChapterList` → 返回空
- 章节从详情页 `parseMangaInfo` 内解析：
  - 容器 `div.chapter-list`，每项 `div.chapter-item`
  - `<a href=.../chapter-{N}/>` → chapterId = `chapter-{N}`
  - `h3` → title
  - `time[datetime]` → updateTime
  - 页面章节为最新在前，需反转为正序。
  - 仅取 `div.chapter-item` 内锚点，避免详情页 "Read" 按钮造成重复。

### Chapter（章节内容 / 图片）
- `prepareChapterFetch(mangaId, chapterId, page)` →
  `GET https://mgread.io/manga/{mangaId}/{chapterId}/`
- `parseChapter`:
  - 解析 `#chapter-content` 内的 `<img>`。
  - 图片是 `https://mg.mgread.io/{postId}/{chapterNum}/{N}.jpg` 直链，无混淆。
  - 每个 `ChapterImage` 带 `Referer: https://mgread.io/` 头以防盗链。
  - 单页返回全部图片，`canLoadMore = false`。

## 5. 关键技术点

- **postId 依赖已规避**：章节图片 host 是 `mg.mgread.io/{postId}/...`，
  postId 只在 HTML 中出现；但章节页 HTML 本身已含完整 `<img src>` 直链，
  故 `parseChapter` 直接从章节页 HTML 提取图片即可，无需预先知道 postId。
- **属性无引号**：站点部分 HTML 属性不带引号，但 `html_parser.parse()` 能
  正常处理，优先用 CSS selector；个别补正则处用 `(?:"|)?` 容错。
- **无 Cloudflare**：主站与图片 CDN 均直接 200，无需 WebView-fetch /
  curl-impersonate。

## 6. 注册与验证

1. 新建 `lib/data/sources/mgread.dart` 继承 `MangaSource`。
2. 在 `lib/app/di/injection.dart` 通过 `registry.register(MgRead())` 注册。
3. `flutter analyze lib/data/sources/mgread.dart` 验证。
4. 参照 `test/data/sources/copy_manga_test.dart` 补充单测（可选，使用离线
   HTML 夹具）。

## 7. 范围（YAGNI）

第一版只覆盖：首页发现（单页）、搜索、详情+内嵌章节列表、章节图片。
不做：发现页筛选器、发现页分页、登录/收藏、REST API。
