# Missing Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the HIGH and MEDIUM priority missing features to bring comic-reader to feature parity with MangaReader.

**Architecture:** BLoC/Cubit pattern with GetIt DI, JSON-backed LocalStorage, Clean Architecture (data/domain/presentation layers). No database — all persistence is JSON files via `LocalStorage`.

**Tech Stack:** Flutter (Dart ^3.11.4), flutter_bloc, go_router, dio, get_it, cached_network_image, extended_image, share_plus, file_picker, image_gallery_saver.

---

## Feature List (in implementation order)

| # | Feature | Priority |
|---|---------|----------|
| 1 | Vertical reader infinite scroll (auto-load next chapter) | HIGH |
| 2 | Batch update checking + "new" badge on bookshelf | HIGH |
| 3 | Data backup & restore | HIGH |
| 4 | Long-press save image to gallery | MEDIUM |
| 5 | Chapter read/unread markers on detail screen | MEDIUM |
| 6 | Bookshelf multi-select + batch delete | MEDIUM |
| 7 | Download task manager (global persistent queue) | MEDIUM |

---

## Task 1: Vertical Reader Infinite Scroll

**Goal:** When scrolling in vertical mode, automatically append next chapter's images inline instead of replacing them.

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_event.dart`
- Modify: `lib/presentation/reader/bloc/reader_state.dart`
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`
- Modify: `lib/presentation/reader/widgets/vertical_reader.dart`

### Step 1: Add `AppendNextChapter` event and state fields

In `reader_event.dart`, add a new event:

```dart
/// Append next chapter images to current list (for infinite vertical scroll)
class AppendNextChapter extends ReaderEvent {
  const AppendNextChapter();
}
```

In `reader_state.dart`, add fields to track multi-chapter reading:

```dart
/// Chapter boundaries for infinite scroll: maps image index to chapterId
final List<ChapterBoundary> chapterBoundaries;
/// Whether next chapter is currently loading (for vertical append)
final bool isAppendingNext;
```

Add a helper class (top of file or separate):

```dart
class ChapterBoundary extends Equatable {
  final int startIndex;
  final String chapterId;
  final String chapterTitle;

  const ChapterBoundary({
    required this.startIndex,
    required this.chapterId,
    required this.chapterTitle,
  });

  @override
  List<Object?> get props => [startIndex, chapterId, chapterTitle];
}
```

Update `ReaderState` constructor defaults:
```dart
this.chapterBoundaries = const [],
this.isAppendingNext = false,
```

Update `copyWith` and `props` accordingly.

### Step 2: Add `_onAppendNextChapter` handler in `reader_bloc.dart`

```dart
on<AppendNextChapter>(_onAppendNextChapter);
```

Handler implementation:

```dart
Future<void> _onAppendNextChapter(
    AppendNextChapter event, Emitter<ReaderState> emit) async {
  if (!state.hasNextChapter || state.isAppendingNext) return;

  emit(state.copyWith(isAppendingNext: true));

  final nextIndex = state.currentChapterIndex + 1;
  final nextChapter = state.chapterList[nextIndex];

  try {
    final result = await _repository.getChapter(
      state.sourceId,
      state.mangaId,
      nextChapter.id,
      1,
    );

    final newImages = [...state.images, ...result.chapter.images];
    final newBoundary = ChapterBoundary(
      startIndex: state.images.length,
      chapterId: nextChapter.id,
      chapterTitle: result.chapter.title,
    );
    final newBoundaries = [...state.chapterBoundaries, newBoundary];

    emit(state.copyWith(
      images: newImages,
      totalPages: newImages.length,
      currentChapterIndex: nextIndex,
      chapterId: nextChapter.id,
      chapterTitle: result.chapter.title,
      chapterBoundaries: newBoundaries,
      isAppendingNext: false,
    ));
  } catch (e) {
    emit(state.copyWith(isAppendingNext: false));
  }
}
```

Also update `_onLoadChapter` to initialize `chapterBoundaries`:
```dart
// After successful load, add initial boundary:
final initialBoundary = ChapterBoundary(
  startIndex: 0,
  chapterId: event.chapterId,
  chapterTitle: result.chapter.title,
);
emit(state.copyWith(
  // ...existing fields...
  chapterBoundaries: [initialBoundary],
));
```

### Step 3: Update `vertical_reader.dart` to dispatch `AppendNextChapter`

Change line 69 from:
```dart
context.read<ReaderBloc>().add(const LoadNextChapter());
```
to:
```dart
context.read<ReaderBloc>().add(const AppendNextChapter());
```

Also add a loading indicator at the bottom when appending:

```dart
@override
Widget build(BuildContext context) {
  return BlocBuilder<ReaderBloc, ReaderState>(
    buildWhen: (prev, curr) => prev.isAppendingNext != curr.isAppendingNext,
    builder: (context, readerState) {
      return GestureDetector(
        onTapUp: _onTap,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: widget.images.length + (readerState.isAppendingNext ? 1 : 0),
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            if (index >= widget.images.length) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final state = context.read<ReaderBloc>().state;
            return SizedBox(
              width: double.infinity,
              child: MangaImage(
                image: widget.images[index],
                fit: BoxFit.fitWidth,
                sourceId: state.sourceId,
                mangaId: state.mangaId,
                chapterId: state.chapterId,
                imageIndex: index,
              ),
            );
          },
        ),
      );
    },
  );
}
```

### Step 4: Update progress saving in `_onPageChanged` for multi-chapter

The current `_onPageChanged` should save progress for the correct chapter based on boundaries:

```dart
void _onPageChanged(PageChanged event, Emitter<ReaderState> emit) {
  emit(state.copyWith(currentPage: event.page));
  if (state.sourceId.isEmpty || state.mangaId.isEmpty) return;

  // Find which chapter this page belongs to
  String chapterId = state.chapterId;
  int pageInChapter = event.page;
  for (int i = state.chapterBoundaries.length - 1; i >= 0; i--) {
    if (event.page >= state.chapterBoundaries[i].startIndex) {
      chapterId = state.chapterBoundaries[i].chapterId;
      pageInChapter = event.page - state.chapterBoundaries[i].startIndex;
      break;
    }
  }
  _historyStore.saveProgress(state.sourceId, state.mangaId, chapterId, pageInChapter);
}
```

### Step 5: Verify

Run: `cd comic-reader && flutter analyze`
Expected: No errors.

Manual test: Open a manga with multiple chapters in vertical mode, scroll to bottom — next chapter images should append seamlessly.

---

## Task 2: Batch Update Checking + "New" Badge

**Goal:** Add a refresh button on the bookshelf that checks all favorites for new chapters and shows a "new" badge on updated manga.

**Files:**
- Create: `lib/data/local/update_store.dart`
- Create: `lib/presentation/home/bloc/home_cubit.dart`
- Create: `lib/presentation/home/bloc/home_state.dart`
- Modify: `lib/presentation/home/home_screen.dart`
- Modify: `lib/app/di/injection.dart`

### Step 1: Create `update_store.dart`

```dart
import 'local_storage.dart';

/// Tracks which manga have unread updates (new chapters since last viewed).
class UpdateStore {
  final LocalStorage _storage;
  static const _key = 'update_status';

  Map<String, dynamic>? _cache;

  UpdateStore({required LocalStorage storage}) : _storage = storage;

  Future<Map<String, dynamic>> _getData() async {
    _cache ??= await _storage.read(_key) ?? {};
    return _cache!;
  }

  /// Check if a manga has new chapters.
  Future<bool> hasUpdate(String sourceId, String mangaId) async {
    final data = await _getData();
    final key = '${sourceId}_$mangaId';
    return data[key] == true;
  }

  /// Mark a manga as having new chapters.
  Future<void> markUpdated(String sourceId, String mangaId) async {
    final data = await _getData();
    data['${sourceId}_$mangaId'] = true;
    _cache = data;
    await _storage.write(_key, data);
  }

  /// Clear update badge for a manga (user opened it).
  Future<void> clearUpdate(String sourceId, String mangaId) async {
    final data = await _getData();
    data.remove('${sourceId}_$mangaId');
    _cache = data;
    await _storage.write(_key, data);
  }

  /// Get all manga keys that have updates.
  Future<Set<String>> getAllUpdated() async {
    final data = await _getData();
    return data.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toSet();
  }

  /// Clear all update badges.
  Future<void> clearAll() async {
    _cache = {};
    await _storage.write(_key, {});
  }
}
```

### Step 2: Create `home_cubit.dart` and `home_state.dart`

**`lib/presentation/home/bloc/home_state.dart`:**

```dart
import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum HomeStatus { initial, loading, loaded, updating }

class HomeState extends Equatable {
  final HomeStatus status;
  final List<MangaSummary> favorites;
  final Set<String> updatedKeys; // "${sourceId}_${mangaId}" keys
  final int updateProgress; // 0-based index of current batch item
  final int updateTotal; // total items to check
  final String? errorMessage;

  const HomeState({
    this.status = HomeStatus.initial,
    this.favorites = const [],
    this.updatedKeys = const {},
    this.updateProgress = 0,
    this.updateTotal = 0,
    this.errorMessage,
  });

  HomeState copyWith({
    HomeStatus? status,
    List<MangaSummary>? favorites,
    Set<String>? updatedKeys,
    int? updateProgress,
    int? updateTotal,
    String? errorMessage,
  }) {
    return HomeState(
      status: status ?? this.status,
      favorites: favorites ?? this.favorites,
      updatedKeys: updatedKeys ?? this.updatedKeys,
      updateProgress: updateProgress ?? this.updateProgress,
      updateTotal: updateTotal ?? this.updateTotal,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  bool hasUpdate(String sourceId, String mangaId) =>
      updatedKeys.contains('${sourceId}_$mangaId');

  @override
  List<Object?> get props =>
      [status, favorites, updatedKeys, updateProgress, updateTotal, errorMessage];
}
```

**`lib/presentation/home/bloc/home_cubit.dart`:**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  final FavoritesStore _favoritesStore;
  final UpdateStore _updateStore;
  final MangaRepository _repository;

  HomeCubit({
    required FavoritesStore favoritesStore,
    required UpdateStore updateStore,
    required MangaRepository repository,
  })  : _favoritesStore = favoritesStore,
        _updateStore = updateStore,
        _repository = repository,
        super(const HomeState());

  Future<void> loadFavorites() async {
    emit(state.copyWith(status: HomeStatus.loading));
    final favorites = await _favoritesStore.getAll();
    final updatedKeys = await _updateStore.getAllUpdated();
    emit(state.copyWith(
      status: HomeStatus.loaded,
      favorites: favorites,
      updatedKeys: updatedKeys,
    ));
  }

  /// Check all favorites for new chapters.
  Future<void> batchUpdate() async {
    if (state.favorites.isEmpty) return;

    emit(state.copyWith(
      status: HomeStatus.updating,
      updateProgress: 0,
      updateTotal: state.favorites.length,
    ));

    for (int i = 0; i < state.favorites.length; i++) {
      final manga = state.favorites[i];
      emit(state.copyWith(updateProgress: i));

      try {
        final detail = await _repository.getMangaInfo(manga.sourceId, manga.id);
        // Compare latest chapter from API with stored value
        if (detail.latestChapter != null &&
            detail.latestChapter != manga.latestChapter &&
            detail.latestChapter!.isNotEmpty) {
          await _updateStore.markUpdated(manga.sourceId, manga.id);
        }
      } catch (_) {
        // Skip failed items silently
      }
    }

    final updatedKeys = await _updateStore.getAllUpdated();
    emit(state.copyWith(
      status: HomeStatus.loaded,
      updatedKeys: updatedKeys,
    ));
  }

  /// Clear update badge for one manga.
  Future<void> clearUpdate(String sourceId, String mangaId) async {
    await _updateStore.clearUpdate(sourceId, mangaId);
    final updatedKeys = await _updateStore.getAllUpdated();
    emit(state.copyWith(updatedKeys: updatedKeys));
  }
}
```

### Step 3: Register `UpdateStore` in DI

In `lib/app/di/injection.dart`, after the `ReadingHistoryStore` registration, add:

```dart
import 'package:comic_reader/data/local/update_store.dart';

// ... in configureDependencies():
getIt.registerLazySingleton<UpdateStore>(
  () => UpdateStore(storage: getIt<LocalStorage>()),
);
```

### Step 4: Rewrite `home_screen.dart` to use `HomeCubit`

Key changes:
- Replace `StatefulWidget` direct store usage with `BlocProvider<HomeCubit>`
- Add refresh/batch-update button in AppBar
- Add "NEW" badge overlay on manga cards with updates
- Clear update badge when user taps into a manga detail

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/core/utils/responsive.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'bloc/home_cubit.dart';
import 'bloc/home_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(
        favoritesStore: GetIt.instance<FavoritesStore>(),
        updateStore: GetIt.instance<UpdateStore>(),
        repository: GetIt.instance<MangaRepository>(),
      )..loadFavorites(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画阅读器'),
        actions: [
          // Batch update button with progress indicator
          BlocBuilder<HomeCubit, HomeState>(
            buildWhen: (p, c) =>
                p.status != c.status || p.updateProgress != c.updateProgress,
            builder: (context, state) {
              if (state.status == HomeStatus.updating) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${state.updateProgress + 1}/${state.updateTotal}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '检查更新',
                onPressed: () => context.read<HomeCubit>().batchUpdate(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => context.push(AppRoutes.search),
          ),
        ],
      ),
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          if (state.status == HomeStatus.initial || state.status == HomeStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.favorites.isEmpty) {
            return _buildEmptyState(context);
          }
          return Responsive.constrainedContent(
            context: context,
            child: RefreshIndicator(
              onRefresh: () => context.read<HomeCubit>().loadFavorites(),
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Responsive.gridColumns(context),
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: state.favorites.length,
                itemBuilder: (context, index) {
                  final manga = state.favorites[index];
                  final hasUpdate = state.hasUpdate(manga.sourceId, manga.id);
                  return _MangaCard(manga: manga, hasUpdate: hasUpdate);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.collections_bookmark_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('暂无收藏',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          Text('去发现页面浏览漫画吧',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              final shell = StatefulNavigationShell.maybeOf(context);
              if (shell != null) {
                shell.goBranch(1);
              } else {
                context.push(AppRoutes.discovery);
              }
            },
            icon: const Icon(Icons.explore),
            label: const Text('去发现'),
          ),
        ],
      ),
    );
  }
}

class _MangaCard extends StatelessWidget {
  final MangaSummary manga;
  final bool hasUpdate;

  const _MangaCard({required this.manga, required this.hasUpdate});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        // Clear update badge when user opens the manga
        if (hasUpdate) {
          context.read<HomeCubit>().clearUpdate(manga.sourceId, manga.id);
        }
        await context.push(
          AppRoutes.detail
              .replaceFirst(':sourceId', manga.sourceId)
              .replaceFirst(':mangaId', manga.id),
        );
        context.read<HomeCubit>().loadFavorites();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: ImageProxy.url(manga.coverUrl),
                    httpHeaders: ImageProxy.safeHeaders(manga.headers),
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
                if (hasUpdate)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
```

### Step 5: Update `FavoritesStore` to persist `latestChapter` from API responses

The `FavoritesStore.add()` already stores `latestChapter`. However, we need a method to update it after batch check:

Add to `favorites_store.dart`:

```dart
/// Update the stored latestChapter for a manga (called after batch update finds new chapters).
Future<void> updateLatestChapter(String sourceId, String mangaId, String latestChapter) async {
  final favorites = await getAll();
  final index = favorites.indexWhere((m) => m.id == mangaId && m.sourceId == sourceId);
  if (index == -1) return;
  final updated = MangaSummary(
    id: favorites[index].id,
    sourceId: favorites[index].sourceId,
    title: favorites[index].title,
    coverUrl: favorites[index].coverUrl,
    author: favorites[index].author,
    latestChapter: latestChapter,
    updateTime: favorites[index].updateTime,
    headers: favorites[index].headers,
  );
  _cache![index] = updated;
  await _save();
}
```

### Step 6: Verify

Run: `cd comic-reader && flutter analyze`
Expected: No errors.

---

## Task 3: Data Backup & Restore

**Goal:** Allow users to export all app data to a JSON file and restore from it.

**Files:**
- Create: `lib/data/local/backup_service.dart`
- Modify: `lib/presentation/settings/settings_screen.dart` (add backup/restore buttons)
- Add dependencies: `share_plus`, `file_picker` to `pubspec.yaml`

### Step 1: Add dependencies

In `pubspec.yaml` under `dependencies:`, add:
```yaml
  share_plus: ^10.1.4
  file_picker: ^8.1.7
```

Run: `cd comic-reader && flutter pub get`

### Step 2: Create `backup_service.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'local_storage.dart';

/// Handles full app data backup and restore.
class BackupService {
  final LocalStorage _storage;

  static const _version = 1;
  static const _storageKeys = [
    'favorites',
    'reading_history',
    'settings',
    'update_status',
  ];

  BackupService({required LocalStorage storage}) : _storage = storage;

  /// Export all app data as a JSON string.
  Future<String> exportData() async {
    final data = <String, dynamic>{
      'version': _version,
      'timestamp': DateTime.now().toIso8601String(),
      'app': 'comic-reader',
    };

    for (final key in _storageKeys) {
      final value = await _storage.read(key);
      if (value != null) {
        data[key] = value;
      }
    }

    return jsonEncode(data);
  }

  /// Share the backup file via system share sheet.
  Future<void> shareBackup() async {
    final json = await exportData();

    if (kIsWeb) {
      // On web, trigger download via JS
      throw UnsupportedError('Backup share not supported on web');
    }

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/comic_reader_backup_$timestamp.json');
    await file.writeAsString(json);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Comic Reader Backup',
      ),
    );
  }

  /// Import data from a JSON string. Returns true on success.
  Future<bool> importData(String jsonString) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate
      if (data['app'] != 'comic-reader') return false;
      final version = data['version'] as int? ?? 0;
      if (version < 1) return false;

      // Restore each key
      for (final key in _storageKeys) {
        if (data.containsKey(key) && data[key] is Map<String, dynamic>) {
          await _storage.write(key, data[key] as Map<String, dynamic>);
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}
```

### Step 3: Register in DI

In `injection.dart`:
```dart
import 'package:comic_reader/data/local/backup_service.dart';

// In configureDependencies():
getIt.registerLazySingleton<BackupService>(
  () => BackupService(storage: getIt<LocalStorage>()),
);
```

### Step 4: Add backup/restore UI to settings screen

In the "数据管理" (Data Management) section of `settings_screen.dart`, add two buttons:

```dart
ListTile(
  leading: const Icon(Icons.upload),
  title: const Text('备份数据'),
  subtitle: const Text('导出收藏、历史、设置到文件'),
  onTap: () async {
    try {
      final backupService = GetIt.instance<BackupService>();
      await backupService.shareBackup();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份文件已生成')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e')),
        );
      }
    }
  },
),
ListTile(
  leading: const Icon(Icons.download),
  title: const Text('恢复数据'),
  subtitle: const Text('从备份文件恢复所有数据'),
  onTap: () async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);
    final json = await file.readAsString();

    final backupService = GetIt.instance<BackupService>();
    final success = await backupService.importData(json);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '恢复成功，请重启应用' : '恢复失败：文件格式错误'),
        ),
      );
    }
  },
),
```

Add import at top of settings_screen.dart:
```dart
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:comic_reader/data/local/backup_service.dart';
```

### Step 5: Verify

Run: `cd comic-reader && flutter analyze`
Expected: No errors.

---

## Task 4: Long-Press Save Image to Gallery

**Goal:** Long-press on any image in the reader to save it to the device photo gallery.

**Files:**
- Add dependency: `image_gallery_saver_plus` (or `gal`) to `pubspec.yaml`
- Modify: `lib/presentation/reader/widgets/manga_image.dart`
- Possibly modify: `lib/presentation/reader/widgets/vertical_reader.dart`
- Possibly modify: `lib/presentation/reader/widgets/horizontal_reader.dart`

### Step 1: Add dependency

In `pubspec.yaml`:
```yaml
  gal: ^2.3.0
```

Run: `cd comic-reader && flutter pub get`

Also add iOS permissions to `ios/Runner/Info.plist`:
```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save manga images to your photo library</string>
```

And Android permissions in `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
```

### Step 2: Create a save image utility

Add a helper function (can be in a new file `lib/core/utils/save_image.dart`):

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Save an image from URL to device gallery.
Future<bool> saveImageToGallery(String url, {Map<String, String>? headers}) async {
  if (kIsWeb) return false;

  try {
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers,
      ),
    );

    final bytes = Uint8List.fromList(response.data!);
    final dir = await getTemporaryDirectory();
    final ext = url.contains('.png') ? 'png' : 'jpg';
    final file = File('${dir.path}/save_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsBytes(bytes);

    await Gal.putImage(file.path);
    await file.delete();
    return true;
  } catch (_) {
    return false;
  }
}
```

### Step 3: Add long-press handler to `MangaImage` widget

Wrap the image in a `GestureDetector` with `onLongPress`:

```dart
GestureDetector(
  onLongPress: () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存图片'),
        content: const Text('是否保存此图片到相册？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final success = await saveImageToGallery(
        image.url,
        headers: image.headers,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '已保存到相册' : '保存失败')),
        );
      }
    }
  },
  child: /* existing image widget */,
)
```

### Step 4: Verify

Run: `cd comic-reader && flutter analyze`
Expected: No errors.

---

## Task 5: Chapter Read/Unread Markers

**Goal:** Show visual indicators on chapter tiles in the detail screen showing which chapters have been read.

**Files:**
- Modify: `lib/data/local/reading_history_store.dart` (add method to get all read chapters for a manga)
- Modify: `lib/presentation/detail/bloc/detail_cubit.dart` (load read chapters)
- Modify: `lib/presentation/detail/bloc/detail_state.dart` (add readChapterIds)
- Modify: `lib/presentation/detail/detail_screen.dart` (show visual marker)

### Step 1: Add `getReadChapters` to `ReadingHistoryStore`

```dart
/// Get all chapter IDs that have been read for a manga.
/// Returns a set of chapterId strings.
Future<Set<String>> getReadChapters(String sourceId, String mangaId) async {
  final data = await _getData();
  final Set<String> result = {};
  // The main progress key stores the last-read chapter
  final key = '${sourceId}_$mangaId';
  final entry = data[key];
  if (entry is Map<String, dynamic> && entry['chapterId'] != null) {
    result.add(entry['chapterId'] as String);
  }
  // Also check per-chapter keys if stored
  final chapterHistoryKey = '${sourceId}_${mangaId}_chapters';
  final chapters = data[chapterHistoryKey];
  if (chapters is List) {
    result.addAll(chapters.cast<String>());
  }
  return result;
}

/// Record that a chapter has been visited.
Future<void> markChapterRead(String sourceId, String mangaId, String chapterId) async {
  final data = await _getData();
  final key = '${sourceId}_${mangaId}_chapters';
  final chapters = (data[key] as List<dynamic>?)?.cast<String>().toSet() ?? {};
  chapters.add(chapterId);
  data[key] = chapters.toList();
  _cache = data;
  await _storage.write(_key, data);
}
```

### Step 2: Update `detail_state.dart`

Add a field:
```dart
final Set<String> readChapterIds;
```

Default: `this.readChapterIds = const {}`, add to `copyWith` and `props`.

### Step 3: Update `detail_cubit.dart`

In `loadDetail()`, after loading chapters, also load read status:

```dart
final readChapters = await _historyStore.getReadChapters(sourceId, mangaId);
emit(state.copyWith(readChapterIds: readChapters));
```

(Add `ReadingHistoryStore _historyStore` as a dependency to DetailCubit.)

### Step 4: Update chapter grid in `detail_screen.dart`

For each chapter tile, check if it's been read and show a dot/icon:

```dart
final isRead = state.readChapterIds.contains(chapter.id);
// Show a small colored dot or dimmed text for read chapters
Container(
  decoration: BoxDecoration(
    border: Border.all(
      color: isRead ? Colors.grey.shade300 : Theme.of(context).colorScheme.outline,
    ),
    borderRadius: BorderRadius.circular(6),
    color: isRead ? Colors.grey.shade100 : null,
  ),
  child: /* existing chapter tile content */,
)
```

### Step 5: Mark chapter as read when reader opens

In `reader_bloc.dart` `_onLoadChapter`, after successful load:
```dart
_historyStore.markChapterRead(event.sourceId, event.mangaId, event.chapterId);
```

### Step 6: Verify

Run: `cd comic-reader && flutter analyze`
Expected: No errors.

---

## Task 6: Bookshelf Multi-Select + Batch Delete

**Goal:** Long-press on the bookshelf to enter selection mode, then batch delete favorites.

**Files:**
- Modify: `lib/presentation/home/bloc/home_state.dart` (add selection state)
- Modify: `lib/presentation/home/bloc/home_cubit.dart` (add selection methods)
- Modify: `lib/presentation/home/home_screen.dart` (add selection UI)

### Step 1: Add selection fields to `HomeState`

```dart
final bool isSelecting;
final Set<String> selectedKeys; // "${sourceId}_${mangaId}" format
```

Defaults: `this.isSelecting = false, this.selectedKeys = const {}`.

Add to `copyWith` and `props`.

### Step 2: Add selection methods to `HomeCubit`

```dart
void enterSelectionMode(String sourceId, String mangaId) {
  emit(state.copyWith(
    isSelecting: true,
    selectedKeys: {'${sourceId}_$mangaId'},
  ));
}

void toggleSelection(String sourceId, String mangaId) {
  final key = '${sourceId}_$mangaId';
  final newSet = Set<String>.from(state.selectedKeys);
  if (newSet.contains(key)) {
    newSet.remove(key);
  } else {
    newSet.add(key);
  }
  // Exit selection mode if nothing selected
  if (newSet.isEmpty) {
    emit(state.copyWith(isSelecting: false, selectedKeys: {}));
  } else {
    emit(state.copyWith(selectedKeys: newSet));
  }
}

void selectAll() {
  final allKeys = state.favorites
      .map((m) => '${m.sourceId}_${m.id}')
      .toSet();
  emit(state.copyWith(selectedKeys: allKeys));
}

void exitSelectionMode() {
  emit(state.copyWith(isSelecting: false, selectedKeys: {}));
}

Future<void> deleteSelected() async {
  for (final key in state.selectedKeys) {
    final parts = key.split('_');
    if (parts.length >= 2) {
      final sourceId = parts[0];
      final mangaId = parts.sublist(1).join('_');
      await _favoritesStore.remove(sourceId, mangaId);
    }
  }
  emit(state.copyWith(isSelecting: false, selectedKeys: {}));
  await loadFavorites();
}
```

### Step 3: Update `_HomeView` and `_MangaCard`

- Long-press on card: enter selection mode
- When selecting: show checkboxes, AppBar changes to show count + delete button
- Tap while selecting: toggle selection

In AppBar when `state.isSelecting`:
```dart
AppBar(
  leading: IconButton(
    icon: const Icon(Icons.close),
    onPressed: () => context.read<HomeCubit>().exitSelectionMode(),
  ),
  title: Text('已选 ${state.selectedKeys.length} 项'),
  actions: [
    IconButton(
      icon: const Icon(Icons.select_all),
      tooltip: '全选',
      onPressed: () => context.read<HomeCubit>().selectAll(),
    ),
    IconButton(
      icon: const Icon(Icons.delete),
      tooltip: '删除',
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确定删除 ${state.selectedKeys.length} 个收藏吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          context.read<HomeCubit>().deleteSelected();
        }
      },
    ),
  ],
)
```

On `_MangaCard`:
- `onLongPress`: enter selection mode
- `onTap` while selecting: toggle selection
- Show checkbox overlay when selecting

### Step 4: Verify

Run: `cd comic-reader && flutter analyze`
Expected: No errors.

---

## Task 7: Download Task Manager

**Goal:** Create a global persistent download task queue that survives navigation and shows progress.

**Files:**
- Create: `lib/data/local/download_manager.dart`
- Create: `lib/presentation/downloads/download_drawer.dart`
- Modify: `lib/app/di/injection.dart`
- Modify: `lib/presentation/shell/app_shell.dart` (add download indicator)
- Modify or replace existing download logic in detail screen

### Step 1: Create `download_manager.dart`

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'local_storage.dart';

enum DownloadTaskStatus { pending, downloading, completed, failed }

class DownloadTask {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final String mangaTitle;
  final String chapterTitle;
  DownloadTaskStatus status;
  int progress; // 0-100
  String? error;

  DownloadTask({
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    required this.mangaTitle,
    required this.chapterTitle,
    this.status = DownloadTaskStatus.pending,
    this.progress = 0,
    this.error,
  });

  String get key => '${sourceId}_${mangaId}_$chapterId';

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'mangaId': mangaId,
    'chapterId': chapterId,
    'mangaTitle': mangaTitle,
    'chapterTitle': chapterTitle,
    'status': status.index,
    'progress': progress,
    'error': error,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    sourceId: json['sourceId'] as String,
    mangaId: json['mangaId'] as String,
    chapterId: json['chapterId'] as String,
    mangaTitle: json['mangaTitle'] as String? ?? '',
    chapterTitle: json['chapterTitle'] as String? ?? '',
    status: DownloadTaskStatus.values[json['status'] as int? ?? 0],
    progress: json['progress'] as int? ?? 0,
    error: json['error'] as String?,
  );
}

/// Global download manager with persistent queue.
class DownloadManager extends ChangeNotifier {
  final MangaRepository _repository;
  final ChapterCacheService _cacheService;
  final LocalStorage _storage;
  static const _key = 'download_tasks';

  final List<DownloadTask> _tasks = [];
  int _maxConcurrent = 3;
  int _activeCount = 0;
  bool _initialized = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _activeCount;
  int get pendingCount => _tasks.where((t) => t.status == DownloadTaskStatus.pending).length;

  DownloadManager({
    required MangaRepository repository,
    required ChapterCacheService cacheService,
    required LocalStorage storage,
  })  : _repository = repository,
        _cacheService = cacheService,
        _storage = storage;

  /// Initialize and resume incomplete tasks from storage.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final data = await _storage.read(_key);
    if (data != null && data['tasks'] is List) {
      for (final json in (data['tasks'] as List)) {
        final task = DownloadTask.fromJson(json as Map<String, dynamic>);
        // Reset downloading tasks to pending (they were interrupted)
        if (task.status == DownloadTaskStatus.downloading) {
          task.status = DownloadTaskStatus.pending;
          task.progress = 0;
        }
        // Only keep non-completed tasks
        if (task.status != DownloadTaskStatus.completed) {
          _tasks.add(task);
        }
      }
    }
    _processQueue();
  }

  /// Add a download task.
  Future<void> addTask({
    required String sourceId,
    required String mangaId,
    required String chapterId,
    required String mangaTitle,
    required String chapterTitle,
  }) async {
    // Skip if already exists
    final key = '${sourceId}_${mangaId}_$chapterId';
    if (_tasks.any((t) => t.key == key && t.status != DownloadTaskStatus.failed)) return;

    // Remove existing failed task with same key
    _tasks.removeWhere((t) => t.key == key && t.status == DownloadTaskStatus.failed);

    _tasks.add(DownloadTask(
      sourceId: sourceId,
      mangaId: mangaId,
      chapterId: chapterId,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
    ));
    await _persist();
    notifyListeners();
    _processQueue();
  }

  /// Add multiple tasks at once.
  Future<void> addTasks(List<DownloadTask> tasks) async {
    for (final task in tasks) {
      final key = task.key;
      if (!_tasks.any((t) => t.key == key && t.status != DownloadTaskStatus.failed)) {
        _tasks.removeWhere((t) => t.key == key && t.status == DownloadTaskStatus.failed);
        _tasks.add(task);
      }
    }
    await _persist();
    notifyListeners();
    _processQueue();
  }

  /// Retry a failed task.
  void retryTask(String key) {
    final task = _tasks.firstWhere((t) => t.key == key, orElse: () => throw StateError('not found'));
    if (task.status == DownloadTaskStatus.failed) {
      task.status = DownloadTaskStatus.pending;
      task.progress = 0;
      task.error = null;
      notifyListeners();
      _processQueue();
    }
  }

  /// Remove a task from the queue.
  void removeTask(String key) {
    _tasks.removeWhere((t) => t.key == key);
    _persist();
    notifyListeners();
  }

  void _processQueue() {
    while (_activeCount < _maxConcurrent) {
      final nextTask = _tasks.cast<DownloadTask?>().firstWhere(
        (t) => t!.status == DownloadTaskStatus.pending,
        orElse: () => null,
      );
      if (nextTask == null) break;
      _activeCount++;
      _downloadTask(nextTask);
    }
  }

  Future<void> _downloadTask(DownloadTask task) async {
    task.status = DownloadTaskStatus.downloading;
    notifyListeners();

    try {
      final result = await _repository.getChapter(
        task.sourceId, task.mangaId, task.chapterId, 1,
      );
      final images = result.chapter.images;
      
      // Cache images (ChapterCacheService handles actual file saving)
      await _cacheService.cacheChapter(
        task.sourceId, task.mangaId, task.chapterId, images,
      );

      task.status = DownloadTaskStatus.completed;
      task.progress = 100;
    } catch (e) {
      task.status = DownloadTaskStatus.failed;
      task.error = e.toString();
    }

    _activeCount--;
    await _persist();
    notifyListeners();
    _processQueue();
  }

  Future<void> _persist() async {
    final tasks = _tasks.where((t) => t.status != DownloadTaskStatus.completed).toList();
    await _storage.write(_key, {
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
  }
}
```

### Step 2: Register in DI

```dart
import 'package:comic_reader/data/local/download_manager.dart';

// In configureDependencies():
getIt.registerLazySingleton<DownloadManager>(
  () => DownloadManager(
    repository: getIt<MangaRepository>(),
    cacheService: getIt<ChapterCacheService>(),
    storage: getIt<LocalStorage>(),
  ),
);
```

Initialize in `main.dart` after `configureDependencies()`:
```dart
await getIt<DownloadManager>().init();
```

### Step 3: Create `download_drawer.dart`

A bottom sheet showing download queue:

```dart
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/data/local/download_manager.dart';

class DownloadDrawer extends StatelessWidget {
  const DownloadDrawer({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DownloadDrawer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = GetIt.instance<DownloadManager>();
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return AnimatedBuilder(
          animation: manager,
          builder: (context, _) {
            final tasks = manager.tasks;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text('下载队列 (${tasks.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (manager.activeCount > 0)
                        Text('下载中: ${manager.activeCount}',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: tasks.isEmpty
                      ? const Center(child: Text('暂无下载任务'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            return _TaskTile(task: task, manager: manager);
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _TaskTile extends StatelessWidget {
  final DownloadTask task;
  final DownloadManager manager;

  const _TaskTile({required this.task, required this.manager});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (task.status) {
      DownloadTaskStatus.pending => (Icons.schedule, Colors.grey),
      DownloadTaskStatus.downloading => (Icons.downloading, Colors.blue),
      DownloadTaskStatus.completed => (Icons.check_circle, Colors.green),
      DownloadTaskStatus.failed => (Icons.error, Colors.red),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(task.chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(task.mangaTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: task.status == DownloadTaskStatus.failed
          ? IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => manager.retryTask(task.key),
            )
          : task.status == DownloadTaskStatus.downloading
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
      onLongPress: () {
        manager.removeTask(task.key);
      },
    );
  }
}
```

### Step 4: Add download indicator to `app_shell.dart`

Add a badge or indicator in the navigation that shows active downloads:

```dart
// In the NavigationBar destinations, add a badge to the settings/home icon,
// or add a floating action button for downloads.
// Simplest: Add a download button to the AppBar of home_screen that opens the drawer.
```

In `home_screen.dart` actions, add:
```dart
IconButton(
  icon: Badge(
    isLabelVisible: downloadManager.activeCount > 0,
    label: Text('${downloadManager.activeCount}'),
    child: const Icon(Icons.download),
  ),
  tooltip: '下载',
  onPressed: () => DownloadDrawer.show(context),
),
```

### Step 5: Verify

Run: `cd comic-reader && flutter analyze`
Expected: No errors.

---

## Implementation Notes

### Dependencies Summary (add to pubspec.yaml)

```yaml
dependencies:
  share_plus: ^10.1.4
  file_picker: ^8.1.7
  gal: ^2.3.0
```

### Testing Strategy

Each task should be manually verified:
1. **Infinite scroll:** Open vertical mode, scroll to end of chapter, verify images append
2. **Batch update:** Add favorites, trigger refresh, verify badges appear on updated manga
3. **Backup/Restore:** Export data, clear app, import backup, verify data restored
4. **Save image:** Long-press image in reader, confirm saves to gallery
5. **Read markers:** Read a chapter, go back to detail, verify it shows as read
6. **Multi-select:** Long-press on bookshelf, select multiple, delete
7. **Download manager:** Queue multiple chapters, verify concurrent downloads, check persistence

### Order of Implementation

Implement in the order listed (1-7). Each task is independent and can be committed separately. Tasks 1 and 4 are reader-focused. Tasks 2, 5, 6 are bookshelf/detail-focused. Tasks 3 and 7 are infrastructure.
