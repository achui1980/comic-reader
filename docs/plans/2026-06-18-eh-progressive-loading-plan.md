# EH渐进式加载 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让EH漫画阅读器在解析完所有图片URL之前就能开始浏览，通过Stream化仓库层实现渐进式填充。

**Architecture:** 在 `MangaRepository` 接口新增 `getChapterStream()` 方法返回 `Stream<ChapterResult>`；仓库实现中EH分支每解析一批图片URL就 yield 一次；ReaderBloc 订阅此 Stream 持续更新 state.images；MangaImage 组件在 url 为空时展示占位加载UI。

**Tech Stack:** Flutter / Dart, BLoC, Stream (dart:async), Equatable

---

## Task 1: 扩展 MangaRepository 接口

**Files:**
- Modify: `lib/domain/repositories/manga_repository.dart`

**Step 1: 添加 `getChapterStream` 方法声明**

在 `MangaRepository` 抽象类中添加：

```dart
/// Progressive chapter loading - yields partial results as images are resolved.
/// Falls back to single-emit for sources that don't need progressive loading.
Stream<ChapterResult> getChapterStream(String sourceId, String mangaId, String chapterId, int page, {dynamic extra});
```

**Step 2: 确认文件编译通过**

Run: `cd comic-reader && flutter analyze lib/domain/repositories/manga_repository.dart`
Expected: 会报错因为 impl 还没实现新方法（这是正常的）

---

## Task 2: 实现仓库层 Stream 化

**Files:**
- Modify: `lib/data/repositories/manga_repository_impl.dart`

**Step 1: 添加 `import 'dart:async';` (如果还没有)**

检查文件顶部是否已有 `dart:async` import。当前有 `dart:convert`，需要加 `dart:async`。

**Step 2: 实现 `getChapterStream` 方法**

在 `MangaRepositoryImpl` 类中添加以下方法（在文件末尾 `}` 之前）：

```dart
@override
Stream<ChapterResult> getChapterStream(
  String sourceId,
  String mangaId,
  String chapterId,
  int page, {
  dynamic extra,
}) async* {
  final source = _sourceRegistry.getSource(sourceId);
  if (source == null) {
    throw Exception('Source not found: $sourceId');
  }

  final effectivePage = page > 0 ? page : 1;

  // Phase 1: Initial fetch
  final config = source.prepareChapterFetch(mangaId, chapterId, effectivePage, extra: extra);
  final response = await _httpClient.execute(_mergeHeaders(config, source));
  var result = source.parseChapter(response.data, mangaId, chapterId, effectivePage);

  // Handle JMC source multi-page images (same as getChapter)
  if (result.chapter.images.isNotEmpty && result.canLoadMore) {
    final allImages = List<ChapterImage>.from(result.chapter.images);
    var currentPage = effectivePage;
    while (result.canLoadMore && result.nextPage != null) {
      currentPage = result.nextPage!;
      final nextConfig = source.prepareChapterFetch(mangaId, chapterId, currentPage, extra: extra);
      final nextResponse = await _httpClient.execute(_mergeHeaders(nextConfig, source));
      result = source.parseChapter(nextResponse.data, mangaId, chapterId, currentPage);
      allImages.addAll(result.chapter.images);
    }
    yield ChapterResult(
      chapter: Chapter(
        id: result.chapter.id,
        mangaId: result.chapter.mangaId,
        title: result.chapter.title,
        images: allImages,
      ),
    );
    return;
  }

  // Handle EH-style: images empty + nextExtra has image page URLs
  if (result.chapter.images.isEmpty && result.nextExtra != null) {
    var allImagePageUrls = List<dynamic>.from(jsonDecode(result.nextExtra!));
    debugPrint('[getChapterStream] Starting progressive resolution. Initial URLs: ${allImagePageUrls.length}');

    // Phase 2: Collect all thumbnail pages
    var currentPage = effectivePage;
    var canLoadMore = result.canLoadMore;
    while (canLoadMore && result.nextPage != null) {
      currentPage = result.nextPage!;
      final nextConfig = source.prepareChapterFetch(mangaId, chapterId, currentPage, extra: extra);
      final nextResponse = await _httpClient.execute(_mergeHeaders(nextConfig, source));
      result = source.parseChapter(nextResponse.data, mangaId, chapterId, currentPage);
      if (result.nextExtra != null) {
        final moreUrls = jsonDecode(result.nextExtra!) as List;
        allImagePageUrls.addAll(moreUrls);
      }
      canLoadMore = result.canLoadMore;
    }

    final totalCount = allImagePageUrls.length;
    debugPrint('[getChapterStream] Total pages to resolve: $totalCount');

    // Yield initial state: placeholder images (empty URLs) for total count
    final placeholderImages = List<ChapterImage>.generate(
      totalCount,
      (_) => const ChapterImage(url: ''),
    );
    yield ChapterResult(
      chapter: Chapter(
        id: result.chapter.id,
        mangaId: result.chapter.mangaId,
        title: result.chapter.title,
        images: placeholderImages,
      ),
    );

    // Phase 3: Resolve each image page URL progressively
    final resolvedImages = List<ChapterImage>.from(placeholderImages);
    const batchSize = 5;
    for (int i = 0; i < allImagePageUrls.length; i++) {
      final pageUrl = allImagePageUrls[i];
      try {
        final imgConfig = FetchConfig(url: pageUrl as String);
        final imgResponse = await _httpClient.execute(_mergeHeaders(imgConfig, source));
        final imgHtml = imgResponse.data as String;
        String? imgSrc;
        final srcMatch1 = RegExp(r'<img[^>]+id="img"[^>]+src="([^"]+)"').firstMatch(imgHtml);
        if (srcMatch1 != null) {
          imgSrc = srcMatch1.group(1);
        } else {
          final srcMatch2 = RegExp(r'<img[^>]+src="([^"]+)"[^>]+id="img"').firstMatch(imgHtml);
          if (srcMatch2 != null) {
            imgSrc = srcMatch2.group(1);
          }
        }
        if (imgSrc != null && imgSrc.isNotEmpty) {
          resolvedImages[i] = ChapterImage(
            url: imgSrc,
            headers: source.defaultHeaders != null
                ? Map<String, String>.from(source.defaultHeaders!)
                : null,
          );
        }
      } catch (e) {
        debugPrint('[EH-Stream] Failed to resolve image page [$i] $pageUrl: $e');
      }

      // Yield after every batchSize images or last image
      if ((i + 1) % batchSize == 0 || i == allImagePageUrls.length - 1) {
        yield ChapterResult(
          chapter: Chapter(
            id: result.chapter.id,
            mangaId: result.chapter.mangaId,
            title: result.chapter.title,
            images: List<ChapterImage>.from(resolvedImages),
          ),
        );
      }
    }
    return;
  }

  // Default: non-EH sources just yield once
  yield result;
}
```

**Step 3: 确保原有 `getChapter` 方法保持不变**

不修改原 `getChapter` 方法，保持向后兼容。

**Step 4: 验证编译**

Run: `cd comic-reader && flutter analyze lib/data/repositories/manga_repository_impl.dart`
Expected: PASS (no errors)

---

## Task 3: ReaderBloc 支持 Stream 订阅

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`
- Modify: `lib/presentation/reader/bloc/reader_event.dart`
- Modify: `lib/presentation/reader/bloc/reader_state.dart`

**Step 1: 在 reader_state.dart 中添加 `isProgressiveLoading` 字段**

在 `ReaderState` 类中添加：

```dart
/// Whether images are still being resolved progressively (EH)
final bool isProgressiveLoading;
```

添加到构造函数默认值：`this.isProgressiveLoading = false`

添加到 `copyWith` 参数和返回值中。

添加到 `props` 列表中。

**Step 2: 在 reader_event.dart 中添加 `ImagesUpdated` 事件**

```dart
class ImagesUpdated extends ReaderEvent {
  final List<ChapterImage> images;
  final bool isComplete;

  const ImagesUpdated({required this.images, required this.isComplete});

  @override
  List<Object?> get props => [images, isComplete];
}
```

**Step 3: 在 reader_bloc.dart 中添加 Stream 订阅逻辑**

3a. 添加字段：

```dart
StreamSubscription<ChapterResult>? _chapterStreamSubscription;
```

确保文件顶部有 `import 'dart:async';`

确保导入了 chapter 实体：已有 `import 'package:comic_reader/domain/entities/entities.dart';`（通过 manga_repository）

3b. 注册 ImagesUpdated handler（在构造函数中）：

```dart
on<ImagesUpdated>(_onImagesUpdated);
```

3c. 修改 `_onLoadChapter` 方法：

替换原来的 `_repository.getChapter(...)` 调用，改为订阅 `getChapterStream`：

```dart
Future<void> _onLoadChapter(
    LoadChapter event, Emitter<ReaderState> emit) async {
  // Cancel any existing stream subscription
  await _chapterStreamSubscription?.cancel();
  _chapterStreamSubscription = null;

  emit(state.copyWith(
    status: ReaderStatus.loading,
    sourceId: event.sourceId,
    mangaId: event.mangaId,
    chapterId: event.chapterId,
    chapterList: event.chapterList.isNotEmpty ? event.chapterList : null,
    showControls: false,
    isProgressiveLoading: false,
  ));

  try {
    final stream = _repository.getChapterStream(
      event.sourceId,
      event.mangaId,
      event.chapterId,
      1,
    );

    bool isFirstEmit = true;
    _chapterStreamSubscription = stream.listen(
      (result) {
        if (isFirstEmit) {
          isFirstEmit = false;
          // First emit: set up the reader state
          int chapterIndex = -1;
          if (state.chapterList.isNotEmpty) {
            chapterIndex =
                state.chapterList.indexWhere((c) => c.id == event.chapterId);
          }
          final initialBoundary = ChapterBoundary(
            startIndex: 0,
            chapterId: event.chapterId,
            chapterTitle: result.chapter.title,
          );
          add(ImagesUpdated(
            images: result.chapter.images,
            isComplete: false, // first emit is never complete for EH
          ));
          // We need to emit initial loaded state - do it via an internal event
          // Actually, since listen callback can't use emit, we use add()
        } else {
          // Subsequent emits: update images progressively
          add(ImagesUpdated(
            images: result.chapter.images,
            isComplete: false,
          ));
        }
      },
      onDone: () {
        add(const ImagesUpdated(images: [], isComplete: true));
      },
      onError: (e, stack) {
        debugPrint('[ReaderBloc] Stream error: $e');
        add(ImagesUpdated(images: const [], isComplete: true));
      },
    );
  } catch (e, stack) {
    debugPrint('[ReaderBloc] ERROR loading chapter: $e');
    debugPrint('[ReaderBloc] Stack: ${stack.toString().split('\n').take(5).join('\n')}');
    emit(state.copyWith(
      status: ReaderStatus.error,
      errorMessage: e.toString(),
    ));
  }
}
```

**注意**: BLoC的 `listen` 回调中不能直接使用 `emit`。必须用 `add()` 发送事件。因此需要重构为：第一次数据到达时通过 `_onImagesUpdated` handler 设置初始状态。

3d. 实现 `_onImagesUpdated`：

```dart
void _onImagesUpdated(ImagesUpdated event, Emitter<ReaderState> emit) {
  if (event.isComplete && event.images.isEmpty) {
    // Stream completed - just mark progressive loading as done
    emit(state.copyWith(isProgressiveLoading: false));
    _historyStore.markChapterRead(state.sourceId, state.mangaId, state.chapterId);
    return;
  }

  if (state.status == ReaderStatus.loading) {
    // First batch arrived - transition to loaded
    int chapterIndex = -1;
    if (state.chapterList.isNotEmpty) {
      chapterIndex = state.chapterList.indexWhere((c) => c.id == state.chapterId);
    }
    final initialBoundary = ChapterBoundary(
      startIndex: 0,
      chapterId: state.chapterId,
      chapterTitle: state.chapterTitle ?? '',
    );
    emit(state.copyWith(
      status: ReaderStatus.loaded,
      images: event.images,
      currentPage: 0,
      totalPages: event.images.length,
      currentChapterIndex: chapterIndex,
      lastLoadedChapterIndex: chapterIndex,
      errorMessage: null,
      chapterBoundaries: [initialBoundary],
      isAppendingNext: false,
      isProgressiveLoading: true,
    ));
    debugPrint('[ReaderBloc] First batch: ${event.images.length} images (progressive)');
  } else {
    // Subsequent batches - update images list
    emit(state.copyWith(
      images: event.images,
      totalPages: event.images.length,
      isProgressiveLoading: true,
    ));
    debugPrint('[ReaderBloc] Updated: ${event.images.where((img) => img.url.isNotEmpty).length}/${event.images.length} resolved');
  }
}
```

3e. 在 `close()` 方法中取消订阅：

```dart
@override
Future<void> close() {
  _autoPageTimer?.cancel();
  _chapterStreamSubscription?.cancel();
  return super.close();
}
```

3f. 也在 `_onLoadChapter` 顶部取消旧订阅（已在上面的代码中包含）。

**Step 4: 验证编译**

Run: `cd comic-reader && flutter analyze lib/presentation/reader/bloc/`
Expected: PASS

---

## Task 4: MangaImage 支持空 URL 占位符

**Files:**
- Modify: `lib/presentation/reader/widgets/manga_image.dart`

**Step 1: 在 `build()` 方法中增加空 URL 检测**

在 `_buildImageContent()` 方法开头（line 179之后）添加空URL检测：

```dart
Widget _buildImageContent() {
  // Placeholder for images not yet resolved (progressive loading)
  if (widget.image.url.isEmpty) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(strokeWidth: 2),
          SizedBox(height: 8),
          Text(
            '加载中...',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // If we have a local file, load from disk (native only)
  if (_localPath != null) {
    // ... existing code ...
```

**Step 2: 验证编译**

Run: `cd comic-reader && flutter analyze lib/presentation/reader/widgets/manga_image.dart`
Expected: PASS

---

## Task 5: 处理 LoadChapter 的 initialPage 和 chapterTitle

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`

**Step 1: 保存 initialPage 和 chapterTitle 到 LoadChapter 流程中**

问题：当前 `_onLoadChapter` 中 `event.initialPage` 用于首次emit的 `currentPage`。Stream方式中，第一次 `ImagesUpdated` 到达时已丢失了 event 引用。

解决方案：在 `_onLoadChapter` 中emit loading状态时，就把 initialPage 设置到 state：

在loading emit中增加 `currentPage: event.initialPage`：

```dart
emit(state.copyWith(
  status: ReaderStatus.loading,
  sourceId: event.sourceId,
  mangaId: event.mangaId,
  chapterId: event.chapterId,
  chapterList: event.chapterList.isNotEmpty ? event.chapterList : null,
  showControls: false,
  isProgressiveLoading: false,
  currentPage: event.initialPage,
));
```

然后在 `_onImagesUpdated` 第一次到达时，使用 `state.currentPage` (已经是 initialPage)：

```dart
emit(state.copyWith(
  status: ReaderStatus.loaded,
  images: event.images,
  currentPage: state.currentPage,  // preserve initialPage set during loading
  totalPages: event.images.length,
  // ...
));
```

**Step 2: chapterTitle 的传递**

Stream中的 `result.chapter.title` 在第一次emit时会带过来。在 `_onImagesUpdated` 中需要从状态外获取。

解决方案：修改 `ImagesUpdated` 事件增加可选 title 字段：

```dart
class ImagesUpdated extends ReaderEvent {
  final List<ChapterImage> images;
  final bool isComplete;
  final String? chapterTitle;

  const ImagesUpdated({required this.images, required this.isComplete, this.chapterTitle});

  @override
  List<Object?> get props => [images, isComplete, chapterTitle];
}
```

在 stream.listen 第一次回调时传递 title：

```dart
add(ImagesUpdated(
  images: result.chapter.images,
  isComplete: false,
  chapterTitle: result.chapter.title,
));
```

在 `_onImagesUpdated` 中使用：

```dart
emit(state.copyWith(
  // ...
  chapterTitle: event.chapterTitle ?? state.chapterTitle,
  // ...
));
```

---

## Task 6: 处理 `_onRefreshChapter` 和 `_onAppendNextChapter`

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`

**Step 1: 查看当前 `_onRefreshChapter` 和 `_onAppendNextChapter` 实现**

这两个方法也调用 `_repository.getChapter()`。对于简单实现，它们可以保持使用旧的 `getChapter`（非stream版本），因为：
- `RefreshChapter`：重新加载当前章节，可以使用 stream 版
- `AppendNextChapter`：追加下一章节图片，一般不是EH

**Step 2: 让 `_onRefreshChapter` 也使用 stream**

将 `_onRefreshChapter` 改为调用相同的 loadChapter 逻辑（直接 `add(LoadChapter(...))` 重触发）：

```dart
void _onRefreshChapter(RefreshChapter event, Emitter<ReaderState> emit) {
  // Re-trigger load using current state
  add(LoadChapter(
    sourceId: state.sourceId,
    mangaId: state.mangaId,
    chapterId: state.chapterId,
    chapterList: state.chapterList,
    initialPage: state.currentPage,
  ));
}
```

**Step 3: `_onAppendNextChapter` 保持不变**（仍用 `getChapter`）

追加章节用一次性加载即可，因为目标是快速看到当前章节的首批图片。

---

## Task 7: UI 中展示渐进加载进度（可选优化）

**Files:**
- Modify: `lib/presentation/reader/reader_screen.dart` (or relevant widget)

**Step 1: 在阅读器顶部栏显示加载进度**

如果 `state.isProgressiveLoading` 为 true，在页面指示器旁显示一个小进度条或文字提示。

具体做法：在 reader_screen 或对应的controls widget中，当 `state.isProgressiveLoading` 时，在页码显示后面追加一个小的加载指示：

```dart
// 在页码显示区域
Text(
  state.isProgressiveLoading
    ? '${state.currentPage + 1}/${state.images.where((i) => i.url.isNotEmpty).length}(${state.totalPages})'
    : '${state.currentPage + 1}/${state.totalPages}',
)
```

这是可选优化，不影响核心功能。

---

## Task 8: 整体测试验证

**Step 1: 静态分析**

Run: `cd comic-reader && flutter analyze`
Expected: No errors

**Step 2: 编译测试**

Run: `cd comic-reader && flutter build web --release`（或对应平台）
Expected: Build successful

**Step 3: 功能验证**

手动测试：
1. 打开EH漫画，观察是否立即显示总页数的占位符
2. 观察页面是否从第1页开始逐步填充真实图片
3. 翻到未解析的页面，应看到加载中占位符
4. 等待全部解析完成，isProgressiveLoading 应变为 false
5. 翻页、滑块、所有交互正常

---

## 修改文件汇总

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `lib/domain/repositories/manga_repository.dart` | 新增方法 | 添加 `getChapterStream` 接口 |
| `lib/data/repositories/manga_repository_impl.dart` | 新增方法 | 实现 `getChapterStream`，含EH渐进解析 |
| `lib/presentation/reader/bloc/reader_state.dart` | 新增字段 | `isProgressiveLoading` |
| `lib/presentation/reader/bloc/reader_event.dart` | 新增事件 | `ImagesUpdated` |
| `lib/presentation/reader/bloc/reader_bloc.dart` | 重构 | Stream订阅 + ImagesUpdated handler |
| `lib/presentation/reader/widgets/manga_image.dart` | 新增逻辑 | 空URL占位符显示 |

**核心思路**: 仓库层 yield 含空URL占位图片列表（确定总数）→ 每解析5个真实URL yield一次 → BLoC 通过 Stream 订阅持续更新 state → Widget 层空URL显示占位加载UI。
