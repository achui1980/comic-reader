# Komiic 数据源集成设计

**日期**: 2025-06-26  
**状态**: 草案  
**目标**: 在 comic-reader 中集成 komiic.com 作为新的漫画源插件

---

## 1. 概述

### 1.1 目标网站

- **名称**: Komiic
- **域名**: `https://komiic.com`
- **图片CDN**: `https://public.komiic.com/comics/{hash}/cover.jpg`（封面）、`https://komiic.com/api/image/{kid}`（章节图片）
- **内容**: 日本漫画为主，繁体中文翻译
- **语言**: 繁体中文

### 1.2 技术特点

| 层次 | 特征 | 备注 |
|------|------|------|
| 前端 | Vue.js SPA (Vite) | 纯 SPA，无 SSR |
| 后端 API | **GraphQL** (`POST /api/query`) | 所有数据查询 |
| 反爬 | Cloudflare | 有 challenge platform，但 API 层面无阻拦 |
| 图片认证 | 需要特定 Referer | 格式: `/comic/{id}/chapter/{chapterId}/page/1` |
| 日限额 | 未登录 300 张/天 | 超出返回 HTTP 402 |
| 登录 | JWT token (cookie `komiic-access-token`) | 登录后无限制 |

**结论**: 纯 GraphQL JSON 解析。不需要 HTML 解析。图片需要精确的 Referer header。

---

## 2. 架构设计

### 2.1 新增文件

```
lib/data/sources/komiic.dart    # 主源实现（MangaSource子类，单文件）
```

### 2.2 架构层级

```
Komiic (MangaSource)
  ├── prepareDiscoveryFetch / parseDiscovery   → GraphQL: hotComics / recentUpdate / comicByCategories
  ├── prepareSearchFetch / parseSearch         → GraphQL: searchComicsAndAuthors
  ├── prepareMangaInfoFetch / parseMangaInfo   → GraphQL: comicById (extra 存章节)
  ├── prepareChapterListFetch                  → GraphQL: chaptersByComicId
  ├── parseChapterList                         → 解析章节列表 JSON
  └── prepareChapterFetch / parseChapter       → GraphQL: imagesByChapterId
```

### 2.3 与其他源的区别

与现有源（都是 HTML 解析）不同，Komiic 是第一个 **纯 GraphQL** 源：
- `FetchConfig.method` 全部为 `POST`
- `FetchConfig.body` 为 JSON 字符串（GraphQL query + variables）
- `FetchConfig.headers` 包含 `Content-Type: application/json`
- 响应为 JSON，解析使用 `jsonDecode` 而非 `html_parser`

---

## 3. GraphQL API 详细规格

### 3.1 端点

```
POST https://komiic.com/api/query
Content-Type: application/json
```

### 3.2 通用请求结构

```json
{
  "operationName": "操作名",
  "query": "GraphQL query 字符串",
  "variables": { ... }
}
```

### 3.3 Pagination 结构

```json
{
  "pagination": {
    "offset": 0,       // 起始位置 (0-indexed)
    "limit": 30,       // 每页数量
    "orderBy": "DATE_UPDATED",  // 排序方式
    "status": "",      // 过滤状态: "" / "ONGOING" / "END"
    "asc": false       // 升序/降序
  }
}
```

**OrderBy 可选值**:
- `DATE_UPDATED` — 最近更新
- `MONTH_VIEWS` — 本月观看
- `VIEWS` — 总观看数
- `FAVORITE_COUNT` — 收藏数

### 3.4 具体查询

#### Discovery: hotComics

```graphql
query hotComics($pagination: Pagination!) {
  comics: hotComics(pagination: $pagination) {
    id title status imageUrl
    authors { id name }
    categories { id name }
  }
}
```

#### Discovery: recentUpdate

```graphql
query recentUpdate($pagination: Pagination!) {
  comics: recentUpdate(pagination: $pagination) {
    id title status imageUrl
    authors { id name }
    categories { id name }
  }
}
```

#### Discovery: comicByCategories

```graphql
query comicByCategories($categoryId: [ID!]!, $pagination: Pagination!) {
  comics: comicByCategories(categoryId: $categoryId, pagination: $pagination) {
    id title status imageUrl
    authors { id name }
    categories { id name }
  }
}
```

变量: `{"categoryId": ["1"], "pagination": {...}}`

#### Search: searchComicsAndAuthors

```graphql
query searchComicAndAuthor($keyword: String!) {
  searchComicsAndAuthors(keyword: $keyword) {
    comics {
      id title status imageUrl
      authors { id name }
      categories { id name }
    }
  }
}
```

注意：搜索无分页。

#### MangaInfo: comicById

```graphql
query comicById($comicId: ID!) {
  comicById(comicId: $comicId) {
    id title description status imageUrl
    authors { id name }
    categories { id name }
    dateUpdated
  }
}
```

#### ChapterList: chaptersByComicId

```graphql
query chapterByComicId($comicId: ID!) {
  chaptersByComicId(comicId: $comicId) {
    id serial type size dateCreated dateUpdated
  }
}
```

返回所有章节（无分页）。章节有 `type`: `chapter`（话）或 `book`（卷）。

#### Chapter Images: imagesByChapterId

```graphql
query imagesByChapterId($chapterId: ID!) {
  imagesByChapterId(chapterId: $chapterId) {
    id kid height width
  }
}
```

图片 URL 构建: `https://komiic.com/api/image/{kid}`

---

## 4. Discovery Filters 设计

### 4.1 Filter 列表（4个）

```dart
List<FilterOption> get discoveryFilters => [
  FilterOption(
    name: 'mode',
    label: '模式',
    defaultValue: 'hot',
    choices: [
      FilterChoice(label: '热门', value: 'hot'),
      FilterChoice(label: '最新更新', value: 'recent'),
      FilterChoice(label: '按分类', value: 'category'),
    ],
  ),
  FilterOption(
    name: 'orderBy',
    label: '排序',
    defaultValue: 'DATE_UPDATED',
    choices: [
      FilterChoice(label: '更新时间', value: 'DATE_UPDATED'),
      FilterChoice(label: '本月人气', value: 'MONTH_VIEWS'),
      FilterChoice(label: '总观看数', value: 'VIEWS'),
      FilterChoice(label: '收藏数', value: 'FAVORITE_COUNT'),
    ],
  ),
  FilterOption(
    name: 'status',
    label: '状态',
    defaultValue: '',
    choices: [
      FilterChoice(label: '全部', value: ''),
      FilterChoice(label: '连载', value: 'ONGOING'),
      FilterChoice(label: '完结', value: 'END'),
    ],
  ),
  FilterOption(
    name: 'category',
    label: '分类',
    defaultValue: '',
    choices: [
      FilterChoice(label: '全部', value: ''),
      FilterChoice(label: '愛情', value: '1'),
      FilterChoice(label: '後宮', value: '2'),
      FilterChoice(label: '冒險', value: '8'),
      FilterChoice(label: '搞笑', value: '5'),
      FilterChoice(label: '校園', value: '4'),
      FilterChoice(label: '生活', value: '6'),
      FilterChoice(label: '懸疑', value: '7'),
      FilterChoice(label: '神鬼', value: '3'),
      FilterChoice(label: '異世界', value: '47'),
      FilterChoice(label: '熱血', value: '21'),
      FilterChoice(label: '科幻', value: '17'),
      FilterChoice(label: '百合', value: '18'),
      FilterChoice(label: '成人', value: '51'),
      FilterChoice(label: '戰鬥', value: '54'),
      FilterChoice(label: '職場', value: '10'),
      FilterChoice(label: '恐怖', value: '9'),
      FilterChoice(label: '運動', value: '40'),
      FilterChoice(label: '日常', value: '78'),
      FilterChoice(label: '奇幻', value: '189'),
      FilterChoice(label: 'BL', value: '274'),
      FilterChoice(label: '治癒', value: '19'),
      FilterChoice(label: '劇情', value: '97'),
    ],
  ),
];
```

### 4.2 Discovery 逻辑

```
if mode == 'category' && category != '':
  → comicByCategories(categoryId: [category], pagination)
elif mode == 'recent':
  → recentUpdate(pagination)
else (mode == 'hot'):
  → hotComics(pagination)
```

`pagination` 中的 `orderBy`、`status` 始终从 filter 传入。

---

## 5. 图片访问规则

### 5.1 封面图

- URL: `imageUrl` 字段直接返回（如 `https://public.komiic.com/comics/{hash}/cover.jpg`）
- 无 Referer 要求
- 无认证要求

### 5.2 章节图片

- URL: `https://komiic.com/api/image/{kid}`
- **必需 Referer**: `https://komiic.com/comic/{mangaId}/chapter/{chapterId}/page/1`
  - 只有 `/comic/{id}/chapter/{chapterId}/page/{n}` 或 `/comic/{id}/chapter/{chapterId}/images/all` 格式有效
  - 简单的 `https://komiic.com/` 或 `/comic/{id}` 会返回 400
- 无需 auth token（未登录也能用）
- 超过 300 张/天返回 HTTP 402

### 5.3 defaultHeaders

```dart
Map<String, String>? get defaultHeaders => {
  'User-Agent': _userAgent,
  'Referer': 'https://komiic.com/',
};
```

注意：`defaultHeaders` 用于通用请求和封面加载。章节图片需要在 `ChapterImage.headers` 中覆盖 Referer。

---

## 6. 章节处理

### 6.1 章节类型

每部漫画可能同时有两种章节类型：
- `chapter` — 按话连载（第1話, 第2話...）
- `book` — 按卷合集（第1卷, 第2卷...）

### 6.2 处理策略

在 `parseChapterList` 中，将两种类型分开处理：
- 优先展示 `chapter` 类型
- 如果只有 `book` 类型，则展示 `book`
- 如果两者都有，只展示 `chapter`（`book` 通常是话的合集，内容重复）

### 6.3 章节 ID 格式

使用 komiic 的 chapter id 作为 `ChapterItem.id`（纯数字字符串如 "7380"）。

### 6.4 章节标题格式

```
type == 'chapter' → "第{serial}話"
type == 'book' → "第{serial}卷"
```

---

## 7. 认证支持（可选）

### 7.1 Token 管理

- Token 存储在 cookie `komiic-access-token`
- 刷新端点: `POST /auth/refresh`
- 过期时间在 JWT payload 的 `exp` 字段

### 7.2 当前实现范围

本次实现**不**包含登录逻辑。预留 `needsCloudflare: false` 和无 auth 状态。未来可以：
1. 用 WebView 登录获取 token
2. 将 token 存入 `authHeaders`
3. 在请求中携带 `Cookie: komiic-access-token={token}`

---

## 8. 源属性

```dart
@override String get id => 'komiic';
@override String get name => 'Komiic';
@override String get shortName => 'KMC';
@override String get description => '日漫/台漫';
@override double get score => 4.5;
@override String? get href => 'https://komiic.com';
@override bool get needsProxy => false;
@override bool get needsCloudflare => false;
```

---

## 9. 方法实现映射

| 方法 | GraphQL 操作 | 返回 |
|------|------|------|
| `prepareDiscoveryFetch(page, filters)` | POST + hotComics/recentUpdate/comicByCategories | `FetchConfig(method: POST, body: jsonString)` |
| `parseDiscovery(response)` | 解析 `data.comics[]` | `List<MangaSummary>` |
| `prepareSearchFetch(keyword, page, filters)` | POST + searchComicsAndAuthors | `FetchConfig` |
| `parseSearch(response)` | 解析 `data.searchComicsAndAuthors.comics[]` | `List<MangaSummary>` |
| `prepareMangaInfoFetch(mangaId)` | POST + comicById | `FetchConfig` |
| `parseMangaInfo(response, mangaId)` | 解析详情 JSON | `MangaDetail` |
| `prepareChapterListFetch(mangaId, page)` | POST + chaptersByComicId（page=1 时返回 FetchConfig，page>1 返回 null） | `FetchConfig?` |
| `parseChapterList(response, mangaId)` | 解析章节 JSON 列表 | `ChapterListResult` |
| `prepareChapterFetch(mangaId, chapterId, page)` | POST + imagesByChapterId | `FetchConfig` |
| `parseChapter(response, mangaId, chapterId, page)` | 构建 image URLs | `ChapterResult` |

---

## 10. 分页策略

- **Discovery**: offset = (page - 1) * 30, limit = 30
- **Search**: 无分页（API 一次返回所有结果）
- **ChapterList**: 一次返回所有章节（`canLoadMore: false`）
- **Chapter Images**: 一次返回所有图片（`canLoadMore: false`）

---

## 11. 错误处理

- GraphQL 错误: 检查 `response['errors']`，非空则抛出
- HTTP 402: 图片日限额已达，显示友好提示
- 网络错误: 由框架层统一处理

---

## 12. 注册

在 `lib/app/di/injection.dart` 中：

```dart
import 'package:comic_reader/data/sources/komiic.dart';
// ...
registry.register(Komiic());
```
