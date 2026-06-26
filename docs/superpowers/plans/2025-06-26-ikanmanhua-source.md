# IkanManhua Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement ikanmanhua.org (爱看漫画) as a MangaSource plugin supporting discovery with filters/rankings, search, manga detail, and chapter reading.

**Architecture:** Single-file MangaSource subclass using pure HTML parsing (package:html). No encryption, no proxy, no special image handling. Pattern follows baozi_manga closely.

**Tech Stack:** Dart/Flutter, package:html for HTML parsing, existing MangaSource/FetchConfig framework.

## Global Constraints

- Source file: `lib/data/sources/ikan_manhua.dart`
- Registration: `lib/app/di/injection.dart`
- Must pass `flutter analyze lib/data/sources/ikan_manhua.dart`
- All method signatures must match `MangaSource` abstract class exactly
- Use `package:html/parser.dart as html_parser` for parsing
- Imports use `package:comic_reader/...` paths
- No direct HTTP calls — only prepare FetchConfig, parse response

---

### Task 1: Source Scaffold with Properties and Filters

**Files:**
- Create: `lib/data/sources/ikan_manhua.dart`
- Modify: `lib/app/di/injection.dart:17` (add import + registration)

**Interfaces:**
- Consumes: `MangaSource` abstract class from `package:comic_reader/data/sources/manga_source.dart`
- Produces: `IkanManhua` class registered and visible to the app; `discoveryFilters` getter returning filter options

- [ ] **Step 1: Create the source file with class skeleton and all property overrides**

Create `lib/data/sources/ikan_manhua.dart`:

```dart
import 'package:html/parser.dart' as html_parser;
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/manga.dart';
import 'package:comic_reader/domain/entities/chapter.dart';
import 'package:comic_reader/domain/entities/plugin_info.dart';

class IkanManhua extends MangaSource {
  static const String sourceId = 'ikanmanhua';
  static const String _baseUrl = 'https://ikanmanhua.org';
  static const String _imageCdn = 'https://www.jjmh.cc/static/upload/book';

  static const String _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

  @override
  String get id => sourceId;

  @override
  String get name => '爱看漫画';

  @override
  String get shortName => 'IKM';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;

  @override
  String? get userAgent => _mobileUserAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _mobileUserAgent,
        'Referer': '$_baseUrl/',
      };

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

  // --- Discovery ---

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    // TODO: Task 2
    throw UnimplementedError();
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    // TODO: Task 2
    throw UnimplementedError();
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // TODO: Task 3
    throw UnimplementedError();
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    // TODO: Task 3
    throw UnimplementedError();
  }

  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    // TODO: Task 4
    throw UnimplementedError();
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    // TODO: Task 4
    throw UnimplementedError();
  }

  // --- Chapter List ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    return null; // Chapters are embedded in the manga info page
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // TODO: Task 5
    throw UnimplementedError();
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    // TODO: Task 5
    throw UnimplementedError();
  }
}
```

- [ ] **Step 2: Register the source in injection.dart**

Add import at line 17 (after `goda_manga.dart` import):

```dart
import 'package:comic_reader/data/sources/ikan_manhua.dart';
```

Add registration after line 78 (after `registry.register(GodaManga())`):

```dart
  registry.register(IkanManhua());
```

- [ ] **Step 3: Run static analysis to verify scaffold compiles**

Run: `flutter analyze lib/data/sources/ikan_manhua.dart`

Expected: No errors (warnings about UnimplementedError are acceptable at this stage since we're using `throw UnimplementedError()` as placeholder).

- [ ] **Step 4: Commit scaffold**

```bash
git add lib/data/sources/ikan_manhua.dart lib/app/di/injection.dart
git commit -m "feat(ikanmanhua): add source scaffold with filters and DI registration"
```

---

### Task 2: Discovery — prepareDiscoveryFetch and parseDiscovery

**Files:**
- Modify: `lib/data/sources/ikan_manhua.dart`

**Interfaces:**
- Consumes: `FetchConfig` from `package:comic_reader/core/models/fetch_config.dart`; `MangaSummary` from entities
- Produces: `prepareDiscoveryFetch(int page, Map<String, String> filters) → FetchConfig` and `parseDiscovery(dynamic response) → List<MangaSummary>`

- [ ] **Step 1: Implement prepareDiscoveryFetch**

Replace the `prepareDiscoveryFetch` method:

```dart
  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final mode = filters['mode'] ?? 'books';

    if (mode == 'rank') {
      // Rank page has no pagination; page > 1 will return empty in parse
      return FetchConfig(
        url: '$_baseUrl/rank',
        headers: defaultHeaders,
        extra: {
          'mode': 'rank',
          'rank_type': filters['rank_type'] ?? 'popular',
          'page': page,
        },
      );
    }

    // Category browsing mode with filters
    final queryParams = <String, dynamic>{};
    final tag = filters['tag'] ?? '';
    final region = filters['region'] ?? '';
    final status = filters['status'] ?? '';
    if (tag.isNotEmpty) queryParams['tag'] = tag;
    if (region.isNotEmpty) queryParams['region'] = region;
    if (status.isNotEmpty) queryParams['status'] = status;
    queryParams['page'] = page.toString();

    return FetchConfig(
      url: '$_baseUrl/books',
      queryParameters: queryParams,
      headers: defaultHeaders,
    );
  }
```

- [ ] **Step 2: Implement parseDiscovery with _parseGridCards helper**

Replace the `parseDiscovery` method and add private helpers:

```dart
  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final html = response as String;
    final document = html_parser.parse(html);

    // Rank page has a tablist element; books page does not
    if (document.querySelector('[role="tablist"]') != null) {
      return _parseRankPage(document);
    }

    return _parseGridCards(document);
  }

  /// Parse grid cards from /books or /search pages.
  /// Cards are <a href="/book/{id}"> with nested img and title.
  List<MangaSummary> _parseGridCards(dynamic document) {
    final cards = document.querySelectorAll('a[href^="/book/"]');
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final card in cards) {
      final href = card.attributes['href'] ?? '';
      final match = RegExp(r'/book/(\d+)').firstMatch(href);
      if (match == null) continue;

      final mangaId = match.group(1)!;
      if (seen.contains(mangaId)) continue;
      seen.add(mangaId);

      final titleEl = card.querySelector('.line-clamp-1');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;

      final imgEl = card.querySelector('img');
      final coverUrl = imgEl?.attributes['src'] ??
          '$_imageCdn/$mangaId/cover.jpg';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        headers: defaultHeaders,
      ));
    }

    return results;
  }

  /// Parse rank page — all tabs content is SSR'd in HTML.
  /// Each rank item is an <a href="/book/{id}"> with title/author inside.
  List<MangaSummary> _parseRankPage(dynamic document) {
    // Rank page renders all tab panels; items have a different structure
    // They use flex layout with ranking number, cover, and info
    final cards = document.querySelectorAll('a[href^="/book/"]');
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final card in cards) {
      final href = card.attributes['href'] ?? '';
      final match = RegExp(r'/book/(\d+)').firstMatch(href);
      if (match == null) continue;

      final mangaId = match.group(1)!;
      if (seen.contains(mangaId)) continue;
      seen.add(mangaId);

      // Title is in h3 element
      final titleEl = card.querySelector('h3');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;

      // Author from <p> containing "作者："
      String author = '';
      final paragraphs = card.querySelectorAll('p');
      for (final p in paragraphs) {
        final text = p.text.trim();
        if (text.startsWith('作者：') || text.startsWith('作者:')) {
          author = text.replaceFirst(RegExp(r'^作者[：:]'), '').trim();
          break;
        }
      }

      final imgEl = card.querySelector('img');
      final coverUrl = imgEl?.attributes['src'] ??
          '$_imageCdn/$mangaId/cover.jpg';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        author: author,
        headers: defaultHeaders,
      ));
    }

    return results;
  }
```

- [ ] **Step 3: Verify with curl that /books HTML matches expected selectors**

Run: `curl -s 'https://ikanmanhua.org/books' -H 'User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X)' | grep -c 'href="/book/'`

Expected: A number > 0 (e.g., 20+), confirming the selector works.

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze lib/data/sources/ikan_manhua.dart`

Expected: No errors (may still have warnings from remaining UnimplementedError stubs).

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/ikan_manhua.dart
git commit -m "feat(ikanmanhua): implement discovery with filters and rank page parsing"
```

---

### Task 3: Search — prepareSearchFetch and parseSearch

**Files:**
- Modify: `lib/data/sources/ikan_manhua.dart`

**Interfaces:**
- Consumes: `_parseGridCards` helper from Task 2
- Produces: `prepareSearchFetch(String keyword, int page, Map<String, String> filters) → FetchConfig` and `parseSearch(dynamic response) → List<MangaSummary>`

- [ ] **Step 1: Implement prepareSearchFetch**

Replace the `prepareSearchFetch` method:

```dart
  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search',
      queryParameters: {'keyword': keyword},
      headers: defaultHeaders,
    );
  }
```

- [ ] **Step 2: Implement parseSearch**

Replace the `parseSearch` method:

```dart
  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final html = response as String;
    final document = html_parser.parse(html);
    return _parseGridCards(document);
  }
```

- [ ] **Step 3: Verify with curl that /search HTML has expected structure**

Run: `curl -s 'https://ikanmanhua.org/search?keyword=秘密' -H 'User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X)' | grep -c 'href="/book/'`

Expected: A number > 0.

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze lib/data/sources/ikan_manhua.dart`

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/ikan_manhua.dart
git commit -m "feat(ikanmanhua): implement search"
```

---

### Task 4: Manga Info — prepareMangaInfoFetch and parseMangaInfo

**Files:**
- Modify: `lib/data/sources/ikan_manhua.dart`

**Interfaces:**
- Consumes: `MangaDetail`, `MangaStatus`, `ChapterItem` from entities
- Produces: `prepareMangaInfoFetch(String mangaId) → FetchConfig` and `parseMangaInfo(dynamic response, String mangaId) → MangaDetail`

- [ ] **Step 1: Implement prepareMangaInfoFetch**

Replace the `prepareMangaInfoFetch` method:

```dart
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/book/$mangaId',
      headers: defaultHeaders,
    );
  }
```

- [ ] **Step 2: Implement parseMangaInfo**

Replace the `parseMangaInfo` method:

```dart
  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final html = response as String;
    final document = html_parser.parse(html);

    // Title
    final title = document.querySelector('h1')?.text.trim() ?? '';

    // Metadata paragraphs (author, status, tags, region)
    String author = '';
    MangaStatus status = MangaStatus.unknown;
    List<String> tags = [];
    String? description;

    final metaParagraphs = document.querySelectorAll('p.text-sm.text-gray-700');
    for (final p in metaParagraphs) {
      final text = p.text.trim();
      if (text.startsWith('作者：') || text.startsWith('作者:')) {
        author = text.replaceFirst(RegExp(r'^作者[：:]'), '').trim();
      } else if (text.startsWith('状态：') || text.startsWith('状态:') ||
                 text.startsWith('狀態：') || text.startsWith('狀態:')) {
        if (text.contains('完结') || text.contains('完結')) {
          status = MangaStatus.completed;
        } else if (text.contains('连载') || text.contains('連載')) {
          status = MangaStatus.ongoing;
        }
      } else if (text.startsWith('标签：') || text.startsWith('标签:') ||
                 text.startsWith('標籤：') || text.startsWith('標籤:')) {
        final tagText = text.replaceFirst(RegExp(r'^(标签|標籤)[：:]'), '').trim();
        tags = tagText.split(RegExp(r'[,，、\s]+'))
            .where((t) => t.isNotEmpty)
            .toList();
      } else if (!text.startsWith('地区') && !text.startsWith('地區') &&
                 !text.startsWith('浏览') && !text.startsWith('瀏覽') &&
                 text.length > 20) {
        // Long text not matching known prefixes is likely the description
        description ??= text;
      }
    }

    // Also check for description in a dedicated section below metadata
    if (description == null) {
      final descEl = document.querySelector('.mt-4 p.text-sm.text-gray-700');
      description = descEl?.text.trim();
    }

    // Cover URL
    final coverUrl = '$_imageCdn/$mangaId/cover.jpg';

    // Chapters — extract from all <a href="/chapter/{id}"> links
    final chapterLinks = document.querySelectorAll('a[href^="/chapter/"]');
    final chapters = <ChapterItem>[];
    final seenChapterIds = <String>{};

    for (final link in chapterLinks) {
      final chapterHref = link.attributes['href'] ?? '';
      final chapterMatch = RegExp(r'/chapter/(\d+)').firstMatch(chapterHref);
      if (chapterMatch == null) continue;

      final chapterId = chapterMatch.group(1)!;
      if (seenChapterIds.contains(chapterId)) continue;
      seenChapterIds.add(chapterId);

      final chapterTitle = link.text.trim();
      if (chapterTitle.isEmpty) continue;

      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: chapterTitle,
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
      chapters: chapters,
      headers: defaultHeaders,
    );
  }
```

- [ ] **Step 3: Verify with curl that /book/{id} HTML has expected structure**

Run: `curl -s 'https://ikanmanhua.org/book/887' -H 'User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X)' | grep -c 'href="/chapter/'`

Expected: A number > 0 (chapter links present).

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze lib/data/sources/ikan_manhua.dart`

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/ikan_manhua.dart
git commit -m "feat(ikanmanhua): implement manga info and chapter list parsing"
```

---

### Task 5: Chapter Content — prepareChapterFetch and parseChapter

**Files:**
- Modify: `lib/data/sources/ikan_manhua.dart`

**Interfaces:**
- Consumes: `Chapter`, `ChapterImage`, `ChapterResult` from entities
- Produces: `prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra}) → FetchConfig` and `parseChapter(dynamic response, String mangaId, String chapterId, int page) → ChapterResult`

- [ ] **Step 1: Implement prepareChapterFetch**

Replace the `prepareChapterFetch` method:

```dart
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/chapter/$chapterId',
      headers: defaultHeaders,
    );
  }
```

- [ ] **Step 2: Implement parseChapter**

Replace the `parseChapter` method:

```dart
  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final html = response as String;
    final document = html_parser.parse(html);

    // Chapter title from the subtitle element
    final title =
        document.querySelector('p.text-lg.text-gray-700')?.text.trim() ??
            document.querySelector('h1')?.text.trim() ??
            '第?話';

    // Extract all chapter images from img tags pointing to the CDN
    final imgElements = document.querySelectorAll('img[src*="jjmh.cc"]');
    final images = <ChapterImage>[];

    for (final img in imgElements) {
      final src = img.attributes['src'];
      if (src == null || src.isEmpty) continue;
      // Skip cover images (they contain /cover.jpg)
      if (src.contains('/cover.jpg')) continue;
      images.add(ChapterImage(url: src, headers: defaultHeaders));
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: defaultHeaders,
      ),
    );
  }
```

- [ ] **Step 3: Verify with curl that /chapter/{id} HTML contains images**

Run: `curl -s 'https://ikanmanhua.org/chapter/38236' -H 'User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X)' | grep -c 'jjmh.cc'`

Expected: A number > 0 (image URLs present).

- [ ] **Step 4: Run full static analysis on the completed source**

Run: `flutter analyze lib/data/sources/ikan_manhua.dart`

Expected: No errors, no warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/ikan_manhua.dart
git commit -m "feat(ikanmanhua): implement chapter image parsing - source complete"
```

---

### Task 6: Final Verification and Cleanup

**Files:**
- Review: `lib/data/sources/ikan_manhua.dart` (remove any leftover TODOs)
- Review: `lib/app/di/injection.dart` (confirm registration)

**Interfaces:**
- Consumes: Full source implementation from Tasks 1-5
- Produces: Verified, clean, analysis-passing source ready for use

- [ ] **Step 1: Remove all TODO comments from the source file**

Search for any remaining `// TODO` comments in `lib/data/sources/ikan_manhua.dart` and remove them. The file should have no placeholder code.

- [ ] **Step 2: Run full project analysis**

Run: `flutter analyze`

Expected: No new errors introduced by our source. Existing warnings in other files are acceptable.

- [ ] **Step 3: Verify the complete source file looks clean**

Read through `lib/data/sources/ikan_manhua.dart` and confirm:
- No `UnimplementedError()` throws remain
- All methods have real implementations
- Import statements are minimal and correct
- Code formatting follows project style

- [ ] **Step 4: Test image CDN accessibility**

Run: `curl -sI 'https://www.jjmh.cc/static/upload/book/887/cover.jpg' | head -5`

Expected: HTTP 200 response, confirming image CDN is accessible without special auth.

- [ ] **Step 5: Final commit (if any cleanup was needed)**

```bash
git add lib/data/sources/ikan_manhua.dart
git commit -m "chore(ikanmanhua): cleanup and final verification"
```
