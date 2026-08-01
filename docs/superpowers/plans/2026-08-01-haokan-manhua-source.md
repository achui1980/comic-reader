# 好看漫画（Haokan Manhua）Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 comic-reader 新增图片型漫画源「好看漫画」（haokantxt.com，MCCMS 系统），覆盖发现/搜索/详情/章节图片五组契约。

**Architecture:** 标准 HTML 抓取源，`extends MangaSource`，遵循「源是纯函数」惯例（prepare 构建 FetchConfig，parse 解析 HTML→domain entity），零框架改动。参照 `manhuagui_mobile.dart` 的 HTML 解析骨架与 `mmero.dart` 的防御性写法。

**Tech Stack:** Dart/Flutter；`html: ^0.15.4`（`html_parser.parse`/`parseFragment` + `querySelector(All)`）；`dart:convert` 解析详情页 ld+json；`equatable` 实体。

**Spec:** `docs/superpowers/specs/2026-08-01-haokan-manhua-source-design.md`

---

## File Structure

- **Create** `lib/data/sources/haokan_manhua.dart` — 源实现类 `HaokanManhua`，单一职责：把 haokantxt.com 的页面/URL 与 domain entity 互转。
- **Create** `test/data/sources/haokan_manhua_test.dart` — 单测，零网络零 mock。
- **Modify** `lib/app/di/injection.dart` — register 块追加 import + 一行 `registry.register(HaokanManhua())`。

---

## Key Reference Signatures (照抄，禁止臆造)

```dart
// lib/core/models/fetch_config.dart
enum HttpMethod { get, post }
FetchConfig({required String url, HttpMethod method=get, Map<String,String>? headers,
  Map<String,dynamic>? queryParameters, dynamic body, Duration? timeout,
  Map<String,dynamic>? extra, ResponseType? responseType})

// lib/domain/entities/plugin_info.dart
FilterChoice({required String label, required String value})
FilterOption({required String name, required String label, required String defaultValue,
  required List<FilterChoice> choices})

// lib/domain/entities/manga.dart
enum MangaStatus { ongoing, completed, unknown }
MangaSummary({required String id, required String sourceId, required String title,
  required String coverUrl, String author='', List<String> altTitles=const[],
  String? latestChapter, String? updateTime, Map<String,String>? headers,
  int? chapterCount, String? popularityText})
MangaDetail({required String id, required String sourceId, required String title,
  required String coverUrl, String? description, String author='', List<String> tags=const[],
  List<String> altTitles=const[], MangaStatus status=MangaStatus.unknown, String? latestChapter,
  String? updateTime, Map<String,String>? headers, List<ChapterItem> chapters=const[]})

// lib/domain/entities/chapter.dart
ChapterItem({required String id, required String mangaId, required String title, String? href})
ChapterImage({required String url, ScrambleType scrambleType=ScrambleType.none,
  ImageResponseEncoding responseEncoding=ImageResponseEncoding.binary,
  Map<String,String>? headers, int? scrambleId, int? wu55BookId, int? wu55PageNumber})
Chapter({required String id, required String mangaId, required String title,
  required List<ChapterImage> images, Map<String,String>? headers})
ChapterListResult({required List<ChapterItem> chapters, bool canLoadMore=false, int? nextPage})
ChapterResult({required Chapter chapter, bool canLoadMore=false, int? nextPage, dynamic nextExtra})

// lib/data/sources/manga_source.dart — 10 abstract methods:
FetchConfig prepareDiscoveryFetch(int page, Map<String,String> filters);
List<MangaSummary> parseDiscovery(dynamic response);
FetchConfig prepareSearchFetch(String keyword, int page, Map<String,String> filters);
List<MangaSummary> parseSearch(dynamic response);
FetchConfig prepareMangaInfoFetch(String mangaId);
MangaDetail parseMangaInfo(dynamic response, String mangaId);
FetchConfig? prepareChapterListFetch(String mangaId, int page);
ChapterListResult parseChapterList(dynamic response, String mangaId);
FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra});
ChapterResult parseChapter(dynamic response, String mangaId, String chapterId, int page);
// overridable: String? getChapterWebUrl(String mangaId, String chapterId)
```

---

## Task 1: Skeleton — metadata getters + filters

**Files:**
- Create: `lib/data/sources/haokan_manhua.dart`
- Test: `test/data/sources/haokan_manhua_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/sources/haokan_manhua_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/haokan_manhua.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() {
  late HaokanManhua source;

  setUp(() {
    source = HaokanManhua();
  });

  group('HaokanManhua metadata and request builders', () {
    test('declares a non-adult haokan source with discovery filters', () {
      expect(source.id, 'haokan');
      expect(source.name, '好看漫画');
      expect(source.shortName, 'HK');
      expect(source.score, 3.5);
      expect(source.href, 'https://www.haokantxt.com');
      expect(source.isAdult, isFalse);
      expect(source.needsProxy, isFalse);
      expect(source.discoveryFilters.map((f) => f.name), ['tags', 'finish', 'order']);
      final tags = source.discoveryFilters[0];
      expect(tags.defaultValue, '');
      expect(tags.choices.first.value, ''); // 全部
      expect(tags.choices.map((c) => c.value), contains('6')); // 热血
      final finish = source.discoveryFilters[1];
      expect(finish.choices.map((c) => c.value), ['', '1', '2']);
      final order = source.discoveryFilters[2];
      expect(order.choices.map((c) => c.value), ['addtime', 'hits']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'comic_reader/data/sources/haokan_manhua.dart'` / `HaokanManhua isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/data/sources/haokan_manhua.dart`:

```dart
import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class HaokanManhua extends MangaSource {
  static const String sourceId = 'haokan';
  static const String _baseUrl = 'https://www.haokantxt.com';

  @override
  String get id => sourceId;

  @override
  String get name => '好看漫画';

  @override
  String get shortName => 'HK';

  @override
  String? get description => '国内免费漫画站，MCCMS 系统';

  @override
  double get score => 3.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => false;

  @override
  bool get needsProxy => false;

  @override
  Map<String, String>? get defaultHeaders => {'Referer': _baseUrl};

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'tags',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '热血', value: '6'),
            FilterChoice(label: '冒险', value: '7'),
            FilterChoice(label: '科幻', value: '8'),
            FilterChoice(label: '霸总', value: '9'),
            FilterChoice(label: '玄幻', value: '10'),
            FilterChoice(label: '校园', value: '11'),
            FilterChoice(label: '修真', value: '12'),
            FilterChoice(label: '搞笑', value: '13'),
          ],
        ),
        FilterOption(
          name: 'finish',
          label: '状态',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '连载', value: '1'),
            FilterChoice(label: '完结', value: '2'),
          ],
        ),
        FilterOption(
          name: 'order',
          label: '排序',
          defaultValue: 'addtime',
          choices: [
            FilterChoice(label: '最新', value: 'addtime'),
            FilterChoice(label: '人气', value: 'hits'),
          ],
        ),
      ];

  // --- Discovery ---
  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    throw UnimplementedError();
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    throw UnimplementedError();
  }

  // --- Search ---
  @override
  FetchConfig prepareSearchFetch(String keyword, int page, Map<String, String> filters) {
    throw UnimplementedError();
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    throw UnimplementedError();
  }

  // --- Manga Info ---
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    throw UnimplementedError();
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    throw UnimplementedError();
  }

  // --- Chapter List (embedded in info page) ---
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra}) {
    throw UnimplementedError();
  }

  @override
  ChapterResult parseChapter(dynamic response, String mangaId, String chapterId, int page) {
    throw UnimplementedError();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/haokan_manhua.dart test/data/sources/haokan_manhua_test.dart
git commit -m "feat(haokan): add source skeleton with metadata and filters"
```

---

## Task 2: Discovery — prepareDiscoveryFetch + parseDiscovery + card helper

**Files:**
- Modify: `lib/data/sources/haokan_manhua.dart`
- Test: `test/data/sources/haokan_manhua_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in the test file (after the metadata group):

```dart
  group('HaokanManhua discovery', () {
    test('builds a filtered category request with path segments', () {
      final config = source.prepareDiscoveryFetch(2, {
        'tags': '6',
        'finish': '2',
        'order': 'hits',
      });
      expect(config.url, 'https://www.haokantxt.com/category/tags/6/finish/2/order/hits/page/2');
      expect(config.method, HttpMethod.get);
    });

    test('builds a bare category request when no filters given', () {
      final config = source.prepareDiscoveryFetch(1, const {});
      expect(config.url, 'https://www.haokantxt.com/category/page/1');
    });

    test('parses category cards into summaries', () {
      const html = '''
      <div class="comic-list">
        <div class="comic-item">
          <a class="comic-cover" href="/comic_yirenzhixia.html">
            <img src="https://comic.5um.net/comic/cover/yirenzhixia.webp" />
            <span class="update-badge">连载中</span>
          </a>
          <h3><a href="/comic_yirenzhixia.html">一人之下</a></h3>
          <p class="comic-author">米二</p>
        </div>
      </div>
      ''';
      final results = source.parseDiscovery(html);
      expect(results, hasLength(1));
      expect(results.single.id, 'yirenzhixia');
      expect(results.single.sourceId, 'haokan');
      expect(results.single.title, '一人之下');
      expect(results.single.coverUrl, 'https://comic.5um.net/comic/cover/yirenzhixia.webp');
      expect(results.single.author, '米二');
    });

    test('skips cards without a resolvable slug', () {
      const html = '<div class="comic-list"><div class="comic-item"><a class="comic-cover" href="/notacomic"></a></div></div>';
      expect(source.parseDiscovery(html), isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: FAIL — `UnimplementedError` thrown by `prepareDiscoveryFetch`/`parseDiscovery`.

- [ ] **Step 3: Write minimal implementation**

Replace the Discovery section stubs in `haokan_manhua.dart`:

```dart
  // --- Discovery ---
  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final buffer = StringBuffer('$_baseUrl/category');
    final tags = filters['tags'] ?? '';
    final finish = filters['finish'] ?? '';
    final order = filters['order'] ?? '';
    if (tags.isNotEmpty) buffer.write('/tags/$tags');
    if (finish.isNotEmpty) buffer.write('/finish/$finish');
    if (order.isNotEmpty) buffer.write('/order/$order');
    buffer.write('/page/$page');
    return FetchConfig(url: buffer.toString());
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseCards(response as String);
  }
```

Add private helpers at the end of the class (before the closing `}`):

```dart
  /// Resolve the manga URL slug from a detail-page href like /comic_yirenzhixia.html
  String? _extractSlug(String href) {
    final match = RegExp(r'comic_(.+?)\.html').firstMatch(href);
    return match?.group(1);
  }

  /// Parse `.comic-item` cards (handles the three DOM variants observed on the
  /// site: div-wrapper with inner a.comic-cover, outer <a class="comic-item">,
  /// and the search/category variant).
  List<MangaSummary> _parseCards(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final items = document.querySelectorAll('.comic-item');
    final results = <MangaSummary>[];
    for (final item in items) {
      final href = item.localName == 'a'
          ? (item.attributes['href'] ?? '')
          : (item.querySelector('a')?.attributes['href'] ?? '');
      final slug = _extractSlug(href);
      if (slug == null) continue;

      final titleEl = item.querySelector('.comic-title') ??
          item.querySelector('h3 a') ??
          item.querySelector('h3');
      final title = titleEl?.text.trim() ?? '';

      final imgEl = item.querySelector('img');
      final cover = imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '';

      final author = item.querySelector('p.comic-author')?.text.trim() ?? '';
      final badge = item.querySelector('span.update-badge')?.text.trim();

      results.add(MangaSummary(
        id: slug,
        sourceId: sourceId,
        title: title,
        coverUrl: cover,
        author: author,
        latestChapter: badge,
      ));
    }
    return results;
  }
```

> Note: the test's `h3 > a` markup is covered by `item.querySelector('h3 a')`. The `.comic-title` selector handles the homepage variant; kept for robustness even though category cards use `h3 a`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: PASS (all discovery tests + metadata test).

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/haokan_manhua.dart test/data/sources/haokan_manhua_test.dart
git commit -m "feat(haokan): implement category discovery + card parsing"
```

---

## Task 3: Search — prepareSearchFetch + parseSearch

**Files:**
- Modify: `lib/data/sources/haokan_manhua.dart`
- Test: `test/data/sources/haokan_manhua_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()`:

```dart
  group('HaokanManhua search', () {
    test('builds a path-form search request (page in path, keyword encoded)', () {
      final config = source.prepareSearchFetch('一人之下', 2, const {});
      expect(config.method, HttpMethod.get);
      expect(
        config.url,
        'https://www.haokantxt.com/search/${Uri.encodeComponent('一人之下')}/2',
      );
    });

    test('parses search result cards', () {
      const html = '''
      <div class="listbox"><div class="comic-list">
        <div class="comic-item">
          <a class="comic-cover" href="/comic_lianai.html">
            <img src="https://comic.5um.net/comic/cover/lianai.webp" />
          </a>
          <h3><a href="/comic_lianai.html">恋爱</a></h3>
          <p class="comic-author"></p>
        </div>
      </div></div>
      ''';
      final results = source.parseSearch(html);
      expect(results, hasLength(1));
      expect(results.single.id, 'lianai');
      expect(results.single.title, '恋爱');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: FAIL — `UnimplementedError` from `prepareSearchFetch`/`parseSearch`.

- [ ] **Step 3: Write minimal implementation**

Replace the Search section stubs:

```dart
  // --- Search ---
  @override
  FetchConfig prepareSearchFetch(String keyword, int page, Map<String, String> filters) {
    // Path form is required: query form (?key=) does not support pagination.
    return FetchConfig(url: '$_baseUrl/search/${Uri.encodeComponent(keyword)}/$page');
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseCards(response as String);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/haokan_manhua.dart test/data/sources/haokan_manhua_test.dart
git commit -m "feat(haokan): implement path-form search"
```

---

## Task 4: Manga info — prepareMangaInfoFetch + parseMangaInfo (ld+json primary, DOM fallback) + embedded chapters

**Files:**
- Modify: `lib/data/sources/haokan_manhua.dart`
- Test: `test/data/sources/haokan_manhua_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()`:

```dart
  group('HaokanManhua manga info', () {
    test('builds detail request from slug', () {
      final config = source.prepareMangaInfoFetch('yirenzhixia');
      expect(config.url, 'https://www.haokantxt.com/comic_yirenzhixia.html');
      expect(config.method, HttpMethod.get);
    });

    test('does not request a separate chapter list', () {
      expect(source.prepareChapterListFetch('yirenzhixia', 1), isNull);
    });

    test('parses detail via ld+json and embedded chapters with numeric mangaId', () {
      const html = '''
      <html><head>
      <script type="application/ld+json">
      {"@type":"Book","name":"《一人之下》","author":{"name":"米二"},
       "description":"道术漫画","genre":"玄幻",
       "image":"https://comic.5um.net/comic/cover/yirenzhixia.webp",
       "workExample":{"bookEdition":"第100话","datePublished":"2026-07-02"}}
      </script></head>
      <body>
        <a data-id="13871" class="btn--collect"></a>
        <div class="comic-tags"><span class="tag">玄幻</span><span class="tag">连载</span></div>
        <div class="chapter-list" id="chapter-list">
          <div class="chapter-item"><a href="/chapter_13871_4992.html">第1话</a></div>
          <div class="chapter-item"><a href="/chapter_13871_4993.html">第2话</a></div>
        </div>
      </body></html>
      ''';
      final detail = source.parseMangaInfo(html, 'yirenzhixia');
      expect(detail.id, 'yirenzhixia');
      expect(detail.sourceId, 'haokan');
      expect(detail.title, '一人之下'); // 书名号已 strip
      expect(detail.author, '米二');
      expect(detail.description, '道术漫画');
      expect(detail.coverUrl, 'https://comic.5um.net/comic/cover/yirenzhixia.webp');
      expect(detail.status, MangaStatus.ongoing);
      expect(detail.latestChapter, '第100话');
      expect(detail.chapters.map((c) => c.id), ['4992', '4993']);
      expect(detail.chapters.map((c) => c.mangaId), ['13871', '13871']);
      expect(detail.chapters.first.title, '第1话');
      expect(detail.chapters.first.href, 'https://www.haokantxt.com/chapter_13871_4992.html');
    });

    test('falls back to DOM when ld+json is absent', () {
      const html = '''
      <html><body>
        <a data-id="13871"></a>
        <div class="comic-meta-info"><h1>《测试漫画》</h1></div>
        <div class="comic-cover-large"><img src="https://comic.5um.net/comic/cover/test.webp" /></div>
        <div class="comic-tags"><span class="tag">热血</span><span class="tag">完结</span></div>
        <div class="comic-description"><p>简介文本</p></div>
        <div class="chapter-list" id="chapter-list">
          <div class="chapter-item"><a href="/chapter_13871_5000.html">第1话</a></div>
        </div>
      </body></html>
      ''';
      final detail = source.parseMangaInfo(html, 'test');
      expect(detail.title, '测试漫画');
      expect(detail.coverUrl, 'https://comic.5um.net/comic/cover/test.webp');
      expect(detail.description, '简介文本');
      expect(detail.status, MangaStatus.completed);
      expect(detail.chapters.single.id, '5000');
    });

    test('falls back to slug for chapter mangaId when numeric id missing', () {
      const html = '''
      <html><body>
        <div class="comic-meta-info"><h1>无id漫画</h1></div>
        <div class="chapter-list" id="chapter-list"></div>
      </body></html>
      ''';
      final detail = source.parseMangaInfo(html, 'noidmanga');
      expect(detail.title, '无id漫画');
      expect(detail.chapters, isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: FAIL — `UnimplementedError` from `prepareMangaInfoFetch`/`parseMangaInfo`.

- [ ] **Step 3: Write minimal implementation**

Replace the Manga Info section stubs (keep `prepareChapterListFetch`/`parseChapterList` as-is):

```dart
  // --- Manga Info ---
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/comic_$mangaId.html');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Numeric comic id: needed to build chapter URLs. Fall back to slug.
    final numericId = _extractNumericId(htmlStr) ?? mangaId;

    // Prefer ld+json for metadata; fall back to DOM.
    final ld = _parseLdJson(document);

    String title = _stripBrackets((ld?['name'] as String?) ??
        document.querySelector('.comic-meta-info h1')?.text.trim() ??
        '');

    final author = (ld?['author'] is Map ? ld!['author']['name'] as String? : null) ?? '';

    final description = (ld?['description'] as String?) ??
        document.querySelector('.comic-description p')?.text.trim();

    String coverUrl = (ld?['image'] as String?) ??
        document.querySelector('.comic-cover-large img')?.attributes['src'] ??
        '';

    String? latestChapter;
    if (ld?['workExample'] is Map) {
      latestChapter = ld!['workExample']['bookEdition'] as String?;
    }

    // Status from the second .comic-tags .tag (连载 / 完结).
    final statusTags = document.querySelectorAll('.comic-tags .tag');
    MangaStatus status = MangaStatus.unknown;
    if (statusTags.length >= 2) {
      final text = statusTags[1].text.trim();
      if (text.contains('连载')) {
        status = MangaStatus.ongoing;
      } else if (text.contains('完结')) {
        status = MangaStatus.completed;
      }
    }

    final tags = <String>[];
    final genre = ld?['genre'];
    if (genre is String && genre.isNotEmpty) tags.add(genre);

    // Chapters embedded in the info page.
    final chapters = <ChapterItem>[];
    for (final a in document.querySelectorAll('#chapter-list .chapter-item > a')) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'chapter_(\d+)_(\d+)\.html').firstMatch(href);
      if (m == null) continue;
      final chapterId = m.group(2)!;
      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: numericId,
        title: a.text.trim(),
        href: '$_baseUrl$href',
      ));
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: tags,
      status: status,
      latestChapter: latestChapter,
      chapters: chapters,
    );
  }
```

Add private helpers (near the other helpers):

```dart
  String? _extractNumericId(String htmlStr) {
    final byData = RegExp(r'data-id="(\d+)"').firstMatch(htmlStr);
    if (byData != null) return byData.group(1);
    final byChapter = RegExp(r'chapter_(\d+)_').firstMatch(htmlStr);
    return byChapter?.group(1);
  }

  Map<String, dynamic>? _parseLdJson(Document document) {
    final el = document.querySelector('script[type="application/ld+json"]');
    if (el == null) return null;
    try {
      final decoded = json.decode(el.text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _stripBrackets(String s) => s.replaceAll('《', '').replaceAll('》', '').trim();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/haokan_manhua.dart test/data/sources/haokan_manhua_test.dart
git commit -m "feat(haokan): parse manga info via ld+json with DOM fallback and embedded chapters"
```

---

## Task 5: Chapter images — prepareChapterFetch + parseChapter (Referer injection + paywall guard) + getChapterWebUrl

**Files:**
- Modify: `lib/data/sources/haokan_manhua.dart`
- Test: `test/data/sources/haokan_manhua_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()`:

```dart
  group('HaokanManhua chapter content', () {
    test('builds chapter request from numeric mangaId and chapterId', () {
      final config = source.prepareChapterFetch('13871', '4992', 1);
      expect(config.url, 'https://www.haokantxt.com/chapter_13871_4992.html');
      expect(config.method, HttpMethod.get);
      expect(source.getChapterWebUrl('13871', '4992'),
          'https://www.haokantxt.com/chapter_13871_4992.html');
    });

    test('parses images and injects Referer header on each', () {
      const html = '''
      <div class="comic-content">
        <img class="comic-image" src="https://manhua.5um.net/colatj/yirenzhixia/1/a.webp" />
        <img class="comic-image" data-src="https://manhua.5um.net/colatj/yirenzhixia/1/b.webp" />
        <img class="comic-image" src="https://manhua.5um.net/colatj/yirenzhixia/1/c.webp" />
      </div>
      ''';
      final result = source.parseChapter(html, '13871', '4992', 1);
      expect(result.canLoadMore, isFalse);
      expect(result.chapter.id, '4992');
      expect(result.chapter.mangaId, '13871');
      expect(result.chapter.images.map((i) => i.url), [
        'https://manhua.5um.net/colatj/yirenzhixia/1/a.webp',
        'https://manhua.5um.net/colatj/yirenzhixia/1/b.webp',
        'https://manhua.5um.net/colatj/yirenzhixia/1/c.webp',
      ]);
      expect(
        result.chapter.images.map((i) => i.headers?['Referer']),
        everyElement('https://www.haokantxt.com'),
      );
    });

    test('throws when zero images and a visible paywall box is present', () {
      const html = '''
      <div class="comic-content"></div>
      <div class="hide buy-box"><p class="buy-title">当前章节为付费章节</p></div>
      ''';
      expect(
        () => source.parseChapter(html, '13871', '4992', 1),
        throwsA(isA<Exception>()),
      );
    });

    test('returns empty images (no throw) on malformed page with hidden paywall', () {
      const html = '''
      <div class="comic-content"></div>
      <div class="hide buy-box" style="display:none;"></div>
      ''';
      final result = source.parseChapter(html, '13871', '4992', 1);
      expect(result.chapter.images, isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: FAIL — `UnimplementedError` from `prepareChapterFetch`/`parseChapter`.

- [ ] **Step 3: Write minimal implementation**

Replace the Chapter Content section stubs:

```dart
  // --- Chapter Content ---
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra}) {
    return FetchConfig(url: '$_baseUrl/chapter_${mangaId}_$chapterId.html');
  }

  @override
  ChapterResult parseChapter(dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final imgEls = document.querySelectorAll('.comic-content img.comic-image');
    final images = <ChapterImage>[];
    for (final el in imgEls) {
      final url = el.attributes['src'] ?? el.attributes['data-src'] ?? '';
      if (url.isEmpty) continue;
      images.add(ChapterImage(
        url: url,
        headers: const {'Referer': _baseUrl},
      ));
    }

    // Paywall guard: zero images + a paywall box that is NOT hidden.
    if (images.isEmpty) {
      final buyBox = document.querySelector('.buy-box');
      if (buyBox != null) {
        final style = buyBox.attributes['style'] ?? '';
        if (!style.contains('display:none') && !style.contains('display: none')) {
          throw Exception('该章节需要付费');
        }
      }
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: images,
      ),
      canLoadMore: false,
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/chapter_${mangaId}_$chapterId.html';
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/haokan_manhua.dart test/data/sources/haokan_manhua_test.dart
git commit -m "feat(haokan): parse chapter images with Referer injection and paywall guard"
```

---

## Task 6: Register the source + static analysis

**Files:**
- Modify: `lib/app/di/injection.dart`

- [ ] **Step 1: Add the import**

In `lib/app/di/injection.dart`, add alongside the other source imports (alphabetical/grouped as the file does):

```dart
import 'package:comic_reader/data/sources/haokan_manhua.dart';
```

- [ ] **Step 2: Register in the registry block**

In the `registry.register(...)` block (after the existing entries, e.g. after `registry.register(MmeroSource());`), add:

```dart
  registry.register(HaokanManhua());
```

- [ ] **Step 3: Run static analysis on both changed files**

Run: `flutter analyze lib/data/sources/haokan_manhua.dart lib/app/di/injection.dart`
Expected: `No issues found!` (or only pre-existing warnings unrelated to these files).

- [ ] **Step 4: Run the focused test suite once more**

Run: `flutter test test/data/sources/haokan_manhua_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/di/injection.dart
git commit -m "feat(haokan): register source in DI container"
```

---

## Self-Review

- **Spec coverage:**
  - 文件与注册 → Task 1 (create) + Task 6 (register). ✓
  - 元数据 getter / defaultHeaders / filters → Task 1. ✓
  - ① Discovery (path-segment category URL + card parse) → Task 2. ✓
  - ② Search (path-form pagination) → Task 3. ✓
  - ③ MangaInfo (ld+json primary, DOM fallback, numeric-id extraction, embedded chapters, dual-ID) → Task 4. ✓
  - ④ ChapterList (return null / empty result) → Task 1 (stubs are final impl; asserted null in Task 4). ✓
  - ⑤ Chapter (img.comic-image, `src ?? data-src`, Referer per image, canLoadMore=false, paywall guard, getChapterWebUrl) → Task 5. ✓
  - mangaId 传递链 (slug in Summary.id → detail req by slug → numeric id parsed → ChapterItem.mangaId numeric → chapter req by numeric) → Task 4 + Task 5. ✓
  - 私有辅助 (_baseUrl/_extractSlug/_extractNumericId/_parseCards/_parseLdJson/_stripBrackets) → covered. ✓
  - 边界处理 (缺字段默认值/无ld+json兜底/数字id缺失回退slug/0图不抛) → Tasks 2,4,5 tests. ✓
  - 测试用例清单 → all mapped across tasks. ✓
- **Placeholder scan:** No TBD/TODO/"similar to Task N"; every code step shows full code. ✓
- **Type consistency:** `_parseCards(String)` used by both parseDiscovery/parseSearch; `_extractSlug`/`_extractNumericId`/`_parseLdJson`/`_stripBrackets` names consistent across tasks; entity constructors match confirmed signatures; `ChapterImage.headers` is `Map<String,String>?` and `const {'Referer': _baseUrl}` is valid since `_baseUrl` is `static const`. ✓

> Note on `_map`/`_list`: the design mentioned defensive JSON helpers borrowed from mmero, but this source parses HTML (not JSON responses), and ld+json access is guarded by `_parseLdJson` try/catch plus `is Map`/`is String` checks. Dedicated `_map`/`_list` helpers are YAGNI here and intentionally omitted — the guards cover the same defensive intent.

---

## Execution notes

- Do NOT run whole-repo `flutter test` (it includes live-network scripts and a known-failing `widget_test.dart`). Always target `test/data/sources/haokan_manhua_test.dart`.
- All image loads MUST carry `Referer` — missing it returns HTTP 200 + a text/html captcha page (silent failure), handled by per-image `headers` in Task 5.
