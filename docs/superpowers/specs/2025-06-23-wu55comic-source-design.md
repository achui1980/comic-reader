# Wu55Comic 数据源集成设计

**日期**: 2025-06-23  
**状态**: 草案  
**目标**: 在 comic-reader 中集成 wu55comic（污污漫画）作为新的漫画源插件

---

## 1. 概述

### 1.1 目标网站

- **名称**: 污污漫画 (wu55comic)
- **当前域名**: `www.wu55comic.store`（域名频繁更换）
- **永久入口**: `https://bitbucket.org/h365g/55comic/src/main/`
- **内容**: 韩漫、日漫、成人漫画，每部含多话（长条漫画格式）

### 1.2 核心技术挑战

| 层次 | 保护手段 | 参数 |
|------|---------|------|
| URL混淆 | 文件分成2片，分布在不同CDN | split_count=2 |
| 加密 | AES-CBC | key=16×'a', iv=8×'b'+8×'a' |
| 文件头替换 | 自定义magic number替代真实图片头 | 前8~12字节 |
| 图片打乱 | 水平条带逆序 | 切片数=f(md5(book_id+page_number))，范围44~80 |

---

## 2. 架构设计

### 2.1 新增文件

```
lib/data/sources/wu55comic.dart          # 主源实现（MangaSource子类）
lib/data/sources/wu55comic_decoder.dart   # 图片解密器（分片下载+AES+重组）
```

### 2.2 架构层级

```
Wu55Comic (MangaSource)
  ├── prepareDiscoveryFetch / parseDiscovery   → HTML解析首页/分类列表
  ├── prepareSearchFetch / parseSearch         → HTML解析搜索结果
  ├── prepareMangaInfoFetch / parseMangaInfo   → HTML解析漫画详情
  ├── prepareChapterListFetch                  → 返回null(章节嵌入详情页)
  ├── prepareChapterFetch / parseChapter       → HTML解析章节页，提取div[data-src]
  └── Wu55ComicDecoder (图片处理器)
        ├── resolveImageUrl()     → URL分片转换
        ├── downloadShards()      → 并行下载2个分片
        ├── decryptAES()          → AES-CBC解密
        ├── restoreMagicNumber()  → 还原文件头
        └── getSliceCount()       → 计算切片数(用于UI端重组)
```

### 2.3 与现有架构的集成点

- **DI注册**: 在 `injection.dart` 中 `registry.register(Wu55Comic())`
- **图片Scramble**: 新增 `ScrambleType.wu55` 枚举值
- **图片显示**: 在 `MangaImage` widget 中处理 `wu55` 类型（复用 JMC 的 CustomPainter 模式，但切片数计算逻辑不同）
- **CORS代理**: Web平台使用现有 `ImageProxy` 机制

---

## 3. 域名动态发现

### 3.1 策略

网站域名频繁更换，通过 Bitbucket 永久页面维护最新域名列表。

### 3.2 实现

```dart
class Wu55Comic extends MangaSource {
  String _baseUrl = 'https://www.wu55comic.store'; // 默认
  static const String _domainDiscoveryUrl = 
      'https://bitbucket.org/h365g/55comic/raw/main/README.md';
  
  /// 启动时或请求失败时调用
  Future<void> refreshBaseUrl() async {
    // 从 bitbucket README 解析出当前活跃域名
    // 正则匹配 https://www.wu55comic.xxx 格式
  }
}
```

### 3.3 触发时机

- 源初始化时尝试刷新（静默失败使用默认）
- 任何请求返回非200状态码时触发刷新重试

---

## 4. HTML解析方案

### 4.1 依赖

使用项目已有的 `html` package（`package:html/parser.dart`）。

### 4.2 URL路由映射

| 功能 | URL模式 | prepare方法输出 |
|------|---------|----------------|
| 发现/分类 | `/booklist?tag={tag}&area={area}&end={end}&page={page}` | GET请求 |
| 搜索 | `/search?keyword={keyword}` | GET请求 |
| 漫画详情 | `/book/{bookId}` | GET请求 |
| 章节阅读 | `/free-chapter/{chapterId}?t={timestamp}` | GET请求 |

### 4.3 关键CSS选择器

| 数据项 | 选择器 |
|--------|--------|
| 漫画标题 | `h1.sp-book-title` |
| 作者 | `p.sp-book-author` |
| 标签 | `a.sp-book-tag` |
| 简介 | `p.sp-book-summary` |
| 封面 | `[data-src]`（加密URL） |
| 章节列表 | `a.sp-chapter-item[href]` |
| 章节图片 | `div.cropped[data-src]` |
| 搜索结果 | 搜索结果列表项（含 `/book/{id}` 链接） |

### 4.4 分页

- 分类列表: URL参数 `page=N`，从1开始，解析页面中总页数
- 搜索: 无分页（一次返回最多100结果）
- 章节内容: 单页展示所有图片（无分页）

---

## 5. 图片解密管线

### 5.1 概述

wu55comic 的图片保护分为两个独立阶段：
1. **下载解密**（在Repository/Source层完成）：分片下载 → AES解密 → 文件头还原 → 得到打乱的JPEG
2. **切片重组**（在UI Widget层完成）：计算切片数 → Canvas重排条带

### 5.2 下载解密详细算法

```dart
class Wu55ComicDecoder {
  static const String _aesKey = 'aaaaaaaaaaaaaaaa'; // 16 bytes
  static const String _aesIV  = 'bbbbbbbbaaaaaaaa'; // 16 bytes
  static const List<String> _cdnHosts = [
    'https://bmigmij-wuwu.sqxxov.com/break_2',
    'https://bmigmih-wuwu.sqxxov.com/break_2',
  ];
  
  /// 将原始图片URL转为2个分片URL
  List<String> buildShardUrls(String originalUrl) {
    // 1. 去除 /break_xxx/ 路径段
    // 2. 将扩展名 .jpg 替换为 .b_0 和 .b_1
    // 3. 分别使用两个CDN host
    // 4. 追加 ?v={cacheKey} (当天日期 YYYYMMDD)
  }
  
  /// 并行下载两个分片并解密
  Future<Uint8List> downloadAndDecrypt(List<String> shardUrls) {
    // 1. 并行 GET 两个分片 (responseType: bytes)
    // 2. 拼接为单个 Uint8List
    // 3. AES-CBC 解密 (key, iv 硬编码)
    // 4. 返回解密后的数据
  }
  
  /// 解析 magic number 并还原文件头
  ImageDecodeResult restoreImage(Uint8List decrypted) {
    // 1. 读取 decrypted[0] 判断文件类型 (0=JPEG, 3=GIF, 4=AVIF)
    // 2. 读取 decrypted[1] 判断子类型 (0=monga需重组, 1=other不需要)
    // 3. 如果是 monga 类型，读取 book_id 和 page_number
    // 4. 用真实文件头覆盖前 N 字节
    // 5. 返回 {imageBytes, needsUnscramble, bookId, pageNumber}
  }
}
```

### 5.3 切片重组算法

```dart
/// 计算切片数量
int getSliceCount(int bookId, int pageNumber) {
  final combined = '$bookId$pageNumber';
  final hash = md5.convert(utf8.encode(combined)).toString();
  final lastChar = hash.codeUnitAt(hash.length - 1);
  final mod = lastChar % 10;
  return 44 + mod * 4; // 结果: 44, 48, 52, 56, 60, 64, 68, 72, 76, 80
}
```

### 5.4 UI端重组

复用项目现有的 `CustomPainter` 模式。wu55comic 的切片逻辑与 JmComic 本质相同（水平条带逆序），仅切片数计算方式不同：

- JmComic: `segments = f(chapterId, filename)`, 范围 2~20
- Wu55Comic: `segments = f(bookId, pageNumber)`, 范围 44~80

新增 `_Wu55UnscramblePainter` 或扩展现有 `_JmcUnscramblePainter` 使其参数化。

---

## 6. ScrambleType 扩展

### 6.1 枚举扩展

```dart
enum ScrambleType { none, jmc, rm5, wu55 }
```

### 6.2 ChapterImage 扩展

wu55 类型需要额外的 `bookId` 和 `pageNumber` 信息用于切片数计算：

```dart
class ChapterImage extends Equatable {
  final String url;
  final ScrambleType scrambleType;
  final Map<String, String>? headers;
  final int? scrambleId;       // JMC 使用
  final int? wu55BookId;       // wu55 使用
  final int? wu55PageNumber;   // wu55 使用
}
```

---

## 7. 筛选器设计 (discoveryFilters)

### 7.1 分类筛选

```dart
@override
List<FilterOption> get discoveryFilters => [
  FilterOption(
    name: 'area',
    label: '地区',
    defaultValue: '-1',
    choices: [
      FilterChoice(label: '全部', value: '-1'),
      FilterChoice(label: '韩漫', value: '2'),
      FilterChoice(label: '日漫', value: '1'),
    ],
  ),
  FilterOption(
    name: 'tag',
    label: '标签',
    defaultValue: '',
    choices: [
      FilterChoice(label: '全部', value: ''),
      FilterChoice(label: '巨乳', value: '巨乳'),
      FilterChoice(label: '人妻', value: '人妻'),
      FilterChoice(label: 'NTR', value: 'NTR'),
      FilterChoice(label: '长篇', value: '長篇'),
      FilterChoice(label: '剧情向', value: '劇情向'),
      // ... 更多标签
    ],
  ),
  FilterOption(
    name: 'end',
    label: '状态',
    defaultValue: '-1',
    choices: [
      FilterChoice(label: '全部', value: '-1'),
      FilterChoice(label: '完结', value: '1'),
      FilterChoice(label: '连载', value: '0'),
    ],
  ),
];
```

---

## 8. 请求配置

### 8.1 默认请求头

```dart
@override
Map<String, String>? get defaultHeaders => {
  'Referer': '$_baseUrl/',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8',
};
```

### 8.2 图片分片请求头

```dart
Map<String, String> get _imageHeaders => {
  'Referer': '$_baseUrl/',
  'Accept': '*/*',
  'Origin': _baseUrl,
};
```

### 8.3 代理配置

- Web平台：通过 `ImageProxy.url()` 前缀 `http://localhost:9090/`
- 原生平台：直接请求CDN

---

## 9. 数据流总览

```
用户浏览发现页
  → Wu55Comic.prepareDiscoveryFetch(page, filters)
    → GET /booklist?tag=...&area=...&page=N
  → Wu55Comic.parseDiscovery(html)
    → 解析HTML → List<MangaSummary>
    → 封面URL: 加密的 data-src（展示时需单独解密或用占位图）

用户进入漫画详情
  → Wu55Comic.prepareMangaInfoFetch(bookId)
    → GET /book/{bookId}
  → Wu55Comic.parseMangaInfo(html, bookId)
    → 解析标题/作者/简介/标签/章节列表
    → 返回 MangaDetail(chapters: [...])

用户阅读章节
  → Wu55Comic.prepareChapterFetch(mangaId, chapterId, page)
    → GET /free-chapter/{chapterId}?t={timestamp}
  → Wu55Comic.parseChapter(html, mangaId, chapterId, page)
    → 提取所有 div.cropped[data-src]
    → 对每个图片URL:
      1. buildShardUrls() → 2个分片URL
      2. downloadAndDecrypt() → AES解密
      3. restoreImage() → 还原文件头，得到bookId/pageNumber
      4. 保存解密后图片到内存/临时文件
      5. 返回 ChapterImage(localUrl, scrambleType: wu55, wu55BookId, wu55PageNumber)
    → ChapterResult(chapter, canLoadMore: false)

UI 显示图片
  → MangaImage widget 加载本地/内存图片
  → 检测 scrambleType == wu55
  → 使用 wu55BookId + wu55PageNumber 计算切片数
  → CustomPainter 重排条带
  → 显示最终图片
```

---

## 10. 封面处理

封面图片也使用同样的加密机制。考虑到列表页需要快速显示封面，采用以下策略：

- **列表页**: 使用灰色占位图 + 异步解密封面，解密完成后替换
- **详情页**: 同步等待封面解密完成后显示

或者，如果发现列表页的封面 `data-src` 实际上是直接可访问的URL（只是CDN域名不同），则直接使用。需要实测确认。

---

## 11. 错误处理

| 场景 | 处理方式 |
|------|---------|
| 域名失效 | 触发 `refreshBaseUrl()`，从bitbucket获取新域名重试 |
| 分片下载失败 | 使用备用CDN节点重试 |
| AES解密失败 | 记录错误，跳过该图片，显示加载失败占位图 |
| 切片数为0 | 直接显示原图（不做重组） |
| 网络超时 | 使用默认超时30s，分片请求15s |

---

## 12. 性能考虑

- **并行下载**: 2个分片使用 `Future.wait()` 并行下载
- **预加载**: 阅读时预加载后续2-3张图片
- **内存管理**: 解密后图片存为临时文件而非全部保持在内存
- **缓存**: 解密后的完整图片可缓存到磁盘，避免重复解密

---

## 13. 依赖

### 13.1 已有依赖（无需新增）

- `dio` — HTTP请求
- `html` — HTML解析
- `crypto` (dart:crypto/md5) — MD5计算
- `dart:typed_data` — Uint8List操作
- `dart:ui` — Canvas图片操作

### 13.2 新增依赖

无。项目已有 `pointycastle`、`encrypt`、`crypto` 三个加密包，直接使用。

---

## 14. 测试策略

- **单元测试**: 
  - URL分片转换逻辑
  - AES解密（用已知明文/密文对）
  - Magic number解析与还原
  - 切片数计算（md5确定性输出）
- **集成测试**: 
  - 完整的单张图片解密流程（需网络）
  - 标记为网络实测脚本，不纳入CI

---

## 15. 元数据

```dart
@override String get id => 'wu55comic';
@override String get name => '污污漫画';
@override String get shortName => '污漫';
@override String? get description => '韩漫日漫在线阅读';
@override double get score => 3.5;
@override String? get href => null; // 动态域名，不固定
@override bool get needsProxy => false;
@override int get firstPage => 1;
```
