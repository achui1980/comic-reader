# Discovery List Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a switchable list layout (方案C·详情列表) to the Discovery screen, toggleable via an AppBar icon button, with the user's choice persisted across app restarts.

**Architecture:** Extend the existing Cubit-based state (`DiscoveryState.viewMode`) and global settings (`AppSettings.discoveryViewMode`) to track grid/list preference. Extract the private `_MangaCard` into a public `MangaGridCard` and add a new `MangaListItem` widget in `lib/presentation/common/manga_card.dart`. `discovery_screen.dart`'s content builder branches between `GridView.builder` (existing) and `ListView.separated` (new) based on `state.viewMode`. `MangaSummary` gains an optional `description` field, populated only by `comick` and `pica_comic` sources for now.

**Tech Stack:** Flutter (Material 3), flutter_bloc (Cubit), get_it (DI), equatable, bloc_test + mocktail (testing).

## Global Constraints

- No new third-party dependencies — chip UI must use native Material 3 `Container`/`Text`, not a new package.
- Persist the view-mode preference through the existing `SettingsStore`/`LocalStorage` mechanism (`local_storage_io.dart` / `local_storage_web.dart`) — do not introduce a new storage channel.
- `home_screen.dart` and its `_buildMangaCard()` method must NOT be modified in this plan (only referenced as evidence of duplication).
- The list layout is always a single column at every screen width — no responsive multi-column strategy for list mode. Desktop still uses `Responsive.constrainedContent` for centering.
- Only `lib/data/sources/comick.dart` and `lib/data/sources/pica_comic.dart` get `description` parsing in this plan. All other sources keep `description == null`.
- Divider in list mode must use `indent: 96 + 12 + 12` (cover width + horizontal padding + gap) so the separator aligns with the text column, not the cover.
- No new `discovery_screen`-level widget tests (no existing precedent in this codebase given GetIt DI complexity). Coverage comes from: entity tests, source-parser tests, `AppSettings` tests, `DiscoveryState` tests, `DiscoveryCubit` bloc_test, and `MangaGridCard`/`MangaListItem` widget tests.

---

### Task 1: Add `description` field + `copyWith` to `MangaSummary`

**Files:**
- Modify: `lib/domain/entities/manga.dart` (MangaSummary class, currently lines 1-50 of the file)
- Test: `test/domain/entities/manga_test.dart` (new)

**Interfaces:**
- Consumes: nothing new
- Produces: `MangaSummary.description` (`String?`, defaults to `null`), `MangaSummary.copyWith({...})` returning a new `MangaSummary`

- [ ] **Step 1: Write the failing test**

Create `test/domain/entities/manga_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() {
  group('MangaSummary.description', () {
    test('defaults to null when not provided', () {
      const summary = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
      );
      expect(summary.description, isNull);
    });

    test('can be set via constructor', () {
      const summary = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
        description: 'A test description',
      );
      expect(summary.description, 'A test description');
    });

    test('copyWith updates description without affecting other fields', () {
      const original = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
      );
      final updated = original.copyWith(description: 'New description');
      expect(updated.description, 'New description');
      expect(updated.id, original.id);
      expect(updated.title, original.title);
      expect(updated.coverUrl, original.coverUrl);
    });

    test('two summaries with different description are not equal', () {
      const a = MangaSummary(
        id: '1',
        sourceId: 's',
        title: 't',
        coverUrl: 'c',
        description: 'A',
      );
      const b = MangaSummary(
        id: '1',
        sourceId: 's',
        title: 't',
        coverUrl: 'c',
        description: 'B',
      );
      expect(a == b, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/entities/manga_test.dart`
Expected: FAIL — compile error, `description` and `copyWith` are not defined on `MangaSummary`.

- [ ] **Step 3: Modify `MangaSummary` in `lib/domain/entities/manga.dart`**

Add the `description` field right after `popularityText`, add it to the constructor and `props`, and add a `copyWith` method (the class currently has none). The full class becomes:

```dart
class MangaSummary extends Equatable {
  final String id;
  final String sourceId;
  final String title;
  final String coverUrl;
  final String author;
  final List<String> altTitles;
  final String? latestChapter;
  final String? updateTime;
  final Map<String, String>? headers;
  final int? chapterCount;
  final String? popularityText;
  final String? description;

  const MangaSummary({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.coverUrl,
    this.author = '',
    this.altTitles = const [],
    this.latestChapter,
    this.updateTime,
    this.headers,
    this.chapterCount,
    this.popularityText,
    this.description,
  });

  MangaSummary copyWith({
    String? id,
    String? sourceId,
    String? title,
    String? coverUrl,
    String? author,
    List<String>? altTitles,
    String? latestChapter,
    String? updateTime,
    Map<String, String>? headers,
    int? chapterCount,
    String? popularityText,
    String? description,
  }) {
    return MangaSummary(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      author: author ?? this.author,
      altTitles: altTitles ?? this.altTitles,
      latestChapter: latestChapter ?? this.latestChapter,
      updateTime: updateTime ?? this.updateTime,
      headers: headers ?? this.headers,
      chapterCount: chapterCount ?? this.chapterCount,
      popularityText: popularityText ?? this.popularityText,
      description: description ?? this.description,
    );
  }

  @override
  List<Object?> get props => [
        id,
        sourceId,
        title,
        coverUrl,
        author,
        altTitles,
        latestChapter,
        updateTime,
        chapterCount,
        popularityText,
        description,
      ];
}
```

Keep the rest of the file (imports, `MangaStatus`, `MangaDetail`) unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/entities/manga_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/domain/entities/manga.dart test/domain/entities/manga_test.dart
git commit -m "feat(discovery): add description field to MangaSummary"
```

---

### Task 2: Parse `description` in `ComicKSource.parseDiscovery`

**Files:**
- Modify: `lib/data/sources/comick.dart` (`_parseMangaList`, currently lines 475-505)
- Test: `test/data/sources/comick_test.dart` (new)

**Interfaces:**
- Consumes: `MangaSummary(..., description: ...)` from Task 1
- Produces: `ComicKSource.parseDiscovery()` results with `description` populated from `item['desc']` when present

- [ ] **Step 1: Write the failing test**

Create `test/data/sources/comick_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/comick.dart';

void main() {
  late ComicKSource source;

  setUp(() {
    source = ComicKSource();
  });

  group('ComicKSource.parseDiscovery description', () {
    test('parses description field when present', () {
      final input = [
        {
          'hid': 'abc123',
          'title': 'Test Manga',
          'last_chapter': 12,
          'rating': 4.5,
          'follow_count': 100,
          'desc': 'A test description',
        },
      ];

      final result = source.parseDiscovery(input);

      expect(result.length, 1);
      expect(result[0].id, 'abc123');
      expect(result[0].description, 'A test description');
    });

    test('description is null when field is missing', () {
      final input = [
        {
          'hid': 'abc123',
          'title': 'Test Manga',
        },
      ];

      final result = source.parseDiscovery(input);

      expect(result[0].description, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sources/comick_test.dart`
Expected: FAIL — `result[0].description` is `null` in the first test (expected `'A test description'`).

- [ ] **Step 3: Modify `_parseMangaList` in `lib/data/sources/comick.dart`**

Find the `MangaSummary(...)` construction inside `_parseMangaList` (around line 486-495) and add the `description` line:

```dart
    result.add(
      MangaSummary(
        id: id,
        sourceId: sourceId,
        title: _pickListTitle(item),
        coverUrl: _buildCoverFromList(item),
        author: '',
        latestChapter: _stringify(item['last_chapter']),
        headers: defaultHeaders,
        popularityText: _buildPopularityText(item),
        description: item['desc'] as String?,
      ),
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sources/comick_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/sources/comick.dart test/data/sources/comick_test.dart
git commit -m "feat(discovery): parse description from comick source"
```

---

### Task 3: Parse `description` in `PicaComic.parseDiscovery`

**Files:**
- Modify: `lib/data/sources/pica_comic.dart` (`_parseComicToSummary`, currently lines 422-446)
- Test: `test/data/sources/pica_comic_test.dart` (new)

**Interfaces:**
- Consumes: `MangaSummary(..., description: ...)` from Task 1
- Produces: `PicaComic.parseDiscovery()` results with `description` populated from `comic['description']` when present

- [ ] **Step 1: Write the failing test**

Create `test/data/sources/pica_comic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';

void main() {
  late PicaComic source;

  setUp(() {
    source = PicaComic();
  });

  group('PicaComic.parseDiscovery description', () {
    test('parses description field when present', () {
      final response = {
        'comics': [
          {
            '_id': 'xyz789',
            'title': 'Test Pica Manga',
            'author': 'Some Author',
            'thumb': <String, dynamic>{},
            'finished': false,
            'epsCount': 20,
            'likesCount': 50,
            'description': 'A pica description',
          },
        ],
      };

      final result = source.parseDiscovery(response);

      expect(result.length, 1);
      expect(result[0].id, 'xyz789');
      expect(result[0].description, 'A pica description');
    });

    test('description is null when field is missing', () {
      final response = {
        'comics': [
          {
            '_id': 'xyz789',
            'title': 'Test Pica Manga',
            'thumb': <String, dynamic>{},
          },
        ],
      };

      final result = source.parseDiscovery(response);

      expect(result[0].description, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/sources/pica_comic_test.dart`
Expected: FAIL — `result[0].description` is `null` in the first test (expected `'A pica description'`).

- [ ] **Step 3: Modify `_parseComicToSummary` in `lib/data/sources/pica_comic.dart`**

Find the `MangaSummary(...)` return inside `_parseComicToSummary` (around line 434-443) and add the `description` line:

```dart
  return MangaSummary(
    id: mangaId,
    sourceId: sourceId,
    title: title,
    coverUrl: coverUrl,
    author: author,
    latestChapter: finished ? 'Completed' : null,
    chapterCount: epsCount is num ? epsCount.toInt() : null,
    popularityText: likesCount is num && likesCount > 0 ? '❤ ${likesCount.toInt()}' : null,
    description: comic['description'] as String?,
  );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/sources/pica_comic_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/sources/pica_comic.dart test/data/sources/pica_comic_test.dart
git commit -m "feat(discovery): parse description from pica_comic source"
```

---

### Task 4: Add `DiscoveryViewMode` + `AppSettings.discoveryViewMode`

**Files:**
- Modify: `lib/data/local/settings_store.dart` (enum block near top; `AppSettings` class constructor/copyWith/toJson/fromJson, currently lines 1-138)
- Test: `test/data/local/settings_store_test.dart` (new)

**Interfaces:**
- Consumes: nothing new
- Produces: `enum DiscoveryViewMode { grid, list }`, `AppSettings.discoveryViewMode` (`DiscoveryViewMode`, default `DiscoveryViewMode.grid`), `AppSettings.copyWith({..., discoveryViewMode})`, JSON round-trip via `toJson()`/`fromJson()`

- [ ] **Step 1: Write the failing test**

Create `test/data/local/settings_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/local/settings_store.dart';

void main() {
  group('AppSettings.discoveryViewMode', () {
    test('defaults to grid', () {
      const settings = AppSettings();
      expect(settings.discoveryViewMode, DiscoveryViewMode.grid);
    });

    test('copyWith updates discoveryViewMode', () {
      const settings = AppSettings();
      final updated = settings.copyWith(discoveryViewMode: DiscoveryViewMode.list);
      expect(updated.discoveryViewMode, DiscoveryViewMode.list);
    });

    test('toJson/fromJson round-trip preserves discoveryViewMode', () {
      const settings = AppSettings(discoveryViewMode: DiscoveryViewMode.list);
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.discoveryViewMode, DiscoveryViewMode.list);
    });

    test('fromJson defaults to grid when field is missing', () {
      final restored = AppSettings.fromJson(<String, dynamic>{});
      expect(restored.discoveryViewMode, DiscoveryViewMode.grid);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/local/settings_store_test.dart`
Expected: FAIL — compile error, `DiscoveryViewMode` and `AppSettings.discoveryViewMode` are not defined.

- [ ] **Step 3: Modify `lib/data/local/settings_store.dart`**

Add the enum next to the existing `LayoutMode`/`ReadingDirection`/`ScaleType` enums (near the top of the file, before the `AppSettings` class):

```dart
enum DiscoveryViewMode { grid, list }
```

Add the field to `AppSettings` (alongside the other fields, e.g. after `scaleType`):

```dart
  final DiscoveryViewMode discoveryViewMode;
```

Add it to the constructor with a default value:

```dart
    this.discoveryViewMode = DiscoveryViewMode.grid,
```

Add it as a parameter in `copyWith` and to the returned instance:

```dart
    DiscoveryViewMode? discoveryViewMode,
```
```dart
      discoveryViewMode: discoveryViewMode ?? this.discoveryViewMode,
```

Add it to `toJson`:

```dart
      'discoveryViewMode': discoveryViewMode.index,
```

Add it to `fromJson`:

```dart
      discoveryViewMode: DiscoveryViewMode.values[
          json['discoveryViewMode'] as int? ?? 0],
```

Leave every other field/enum in the file untouched.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/local/settings_store_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/local/settings_store.dart test/data/local/settings_store_test.dart
git commit -m "feat(discovery): add DiscoveryViewMode setting"
```

---

### Task 5: Add `viewMode` to `DiscoveryState`

**Files:**
- Modify: `lib/presentation/discovery/bloc/discovery_state.dart` (currently 51 lines)
- Test: `test/presentation/discovery/bloc/discovery_state_test.dart` (new)

**Interfaces:**
- Consumes: `DiscoveryViewMode` from Task 4 (`lib/data/local/settings_store.dart`)
- Produces: `DiscoveryState.viewMode` (`DiscoveryViewMode`, default `DiscoveryViewMode.grid`), `DiscoveryState.copyWith({..., viewMode})`

- [ ] **Step 1: Write the failing test**

Create `test/presentation/discovery/bloc/discovery_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/presentation/discovery/bloc/discovery_state.dart';

void main() {
  group('DiscoveryState.viewMode', () {
    test('defaults to grid', () {
      const state = DiscoveryState();
      expect(state.viewMode, DiscoveryViewMode.grid);
    });

    test('copyWith updates viewMode without affecting other fields', () {
      const state = DiscoveryState(sourceId: 'test');
      final updated = state.copyWith(viewMode: DiscoveryViewMode.list);
      expect(updated.viewMode, DiscoveryViewMode.list);
      expect(updated.sourceId, 'test');
    });

    test('two states with different viewMode are not equal', () {
      const a = DiscoveryState(viewMode: DiscoveryViewMode.grid);
      const b = DiscoveryState(viewMode: DiscoveryViewMode.list);
      expect(a == b, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/discovery/bloc/discovery_state_test.dart`
Expected: FAIL — compile error, `DiscoveryState.viewMode` is not defined.

- [ ] **Step 3: Modify `lib/presentation/discovery/bloc/discovery_state.dart`**

Add the import at the top of the file:

```dart
import 'package:comic_reader/data/local/settings_store.dart';
```

Add the field, constructor default, `copyWith` param/usage, and `props` entry. The full file becomes:

```dart
import 'package:equatable/equatable.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum DiscoveryStatus { initial, loading, loaded, error, loadingMore }

class DiscoveryState extends Equatable {
  final DiscoveryStatus status;
  final List<MangaSummary> manga;
  final int currentPage;
  final bool hasMore;
  final String? errorMessage;
  final String sourceId;
  final Map<String, String> filters;
  final List<FilterOption> filterOptions;
  final DiscoveryViewMode viewMode;

  const DiscoveryState({
    this.status = DiscoveryStatus.initial,
    this.manga = const [],
    this.currentPage = 1,
    this.hasMore = true,
    this.errorMessage,
    this.sourceId = '',
    this.filters = const {},
    this.filterOptions = const [],
    this.viewMode = DiscoveryViewMode.grid,
  });

  DiscoveryState copyWith({
    DiscoveryStatus? status,
    List<MangaSummary>? manga,
    int? currentPage,
    bool? hasMore,
    String? errorMessage,
    String? sourceId,
    Map<String, String>? filters,
    List<FilterOption>? filterOptions,
    DiscoveryViewMode? viewMode,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      manga: manga ?? this.manga,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
      sourceId: sourceId ?? this.sourceId,
      filters: filters ?? this.filters,
      filterOptions: filterOptions ?? this.filterOptions,
      viewMode: viewMode ?? this.viewMode,
    );
  }

  @override
  List<Object?> get props => [
        status,
        manga,
        currentPage,
        hasMore,
        errorMessage,
        sourceId,
        filters,
        filterOptions,
        viewMode,
      ];
}
```

> Note: the exact original import list/order for `equatable`/`entities.dart` must be preserved as found in the current file — only add the `settings_store.dart` import and the fields/params/props shown above. Do not change unrelated fields.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/discovery/bloc/discovery_state_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/presentation/discovery/bloc/discovery_state.dart test/presentation/discovery/bloc/discovery_state_test.dart
git commit -m "feat(discovery): add viewMode to DiscoveryState"
```

---

### Task 6: Add `SettingsStore` dependency + `toggleViewMode()` to `DiscoveryCubit`

**Files:**
- Modify: `lib/presentation/discovery/bloc/discovery_cubit.dart` (constructor lines 10-15, `init()` lines 17-26; rest of file unchanged)
- Test: `test/presentation/discovery/bloc/discovery_cubit_test.dart` (new)

**Interfaces:**
- Consumes: `DiscoveryState.viewMode` (Task 5), `SettingsStore.load()`/`save()` and `AppSettings.discoveryViewMode`/`DiscoveryViewMode` (Task 4)
- Produces: `DiscoveryCubit({required MangaRepository repository, required SourceRegistry registry, required SettingsStore settingsStore})`, `DiscoveryCubit.toggleViewMode()` (void, fire-and-forget persistence)

- [ ] **Step 1: Write the failing test**

Create `test/presentation/discovery/bloc/discovery_cubit_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/discovery/bloc/discovery_cubit.dart';
import 'package:comic_reader/presentation/discovery/bloc/discovery_state.dart';

class MockMangaRepository extends Mock implements MangaRepository {}

class MockSettingsStore extends Mock implements SettingsStore {}

void main() {
  late MockMangaRepository repository;
  late MockSettingsStore settingsStore;
  late SourceRegistry registry;

  setUpAll(() {
    registerFallbackValue(const AppSettings());
  });

  setUp(() {
    repository = MockMangaRepository();
    settingsStore = MockSettingsStore();
    registry = SourceRegistry();
    when(() => settingsStore.load()).thenAnswer(
      (_) async => const AppSettings(discoveryViewMode: DiscoveryViewMode.grid),
    );
    when(() => settingsStore.save(any())).thenAnswer((_) async {});
  });

  DiscoveryCubit buildCubit() => DiscoveryCubit(
        repository: repository,
        registry: registry,
        settingsStore: settingsStore,
      );

  group('DiscoveryCubit.toggleViewMode', () {
    blocTest<DiscoveryCubit, DiscoveryState>(
      'toggles viewMode from grid to list and persists the change',
      build: buildCubit,
      act: (cubit) => cubit.toggleViewMode(),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.viewMode, 'viewMode', DiscoveryViewMode.list),
      ],
      verify: (_) {
        final captured =
            verify(() => settingsStore.save(captureAny())).captured;
        expect(
          (captured.single as AppSettings).discoveryViewMode,
          DiscoveryViewMode.list,
        );
      },
    );

    blocTest<DiscoveryCubit, DiscoveryState>(
      'toggles viewMode from list back to grid',
      build: buildCubit,
      seed: () => const DiscoveryState(viewMode: DiscoveryViewMode.list),
      act: (cubit) => cubit.toggleViewMode(),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.viewMode, 'viewMode', DiscoveryViewMode.grid),
      ],
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/discovery/bloc/discovery_cubit_test.dart`
Expected: FAIL — compile error, `DiscoveryCubit` has no `settingsStore` named parameter and no `toggleViewMode()` method.

- [ ] **Step 3: Modify `lib/presentation/discovery/bloc/discovery_cubit.dart`**

Add the import:

```dart
import 'package:comic_reader/data/local/settings_store.dart';
```

Update the constructor and add the `_settingsStore` field:

```dart
class DiscoveryCubit extends Cubit<DiscoveryState> {
  final MangaRepository _repository;
  final SourceRegistry _registry;
  final SettingsStore _settingsStore;

  DiscoveryCubit({
    required MangaRepository repository,
    required SourceRegistry registry,
    required SettingsStore settingsStore,
  })  : _repository = repository,
        _registry = registry,
        _settingsStore = settingsStore,
        super(const DiscoveryState());
```

Replace `init()` with an async version that reads the persisted view mode, and add `toggleViewMode()` + its private helper right after it:

```dart
  Future<void> init() async {
    final settings = await _settingsStore.load();
    final source = _registry.defaultSource;
    if (source == null) return;
    emit(state.copyWith(
      sourceId: source.id,
      filterOptions: source.discoveryFilters,
      filters: {
        for (final f in source.discoveryFilters) f.name: f.defaultValue,
      },
      viewMode: settings.discoveryViewMode,
    ));
    loadDiscovery();
  }

  void toggleViewMode() {
    final newMode = state.viewMode == DiscoveryViewMode.grid
        ? DiscoveryViewMode.list
        : DiscoveryViewMode.grid;
    emit(state.copyWith(viewMode: newMode));
    _persistViewMode(newMode);
  }

  Future<void> _persistViewMode(DiscoveryViewMode mode) async {
    final settings = await _settingsStore.load();
    await _settingsStore.save(settings.copyWith(discoveryViewMode: mode));
  }
```

Leave `changeSource`, `changeFilter`, `loadDiscovery`, `loadMore`, and `refresh` exactly as they are.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/discovery/bloc/discovery_cubit_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/presentation/discovery/bloc/discovery_cubit.dart test/presentation/discovery/bloc/discovery_cubit_test.dart
git commit -m "feat(discovery): add toggleViewMode with settings persistence"
```

---

### Task 7: Create `MangaGridCard` and `MangaListItem` in `lib/presentation/common/manga_card.dart`

**Files:**
- Create: `lib/presentation/common/manga_card.dart`
- Test: `test/presentation/common/manga_card_test.dart` (new)

**Interfaces:**
- Consumes: `MangaSummary` (with `description` from Task 1), `MangaCoverImage` (`lib/presentation/common/manga_cover_image.dart`), `AppRoutes.detailPath` (`lib/app/router/routes.dart`)
- Produces: `MangaGridCard({required MangaSummary manga})`, `MangaListItem({required MangaSummary manga})` — both `StatelessWidget`

- [ ] **Step 1: Write the failing test**

Create `test/presentation/common/manga_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/common/manga_card.dart';

void main() {
  const baseManga = MangaSummary(
    id: '1',
    sourceId: 'test',
    title: 'Test Manga',
    coverUrl: 'https://example.com/cover.jpg',
    author: 'Test Author',
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MangaListItem', () {
    testWidgets('renders title and author', (tester) async {
      await tester.pumpWidget(wrap(const MangaListItem(manga: baseManga)));
      expect(find.text('Test Manga'), findsOneWidget);
      expect(find.text('Test Author'), findsOneWidget);
    });

    testWidgets('does not render a description when null', (tester) async {
      await tester.pumpWidget(wrap(const MangaListItem(manga: baseManga)));
      expect(find.text('A description'), findsNothing);
    });

    testWidgets('renders description text when present', (tester) async {
      const manga = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
        description: 'A description',
      );
      await tester.pumpWidget(wrap(const MangaListItem(manga: manga)));
      expect(find.text('A description'), findsOneWidget);
    });

    testWidgets('renders no chips when chapterCount/popularityText/updateTime are all missing',
        (tester) async {
      await tester.pumpWidget(wrap(const MangaListItem(manga: baseManga)));
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders a chapterCount chip when present', (tester) async {
      const manga = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
        chapterCount: 42,
      );
      await tester.pumpWidget(wrap(const MangaListItem(manga: manga)));
      expect(find.text('42章'), findsOneWidget);
    });
  });

  group('MangaGridCard', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(wrap(const MangaGridCard(manga: baseManga)));
      expect(find.text('Test Manga'), findsOneWidget);
    });

    testWidgets('renders chapterCount + popularityText as meta text', (tester) async {
      const manga = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
        chapterCount: 10,
        popularityText: '100 views',
      );
      await tester.pumpWidget(wrap(const MangaGridCard(manga: manga)));
      expect(find.text('10章 · 100 views'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/common/manga_card_test.dart`
Expected: FAIL — `package:comic_reader/presentation/common/manga_card.dart` does not exist.

- [ ] **Step 3: Create `lib/presentation/common/manga_card.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'manga_cover_image.dart';

/// Grid-style manga card. This is the original `_MangaCard` from
/// `discovery_screen.dart`, extracted so it can be shared and tested
/// independently of the screen.
class MangaGridCard extends StatelessWidget {
  final MangaSummary manga;
  const MangaGridCard({super.key, required this.manga});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.detailPath(manga.sourceId, manga.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MangaCoverImage(
                imageUrl: manga.coverUrl,
                headers: manga.headers,
                sourceId: manga.sourceId,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          if (_metaText != null)
            Text(
              _metaText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  /// Chapter count + popularity text, joined with ' · '. Returns null
  /// (hiding the row) when both are missing.
  String? get _metaText {
    final parts = <String>[];
    if (manga.chapterCount != null) {
      parts.add('${manga.chapterCount}章');
    }
    if (manga.popularityText != null && manga.popularityText!.isNotEmpty) {
      parts.add(manga.popularityText!);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// List-style manga item (方案C·详情列表). Shows a larger cover plus
/// title, author, dynamic chips (chapter count / popularity / update
/// time), and an optional description.
class MangaListItem extends StatelessWidget {
  final MangaSummary manga;
  const MangaListItem({super.key, required this.manga});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(AppRoutes.detailPath(manga.sourceId, manga.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 136,
                child: MangaCoverImage(
                  imageUrl: manga.coverUrl,
                  headers: manga.headers,
                  sourceId: manga.sourceId,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    manga.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _buildChips(context),
                  ),
                  if (manga.description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      manga.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds one chip per available field among chapterCount /
  /// popularityText / updateTime, skipping missing/empty ones. Returns
  /// an empty list (Wrap collapses to zero height, no blank row) when
  /// all three are missing.
  List<Widget> _buildChips(BuildContext context) {
    final chips = <Widget>[];
    if (manga.chapterCount != null) {
      chips.add(_buildChip(context, '${manga.chapterCount}章'));
    }
    if (manga.popularityText != null && manga.popularityText!.isNotEmpty) {
      chips.add(_buildChip(context, manga.popularityText!));
    }
    if (manga.updateTime != null && manga.updateTime!.isNotEmpty) {
      chips.add(_buildChip(context, manga.updateTime!));
    }
    return chips;
  }

  Widget _buildChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/common/manga_card_test.dart`
Expected: PASS (7 tests). Network image requests for `https://example.com/cover.jpg` will fail silently in the test environment (no real network) — this does not affect the text/layout assertions above since `MangaCoverImage`'s error handling does not throw synchronously into the widget tree.

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/presentation/common/manga_card.dart test/presentation/common/manga_card_test.dart
git commit -m "feat(discovery): extract MangaGridCard and add MangaListItem"
```

---

### Task 8: Wire grid/list switching into `discovery_screen.dart`

**Files:**
- Modify: `lib/presentation/discovery/discovery_screen.dart` (full file, currently 299 lines)

**Interfaces:**
- Consumes: `DiscoveryCubit({..., settingsStore})` and `toggleViewMode()` (Task 6), `DiscoveryState.viewMode` (Task 5), `DiscoveryViewMode` (Task 4), `MangaGridCard`/`MangaListItem` (Task 7)
- Produces: Discovery screen renders grid or list based on `state.viewMode`, with an AppBar icon button to toggle it

- [ ] **Step 1: Replace the full contents of `lib/presentation/discovery/discovery_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/core/utils/responsive.dart';
import 'package:comic_reader/presentation/common/manga_card.dart';
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/presentation/common/cloudflare_dialog.dart';
import 'bloc/discovery_cubit.dart';
import 'bloc/discovery_state.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DiscoveryCubit(
        repository: GetIt.instance<MangaRepository>(),
        registry: GetIt.instance<SourceRegistry>(),
        settingsStore: GetIt.instance<SettingsStore>(),
      )..init(),
      child: const _DiscoveryView(),
    );
  }
}

class _DiscoveryView extends StatelessWidget {
  const _DiscoveryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        actions: [
          BlocBuilder<DiscoveryCubit, DiscoveryState>(
            buildWhen: (previous, current) => previous.viewMode != current.viewMode,
            builder: (context, state) {
              final isGrid = state.viewMode == DiscoveryViewMode.grid;
              return IconButton(
                icon: Icon(isGrid ? Icons.view_list : Icons.grid_view),
                tooltip: isGrid ? '切换到列表' : '切换到网格',
                onPressed: () => context.read<DiscoveryCubit>().toggleViewMode(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.search),
          ),
        ],
      ),
      body: Responsive.constrainedContent(
        context: context,
        child: Column(
          children: [
            _buildFilterBar(context),
            Expanded(child: _buildContent(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return BlocBuilder<DiscoveryCubit, DiscoveryState>(
      buildWhen: (previous, current) =>
          previous.filterOptions != current.filterOptions ||
          previous.filters != current.filters ||
          previous.sourceId != current.sourceId,
      builder: (context, state) {
        return SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.source, size: 16),
                  label: Text(
                    GetIt.instance<SourceRegistry>().get(state.sourceId)?.shortName ??
                        state.sourceId,
                  ),
                  onPressed: () => _showSourcePicker(context),
                ),
              ),
              ...state.filterOptions.map((option) {
                final currentValue = state.filters[option.name] ?? option.defaultValue;
                final currentChoice = option.choices.firstWhere(
                  (c) => c.value == currentValue,
                  orElse: () => option.choices.first,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(currentChoice.label),
                    selected: currentValue != option.defaultValue,
                    onSelected: (_) => _showFilterPicker(context, option),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showSourcePicker(BuildContext context) {
    final cubit = context.read<DiscoveryCubit>();
    final registry = GetIt.instance<SourceRegistry>();
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return ListView.builder(
          itemCount: registry.all.length,
          itemBuilder: (sheetContext, index) {
            final source = registry.all[index];
            return ListTile(
              title: Text(source.info.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (source.info.needsProxy)
                    const Icon(Icons.vpn_lock, size: 18, color: Colors.blue),
                  if (source.info.requiresLogin && !source.isAuthenticated)
                    const Icon(Icons.login, size: 18, color: Colors.orange),
                ],
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (source.info.requiresLogin && !source.isAuthenticated) {
                  final autoLoggedIn = await source.picaAutoLogin();
                  if (!autoLoggedIn && context.mounted) {
                    await showPicaLoginDialog(context, source: source);
                  }
                }
                cubit.changeSource(source.id);
              },
            );
          },
        );
      },
    );
  }

  void _showFilterPicker(BuildContext context, FilterOption option) {
    final cubit = context.read<DiscoveryCubit>();
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return ListView.builder(
          itemCount: option.choices.length,
          itemBuilder: (sheetContext, index) {
            final choice = option.choices[index];
            return ListTile(
              title: Text(choice.label),
              onTap: () {
                Navigator.pop(sheetContext);
                cubit.changeFilter(option.name, choice.value);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return BlocBuilder<DiscoveryCubit, DiscoveryState>(
      builder: (context, state) {
        if (state.status == DiscoveryStatus.loading && state.manga.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == DiscoveryStatus.error && state.manga.isEmpty) {
          final message = state.errorMessage ?? '';
          final isCloudflareError =
              message.contains('CloudflareException') || message.contains('Cloudflare');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isCloudflareError ? Icons.shield_outlined : Icons.error_outline,
                  size: 48,
                  color: isCloudflareError ? Colors.orange : Colors.red,
                ),
                const SizedBox(height: 12),
                Text(
                  isCloudflareError ? '需要完成 Cloudflare 验证' : message,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (isCloudflareError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      onPressed: () async {
                        final verified = await showCloudflareDialog(
                          context,
                          sourceId: state.sourceId,
                        );
                        if (verified == true && context.mounted) {
                          context.read<DiscoveryCubit>().loadDiscovery();
                        }
                      },
                      icon: const Icon(Icons.verified_user_outlined, size: 18),
                      label: const Text('去验证'),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () => context.read<DiscoveryCubit>().loadDiscovery(),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        final isGrid = state.viewMode == DiscoveryViewMode.grid;

        return RefreshIndicator(
          onRefresh: () => context.read<DiscoveryCubit>().refresh(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification &&
                  notification.metrics.extentAfter < 200) {
                context.read<DiscoveryCubit>().loadMore();
              }
              return false;
            },
            child: isGrid
                ? GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Responsive.gridColumns(context),
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: state.manga.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= state.manga.length) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      return MangaGridCard(manga: state.manga[index]);
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: state.manga.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 96 + 12 + 12,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      if (index >= state.manga.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return MangaListItem(manga: state.manga[index]);
                    },
                  ),
          ),
        );
      },
    );
  }
}
```

> **Important:** `_buildFilterBar`, `_showSourcePicker`, and `_showFilterPicker` above are reproduced from the current file so the whole file can be pasted as one block. Before pasting, diff against the current file (`git diff` after paste) to confirm these three methods are byte-for-byte identical to what existed before — if your checked-out copy differs (e.g. from other in-flight work), keep the existing versions of those three methods and only apply the `DiscoveryScreen.build`, `_DiscoveryView.build` (AppBar), and `_buildContent` changes plus the import/removal changes and deletion of the old `_MangaCard` class.

Also remove the old private `_MangaCard` class entirely (it no longer exists anywhere in this file — it has moved to `lib/presentation/common/manga_card.dart` as `MangaGridCard`).

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/presentation/discovery/discovery_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run the regression test suite for touched dependencies**

Run:
```bash
flutter test test/presentation/discovery/bloc/discovery_cubit_test.dart test/presentation/discovery/bloc/discovery_state_test.dart test/presentation/common/manga_card_test.dart
```
Expected: All PASS (this confirms `DiscoveryCubit`, `DiscoveryState`, `MangaGridCard`, and `MangaListItem` — the units `discovery_screen.dart` wires together — still behave correctly). There is no dedicated widget test for `discovery_screen.dart` itself (no precedent for screen-level tests in this codebase given its GetIt dependency graph); verify manually per Step 4.

- [ ] **Step 4: Manual verification**

Run the app (`flutter run`), navigate to the 发现 (Discovery) tab, and confirm:
1. Grid view renders as before (regression check against pre-change screenshots/behavior).
2. Tapping the AppBar icon (left of the search icon) switches to a single-column list showing cover, title, author, chips (when data available), and description (when available).
3. Tapping the icon again switches back to grid.
4. Restart the app — the previously selected view mode (grid or list) is remembered.

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/presentation/discovery/discovery_screen.dart
git commit -m "feat(discovery): switch between grid and list layouts"
```

---

## Self-Review

**Spec coverage:**
- MangaSummary.description field + copyWith → Task 1 ✅
- comick/pica_comic description parsing → Tasks 2-3 ✅
- AppSettings.discoveryViewMode persistence → Task 4 ✅
- DiscoveryState.viewMode → Task 5 ✅
- DiscoveryCubit.toggleViewMode + init() reading settings → Task 6 ✅
- MangaGridCard extraction + MangaListItem (方案C) → Task 7 ✅
- AppBar toggle button + _buildContent grid/list branching + Divider indent rule → Task 8 ✅
- home_screen.dart untouched → confirmed, no task modifies it ✅
- No new dependencies, single-column list at all widths → enforced via Global Constraints and Task 8/7 code (no responsive column logic in list branch) ✅

**Placeholder scan:** No "TBD"/"TODO"/"add appropriate handling" phrases in any task. Every step has complete, runnable code. `_buildChips` (left unspecified in the spec) has a full concrete implementation in Task 7.

**Type consistency:** `DiscoveryViewMode` (Task 4) is consumed identically as the type of `DiscoveryState.viewMode` (Task 5) and `AppSettings.discoveryViewMode` (Task 4), and referenced the same way in `DiscoveryCubit.toggleViewMode()` (Task 6) and `discovery_screen.dart` (Task 8). `MangaGridCard`/`MangaListItem` constructor signature (`{required MangaSummary manga}`) matches usage in Task 8. `SettingsStore` methods `load()`/`save()` used consistently across Tasks 4, 6.
