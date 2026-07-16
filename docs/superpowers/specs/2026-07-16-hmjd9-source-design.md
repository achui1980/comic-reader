# hmjd9.com 数据源设计

日期：2026-07-16
状态：已批准

## 概述

为 comic-reader 新增数据源 `hmjd9.com`（站名「韓漫基地」），一个基于 maccms（苹果CMS）的成人韩漫站，繁体中文。标记为成人源（`isAdult = true`）。

## 站点事实

- baseUrl：`https://hmjd9.com`
- 图片 CDN：`jmpic.xyz`（封面 `last.jmpic.xyz` webp，内页 `p4.jmpic.xyz` jpg）
- 无 Cloudflare、无 JS 加密、无独立图片接口，图片全部内联 HTML
- 图片/封面用 `data-original` 懒加载属性（非 src）
- 图片 CDN 可能有防盗链，需 Referer header

## 元数据

| 字段 | 值 |
|---|---|
| id | `hmjd9` |
| name | `韓漫基地` |
| shortName | `HM` |
| score | `3.5` |
| href | `https://hmjd9.com` |
| isAdult | `true` |

无需 needsProxy / needsCloudflare / usesWebViewFetch。

## 方法实现

### 发现 Discovery
- `prepareDiscoveryFetch(page, filters)` → `FetchConfig(url: '$_baseUrl/manhua/all/ob/time/st/all/page/$page')`
- `parseDiscovery` → 复用 `_parseList`
- 不实现 discoveryFilters（基础发现即可）

### 搜索 Search
- `prepareSearchFetch(keyword, page, filters)` → `FetchConfig(url: '$_baseUrl/search/${Uri.encodeComponent(keyword)}.html')`
- `parseSearch` → 复用 `_parseList`

### 列表解析 `_parseList`（发现+搜索共用）
- `querySelectorAll('.hl-list-item')` 遍历
- mangaId：`a[href]` 正则 `/manhua-(\d+)\.html`
- title：`.hl-item-title a` 的 title 属性或文本
- coverUrl：`a.hl-item-thumb` 的 `data-original`
- latestChapter：`.hl-item-sub` 文本
- 每项 `headers: {'Referer': _baseUrl}`

### 详情 Manga Info
- `prepareMangaInfoFetch(mangaId)` → `FetchConfig(url: '$_baseUrl/manhua-$mangaId.html')`
- `parseMangaInfo(resp, mangaId)` → `MangaDetail`：
  - title：`h1.hl-dc-title` 文本
  - coverUrl：`.hl-dc-pic img` 的 data-original/src
  - description / tags：尽力解析
  - status：默认 `MangaStatus.unknown`
  - chapters：遍历 `#hl-plays-list li a`，反转为正序；每项 `ChapterItem(id: hash, mangaId, title, href)`；hash 从 `/manhua-{id}/{hash}.html` 正则提取

### 章节列表 Chapter List
- `prepareChapterListFetch` → 返回 `null`（章节内嵌详情页）
- `parseChapterList` → 空实现

### 章节内容 Chapter Content
- `prepareChapterFetch(mangaId, chapterId, page, {extra})` → `FetchConfig(url: '$_baseUrl/manhua-$mangaId/$chapterId.html', headers: {'Referer': '$_baseUrl/manhua-$mangaId.html'})`
- `parseChapter` → `ChapterResult`：
  - 阅读区 `img[data-original]` 取 data-original
  - 每张 `ChapterImage(url, scrambleType: none, headers: {'Referer': _baseUrl})`
  - `canLoadMore = false`

### 辅助
- `_ensureAbsoluteUrl`：http 开头直接返回；// 开头加 https:；否则加 baseUrl

## 章节 ID 格式

只存 hash（16 位字母数字，如 `zpLkjMunX2DSP2pX`）。prepareChapterFetch 重新拼 `/manhua-{mangaId}/{hash}.html`。

## 注册

`lib/app/di/injection.dart`：
- 顶部 `import '../../data/sources/hmjd9.dart';`
- register 块加 `registry.register(Hmjd9());`

## 验证

`flutter analyze lib/data/sources/hmjd9.dart`
