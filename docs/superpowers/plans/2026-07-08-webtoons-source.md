# Webtoons (zh-hant) Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `WebtoonsSource` (www.webtoons.com/zh-hant) as a new manga data source plugin that discovers, searches, and reads officially serialized WEBTOON titles.

**Architecture:** A single `MangaSource` subclass in `lib/data/sources/webtoons.dart`, registered manually in `lib/app/di/injection.dart`. It reuses `dongmanmanhua.dart`'s architecture: instance-level `_pathCache` (titleNo → canonical `genreSlug/titleSlug`), mangaId encoding `"{titleNo}::{path}"`, and forced chapter pagination through the list endpoint. The canonical path is resolved lazily from `<link rel="canonical">` during manga-info / chapter-list parsing and reused for pagination and viewer requests.

**Tech Stack:** Dart, Flutter, `html` package (`html_parser`), the repo's Prepare/Parse source-plugin contract.

## Global Constraints

- Source file: `lib/data/sources/webtoons.dart`; class `WebtoonsSource extends MangaSource`.
- Registration: `lib/app/di/injection.dart` via `registry.register(WebtoonsSource())`.
- Verification is `flutter analyze` only — this repo has NO unit-test convention for sources (confirmed: no `test/**/*source*` files). Do NOT write unit tests; the per-task test cycle is `flutter analyze lib/data/sources/webtoons.dart` (must report "No issues found").
- `id` = `webtoons`, `name` = `Webtoons`, `shortName` = `Webtoons`, `description` = `webtoons.com (繁體中文)`, `href` = `https://www.webtoons.com/zh-hant`, `isAdult` = `false`, `needsProxy` = `false`, `needsCloudflare` = `false`.
- baseUrl constant = `https://www.webtoons.com/zh-hant`.
- Desktop Chrome UA constant: `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36`.
- `defaultHeaders` = `{'User-Agent': ua, 'Referer': '$baseUrl/'}`.
- All chapter/cover images MUST carry `headers: {'Referer': 'https://www.webtoons.com/'}` (CDN 403s otherwise).
- Do NOT commit the unrelated pre-existing dirty files (`manga18_club.dart`, `nhentai.dart`, `Release.entitlements`, `pubspec.lock`, `web/index.html`). Stage only `lib/data/sources/webtoons.dart` and `lib/app/di/injection.dart`.

## Key Framework Constraint (already investigated)

`prepare*Fetch()` is synchronous and does NO network I/O (verified in `manga_repository_impl.dart`). The viewer's canonical path therefore cannot be probed inside `prepareChapterFetch`. This is fine because the normal navigation flow guarantees the cache is warm:

- `detail_cubit.dart:67` calls `getChapterList(...)` when the detail screen loads, which runs `parseChapterList` and writes `_pathCache[titleNo]`.
- The reader is only reachable from the detail screen (`detail_screen.dart:337` uses `cubit.mangaId`, i.e. the plain `titleNo`), which is always visited after the chapter list has loaded. Since the source is a singleton, `_pathCache[titleNo]` is populated by the time `prepareChapterFetch` runs.
- Consequence: `prepareChapterFetch` resolves the path via `_pathOf(mangaId)` (which falls back to `_pathCache[titleNo]`). No async probe is needed. If — in an unforeseen cold-start path — the cache misses, the viewer request falls back to the generic list URL's canonical redirect being unavailable; we accept an empty/failed chapter in that rare case rather than adding an async probe (YAGNI). This is documented in code comments.

---

## Task 1: Source skeleton, identity, and headers

**Files:**
- Create: `lib/data/sources/webtoons.dart`

**Interfaces:**
- Consumes: `MangaSource` (abstract) from `lib/data/sources/manga_source.dart`; entities from `domain/entities/manga.dart`, `domain/entities/chapter.dart`.
- Produces: `class WebtoonsSource extends MangaSource` with constants `sourceId`, `_baseUrl`, `_userAgent` and identity getters, consumed by all later tasks and by `injection.dart` (Task 7).

- [ ] **Step 1: Create the file with imports, class, constants, and identity getters**

```dart
import 'package:html/parser.dart' as html_parser;
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/manga.dart';
import 'package:comic_reader/domain/entities/chapter.dart';

/// Webtoons (www.webtoons.com/zh-hant) — LINE Webtoon 繁體中文站。
///
/// 与咚漫漫画 (dongmanmanhua) 同一套模板，复用其架构：
/// - _pathCache 缓存 titleNo -> '{genre-slug}/{title-slug}' 规范路径。
/// - mangaId 编码为 '{titleNo}::{path}' 以在分页/viewer 保留真实路径。
/// - 章节列表强制走分页接口（详情页只内嵌部分章节）。
///
/// 与 dongmanmanhua 的关键差异：
/// - 详情/章节列表页的通用占位路径 301 会丢弃 page 参数（同 dongmanmanhua 坑）。
/// - viewer 的通用占位路径返回 500（dongmanmanhua 可用），故 viewer 必须用
///   规范路径。正常导航流程（详情页先加载章节列表）保证 _pathCache 已填充。
/// - 图片 CDN 需 Referer 头，否则 403。
class WebtoonsSource extends MangaSource {
  static const String sourceId = 'webtoons';
  static const String _baseUrl = 'https://www.webtoons.com/zh-hant';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  @override
  String get id => sourceId;

  @override
  String get name => 'Webtoons';

  @override
  String get shortName => 'Webtoons';

  @override
  String? get description => 'webtoons.com (繁體中文)';

  @override
  double get score => 4.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => false;

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;

  @override
  String? get userAgent => _userAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/',
      };
}
```

- [ ] **Step 2: Run analyze to verify it fails (abstract methods not implemented)**

Run: `flutter analyze lib/data/sources/webtoons.dart`
Expected: FAIL — errors like "Missing concrete implementations of 'MangaSource.prepareDiscoveryFetch'", etc. (This confirms the class is wired to the base contract; the missing methods are added in later tasks.)

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/webtoons.dart
git commit -m "feat(webtoons): add source skeleton and identity"
```

---

## Task 2: Path-cache helpers and canonical extraction

**Files:**
- Modify: `lib/data/sources/webtoons.dart`

**Interfaces:**
- Consumes: class body from Task 1.
- Produces: `final Map<String,String> _pathCache`; `String _titleNoOf(String mangaId)`; `String? _pathOf(String mangaId)`; `String _listUrl(String mangaId)`; `String? _canonicalPath(dynamic document)`. All consumed by Tasks 5, 6.

- [ ] **Step 1: Add helper fields and methods inside the class**

```dart
  /// 缓存 titleNo -> '{genre-slug}/{title-slug}' 规范路径。
  /// 详情/章节列表页 301 到规范路径并丢弃 page 参数，分页必须直接请求规范路径。
  /// 源为单例，parseMangaInfo/parseChapterList 解析到 canonical 后写入此缓存。
  final Map<String, String> _pathCache = {};

  /// mangaId 可能编码为 '{titleNo}::{genre-slug}/{title-slug}'。返回 titleNo。
  String _titleNoOf(String mangaId) {
    final i = mangaId.indexOf('::');
    return i >= 0 ? mangaId.substring(0, i) : mangaId;
  }

  /// 返回编码在 mangaId 中的 '{genre-slug}/{title-slug}' 路径，
  /// 其次查缓存，未知则 null。
  String? _pathOf(String mangaId) {
    final i = mangaId.indexOf('::');
    if (i >= 0) return mangaId.substring(i + 2);
    return _pathCache[_titleNoOf(mangaId)];
  }

  /// 构建 list 页 URL。已知规范路径时用它（分页 page 参数才不会被 301 丢弃）；
  /// 否则用 /comic/{titleNo}/list（服务器 301 到规范路径，仅第 1 页可靠）。
  String _listUrl(String mangaId) {
    final path = _pathOf(mangaId);
    if (path != null && path.isNotEmpty) {
      return '$_baseUrl/$path/list';
    }
    return '$_baseUrl/comic/${_titleNoOf(mangaId)}/list';
  }

  /// 从页面 <link rel="canonical"> 提取 '{genre-slug}/{title-slug}'，失败返回 null。
  /// webtoons.com 的 slug 段含连字符和 CJK 字符，故用宽松字符类。
  String? _canonicalPath(dynamic document) {
    final el = document.querySelector('link[rel="canonical"]');
    final href = el?.attributes['href'] ?? '';
    final m = RegExp(r'webtoons\.com/zh-hant/([^/?]+/[^/?]+)/list')
        .firstMatch(href);
    return m?.group(1);
  }
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/data/sources/webtoons.dart`
Expected: Still FAILS on missing abstract methods, but NO new errors about the helper code itself (no undefined names, no type errors). Confirm the only remaining errors are the "Missing concrete implementations" ones.

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/webtoons.dart
git commit -m "feat(webtoons): add path-cache helpers and canonical extraction"
```

---

## Task 3: Discovery (filters, fetch, parse)

**Files:**
- Modify: `lib/data/sources/webtoons.dart`

**Interfaces:**
- Consumes: identity/headers from Task 1.
- Produces: `discoveryFilters`, `prepareDiscoveryFetch`, `parseDiscovery`; plus instance fields `_pendingDiscoveryPage`; and a shared card-parser `List<MangaSummary> _parseListCards(dynamic document, String cardSelector)` reused by Task 4.

- [ ] **Step 1: Add discovery filters, pending-page field, fetch, parse, and shared card parser**

```dart
  // --- Discovery ---

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'genre',
          label: '分類',
          defaultValue: 'ACTION',
          choices: [
            FilterChoice(label: '愛情', value: 'ROMANCE'),
            FilterChoice(label: '歐式宮廷', value: 'WESTERN_PALACE'),
            FilterChoice(label: '影視化', value: 'ADAPTATION'),
            FilterChoice(label: '校園', value: 'SCHOOL'),
            FilterChoice(label: '台灣原創作品', value: 'LOCAL'),
            FilterChoice(label: '奇幻冒險', value: 'FANTASY'),
            FilterChoice(label: '驚悚', value: 'THRILLER'),
            FilterChoice(label: '恐怖', value: 'HORROR'),
            FilterChoice(label: '武俠', value: 'MARTIAL_ARTS'),
            FilterChoice(label: 'LGBTQ+', value: 'BL_GL'),
            FilterChoice(label: '大人系', value: 'ROMANCE_M'),
            FilterChoice(label: '劇情', value: 'DRAMA'),
            FilterChoice(label: '動作', value: 'ACTION'),
            FilterChoice(label: '生活/日常', value: 'SLICE_OF_LIFE'),
            FilterChoice(label: '搞笑', value: 'COMEDY'),
            FilterChoice(label: '穿越/轉生', value: 'TIME_SLIP'),
            FilterChoice(label: '現代/職場', value: 'CITY_OFFICE'),
            FilterChoice(label: '懸疑推理', value: 'MYSTERY'),
            FilterChoice(label: '療癒/萌系', value: 'HEARTWARMING'),
            FilterChoice(label: '少年', value: 'SHONEN'),
            FilterChoice(label: '古代宮廷', value: 'EASTERN_PALACE'),
            FilterChoice(label: '小說', value: 'WEB_NOVEL'),
          ],
        ),
        FilterOption(
          name: 'sortOrder',
          label: '排序',
          defaultValue: 'UPDATE',
          choices: [
            FilterChoice(label: '最近更新', value: 'UPDATE'),
            FilterChoice(label: '人氣排序', value: 'MANA'),
            FilterChoice(label: '愛心排序', value: 'LIKEIT'),
          ],
        ),
      ];

  /// 记录最近一次发现请求的页码（parseDiscovery 不接收 page，源为单例故用字段传递）。
  int _pendingDiscoveryPage = 1;

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    _pendingDiscoveryPage = page;
    final genre = (filters['genre'] ?? 'ACTION').toLowerCase();
    final sortOrder = filters['sortOrder'] ?? 'UPDATE';
    return FetchConfig(
      url: '$_baseUrl/genres/$genre',
      queryParameters: {
        'sortOrder': sortOrder,
        'page': page.toString(),
      },
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final document = html_parser.parse(response as String);
    return _parseListCards(
        document, 'ul.webtoon_list > li > a.link._genre_title_a[data-title-no]');
  }

  /// 解析列表卡片（发现页与搜索页结构一致）。
  /// cardSelector 命中的锚点元素含 data-title-no，内部 img + .info_text .title/.author。
  List<MangaSummary> _parseListCards(dynamic document, String cardSelector) {
    final cards = document.querySelectorAll(cardSelector);
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final card in cards) {
      final titleNo = card.attributes['data-title-no'] ?? '';
      if (titleNo.isEmpty || seen.contains(titleNo)) continue;

      final titleEl = card.querySelector('.info_text .title') ??
          card.querySelector('.title');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;

      seen.add(titleNo);

      final imgEl = card.querySelector('img');
      final coverUrl =
          imgEl?.attributes['src'] ?? imgEl?.attributes['data-url'] ?? '';

      final authorEl = card.querySelector('.info_text .author') ??
          card.querySelector('.author');
      final author = authorEl?.text.trim() ?? '';

      results.add(MangaSummary(
        id: titleNo,
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

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/data/sources/webtoons.dart`
Expected: Still FAILS only on the remaining unimplemented abstract methods (search, manga info, chapter list, chapter). NO errors in the discovery code. `_pendingDiscoveryPage` will trigger an "unused field" info/warning — acceptable for now; it is read in a later refinement is NOT planned, so if analyze flags it as a warning, remove the field and the `_pendingDiscoveryPage = page;` line in this same step before committing (the genre listing has real pagination; the framework stops when `parseDiscovery` returns an empty list, so the field is not needed). Re-run analyze after removal to confirm clean of that warning.

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/webtoons.dart
git commit -m "feat(webtoons): implement discovery listing and filters"
```

---

## Task 4: Search (fetch, parse)

**Files:**
- Modify: `lib/data/sources/webtoons.dart`

**Interfaces:**
- Consumes: `_parseListCards` from Task 3, headers from Task 1.
- Produces: `prepareSearchFetch`, `parseSearch`.

- [ ] **Step 1: Add search fetch and parse**

```dart
  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search',
      queryParameters: {'keyword': keyword},
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final document = html_parser.parse(response as String);
    // 只解析官方 WEBTOON 作品，忽略 CANVAS 同人作品。
    return _parseListCards(
        document, 'a.link._card_item[data-webtoon-type="WEBTOON"]');
  }
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/data/sources/webtoons.dart`
Expected: Still FAILS only on the remaining unimplemented abstract methods (manga info, chapter list, chapter). NO errors in the search code.

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/webtoons.dart
git commit -m "feat(webtoons): implement search (WEBTOON only)"
```

---

## Task 5: Manga info (fetch, parse) + canonical caching

**Files:**
- Modify: `lib/data/sources/webtoons.dart`

**Interfaces:**
- Consumes: `_titleNoOf`, `_pathOf`, `_listUrl`, `_canonicalPath`, `_pathCache` from Task 2; headers from Task 1.
- Produces: `prepareMangaInfoFetch`, `parseMangaInfo` returning `MangaDetail` with encoded id `"{titleNo}::{path}"` and `chapters: const []`.

- [ ] **Step 1: Add manga-info fetch and parse**

```dart
  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: _listUrl(mangaId),
      queryParameters: {'title_no': _titleNoOf(mangaId)},
      headers: defaultHeaders,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final html = response as String;
    final document = html_parser.parse(html);

    final titleNo = _titleNoOf(mangaId);
    final canonical = _canonicalPath(document);
    if (canonical != null) {
      _pathCache[titleNo] = canonical;
    }
    final encodedId = canonical != null ? '$titleNo::$canonical' : titleNo;

    // 标题
    String title = document.querySelector('h1.subj')?.text.trim() ?? '';
    if (title.isEmpty) {
      final pageTitle = document.querySelector('title')?.text ?? '';
      title = pageTitle.split('-').first.trim();
    }

    // 封面
    final coverEl = document.querySelector('.detail_header .thmb img') ??
        document.querySelector('.detail_header img');
    final coverUrl = coverEl?.attributes['src'] ??
        coverEl?.attributes['data-url'] ??
        '';

    // 分类/tags: h2.genre 文本空格分隔
    final genreEl = document.querySelector('h2.genre');
    final tags = <String>[];
    if (genreEl != null) {
      for (final t in genreEl.text.trim().split(RegExp(r'\s+'))) {
        if (t.isNotEmpty) tags.add(t);
      }
    }

    // 作者: .author_area 文本，去除内嵌 <button>'作家資訊' / <a> 文字
    String author = '';
    final authorEl = document.querySelector('.author_area');
    if (authorEl != null) {
      author = authorEl.text.trim();
      for (final child in authorEl.querySelectorAll('button')) {
        author = author.replaceAll(child.text.trim(), '');
      }
      for (final child in authorEl.querySelectorAll('a')) {
        author = author.replaceAll(child.text.trim(), '');
      }
      author = author.trim();
    }

    // 简介: 详情页摘要块（若无可靠选择器则留 null）
    final description = document.querySelector('.detail_body .summary')?.text
            .trim() ??
        document.querySelector('p.summary')?.text.trim();

    // 状态: 默认 ongoing，除非页面明确标注完结
    MangaStatus status = MangaStatus.ongoing;
    final statusMatch = RegExp(r'serial_status:(\w+)').firstMatch(html);
    if (statusMatch != null) {
      final s = statusMatch.group(1)!.toUpperCase();
      if (s.contains('COMPLET') || s.contains('END') || s.contains('FINISH')) {
        status = MangaStatus.completed;
      }
    }

    // 章节列表强制走分页接口（详情页只内嵌部分章节，会导致误判无更多章节）。
    return MangaDetail(
      id: encodedId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: tags,
      status: status,
      chapters: const [],
      headers: defaultHeaders,
    );
  }
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/data/sources/webtoons.dart`
Expected: Still FAILS only on the remaining unimplemented abstract methods (chapter list, chapter). NO errors in manga-info code.

- [ ] **Step 3: Commit**

```bash
git add lib/data/sources/webtoons.dart
git commit -m "feat(webtoons): implement manga info with canonical path caching"
```

---

## Task 6: Chapter list + chapter content (viewer) + web url

**Files:**
- Modify: `lib/data/sources/webtoons.dart`

**Interfaces:**
- Consumes: `_titleNoOf`, `_pathOf`, `_listUrl`, `_canonicalPath`, `_pathCache` from Task 2; headers from Task 1.
- Produces: `prepareChapterListFetch`, `parseChapterList`, `_parseChapterItems`, `prepareChapterFetch`, `parseChapter`, `getChapterWebUrl`. Completes all abstract methods.

- [ ] **Step 1: Add chapter list**

```dart
  // --- Chapter List ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    return FetchConfig(
      url: _listUrl(mangaId),
      queryParameters: {
        'title_no': _titleNoOf(mangaId),
        'page': page.toString(),
      },
      headers: defaultHeaders,
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final document = html_parser.parse(response as String);

    // 缓存规范路径（供后续分页/viewer 请求构建正确 URL）
    final canonical = _canonicalPath(document);
    if (canonical != null) {
      _pathCache[_titleNoOf(mangaId)] = canonical;
    }

    final chapters = _parseChapterItems(document, mangaId);

    int maxPage = 1;
    int currentPage = 1;
    final paginate = document.querySelector('div.paginate');
    if (paginate != null) {
      final onEl =
          paginate.querySelector('.on') ?? paginate.querySelector('span.on');
      final curVal = int.tryParse(onEl?.text.trim() ?? '');
      if (curVal != null) currentPage = curVal;

      for (final a in paginate.querySelectorAll('a[href*="page="]')) {
        final m = RegExp(r'page=(\d+)').firstMatch(a.attributes['href'] ?? '');
        if (m != null) {
          final p = int.tryParse(m.group(1)!) ?? 1;
          if (p > maxPage) maxPage = p;
        }
      }
    }
    if (currentPage > maxPage) maxPage = currentPage;

    final canLoadMore = chapters.isNotEmpty && currentPage < maxPage;

    return ChapterListResult(
      chapters: chapters,
      canLoadMore: canLoadMore,
      nextPage: canLoadMore ? currentPage + 1 : null,
    );
  }

  /// 解析章节列表: ul#_listUl li[data-episode-no]
  List<ChapterItem> _parseChapterItems(dynamic document, String mangaId) {
    final items = document.querySelectorAll('ul#_listUl li[data-episode-no]');
    final chapters = <ChapterItem>[];
    final seen = <String>{};

    for (final li in items) {
      var episodeNo = li.attributes['data-episode-no'] ?? '';
      if (episodeNo.isEmpty) {
        final a = li.querySelector('a[href*="episode_no="]');
        final m = RegExp(r'episode_no=(\d+)')
            .firstMatch(a?.attributes['href'] ?? '');
        episodeNo = m?.group(1) ?? '';
      }
      if (episodeNo.isEmpty || seen.contains(episodeNo)) continue;
      seen.add(episodeNo);

      final subjEl = li.querySelector('span.subj span') ??
          li.querySelector('.subj span') ??
          li.querySelector('.subj');
      var chapterTitle = subjEl?.text.trim() ?? '';
      if (chapterTitle.isEmpty) chapterTitle = '第 $episodeNo 話';

      chapters.add(ChapterItem(
        id: episodeNo,
        mangaId: mangaId,
        title: chapterTitle,
      ));
    }

    return chapters;
  }
```

- [ ] **Step 2: Add chapter content (viewer) and web url**

```dart
  // --- Chapter Content ---

  /// 构建 viewer URL。webtoons 的通用占位 viewer 路径返回 500，故必须用规范路径。
  /// 正常流程（详情页先加载章节列表）保证 _pathCache 已填充；
  /// 缓存未命中时退回通用路径（该章节可能失败并显示为空，属可接受的极端兜底）。
  String _viewerUrl(String mangaId) {
    final path = _pathOf(mangaId);
    if (path != null && path.isNotEmpty) {
      return '$_baseUrl/$path/x/viewer';
    }
    return '$_baseUrl/comic/${_titleNoOf(mangaId)}/ep/viewer';
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    final titleNo = _titleNoOf(mangaId);
    return FetchConfig(
      url: _viewerUrl(mangaId),
      queryParameters: {
        'title_no': titleNo,
        'episode_no': chapterId,
      },
      headers: defaultHeaders,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final document = html_parser.parse(response as String);

    String title = '第 $chapterId 話';
    final pageTitle = document.querySelector('title')?.text ?? '';
    if (pageTitle.contains(' - ')) {
      final part = pageTitle.split(' - ').first.trim();
      if (part.isNotEmpty) title = part;
    }

    // 图片: #_imageList img._images 的 data-url（优先）/ src。
    // 图片 CDN 需 Referer 头。付费墙章节可能解析到 0 张图 —— 返回空 images 不报错。
    final imgElements = document.querySelectorAll('#_imageList img._images');
    final images = <ChapterImage>[];
    const imageHeaders = {'Referer': 'https://www.webtoons.com/'};

    for (final img in imgElements) {
      final url = img.attributes['data-url'] ?? img.attributes['src'];
      if (url == null || url.isEmpty) continue;
      if (url.contains('bg_transparency')) continue;
      images.add(ChapterImage(url: url, headers: imageHeaders));
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

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    final titleNo = _titleNoOf(mangaId);
    return '${_viewerUrl(mangaId)}?title_no=$titleNo&episode_no=$chapterId';
  }
```

- [ ] **Step 3: Run analyze — now must be fully clean**

Run: `flutter analyze lib/data/sources/webtoons.dart`
Expected: PASS — "No issues found!" (all abstract methods implemented, no undefined names, no type errors). If `imageHeaders` const map type doesn't match `ChapterImage.headers` expected type, change `const imageHeaders = {...}` to `const Map<String, String> imageHeaders = {...}` and re-run.

- [ ] **Step 4: Commit**

```bash
git add lib/data/sources/webtoons.dart
git commit -m "feat(webtoons): implement chapter list and viewer"
```

---

## Task 7: Register the source and verify whole project

**Files:**
- Modify: `lib/app/di/injection.dart`

**Interfaces:**
- Consumes: `WebtoonsSource` from Task 1-6.
- Produces: a registered source in the `SourceRegistry`.

- [ ] **Step 1: Read the registration file to find the import block and register calls**

Run: `rtk read lib/app/di/injection.dart`
Locate the block of `import '...dongmanmanhua.dart';` style imports and the block of `registry.register(...)` calls.

- [ ] **Step 2: Add the import**

Add alongside the other source imports (alphabetical/adjacent to dongmanmanhua is fine):

```dart
import 'package:comic_reader/data/sources/webtoons.dart';
```

- [ ] **Step 3: Add the registration**

Add alongside the other `registry.register(...)` calls:

```dart
  registry.register(WebtoonsSource());
```

- [ ] **Step 4: Run analyze on the DI file and the source together**

Run: `flutter analyze lib/app/di/injection.dart lib/data/sources/webtoons.dart`
Expected: PASS — "No issues found!"

- [ ] **Step 5: Run full-project analyze to confirm no regressions**

Run: `flutter analyze`
Expected: No NEW issues attributable to `webtoons.dart` or the registration. (Pre-existing warnings in unrelated dirty files may appear; they are not introduced by this change.)

- [ ] **Step 6: Commit**

```bash
git add lib/app/di/injection.dart
git commit -m "feat(webtoons): register WebtoonsSource in DI"
```

---

## Self-Review

**Spec coverage:**
- Identity/headers → Task 1 ✓
- mangaId encoding + `_pathCache` + `_resolvePath` behavior → Task 2 (path helpers) + framework-constraint note (async probe intentionally omitted; cache-warm guarantee documented) ✓
- Discovery default ACTION/UPDATE + 22 genres + 3 sort orders + real pagination → Task 3 ✓
- Search WEBTOON-only, CANVAS excluded → Task 4 ✓
- Manga info selectors (h1.subj, .detail_header .thmb img, h2.genre, .author_area button strip), chapters=[], canonical caching → Task 5 ✓
- Chapter list (`ul#_listUl li[data-episode-no]`, `第N話` fallback, div.paginate pagination) → Task 6 Step 1 ✓
- Viewer (`#_imageList img._images`, data-url/src, bg_transparency skip, Referer image headers, empty-image degradation), getChapterWebUrl → Task 6 Step 2 ✓
- Registration → Task 7 ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases" without code. Every code step shows full code.

**Type consistency:** `_titleNoOf`/`_pathOf`/`_listUrl`/`_canonicalPath`/`_viewerUrl`/`_parseListCards`/`_parseChapterItems` names are used identically across tasks. `MangaSummary`/`MangaDetail`/`ChapterItem`/`ChapterImage`/`Chapter`/`ChapterResult`/`ChapterListResult`/`FetchConfig`/`FilterOption`/`FilterChoice`/`MangaStatus` match the base contract confirmed from `dongmanmanhua.dart`.

**Deviation noted:** The spec's `_resolvePath` async probe is intentionally NOT implemented (framework `prepare*Fetch` is synchronous, no network I/O possible). Instead, the cache-warm guarantee (detail screen always loads chapter list before reader) makes the path available; `_viewerUrl` falls back to the generic path only in an unreachable-in-practice cold path. This is a simplification that preserves all observable behavior and is documented in code comments.
