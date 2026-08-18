# CopyManga (拷贝漫画) 海外 API 调查与重构计划

## 结论

**CopyManga 有海外线路**：站点 `www.mangacopy.com`、API `api.mangacopy.com`（Cloudflare 前置），与大陆线路（`api.copy-manga.com` → 会轮换）是分开的两套。

当前源码**发现/搜索/信息页已走海外域名，但章节内容仍走大陆的 `api.copy-manga.com` + 老式签名头（version 3.0.6）**，这正是章节坏掉的根因：

- 老版本头（`version: 3.0.0` / `3.0.6`）现在会触发服务器的反破解拦截（HTTP 210，提示"下載過破解版本的拷貝漫畫"）。
- 章节列表走的 AES 接口（`www.mangacopy.com/comicdetail/{id}/chapters`）在海外线路解密出来恒为空（`groups.default.chapters = []`）。

已实测（经本地 7897 代理）：现代 JSON API 在 `api.mangacopy.com` 上**全链路 200 可用**，关键在 `version: 2025.08.15` + `platform:1` 这几个普通头，且无需签名。

## 现代海外 JSON API（已验证可用）

统一头（普通 JSON，无需签名）：

```
User-Agent: COPY/3.0.0
Accept: application/json
version: 2025.08.15
platform: 1
webp: 1
region: 1
```

端点（漫画 path_word 如 `turanchengweigongyuguanliyuan`）：

| 用途 | 端点 |
| --- | --- |
| 信息页 | `GET /api/v3/comic2/{path_word}?platform=1` |
| 章节列表（分页） | `GET /api/v3/comic/{path_word}/group/{group_path_word}/chapters?limit=100&offset=N&platform=1` |
| 章节内容 | `GET /api/v3/comic/{path_word}/chapter2/{uuid}?platform=1` |
| 发现 | `GET /api/v3/comics` |
| 搜索 | `GET /api/v3/search/comic?q=&q_type=&limit=&offset=&platform=1` |

字段映射：

- `comic2`：`results.comic.{name→title, cover→coverUrl, brief→description, author[]→author, theme[]→tags, status{value,display}→MangaStatus, datetime_updated→updateTime, last_chapter{name}→latestChapter}`；`results.groups` = group path_word 映射（如 `{default:{path_word:default,count:51,name:默認}}`）。
- 章节列表：`results.list[]` 每条 `{index, uuid, name, comic_path_word, ...}`，`results.total` 用于分页。
- 章节内容：`results.chapter.{name, contents[{url}], words[]}` —— 与源码现有 `_parseChapterFromApi` 期望的结构一致，无需改动解析逻辑。

## `version` 头是反破解闸门

- `version: 2025.08.15` → 全端点 HTTP 200。
- `version: 3.0.0` / `3.0.6` → chapter2/comic2/group-chapters 端点 HTTP 210（破解版本拦截）。
- 拦截也按 IP：本机直连（被标记 IP）即使带正确头也 210；经 7897 代理 → 200。用户家庭 IP 未被标记（浏览器直连正常）。

## 老端点确认已损坏（当前源码失败原因）

- `www.mangacopy.com/comicdetail/{path}/chapters` AES 接口：解密后 `groups.default.chapters` 恒为空。
- `www.mangacopy.com/comic/{path}` 信息页 HTML 只内嵌一章"開始閱讀"链接，真实章节列表走混淆 JS（`comic_detail_pass202508141558.js`），不值得逆向。
- `api.copy-manga.com`（大陆）已被版本闸门拦截：合法 uuid + `in_mainland=true` + 3.0.6 → 210；非法章节 id → HTTP 500 "服務器升級中" 维护页。

## 重构计划

### 1. `lib/data/sources/copy_manga.dart`

**常量/头**
- `_fetchHeaders` 改为：`version: '2025.08.15'`、`platform: '1'`、`webp:'1'`、`region:'1'`、`accept: application/json`、`User-Agent: COPY/3.0.0`
- 删除 `_appApiUrl`、`_appVersion`、`_appSignatureSecret`、`_appUmString`、`_deviceInfo/_device/_pseudoId/_random`、`_buildAppHeaders()`
- 新增 `_chapterLimit = 100`、实例字段 `_groupPathWord`（默认 `'default'`，在 `parseMangaInfo` 缓存，复用现有 `_mangaKey` 式单例状态模式）

**信息页** `prepareMangaInfoFetch` / `parseMangaInfo`
- URL：`$_apiUrl/comic2/$mangaId?platform=1`（JSON，替代 HTML 抓取）
- 字段映射见上表；从 `results.groups` 选 group path_word（优先 `default`，否则取第一个）→ `_groupPathWord`
- 删除 `_mangaKey` / `_mangaKeyPattern` 提取逻辑

**章节列表** `prepareChapterListFetch` / `parseChapterList`
- URL：`$_apiUrl/comic/$mangaId/group/$_groupPathWord/chapters` + `{platform:1, limit:100, offset:(page-1)*100}`
- 解析：`results.list[]` → `ChapterItem(id: uuid, mangaId: comic_path_word, title: name)`；`canLoadMore` 由 `results.total` 与当前 offset/list 长度决定（`nextPage: page+1`）
- 删除 AES 解密分支

**章节内容** `prepareChapterFetch`
- URL：`$_apiUrl/comic/$mangaId/chapter2/$chapterId` + `{platform:1}`，头用 `_fetchHeaders`（不再签名、不再 `in_mainland`）
- `_parseChapterFromApi` 无需改动

**保留**：`parseChapter` 的 HTML 分支（cct/contentKey）作为兜底、`_imageHeaders`、`getChapterWebUrl`、`needsProxy => true`（仍是徽标，不强制代理）

### 2. `test/data/sources/copy_manga_test.dart`
- 请求构建测试更新为新 URL/头：info → `comic2/{id}?platform=1`、chapterList → `.../group/default/chapters`、chapterFetch → `api.mangacopy.com/.../chapter2/ch-001?platform=1`（去掉 `in_mainland` 与签名头）
- 解析测试：章节列表用 JSON list fixture 替换 AES fixture；信息页用 comic2 JSON 替换 HTML fixture；保留 chapter2 API Map 与 HTML 章节测试
- 保留 `aesDecrypt` roundtrip（`crypto_utils` 仍被 HTML 兜底分支使用）

### 3. 验证
- `flutter analyze lib/data/sources/copy_manga.dart`
- `flutter test test/data/sources/copy_manga_test.dart`
- 经代理实测章节列表/章节内容返回 200 非空

## 已知风险

- 域名会轮换（历史上 mangacopy → copy20 → copy2000.site → 2025copy.com → 2026copy.com）；`api.mangacopy.com` 是当前官方海外域名，但日后可能失效，届时需同步更新 `_apiUrl`。
- `_groupPathWord` / 旧 `_mangaKey` 共享单例状态，并发打开两个漫画详情存在理论竞态（与现状一致，不扩大问题面）。
