# Mmero Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Mmero as an adult JSON API source with catalog browsing, search, comic details, and in-app chapter image reading.

**Architecture:** A new `MmeroSource` implements the existing `MangaSource` prepare/parse contract. It requests Mmero's JSON APIs through `FetchConfig`, maps detail-embedded chapters directly, and generates direct CDN image URLs from the chapter page count. Manual dependency injection registers the new source.

**Tech Stack:** Flutter, Dart, `flutter_test`, Dio-backed `FetchConfig`, existing domain entities.

---

## File Structure

- Create: `lib/data/sources/mmero.dart` - Mmero metadata, filters, API request builders, JSON parsers, and image URL generation.
- Create: `test/data/sources/mmero_test.dart` - Unit coverage for metadata, request builders, JSON mappings, and ordered image URLs.
- Modify: `lib/app/di/injection.dart` - Import and register `MmeroSource`.
- Modify: `docs/superpowers/specs/2026-07-18-mmero-source-design.md` - No changes expected during implementation; revise only if verified site behavior contradicts the approved design.

### Task 1: Define Mmero Source Tests

**Files:**
- Create: `test/data/sources/mmero_test.dart`

- [ ] **Step 1: Add the failing source tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/mmero.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() {
  late MmeroSource source;

  setUp(() {
    source = MmeroSource();
  });

  group('MmeroSource metadata and request builders', () {
    test('declares an adult Mmero source with catalog filters', () {
      expect(source.id, 'mmero');
      expect(source.name, '摸摸漫画');
      expect(source.shortName, 'MM');
      expect(source.isAdult, isTrue);
      expect(source.discoveryFilters.map((filter) => filter.name), [
        'channel',
        'status',
      ]);
    });

    test('builds a filtered catalog request', () {
      final config = source.prepareDiscoveryFetch(2, {
        'channel': '2',
        'status': 'completed',
      });

      expect(config.url, 'https://mmero.com/api/comic/items');
      expect(config.queryParameters, {
        'pageNo': 2,
        'pageSize': 30,
        'channel': 2,
        'isEnded': true,
      });
    });

    test('builds an unfiltered catalog request without optional values', () {
      final config = source.prepareDiscoveryFetch(1, const {});

      expect(config.queryParameters, {
        'pageNo': 1,
        'pageSize': 30,
      });
    });

    test('builds a comic search request', () {
      final config = source.prepareSearchFetch('谷口大介', 3, const {});

      expect(config.url, 'https://mmero.com/api/comic/search');
      expect(config.queryParameters, {
        'keyword': '谷口大介',
        'pageNo': 3,
        'pageSize': 30,
        'type': 1,
      });
    });

    test('builds JSON POST requests for detail and chapter content', () {
      final detail = source.prepareMangaInfoFetch('51118');
      final chapter = source.prepareChapterFetch('51118', '1', 1);

      expect(detail.url, 'https://mmero.com/api/comic/content');
      expect(detail.method, HttpMethod.post);
      expect(detail.body, {'id': 51118});
      expect(chapter.url, 'https://mmero.com/api/comic/chapter');
      expect(chapter.method, HttpMethod.post);
      expect(chapter.body, {'id': 51118, 'chapter': 1});
      expect(source.getChapterWebUrl('51118', '1'),
          'https://mmero.com/comics/51118/1');
    });
  });

  group('MmeroSource response parsing', () {
    test('maps catalog items and derives the cover URL', () {
      final results = source.parseDiscovery({
        'items': [
          {
            'id': 51118,
            'title': '测试漫画',
            'chapter': 3,
          },
        ],
        'page': 1,
        'size': 30,
        'total': 1,
      });

      expect(results, hasLength(1));
      expect(results.single.id, '51118');
      expect(results.single.sourceId, 'mmero');
      expect(results.single.title, '测试漫画');
      expect(results.single.coverUrl,
          'https://cover.2thewash.com/comic/51118/cover.jpg');
      expect(results.single.latestChapter, '第3话');
    });

    test('maps detail metadata, tags, status, and embedded chapters', () {
      final detail = source.parseMangaInfo({
        'id': 51118,
        'title': '测试漫画',
        'author': '测试作者',
        'desc': '测试简介',
        'isEnded': true,
        'tags': [
          {'id': 12, 'name': '后宫'},
          {'id': 25, 'name': '巨乳'},
        ],
        'chapters': [
          {'number': 1, 'title': '第1话', 'pages': 63},
          {'number': 2, 'title': '第2话', 'pages': 40},
        ],
      }, '51118');

      expect(detail.author, '测试作者');
      expect(detail.description, '测试简介');
      expect(detail.status, MangaStatus.completed);
      expect(detail.tags, ['后宫', '巨乳']);
      expect(detail.coverUrl,
          'https://cover.2thewash.com/comic/51118/cover.jpg');
      expect(detail.chapters.map((chapter) => chapter.id), ['1', '2']);
      expect(detail.chapters.map((chapter) => chapter.mangaId),
          ['51118', '51118']);
    });

    test('generates one ordered direct image URL for every chapter page', () {
      final result = source.parseChapter({
        'number': 1,
        'title': '第1话',
        'pages': 3,
        'hadPrevious': false,
        'hadNext': false,
      }, '51118', '1', 1);

      expect(result.canLoadMore, isFalse);
      expect(result.chapter.title, '第1话');
      expect(result.chapter.images.map((image) => image.url), [
        'https://c2.2thewash.com/comic/51118/1/1.jpg',
        'https://c2.2thewash.com/comic/51118/1/2.jpg',
        'https://c2.2thewash.com/comic/51118/1/3.jpg',
      ]);
    });

    test('does not invent image URLs when the chapter page count is absent', () {
      final result = source.parseChapter({'title': '第1话'}, '51118', '1', 1);

      expect(result.chapter.images, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the focused test to verify the missing source fails**

Run: `flutter test test/data/sources/mmero_test.dart`

Expected: FAIL because `lib/data/sources/mmero.dart` does not exist.

### Task 2: Implement the JSON API Source

**Files:**
- Create: `lib/data/sources/mmero.dart`
- Test: `test/data/sources/mmero_test.dart`

- [ ] **Step 1: Add the minimal source implementation**

```dart
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class MmeroSource extends MangaSource {
  static const sourceId = 'mmero';
  static const _baseUrl = 'https://mmero.com';
  static const _coverBaseUrl = 'https://cover.2thewash.com';
  static const _imageBaseUrl = 'https://c2.2thewash.com';
  static const _pageSize = 30;

  @override
  String get id => sourceId;

  @override
  String get name => '摸摸漫画';

  @override
  String get shortName => 'MM';

  @override
  String? get description => '成人漫画';

  @override
  double get score => 3.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => true;

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'channel',
          label: '频道',
          defaultValue: 'all',
          choices: [
            FilterChoice(label: '全部', value: 'all'),
            FilterChoice(label: '韩漫', value: '1'),
            FilterChoice(label: '同人志', value: '2'),
            FilterChoice(label: '杂志', value: '4'),
            FilterChoice(label: '单行本', value: '5'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '状态',
          defaultValue: 'all',
          choices: [
            FilterChoice(label: '全部', value: 'all'),
            FilterChoice(label: '连载中', value: 'ongoing'),
            FilterChoice(label: '已完结', value: 'completed'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final query = <String, dynamic>{'pageNo': page, 'pageSize': _pageSize};
    final channel = int.tryParse(filters['channel'] ?? '');
    if (channel != null) query['channel'] = channel;
    switch (filters['status']) {
      case 'ongoing':
        query['isEnded'] = false;
      case 'completed':
        query['isEnded'] = true;
    }
    return FetchConfig(url: '$_baseUrl/api/comic/items', queryParameters: query);
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) => _parseSummaries(response);

  @override
  FetchConfig prepareSearchFetch(
    String keyword,
    int page,
    Map<String, String> filters,
  ) => FetchConfig(
        url: '$_baseUrl/api/comic/search',
        queryParameters: {
          'keyword': keyword,
          'pageNo': page,
          'pageSize': _pageSize,
          'type': 1,
        },
      );

  @override
  List<MangaSummary> parseSearch(dynamic response) => _parseSummaries(response);

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) => FetchConfig(
        url: '$_baseUrl/api/comic/content',
        method: HttpMethod.post,
        body: {'id': int.parse(mangaId)},
      );

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final data = _map(response);
    final chapters = <ChapterItem>[];
    final rawChapters = data['chapters'];
    if (rawChapters is List) {
      for (final rawChapter in rawChapters) {
        final chapter = _map(rawChapter);
        final number = _int(chapter['number']);
        if (number == null) continue;
        chapters.add(ChapterItem(
          id: '$number',
          mangaId: mangaId,
          title: _string(chapter['title']).isEmpty
              ? '第$number话'
              : _string(chapter['title']),
          href: '$_baseUrl/comics/$mangaId/$number',
        ));
      }
    }
    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: _string(data['title']),
      coverUrl: _coverUrl(mangaId),
      description: _nullableString(data['desc']),
      author: _string(data['author']),
      tags: _tagNames(data['tags']),
      status: switch (data['isEnded']) {
        true => MangaStatus.completed,
        false => MangaStatus.ongoing,
        _ => MangaStatus.unknown,
      },
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) =>
      const ChapterListResult(chapters: []);

  @override
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) => FetchConfig(
        url: '$_baseUrl/api/comic/chapter',
        method: HttpMethod.post,
        body: {'id': int.parse(mangaId), 'chapter': int.parse(chapterId)},
      );

  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) {
    final data = _map(response);
    final pageCount = _int(data['pages']) ?? 0;
    final images = List<ChapterImage>.generate(
      pageCount > 0 ? pageCount : 0,
      (index) => ChapterImage(
        url: '$_imageBaseUrl/comic/$mangaId/$chapterId/${index + 1}.jpg',
      ),
    );
    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: _nullableString(data['title']) ?? '第$chapterId话',
        images: images,
      ),
    );
  }

  @override
  String getChapterWebUrl(String mangaId, String chapterId) =>
      '$_baseUrl/comics/$mangaId/$chapterId';

  List<MangaSummary> _parseSummaries(dynamic response) {
    final items = _map(response)['items'];
    if (items is! List) return const [];
    final summaries = <MangaSummary>[];
    for (final rawItem in items) {
      final item = _map(rawItem);
      final id = _nullableString(item['id']);
      if (id == null) continue;
      final chapter = _int(item['chapter']);
      summaries.add(MangaSummary(
        id: id,
        sourceId: sourceId,
        title: _string(item['title']),
        coverUrl: _coverUrl(id),
        latestChapter: chapter == null ? null : '第$chapter话',
      ));
    }
    return summaries;
  }

  String _coverUrl(String mangaId) => '$_coverBaseUrl/comic/$mangaId/cover.jpg';

  List<String> _tagNames(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((tag) => _nullableString(_map(tag)['name']))
        .whereType<String>()
        .toList();
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  String _string(dynamic value) => value?.toString() ?? '';

  String? _nullableString(dynamic value) {
    final result = _string(value).trim();
    return result.isEmpty ? null : result;
  }

  int? _int(dynamic value) => value is int ? value : int.tryParse('$value');
}
```

- [ ] **Step 2: Run the focused source tests**

Run: `flutter test test/data/sources/mmero_test.dart`

Expected: PASS with all request-builder and parser tests passing.

- [ ] **Step 3: Run focused static analysis**

Run: `flutter analyze lib/data/sources/mmero.dart test/data/sources/mmero_test.dart`

Expected: `No issues found!`

### Task 3: Register and Verify the Source

**Files:**
- Modify: `lib/app/di/injection.dart:38-39`
- Modify: `lib/app/di/injection.dart:128-130`
- Test: `test/data/sources/mmero_test.dart`

- [ ] **Step 1: Import and register the source**

```dart
import 'package:comic_reader/data/sources/mmero.dart';
```

Place the import beside the other source imports. Add the registration before
`getIt.registerSingleton<SourceRegistry>(registry);`:

```dart
registry.register(MmeroSource());
```

- [ ] **Step 2: Re-run the focused test and static analysis**

Run: `flutter test test/data/sources/mmero_test.dart && flutter analyze lib/data/sources/mmero.dart test/data/sources/mmero_test.dart lib/app/di/injection.dart`

Expected: the test suite passes and analysis reports no issues.

- [ ] **Step 3: Refresh the code graph**

Run: `graphify update .`

Expected: graphify completes without errors and updates `graphify-out/`.

- [ ] **Step 4: Inspect the final change set**

Run: `git diff --check && git status --short`

Expected: no whitespace errors; changes are limited to the source, its focused
test, DI registration, the approved spec, the implementation plan, and
generated graph artifacts. Do not commit unless the user explicitly requests
one.
