# 预测性预取 (ROADMAP #21) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给垂直阅读器（`VerticalReader`）加预取窗口（滚动接近某页时提前下载后续几张图字节），并给 `reader_bloc` 加"后台预取下一章"（不影响当前显示，仅提前下载下一章图片字节入缓存，用户翻到下一章时体验无缝）。

**Architecture:** 复用 `docs/superpowers/plans/2026-07-29-split-god-files.md` Task 1 产出的 `loadAndCacheImageBytes`（与 `2026-07-29-unify-precache.md` 相同的复用对象）。垂直reader的预取是"读到哪里就多下几张"，bloc层的预取是"新增一个不改变 `state.images` 的旁路事件"，参考 `_onAppendNextChapter`（311-347行）的结构但不 emit 图片。

**Tech Stack:** Flutter, flutter_bloc。

**前置依赖检查：**
Run: `test -f lib/presentation/reader/widgets/manga_image_loader.dart && grep -n "Future<Uint8List> loadAndCacheImageBytes" lib/presentation/reader/widgets/manga_image_loader.dart`
Expected: 输出确认函数存在。若不存在，先执行 `2026-07-29-split-god-files.md` 的 Part A Task 1。

---

## Part A: 垂直阅读器预取窗口

### Task 1: 在 `VerticalReader._onScroll` 加预取窗口

**Files:**
- Modify: `lib/presentation/reader/widgets/vertical_reader.dart:45-65`

- [ ] **Step 1: 记录基线**

Run: `flutter analyze lib/presentation/reader/widgets/vertical_reader.dart`
Expected: `No issues found!`

- [ ] **Step 2: 添加预取窗口逻辑**

原代码（45-65行）：
```dart
  void _onScroll() {
    // Update current page based on scroll position
    if (_scrollController.hasClients && widget.images.isNotEmpty) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final scrollOffset = _scrollController.offset;
      // Estimate current page based on typical manga page aspect ratio (~1.4:1)
      final screenWidth = MediaQuery.of(context).size.width;
      final estimatedImageHeight = screenWidth * 1.4;
      final estimatedPage = (scrollOffset / estimatedImageHeight).floor();
      final page = estimatedPage.clamp(0, widget.images.length - 1);
      context.read<ReaderBloc>().add(PageChanged(page));

      // Check if we've scrolled near the bottom - use BLoC state as guard
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (scrollOffset >= maxScroll - viewportHeight * 0.5) {
        final bloc = context.read<ReaderBloc>();
        if (!bloc.state.isAppendingNext && bloc.state.canAppendNext) {
          bloc.add(const AppendNextChapter());
        }
      }
    }
  }
```

改为（新增预取窗口，紧跟在 `PageChanged` 之后）：
```dart
  /// Tracks which page indices have already been prefetched this session,
  /// to avoid re-issuing the same download on every scroll tick.
  final Set<int> _prefetchedIndices = {};

  void _onScroll() {
    // Update current page based on scroll position
    if (_scrollController.hasClients && widget.images.isNotEmpty) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final scrollOffset = _scrollController.offset;
      // Estimate current page based on typical manga page aspect ratio (~1.4:1)
      final screenWidth = MediaQuery.of(context).size.width;
      final estimatedImageHeight = screenWidth * 1.4;
      final estimatedPage = (scrollOffset / estimatedImageHeight).floor();
      final page = estimatedPage.clamp(0, widget.images.length - 1);
      context.read<ReaderBloc>().add(PageChanged(page));
      _prefetchWindow(page);

      // Check if we've scrolled near the bottom - use BLoC state as guard
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (scrollOffset >= maxScroll - viewportHeight * 0.5) {
        final bloc = context.read<ReaderBloc>();
        if (!bloc.state.isAppendingNext && bloc.state.canAppendNext) {
          bloc.add(const AppendNextChapter());
        }
      }
    }
  }

  /// Prefetches the next 2 images' bytes (mirrors horizontal_reader's
  /// `_precacheAdjacent` window size) so they're already in
  /// [ChapterCacheService] by the time the user scrolls to them.
  void _prefetchWindow(int currentPage) {
    final state = context.read<ReaderBloc>().state;
    for (int i = 1; i <= 2; i++) {
      final nextIdx = currentPage + i;
      if (nextIdx >= widget.images.length) continue;
      if (!_prefetchedIndices.add(nextIdx)) continue; // already prefetched
      final image = widget.images[nextIdx];
      unawaited(
        loadAndCacheImageBytes(
          image: image,
          sourceId: state.sourceId,
          mangaId: state.mangaId,
          chapterId: state.chapterId,
          imageIndex: nextIdx,
        ).catchError((Object e) {
          debugPrint('[VerticalReader] Prefetch failed for index $nextIdx: $e');
          return Uint8List(0);
        }),
      );
    }
  }
```

在文件顶部 import 区添加：
```dart
import 'dart:async' show unawaited;
import 'dart:typed_data' show Uint8List;
import 'package:flutter/foundation.dart' show debugPrint;
import 'manga_image_loader.dart';
```

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/presentation/reader/widgets/vertical_reader.dart`
Expected: `No issues found!`

- [ ] **Step 4: 手动验证**

垂直阅读一部漫画，缓慢滚动，观察：
1. 滚动到某页附近时，后续2张图应该已经预取完成（可通过网络面板或加日志观察 `[VerticalReader] Prefetch` 相关调试输出的时机早于图片真正进入可视区域）
2. 同一张图不应该被重复预取多次（`_prefetchedIndices` 去重生效）
3. 切换章节（`AppendNextChapter` 追加下一章后）预取窗口对新章节的图片依然生效

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/reader/widgets/vertical_reader.dart
git commit -m "feat: add prefetch window to vertical reader (#21)"
```

---

## Part B: reader_bloc 后台预取下一章

### Task 2: 新增 `PrefetchNextChapter` 事件

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_event.dart`

- [ ] **Step 1: 添加事件类**

在 `reader_event.dart` 文件末尾（紧邻现有的 `AppendNextChapter` 定义之后，116-118行附近）添加：
```dart
/// Silently downloads the next chapter's images into
/// [ChapterCacheService] without touching `state.images` — unlike
/// [AppendNextChapter], this does not change what's currently displayed.
/// Dispatched by the reader UI when the user is close to the end of the
/// current chapter, so the next chapter's images are already cached by
/// the time the user actually navigates there.
class PrefetchNextChapter extends ReaderEvent {
  const PrefetchNextChapter();
}
```

确认 `ReaderEvent` 基类的继承方式（`Equatable`/`props`）与其它事件一致：
Run: `grep -n "class AppendNextChapter" -A 5 lib/presentation/reader/bloc/reader_event.dart`
若 `AppendNextChapter` 有 `@override List<Object?> get props => [];`，`PrefetchNextChapter` 也照抄同样的写法。

- [ ] **Step 2: 验证**

Run: `flutter analyze lib/presentation/reader/bloc/reader_event.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/reader/bloc/reader_event.dart
git commit -m "feat: add PrefetchNextChapter event"
```

---

### Task 3: 实现 `_onPrefetchNextChapter` handler

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`

- [ ] **Step 1: 注册事件 handler**

在构造器（15-46行）的 `on<AppendNextChapter>(_onAppendNextChapter);`（第38行）后面添加：
```dart
    on<PrefetchNextChapter>(_onPrefetchNextChapter);
```

- [ ] **Step 2: 添加去重字段**

在类字段区（16-20行附近，紧邻 `_chapterStreamSubscription`）添加：
```dart
  /// Chapter IDs whose images have already been prefetched via
  /// [PrefetchNextChapter], to avoid redundant re-downloads if the event
  /// fires multiple times while the user lingers near the chapter end.
  final Set<String> _prefetchedChapterIds = {};
```

- [ ] **Step 3: 实现 handler**

在 `_onAppendNextChapter`（311-347行）方法之后添加新方法：
```dart
  /// Downloads the next chapter's images into the disk cache without
  /// emitting a new state — this is a read-ahead side effect, distinct
  /// from [AppendNextChapter] which changes what's displayed.
  Future<void> _onPrefetchNextChapter(
    PrefetchNextChapter event, Emitter<ReaderState> emit) async {
    if (!state.canAppendNext) return;

    final nextIndex = state.lastLoadedChapterIndex + 1;
    final nextChapter = state.chapterList[nextIndex];
    if (!_prefetchedChapterIds.add(nextChapter.id)) return; // already done

    try {
      final result = await _repository.getChapter(
        state.sourceId,
        state.mangaId,
        nextChapter.id,
        1,
      );
      for (var i = 0; i < result.chapter.images.length; i++) {
        await loadAndCacheImageBytes(
          image: result.chapter.images[i],
          sourceId: state.sourceId,
          mangaId: state.mangaId,
          chapterId: nextChapter.id,
          imageIndex: i,
        );
      }
    } catch (e, stack) {
      _log.warning('Failed to prefetch next chapter: $e', e, stack);
      // Allow a future retry: this chapter didn't successfully prefetch.
      _prefetchedChapterIds.remove(nextChapter.id);
    }
  }
```

在文件顶部添加 import：
```dart
import '../widgets/manga_image_loader.dart';
```
（核实相对路径：`reader_bloc.dart` 位于 `lib/presentation/reader/bloc/`，`manga_image_loader.dart` 位于 `lib/presentation/reader/widgets/`，故相对路径为 `../widgets/manga_image_loader.dart`。）

- [ ] **Step 4: 在 `_onPageChanged` 里触发预取**

Run: `grep -n "_onPageChanged" lib/presentation/reader/bloc/reader_bloc.dart`
找到 `_onPageChanged` 方法体，在其末尾（emit 新状态之后）添加触发判断：
```dart
    // Prefetch the next chapter's images once the user is within 2 pages
    // of the end of the currently-loaded content.
    if (state.images.isNotEmpty &&
        event.page >= state.images.length - 2 &&
        state.canAppendNext) {
      add(const PrefetchNextChapter());
    }
```
（具体插入位置需核对 `_onPageChanged` 现有方法体结构，确保插入在 `emit(...)` 调用之后，且不影响该方法原有的返回逻辑。）

- [ ] **Step 5: 验证**

Run: `flutter analyze lib/presentation/reader/bloc/reader_bloc.dart`
Expected: `No issues found!`

- [ ] **Step 6: 编写单测**

**Files:**
- Create or modify: `test/presentation/reader/bloc/reader_bloc_test.dart`

Run: `test -f test/presentation/reader/bloc/reader_bloc_test.dart && echo exists || echo missing`

若文件不存在，先核实项目现有 bloc 测试写法参照（本项目目前无 Bloc/Cubit 单测覆盖，需要从零搭建 mock）：
Run: `grep -rn "MockMangaRepository\|class.*Mock.*Repository" test/`
若无现成 mock，使用 `mocktail`（已在 dev_dependencies）新建：
```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';

class _MockMangaRepository extends Mock implements MangaRepository {}
class _MockReadingHistoryStore extends Mock implements ReadingHistoryStore {}
class _MockSettingsStore extends Mock implements SettingsStore {}

void main() {
  late _MockMangaRepository repository;

  setUp(() {
    repository = _MockMangaRepository();
  });

  group('PrefetchNextChapter', () {
    blocTest<ReaderBloc, ReaderState>(
      'does not dispatch when there is no next chapter to append',
      build: () => ReaderBloc(
        repository: repository,
        readingHistoryStore: _MockReadingHistoryStore(),
        settingsStore: _MockSettingsStore(),
      ),
      seed: () => const ReaderState(
        chapterList: [],
        lastLoadedChapterIndex: 0,
      ),
      act: (bloc) => bloc.add(const PrefetchNextChapter()),
      expect: () => <ReaderState>[], // no state emitted, no repository call
      verify: (_) {
        verifyNever(() => repository.getChapter(any(), any(), any(), any()));
      },
    );
  });
}
```

**注意**：上面的测试骨架里的构造参数/mock 类型（`ReadingHistoryStore`/`SettingsStore`）需要核实实际类名与 `ReaderBloc` 构造器签名完全一致（参照 `reader_bloc.dart:22-28`）。测试重点覆盖："没有下一章时不触发"、"有下一章且翻到临界页时触发一次"、"同一章不重复预取"三个场景，具体 mock 的 `repository.getChapter` stub 返回值需要构造合法的 `ChapterResult`（核实 `domain/entities/chapter.dart` 的构造签名）。

- [ ] **Step 7: 运行测试**

Run: `flutter test test/presentation/reader/bloc/reader_bloc_test.dart -r expanded`
Expected: 新增测例全部 PASS

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/reader/bloc/reader_bloc.dart test/presentation/reader/bloc/reader_bloc_test.dart
git commit -m "feat: prefetch next chapter's images in the background (#21)"
```

- [ ] **Step 9: 手动验证**

阅读一部漫画接近当前章节末尾（横向或纵向均可，因为 `_onPageChanged` 在两种 reader 里都会触发），翻到下一章时应该几乎无加载等待（因为图片已经预取进 `ChapterCacheService`）。

- [ ] **Step 10: 更新 ROADMAP.md**

Run: `grep -n "#21" ROADMAP.md`
把对应复选框从 `- [ ]` 改为 `- [x]`。

```bash
git add ROADMAP.md
git commit -m "docs: mark ROADMAP #21 as complete"
```
