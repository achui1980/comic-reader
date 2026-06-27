# JComic Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add JComic (jcomic.net) as a new manga data source plugin for the comic-reader Flutter app.

**Architecture:** Pure HTML parsing source using `package:html` DOM queries. Implements the standard `MangaSource` prepare/parse pattern. Chapters are embedded in the manga info page (no separate chapter list fetch).

**Tech Stack:** Dart, Flutter, `package:html` for DOM parsing, `MangaSource` base class.

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/data/sources/jcomic.dart` | JComic source class — all discovery, search, info, and chapter parsing |
| Modify | `lib/app/di/injection.dart` | Register `JComic()` in `SourceRegistry` |

---

### Task 1: Create JComic Source File — Class Skeleton & Identity

**Files:**
- Create: `lib/data/sources/jcomic.dart`

- [ ] **Step 1: Create the source file with imports, class declaration, and identity overrides**

```dart
import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// JComic (jcomic.net) data source.
///
/// Traditional Chinese manga site. HTML-based, no auth/login required,
/// no Cloudflare protection. Images served via AWS S3 presigned URLs.
class JComic extends MangaSource {
  static const String sourceId = 'jcomic';
  static const String _baseUrl = 'https://jcomic.net';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36';

  // --- Identity ---

  @override
  String get id => sourceId;

  @override
  String get name => 'JComic';

  @override
  String get shortName => 'JC';

  @override
  String? get description => 'jcomic.net';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  String? get userAgent => _userAgent;

  @override
  Map<String, String>? get defaultHeaders => const {
        'User-Agent': _userAgent,
        'Referer': 'https://jcomic.net',
      };

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;
}
```

- [ ] **Step 2: Run static analysis to verify the skeleton compiles**

Run: `flutter analyze lib/data/sources/jcomic.dart`
Expected: No errors (warnings about unimplemented abstract methods are fine at this stage)

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/jcomic.dart
git commit -m "feat(jcomic): add source skeleton with identity overrides"
```

---

### Task 2: Discovery Filters

**Files:**
- Modify: `lib/data/sources/jcomic.dart`

- [ ] **Step 1: Add discovery filters with all 36 categories**

Add this override inside the `JComic` class, after the identity section:

```dart
  // --- Filters ---

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'category',
          label: '分類',
          defaultValue: '最近更新',
          choices: [
            FilterChoice(label: '最近更新', value: '最近更新'),
            FilterChoice(label: '隨機', value: '隨機'),
            FilterChoice(label: '全彩', value: '全彩'),
            FilterChoice(label: '長篇', value: '長篇'),
            FilterChoice(label: '單行本', value: '單行本'),
            FilterChoice(label: '同人', value: '同人'),
            FilterChoice(label: '短篇', value: '短篇'),
            FilterChoice(label: 'Cosplay', value: 'Cosplay'),
            FilterChoice(label: '歐美', value: '歐美'),
            FilterChoice(label: 'WEBTOON', value: 'WEBTOON'),
            FilterChoice(label: '圓神領域', value: '圓神領域'),
            FilterChoice(label: '碧藍幻想', value: '碧藍幻想'),
            FilterChoice(label: 'CG雜圖', value: 'CG雜圖'),
            FilterChoice(label: '英語 ENG', value: '英語 ENG'),
            FilterChoice(label: '生肉', value: '生肉'),
            FilterChoice(label: '純愛', value: '純愛'),
            FilterChoice(label: '百合花園', value: '百合花園'),
            FilterChoice(label: '耽美花園', value: '耽美花園'),
            FilterChoice(label: '偽娘哲學', value: '偽娘哲學'),
            FilterChoice(label: '後宮閃光', value: '後宮閃光'),
            FilterChoice(label: '扶他樂園', value: '扶他樂園'),
            FilterChoice(label: '姐姐系', value: '姐姐系'),
            FilterChoice(label: '妹妹系', value: '妹妹系'),
            FilterChoice(label: 'SM', value: 'SM'),
            FilterChoice(label: '性轉換', value: '性轉換'),
            FilterChoice(label: '足の恋', value: '足の恋'),
            FilterChoice(label: '重口地帶', value: '重口地帶'),
            FilterChoice(label: '人妻', value: '人妻'),
            FilterChoice(label: 'NTR', value: 'NTR'),
            FilterChoice(label: '強暴', value: '強暴'),
            FilterChoice(label: '非人類', value: '非人類'),
            FilterChoice(label: '艦隊收藏', value: '艦隊收藏'),
            FilterChoice(label: 'Love Live', value: 'Love Live'),
            FilterChoice(label: 'SAO 刀劍神域', value: 'SAO 刀劍神域'),
            FilterChoice(label: 'Fate', value: 'Fate'),
            FilterChoice(label: '東方', value: '東方'),
            FilterChoice(label: '禁書目錄', value: '禁書目錄'),
          ],
        ),
      ];
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/data/sources/jcomic.dart`
Expected: No errors related to filters

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/jcomic.dart
git commit -m "feat(jcomic): add discovery filters with 36 categories"
```

---

### Task 3: Discovery — Prepare & Parse

**Files:**
- Modify: `lib/data/sources/jcomic.dart`

- [ ] **Step 1: Add private helper method for parsing listing items, and the discovery methods**

Add these inside the `JComic` class:

```dart
  // --- Private Helpers ---

  /// Prefix used to mark single-chapter manga IDs.
  static const String _singlePrefix = '__single__';

  /// Shared parser for listing items (used by both discovery and search).
  /// Parses `<div class="row col-lg-4 col-md-6 col-xs-12">` blocks.
  List<MangaSummary> _parseListingItems(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    // Each manga card is in a div with these column classes
    final cards = document.querySelectorAll('div.col-lg-4.col-md-6.col-xs-12');

    for (final card in cards) {
      // Find the link to the manga — either /page/{id} or /eps/{id}
      final linkEl = card.querySelector('a[href^="/page/"], a[href^="/eps/"]');
      if (linkEl == null) continue;

      final href = linkEl.attributes['href'] ?? '';
      String mangaId;
      if (href.startsWith('/page/')) {
        // Single-chapter manga
        mangaId = '$_singlePrefix${Uri.decodeComponent(href.substring('/page/'.length))}';
      } else if (href.startsWith('/eps/')) {
        // Multi-chapter manga
        mangaId = Uri.decodeComponent(href.substring('/eps/'.length));
      } else {
        continue;
      }

      // Cover image
      final imgEl = card.querySelector('img.img-responsive');
      final coverUrl = imgEl?.attributes['src'] ?? '';

      // Title — strip trailing " (N)" image count
      final titleEl = card.querySelector('.comic-title');
      var title = titleEl?.text.trim() ?? '';
      final countSuffix = RegExp(r'\s*\(\d+\)$');
      title = title.replaceFirst(countSuffix, '');

      // Author
      final authorEl = card.querySelector('a[href^="/author/"] button') ??
          card.querySelector('a[href^="/author/"]');
      final author = authorEl?.text.trim() ?? '';

      // Update time
      final dateEl = card.querySelector('.comic-date');
      String? updateTime;
      if (dateEl != null) {
        final dateText = dateEl.text.trim();
        // Format: "最後更新: 2024-05-01 12:30"
        final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(dateText);
        if (dateMatch != null) {
          updateTime = dateMatch.group(1);
        }
      }

      if (title.isNotEmpty) {
        results.add(MangaSummary(
          id: mangaId,
          sourceId: sourceId,
          title: title,
          coverUrl: coverUrl,
          author: author,
          updateTime: updateTime,
          headers: const {'Referer': 'https://jcomic.net'},
        ));
      }
    }

    return results;
  }

  // --- Discovery ---

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final category = filters['category'] ?? '最近更新';
    final encodedCategory = Uri.encodeComponent(category);

    return FetchConfig(
      url: '$_baseUrl/cat/$encodedCategory/$page',
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseListingItems(response as String);
  }
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/data/sources/jcomic.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/jcomic.dart
git commit -m "feat(jcomic): implement discovery fetch and parse"
```

---

### Task 4: Search — Prepare & Parse

**Files:**
- Modify: `lib/data/sources/jcomic.dart`

- [ ] **Step 1: Add search methods**

```dart
  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // JComic search has no pagination — page > 1 returns empty
    if (page > 1) {
      return FetchConfig(
        url: '$_baseUrl/search/${Uri.encodeComponent(keyword)}',
        headers: defaultHeaders,
        extra: {'emptyPage': true},
      );
    }
    return FetchConfig(
      url: '$_baseUrl/search/${Uri.encodeComponent(keyword)}',
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseListingItems(response as String);
  }
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/data/sources/jcomic.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/jcomic.dart
git commit -m "feat(jcomic): implement search fetch and parse"
```

---

### Task 5: Manga Info — Prepare & Parse

**Files:**
- Modify: `lib/data/sources/jcomic.dart`

- [ ] **Step 1: Add manga info methods**

```dart
  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    if (mangaId.startsWith(_singlePrefix)) {
      // Single-chapter: fetch reading page directly
      final stripped = mangaId.substring(_singlePrefix.length);
      return FetchConfig(
        url: '$_baseUrl/page/${Uri.encodeComponent(stripped)}',
        headers: defaultHeaders,
      );
    } else {
      // Multi-chapter: fetch episode list page
      return FetchConfig(
        url: '$_baseUrl/eps/${Uri.encodeComponent(mangaId)}',
        headers: defaultHeaders,
      );
    }
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    if (mangaId.startsWith(_singlePrefix)) {
      return _parseSingleChapterInfo(document, mangaId);
    } else {
      return _parseMultiChapterInfo(document, mangaId);
    }
  }

  /// Parse manga info from the multi-chapter episode list page (/eps/{title}).
  MangaDetail _parseMultiChapterInfo(
      dynamic document, String mangaId) {
    // Title
    final titleEl = document.querySelector('.comic-title') ??
        document.querySelector('h1');
    var title = titleEl?.text.trim() ?? mangaId;
    title = title.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');

    // Cover
    final coverEl = document.querySelector('img.img-responsive');
    final coverUrl = coverEl?.attributes['src'] ?? '';

    // Author
    final authorEl = document.querySelector('a[href^="/author/"] button') ??
        document.querySelector('a[href^="/author/"]');
    final author = authorEl?.text.trim() ?? '';

    // Tags — all category buttons
    final tagEls = document.querySelectorAll('a[href^="/cat/"] button');
    final tags = <String>[];
    for (final el in tagEls) {
      final text = el.text.trim();
      if (text.isNotEmpty) tags.add(text);
    }

    // Update time
    String? updateTime;
    final dateEl = document.querySelector('.comic-date');
    if (dateEl != null) {
      final dateMatch =
          RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(dateEl.text);
      if (dateMatch != null) updateTime = dateMatch.group(1);
    }

    // Chapters — each <a href="/page/{title}/{epNum}"><button>...</button></a>
    final chapters = <ChapterItem>[];
    final chapterLinks =
        document.querySelectorAll('a[href*="/page/$mangaId/"]');
    // Fallback: also try matching encoded form
    final encodedMangaId = Uri.encodeComponent(mangaId);

    final allLinks = chapterLinks.isNotEmpty
        ? chapterLinks
        : document.querySelectorAll('a[href*="/page/$encodedMangaId/"]');

    for (final a in allLinks) {
      final chapterHref = a.attributes['href'] ?? '';
      // Extract episode number from /page/{title}/{epNum}
      final parts = chapterHref.split('/');
      if (parts.length < 4) continue;
      final epNum = parts.last;
      if (int.tryParse(epNum) == null) continue;

      final chapterTitle =
          a.querySelector('button')?.text.trim() ??
          a.text.trim();

      if (chapterTitle.isNotEmpty) {
        chapters.add(ChapterItem(
          id: epNum,
          mangaId: mangaId,
          title: chapterTitle,
        ));
      }
    }

    // Sort chapters by episode number ascending
    chapters.sort((a, b) {
      final aNum = int.tryParse(a.id) ?? 0;
      final bNum = int.tryParse(b.id) ?? 0;
      return aNum.compareTo(bNum);
    });

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      tags: tags,
      status: MangaStatus.unknown,
      updateTime: updateTime,
      headers: const {'Referer': 'https://jcomic.net'},
      chapters: chapters,
    );
  }

  /// Parse manga info from a single-chapter reading page (/page/{title}).
  MangaDetail _parseSingleChapterInfo(
      dynamic document, String mangaId) {
    // Title from <h1>
    final titleEl = document.querySelector('h1');
    var title = titleEl?.text.trim() ?? mangaId.substring(_singlePrefix.length);
    title = title.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');

    // Cover — first comic image
    final coverEl = document.querySelector('img.img-responsive.comic-thumb');
    final coverUrl = coverEl?.attributes['src'] ?? '';

    // Author
    final authorEl = document.querySelector('a[href^="/author/"] button') ??
        document.querySelector('a[href^="/author/"]');
    final author = authorEl?.text.trim() ?? '';

    // Tags
    final tagEls = document.querySelectorAll('a[href^="/cat/"] button');
    final tags = <String>[];
    for (final el in tagEls) {
      final text = el.text.trim();
      if (text.isNotEmpty) tags.add(text);
    }

    // Fixed single chapter
    final chapters = [
      ChapterItem(
        id: '1',
        mangaId: mangaId,
        title: '全一話',
      ),
    ];

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      tags: tags,
      status: MangaStatus.unknown,
      headers: const {'Referer': 'https://jcomic.net'},
      chapters: chapters,
    );
  }
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/data/sources/jcomic.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/jcomic.dart
git commit -m "feat(jcomic): implement manga info fetch and parse"
```

---

### Task 6: Chapter List (null) & Chapter Content

**Files:**
- Modify: `lib/data/sources/jcomic.dart`

- [ ] **Step 1: Add chapter list (no-op) and chapter content methods**

```dart
  // --- Chapter List (embedded in manga info) ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are fully embedded in the manga info page
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    if (mangaId.startsWith(_singlePrefix)) {
      final stripped = mangaId.substring(_singlePrefix.length);
      return FetchConfig(
        url: '$_baseUrl/page/${Uri.encodeComponent(stripped)}',
        headers: defaultHeaders,
      );
    } else {
      return FetchConfig(
        url: '$_baseUrl/page/${Uri.encodeComponent(mangaId)}/$chapterId',
        headers: defaultHeaders,
      );
    }
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final images = <ChapterImage>[];

    // Extract all comic images from the page
    final imgEls = document.querySelectorAll('img.img-responsive.comic-thumb');
    for (final el in imgEls) {
      final src = el.attributes['src'] ?? '';
      // Filter: only S3 image URLs (images.jcomic.net), skip covers/thumbnails
      if (src.contains('images.jcomic.net')) {
        images.add(ChapterImage(
          url: src,
          headers: const {'Referer': 'https://jcomic.net'},
        ));
      }
    }

    // Chapter title
    final titleEl = document.querySelector('h1');
    var title = titleEl?.text.trim() ?? '';
    title = title.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');

    // Also try to get from #eps element
    if (title.isEmpty) {
      final epsEl = document.querySelector('#eps');
      title = epsEl?.text.trim() ?? 'Chapter $chapterId';
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: const {'Referer': 'https://jcomic.net'},
      ),
      canLoadMore: false,
    );
  }

  // --- Web URL ---

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    if (mangaId.startsWith(_singlePrefix)) {
      final stripped = mangaId.substring(_singlePrefix.length);
      return '$_baseUrl/page/${Uri.encodeComponent(stripped)}';
    }
    return '$_baseUrl/page/${Uri.encodeComponent(mangaId)}/$chapterId';
  }
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/data/sources/jcomic.dart`
Expected: No errors (class fully implements MangaSource)

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/jcomic.dart
git commit -m "feat(jcomic): implement chapter list and chapter content parsing"
```

---

### Task 7: Register Source in DI

**Files:**
- Modify: `lib/app/di/injection.dart:22` (add import)
- Modify: `lib/app/di/injection.dart:88-89` (add registration)

- [ ] **Step 1: Add import for JComic**

Add after line 22 (`import '...hot_manga.dart';`):

```dart
import 'package:comic_reader/data/sources/jcomic.dart';
```

- [ ] **Step 2: Register JComic in SourceRegistry**

Add after `registry.register(HotManga());` (line 88):

```dart
  registry.register(JComic());
```

- [ ] **Step 3: Run static analysis on injection.dart**

Run: `flutter analyze lib/app/di/injection.dart`
Expected: No errors

- [ ] **Step 4: Run full project analysis**

Run: `flutter analyze`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add lib/app/di/injection.dart
git commit -m "feat(jcomic): register JComic source in dependency injection"
```

---

### Task 8: Smoke Test — Verify with Live Site

**Files:**
- None (manual verification)

- [ ] **Step 1: Create a quick verification script**

Create `test/verify_jcomic.dart`:

```dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:comic_reader/data/sources/jcomic.dart';

/// Manual verification script for JComic source.
/// Run with: dart run test/verify_jcomic.dart
void main() async {
  final source = JComic();

  print('=== JComic Source Verification ===\n');

  // 1. Test discovery
  print('--- Discovery (最近更新, page 1) ---');
  final discoveryConfig = source.prepareDiscoveryFetch(1, {'category': '最近更新'});
  print('URL: ${discoveryConfig.url}');

  final discoveryResp = await http.get(
    Uri.parse(discoveryConfig.url),
    headers: discoveryConfig.headers,
  );
  print('Status: ${discoveryResp.statusCode}');

  if (discoveryResp.statusCode == 200) {
    final items = source.parseDiscovery(discoveryResp.body);
    print('Found ${items.length} items');
    if (items.isNotEmpty) {
      final first = items.first;
      print('  First: ${first.title} (id=${first.id}, author=${first.author})');
      print('  Cover: ${first.coverUrl.substring(0, 80)}...');
    }

    // 2. Test manga info (pick first multi-chapter item)
    final multiItem = items.where((i) => !i.id.startsWith('__single__')).firstOrNull;
    if (multiItem != null) {
      print('\n--- Manga Info (multi-chapter: ${multiItem.title}) ---');
      final infoConfig = source.prepareMangaInfoFetch(multiItem.id);
      print('URL: ${infoConfig.url}');
      final infoResp = await http.get(
        Uri.parse(infoConfig.url),
        headers: infoConfig.headers,
      );
      print('Status: ${infoResp.statusCode}');
      if (infoResp.statusCode == 200) {
        final detail = source.parseMangaInfo(infoResp.body, multiItem.id);
        print('  Title: ${detail.title}');
        print('  Author: ${detail.author}');
        print('  Tags: ${detail.tags.join(", ")}');
        print('  Chapters: ${detail.chapters.length}');
        if (detail.chapters.isNotEmpty) {
          print('  First chapter: ${detail.chapters.first.title} (id=${detail.chapters.first.id})');

          // 3. Test chapter content
          print('\n--- Chapter Content ---');
          final chConfig = source.prepareChapterFetch(
              multiItem.id, detail.chapters.first.id, 1);
          print('URL: ${chConfig.url}');
          final chResp = await http.get(
            Uri.parse(chConfig.url),
            headers: chConfig.headers,
          );
          print('Status: ${chResp.statusCode}');
          if (chResp.statusCode == 200) {
            final result = source.parseChapter(
                chResp.body, multiItem.id, detail.chapters.first.id, 1);
            print('  Images: ${result.chapter.images.length}');
            if (result.chapter.images.isNotEmpty) {
              print('  First image: ${result.chapter.images.first.url.substring(0, 80)}...');
            }
          }
        }
      }
    }

    // 4. Test single-chapter item
    final singleItem = items.where((i) => i.id.startsWith('__single__')).firstOrNull;
    if (singleItem != null) {
      print('\n--- Manga Info (single-chapter: ${singleItem.title}) ---');
      final infoConfig = source.prepareMangaInfoFetch(singleItem.id);
      print('URL: ${infoConfig.url}');
      final infoResp = await http.get(
        Uri.parse(infoConfig.url),
        headers: infoConfig.headers,
      );
      print('Status: ${infoResp.statusCode}');
      if (infoResp.statusCode == 200) {
        final detail = source.parseMangaInfo(infoResp.body, singleItem.id);
        print('  Title: ${detail.title}');
        print('  Chapters: ${detail.chapters.length} (should be 1)');
      }
    }
  }

  // 5. Test search
  print('\n--- Search (keyword: "火影") ---');
  final searchConfig = source.prepareSearchFetch('火影', 1, {});
  print('URL: ${searchConfig.url}');
  final searchResp = await http.get(
    Uri.parse(searchConfig.url),
    headers: searchConfig.headers,
  );
  print('Status: ${searchResp.statusCode}');
  if (searchResp.statusCode == 200) {
    final searchItems = source.parseSearch(searchResp.body);
    print('Found ${searchItems.length} results');
    if (searchItems.isNotEmpty) {
      print('  First: ${searchItems.first.title}');
    }
  }

  print('\n=== Verification Complete ===');
  exit(0);
}
```

- [ ] **Step 2: Run the verification script**

Run: `dart run test/verify_jcomic.dart`
Expected: Status 200 for all requests, items parsed successfully with titles and images

- [ ] **Step 3: Fix any parsing issues discovered during verification**

If the verification reveals parsing problems (e.g., empty results, wrong selectors), fix the source code and re-run until results are correct.

- [ ] **Step 4: Commit verification script**

```bash
git add test/verify_jcomic.dart
git commit -m "test(jcomic): add manual verification script"
```

---

### Task 9: Final Verification

**Files:**
- None

- [ ] **Step 1: Run full project static analysis**

Run: `flutter analyze`
Expected: No errors

- [ ] **Step 2: Verify the app compiles for web**

Run: `flutter build web --no-tree-shake-icons 2>&1 | tail -5`
Expected: Build succeeds (or at least no new errors introduced by jcomic.dart)

- [ ] **Step 3: Final commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix(jcomic): address final review issues"
```
