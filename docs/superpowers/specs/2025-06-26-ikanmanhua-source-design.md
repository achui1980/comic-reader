# IkanManhua 数据源集成设计

**日期**: 2025-06-26  
**状态**: 草案  
**目标**: 在 comic-reader 中集成 ikanmanhua.org（爱看漫画）作为新的漫画源插件

---

## 1. 概述

### 1.1 目标网站

- **名称**: 爱看漫画 (ikanmanhua)
- **域名**: `https://ikanmanhua.org`
- **图片CDN**: `https://www.jjmh.cc/static/upload/book/`
- **内容**: 韩漫为主，也有日漫/台湾漫画，成人向
- **语言**: 繁体中文标题 + 简体中文描述/标签

### 1.2 技术特点

| 层次 | 特征 | 备注 |
|------|------|------|
| 反爬 | 无 | 无 token/签名/加密 |
| 渲染 | SSR (Next.js) | HTML 中直接包含完整内容 |
| 图片 | 明文 `<img src>` | 无 data-src/JS 动态加载 |
| 认证 | 无 | 无登录/cookie 要求 |
| CDN | Cloudflare | 可能有 rate limit |

**结论**: 纯 HTML 解析即可，类似 baozi_manga 模式。无需 JS 解密、无需代理。

---

## 2. 架构设计

### 2.1 新增文件

```
lib/data/sources/ikan_manhua.dart    # 主源实现（MangaSource子类，单文件）
```

### 2.2 架构层级

```
IkanManhua (MangaSource)
  ├── prepareDiscoveryFetch / parseDiscovery   → HTML解析 /books 或 /rank 页面
  ├── prepareSearchFetch / parseSearch         → HTML解析 /search 搜索结果
  ├── prepareMangaInfoFetch / parseMangaInfo   → HTML解析 /book/{id} 详情页
  ├── prepareChapterListFetch                  → 返回 null（章节列表嵌入详情页）
  └── prepareChapterFetch / parseChapter       → HTML解析 /chapter/{id} 图片列表
```

### 2.3 与现有架构的集成点

- **DI注册**: 在 `injection.dart` 中 `registry.register(IkanManhua())`
- **图片无加密**: `scrambleType` 为默认 `none`
- **无需代理**: `needsProxy = false`
- **无需Cloudflare**: `needsCloudflare = false`

---

## 3. 源属性

```dart
class IkanManhua extends MangaSource {
  static const String sourceId = 'ikanmanhua';
  static const String _baseUrl = 'https://ikanmanhua.org';
  static const String _imageCdn = 'https://www.jjmh.cc/static/upload/book';

  static const String _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

  @override String get id => sourceId;
  @override String get name => '爱看漫画';
  @override String get shortName => 'IKM';
  @override double get score => 4.0;
  @override String? get href => _baseUrl;
  @override bool get needsProxy => false;
  @override bool get needsCloudflare => false;
  @override String? get userAgent => _mobileUserAgent;
  @override Map<String, String>? get defaultHeaders => {
    'User-Agent': _mobileUserAgent,
    'Referer': '$_baseUrl/',
  };
}
```

---

## 4. Discovery（发现/浏览）

### 4.1 筛选器定义

`FilterOption` 接口: `name`(标识), `label`(显示名), `defaultValue`, `choices`  
`FilterChoice` 接口: `label`(显示名), `value`(传递值)

```dart
@override
List<FilterOption> get discoveryFilters => const [
  FilterOption(
    name: 'mode',
    label: '模式',
    defaultValue: 'books',
    choices: [
      FilterChoice(label: '分类浏览', value: 'books'),
      FilterChoice(label: '排行榜', value: 'rank'),
    ],
  ),
  FilterOption(
    name: 'tag',
    label: '题材',
    defaultValue: '',
    choices: [
      FilterChoice(label: '全部', value: ''),
      FilterChoice(label: '青春', value: '青春'),
      FilterChoice(label: '性感', value: '性感'),
      FilterChoice(label: '长腿', value: '长腿'),
      FilterChoice(label: '御姐', value: '御姐'),
      FilterChoice(label: '巨乳', value: '巨乳'),
      FilterChoice(label: '新婚', value: '新婚'),
      FilterChoice(label: '媳妇', value: '媳妇'),
      FilterChoice(label: '暧昧', value: '暧昧'),
      FilterChoice(label: '清纯', value: '清纯'),
      FilterChoice(label: '调教', value: '调教'),
      FilterChoice(label: '少妇', value: '少妇'),
      FilterChoice(label: '风骚', value: '风骚'),
      FilterChoice(label: '同居', value: '同居'),
      FilterChoice(label: '淫乱', value: '淫乱'),
      FilterChoice(label: '好友', value: '好友'),
      FilterChoice(label: '女神', value: '女神'),
      FilterChoice(label: '诱惑', value: '诱惑'),
      FilterChoice(label: '偷懒', value: '偷懒'),
      FilterChoice(label: '出轨', value: '出轨'),
    ],
  ),
  FilterOption(
    name: 'region',
    label: '地区',
    defaultValue: '',
    choices: [
      FilterChoice(label: '全部', value: ''),
      FilterChoice(label: '韩国', value: '韩国'),
      FilterChoice(label: '日本', value: '日本'),
      FilterChoice(label: '台湾', value: '台湾'),
    ],
  ),
  FilterOption(
    name: 'status',
    label: '进度',
    defaultValue: '',
    choices: [
      FilterChoice(label: '全部', value: ''),
      FilterChoice(label: '连载', value: '0'),
      FilterChoice(label: '完结', value: '1'),
    ],
  ),
  FilterOption(
    name: 'rank_type',
    label: '排行类型',
    defaultValue: 'popular',
    choices: [
      FilterChoice(label: '新番榜', value: 'new'),
      FilterChoice(label: '人气榜', value: 'popular'),
      FilterChoice(label: '完结榜', value: 'completed'),
      FilterChoice(label: '推荐榜', value: 'recommend'),
    ],
  ),
];
```

### 4.2 prepareDiscoveryFetch

方法签名: `FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters)`

**排行榜处理**: 由于返回类型不可为 null，排行榜 `page > 1` 时返回空结果需要在 parseDiscovery 中通过检测 URL 来处理。

```dart
@override
FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
  final mode = filters['mode'] ?? 'books';

  if (mode == 'rank') {
    // 排行榜无分页，但仍需返回 FetchConfig
    // page > 1 时 parseDiscovery 会返回空列表
    return FetchConfig(
      url: '$_baseUrl/rank',
      headers: defaultHeaders,
      extra: {'mode': 'rank', 'rank_type': filters['rank_type'] ?? 'popular', 'page': page},
    );
  }

  // 分类浏览模式
  final queryParams = <String, dynamic>{};
  if (filters['tag']?.isNotEmpty == true) queryParams['tag'] = filters['tag'];
  if (filters['region']?.isNotEmpty == true) queryParams['region'] = filters['region'];
  if (filters['status']?.isNotEmpty == true) queryParams['status'] = filters['status'];
  queryParams['page'] = page.toString();

  return FetchConfig(
    url: '$_baseUrl/books',
    queryParameters: queryParams,
    headers: defaultHeaders,
  );
}
```

### 4.3 parseDiscovery

方法签名: `List<MangaSummary> parseDiscovery(dynamic response)`

注意：无 `extra` 参数。排行榜模式的判断通过检测 HTML 内容（rank 页面有明显不同的结构）。

```dart
@override
List<MangaSummary> parseDiscovery(dynamic response) {
  final html = response as String;
  final document = html_parser.parse(html);

  // 判断是否为排行榜页面（检查 rank 特有的元素）
  if (document.querySelector('[role="tablist"]') != null) {
    return _parseRankPage(document);
  }

  return _parseGridCards(document);
}
```

**备选方案**: 如果 `FetchConfig.extra` 可以通过某种方式传递到 parseDiscovery，则可以用 extra 中的 mode 判断。需实现时验证 repo 中是否有此传递机制。若无，则通过 HTML 结构特征区分。

**_parseGridCards**: 选择器 `a[href^="/book/"].block` 或 `a[href^="/book/"] .line-clamp-1`
- id: 从 href `/book/{id}` 提取数字
- title: `.line-clamp-1` 的 text
- cover: `img[src*="jjmh.cc"]` 的 src，或自行拼接 `$_imageCdn/{id}/cover.jpg`

**_parseRankPage**: 根据 rank_type 选择对应 tab 内容
- 选择器: rank 页面中对应 tab panel 内的 `a[href^="/book/"]`
- 提取 title、author、cover、tags

---

## 5. Search（搜索）

### 5.1 prepareSearchFetch

```dart
@override
FetchConfig? prepareSearchFetch(String keyword, int page, Map<String, String> filters) {
  if (keyword.trim().isEmpty) return null;
  return FetchConfig(
    url: '$_baseUrl/search',
    queryParameters: {'keyword': keyword},
    headers: defaultHeaders,
  );
}
```

### 5.2 parseSearch

与 discovery 的 `_parseGridCards` 共享相同解析逻辑。搜索结果使用相同的 grid 布局。

---

## 6. MangaInfo（漫画详情）

### 6.1 prepareMangaInfoFetch

```dart
@override
FetchConfig prepareMangaInfoFetch(String mangaId) {
  return FetchConfig(
    url: '$_baseUrl/book/$mangaId',
    headers: defaultHeaders,
  );
}
```

### 6.2 parseMangaInfo

从详情页 HTML 中提取：

| 数据 | 选择器/逻辑 |
|------|------------|
| title | `h1.text-2xl.font-bold` |
| author | `p` 中包含 "作者：" 的文本 |
| status | `p` 中包含 "状态：" → `ongoing`/`completed` |
| tags | `p` 中包含 "标签：" 的文本，或独立的 tag span |
| description | 简介区域 `p.text-sm.text-gray-700`（在元数据下方） |
| cover | `$_imageCdn/$mangaId/cover.jpg` |
| chapters | 所有 `a[href^="/chapter/"]` → `ChapterItem` 列表 |

**Chapter 提取**：
- id: 从 `/chapter/{id}` 提取数字字符串
- mangaId: 当前漫画 id
- title: 链接内的文本（如 "第1話-哥，你有做過愛嗎?"）
- 列表按页面顺序保留（从第1话到最新话）

---

## 7. ChapterList

方法签名: `FetchConfig? prepareChapterListFetch(String mangaId, int page)`

```dart
@override
FetchConfig? prepareChapterListFetch(String mangaId, int page) {
  // 章节列表嵌入在详情页中，无需单独请求
  return null;
}
```

---

## 8. Chapter Images（章节图片）

### 8.1 prepareChapterFetch

方法签名: `FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra})`

```dart
@override
FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra}) {
  return FetchConfig(
    url: '$_baseUrl/chapter/$chapterId',
    headers: defaultHeaders,
  );
}
```

### 8.2 parseChapter

方法签名: `ChapterResult parseChapter(dynamic response, String mangaId, String chapterId, int page)`

`ChapterResult` 接口: `chapter`(Chapter), `canLoadMore`, `nextPage?`, `nextExtra?`  
`Chapter` 接口: `id`, `mangaId`, `title`, `images`(List<ChapterImage>), `headers?`  
`ChapterImage` 接口: `url`, `scrambleType`(default none), `headers?`

```dart
@override
ChapterResult parseChapter(dynamic response, String mangaId, String chapterId, int page) {
  final html = response as String;
  final document = html_parser.parse(html);

  // 提取章节标题
  final title = document.querySelector('p.text-lg.text-gray-700')?.text.trim() ?? '第?話';

  // 提取所有章节图片
  final images = document
      .querySelectorAll('img[src*="jjmh.cc"]')
      .map((img) => ChapterImage(url: img.attributes['src']!))
      .toList();

  return ChapterResult(
    chapter: Chapter(
      id: chapterId,
      mangaId: mangaId,
      title: title,
      images: images,
    ),
    canLoadMore: false, // 所有图片在单页中
  );
}
```

注：上一章/下一章的导航由 app 的 chapter 列表处理，不需要在 parseChapter 中实现。

### 8.3 图片特性

- **格式**: JPEG
- **URL 模式**: `https://www.jjmh.cc/static/upload/book/{bookId}/{chapterId}/{imageId}.jpg`
- **无加密**: `scrambleType = ScrambleType.none`（默认值）
- **无需额外 headers**: 图片 CDN 不检查 Referer（但保险起见仍传递 defaultHeaders）

---

## 9. URL 与 ID 映射

| 实体 | URL 模式 | ID 格式 | 示例 |
|------|---------|---------|------|
| 漫画 | `/book/{id}` | 纯数字字符串 | `"887"` |
| 章节 | `/chapter/{id}` | 纯数字字符串 | `"38236"` |
| 封面 | `jjmh.cc/.../book/{id}/cover.jpg` | — | — |
| 章节图 | `jjmh.cc/.../book/{bookId}/{chapterId}/{n}.jpg` | — | — |

---

## 10. 错误处理与边界情况

1. **排行榜无分页**: `page > 1` 时 `prepareDiscoveryFetch` 返回 `null`
2. **搜索无结果**: 返回空列表
3. **Cloudflare Rate Limit**: 依赖框架层的重试机制
4. **图片 CDN 异常**: defaultHeaders 包含 Referer 作为保险
5. **Next.js RSC 数据**: 已验证内容在 SSR HTML 中完整渲染，不依赖客户端 hydration

---

## 11. 注册

在 `lib/app/di/injection.dart` 中添加：

```dart
import 'package:comic_reader/data/sources/ikan_manhua.dart';

// 在 configureDependencies() 中的 registry 注册区域
registry.register(IkanManhua());
```

---

## 12. 验证计划

1. `flutter analyze lib/data/sources/ikan_manhua.dart` — 静态分析通过
2. 手动验证各 prepare 方法生成的 URL 正确性
3. 使用 curl 获取页面 HTML，确认选择器匹配
4. 在 app 中验证 discovery、search、detail、reader 完整流程
