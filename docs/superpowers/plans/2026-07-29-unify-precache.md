# 统一 precache 与 byte-cache 路径 (ROADMAP #20) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `horizontal_reader.dart` 的 `_precacheAdjacent` 改走与 `MangaImage` 相同的统一字节加载路径（`loadAndCacheImageBytes`），而不是绕过 headers/`ChapterCacheService`/WebView-fetch 的 `ExtendedNetworkImageProvider`。

**Architecture:** 依赖 `docs/superpowers/plans/2026-07-29-split-god-files.md` Task 1 产出的 `lib/presentation/reader/widgets/manga_image_loader.dart` 里的 `loadAndCacheImageBytes` 函数——**必须先完成该计划的 Part A Task 1，再执行本计划**。本计划只改 `horizontal_reader.dart` 一个文件。

**Tech Stack:** Flutter, dio, extended_image（仅移除对它的 precache 相关用法，不移除整个包——`ExtendedImage.memory`/`ExtendedImageGesturePageView` 等其它用法不受影响）。

**前置依赖检查：**
Run: `test -f lib/presentation/reader/widgets/manga_image_loader.dart && grep -n "Future<Uint8List> loadAndCacheImageBytes" lib/presentation/reader/widgets/manga_image_loader.dart`
Expected: 输出确认函数存在。若不存在，先执行 `2026-07-29-split-god-files.md` 的 Part A Task 1。

---

### Task 1: 改写 `_precacheAdjacent` 复用统一字节加载路径

**Files:**
- Modify: `lib/presentation/reader/widgets/horizontal_reader.dart:124-135`

- [ ] **Step 1: 记录当前基线**

Run: `flutter analyze lib/presentation/reader/widgets/horizontal_reader.dart`
Expected: `No issues found!`

- [ ] **Step 2: 修改 `_precacheAdjacent`**

原代码（124-135行）：
```dart
  /// Precache the next 2 images for smoother page turns.
  void _precacheAdjacent(int currentPage) {
    for (int i = 1; i <= 2; i++) {
      final nextIdx = currentPage + i;
      if (nextIdx < widget.images.length) {
        final image = widget.images[nextIdx];
        if (image.responseEncoding != ImageResponseEncoding.binary) continue;
        final url = ImageProxy.url(image.url);
        precacheImage(ExtendedNetworkImageProvider(url, cache: true), context);
      }
    }
  }
```

改为：
```dart
  /// Precache the next 2 images for smoother page turns. Downloads bytes
  /// through the same [loadAndCacheImageBytes] path used by [MangaImage]
  /// itself, so headers/WebView-fetch/ChapterCacheService are all honored
  /// consistently with the main render path. Fire-and-forget: failures are
  /// swallowed here because MangaImage will retry the load itself if the
  /// prefetch didn't warm the cache in time.
  void _precacheAdjacent(int currentPage) {
    final bloc = context.read<ReaderBloc>();
    final state = bloc.state;
    for (int i = 1; i <= 2; i++) {
      final nextIdx = currentPage + i;
      if (nextIdx >= widget.images.length) continue;
      final image = widget.images[nextIdx];
      unawaited(
        loadAndCacheImageBytes(
          image: image,
          sourceId: state.sourceId,
          mangaId: state.mangaId,
          chapterId: state.chapterId,
          imageIndex: nextIdx,
        ).catchError((Object e) {
          debugPrint('[HorizontalReader] Precache failed for index $nextIdx: $e');
          return Uint8List(0);
        }),
      );
    }
  }
```

在文件顶部 import 区：
- 添加 `import 'dart:async' show unawaited;`
- 添加 `import 'dart:typed_data' show Uint8List;`
- 添加 `import 'manga_image_loader.dart';`
- 移除 `ImageProxy` 相关 import（若本文件其它地方不再使用 `ImageProxy`，确认后删除；若还在别处使用则保留）：
  Run: `grep -n "ImageProxy" lib/presentation/reader/widgets/horizontal_reader.dart`
- 若 `ExtendedNetworkImageProvider`/`precacheImage` 不再被本文件其它地方使用，检查是否可以移除对应 import：
  Run: `grep -n "ExtendedNetworkImageProvider\|precacheImage" lib/presentation/reader/widgets/horizontal_reader.dart`
  （`extended_image` 包本身仍需保留 import，因为 `ExtendedImageGesturePageView`/`ExtendedImageMode` 等其它 API 还在用；只是不再使用 network provider 相关的两个 API。）

- [ ] **Step 3: 验证类型/依赖是否齐全**

Run: `flutter analyze lib/presentation/reader/widgets/horizontal_reader.dart`
Expected: `No issues found!`

若报错 `state.sourceId`/`state.mangaId`/`state.chapterId` 字段不存在或类型不匹配，核实 `lib/presentation/reader/bloc/reader_state.dart` 里的实际字段名（应为 `sourceId`/`mangaId`/`chapterId`，均为 `String` 类型，参照 `MangaImage` 构造调用处 `horizontal_reader.dart` 第219-224行左右的既有用法核对一致性）。

- [ ] **Step 4: 全量分析确认无副作用**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 手动验证**

在模拟器/设备上打开一个需要自定义 headers 才能正常加载图片的漫画源（例如需要 Referer 的源），横向翻页阅读，观察：
1. Network 面板/日志确认预取请求带上了正确的 headers（之前的实现完全不传 headers）
2. 翻到预取过的页面时应该几乎瞬间显示（命中 `ChapterCacheService` 本地缓存），而不是重新走一次完整网络请求
3. 对于走 Cloudflare WebView-fetch 的源（若测试环境有），确认预取不再因为绕过 WebView 而失败
4. 对 `responseEncoding == base64OrBinary` 编码的图源（之前会被 `continue` 跳过），确认现在也能被正确预取

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/reader/widgets/horizontal_reader.dart
git commit -m "fix: unify horizontal reader precache with MangaImage's byte-loader (#20)"
```

- [ ] **Step 7: 更新 ROADMAP.md**

Run: `grep -n "#20" ROADMAP.md`

把 `#20` 对应的复选框从 `- [ ]` 改为 `- [x]`。

```bash
git add ROADMAP.md
git commit -m "docs: mark ROADMAP #20 as complete"
```
