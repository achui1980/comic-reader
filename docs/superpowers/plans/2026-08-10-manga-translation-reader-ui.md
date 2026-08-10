# 漫画翻译接入阅读器 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `ReaderBloc` 支持"翻译开关"，在纵向滚动阅读器里对当前可见且未翻译过的页面自动串行调用 `TranslationPipeline`，并在 UI 上叠加译文（loading/done/error 三态）。

**Architecture:** 扩展现有 `ReaderBloc`（不新建 Controller），新增 3 个事件 + `ReaderState` 里的 `translationEnabled`/`pageTranslations` 两个字段；Bloc 内部维护一个内存队列，永远最多一个页面在翻译中；UI 层（`vertical_reader.dart`/`reader_controls.dart`）纯消费 `ReaderState`，新增两个小组件（`TranslationBadge`、`ReaderTranslationOverlayPainter`，后者从已验证的 PoC painter 直接搬迁逻辑）。

**Tech Stack:** Flutter, `flutter_bloc`, `bloc_test`+`mocktail`（测试），`image` 包解码尺寸，已注册好的 `TranslationPipeline`（GetIt）。

**依据文档：** `docs/superpowers/specs/2026-08-10-manga-translation-reader-ui-design.md`（已提交）

**范围（已与用户确认）：**
1. 首发范围只做纵向滚动模式(`vertical_reader.dart`)，横向翻页模式留待下阶段。
2. 触发方式：阅读器顶部工具栏"翻译"总开关，开启后当前可见且未翻译过的页面自动依次触发翻译。
3. 视觉反馈：翻译中小角标 loading，不阻塞阅读；完成后气泡区域浮现白底遮盖+译文。
4. 开关位置：阅读器顶部工具栏，与"浏览器阅读"图标相邻；**不持久化**，每次进入阅读器默认关闭。
5. 失败处理：小角标变错误图标；点击弹出 `SnackBar` 显示错误信息+"重试"按钮；翻页不自动重试。
6. 复用已有 `loadAndCacheImageBytes` 获取图片字节，不新增下载逻辑。
7. 并发控制：严格串行队列，任意时刻最多一页在翻译中。
8. 技术方案：直接扩展现有 `ReaderBloc`。
9. 明确排除：横向翻页坐标同步、开关持久化、整章批量预翻译、翻译结果导出/分享、对 `manga_image.dart`/`manga_image_network_view.dart` 的任何修改。

---

## 文件结构

| 操作 | 文件 | 职责 |
|---|---|---|
| 改 | `lib/presentation/reader/bloc/reader_state.dart` | 新增 `PageTranslationStatus`/`PageTranslationInfo`，`ReaderState` 新增 2 字段 |
| 改 | `lib/presentation/reader/bloc/reader_event.dart` | 新增 3 个事件 |
| 改 | `lib/presentation/reader/bloc/reader_bloc.dart` | 构造函数可注入 `TranslationPipeline`/`loadImageBytes`；新增串行翻译队列逻辑 |
| 新建 | `lib/presentation/reader/widgets/translation_badge.dart` | loading/error 小角标组件 |
| 新建 | `lib/presentation/reader/widgets/reader_translation_overlay_painter.dart` | 从 PoC painter 搬迁，不含底图绘制 |
| 改 | `lib/presentation/reader/widgets/vertical_reader.dart` | 触发翻译请求 + 叠加层渲染 + 错误 SnackBar |
| 改 | `lib/presentation/reader/widgets/reader_controls.dart` | `_TopBar` 新增翻译开关按钮 |
| 改 | `test/presentation/reader/bloc/reader_bloc_test.dart` | 新增 `group('Translation', ...)` 覆盖队列/开关/重试逻辑 |

**关键实现说明（避免 bloc 报错的坑）：** `_drainTranslationQueue()` 是 fire-and-forget（不被 handler `await`），因此**不能**使用 handler 传入的 `Emitter<ReaderState> emit` 参数（会抛 `emit was called after an event handler completed`）。必须模仿现有 `_applySettings()` 的做法：直接调用 bloc 类级别的 `emit(...)` 方法（`Bloc` 基类暴露的 `@visibleForTesting` 方法），并加 `// ignore: invalid_use_of_visible_for_testing_member` 注释。

---

### Task 1: `ReaderState` 新增翻译相关数据结构

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_state.dart`

- [ ] **Step 1: 新增 import**

在文件顶部 import 块的 `import 'package:flutter/widgets.dart' show BoxFit;` 之前新增：
```dart
import 'dart:ui' show Size;
```
并在 `import 'package:comic_reader/data/local/settings_store.dart' show ScaleType;` 之后新增：
```dart
import 'package:comic_reader/data/translation/models/page_translation.dart';
```

- [ ] **Step 2: 在 `enum ReadingDirection { ltr, rtl }` 之后插入新枚举/类**

```dart
enum PageTranslationStatus { idle, loading, done, error }

/// Per-page translation UI state, keyed by page index in
/// [ReaderState.pageTranslations]. Not persisted — lives only in memory for
/// the current [ReaderBloc] instance / reading session.
class PageTranslationInfo {
  const PageTranslationInfo({
    required this.status,
    this.translation,
    this.errorMessage,
    this.imageSize,
  });

  final PageTranslationStatus status;
  final PageTranslation? translation;
  final String? errorMessage;

  /// Original image pixel size, used by [ReaderTranslationOverlayPainter]
  /// to scale [TextRegion.box] coordinates onto the rendered widget size.
  final Size? imageSize;

  static const idle = PageTranslationInfo(status: PageTranslationStatus.idle);
}
```

- [ ] **Step 3: 给 `ReaderState` 新增两个字段（字段定义区，放在 `showTapZones` 字段之后）**
```dart

  // --- Manga translation overlay (vertical reader only) ---
  /// Whether the user has toggled on translation for the current session.
  /// Not persisted; resets to false every time the reader is opened.
  final bool translationEnabled;
  /// Per-page translation state, keyed by page index.
  final Map<int, PageTranslationInfo> pageTranslations;
```

- [ ] **Step 4: 构造函数默认值（放在 `this.showTapZones = false,` 之后）**
```dart
    this.translationEnabled = false,
    this.pageTranslations = const {},
```

- [ ] **Step 5: `copyWith` 参数列表（放在 `bool? showTapZones,` 之后）与赋值（放在 `showTapZones: showTapZones ?? this.showTapZones,` 之后）**

参数列表新增：
```dart
    bool? translationEnabled,
    Map<int, PageTranslationInfo>? pageTranslations,
```
构造调用新增：
```dart
      translationEnabled: translationEnabled ?? this.translationEnabled,
      pageTranslations: pageTranslations ?? this.pageTranslations,
```

- [ ] **Step 6: `props` 列表（放在 `showTapZones,` 之后）**
```dart
        translationEnabled,
        pageTranslations,
```

- [ ] **Step 7: 静态检查**

Run: `flutter analyze lib/presentation/reader/bloc/reader_state.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**
```bash
git add lib/presentation/reader/bloc/reader_state.dart
git commit -m "feat(reader): add translation state fields to ReaderState"
```

---

### Task 2: 新增翻译相关事件

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_event.dart`

- [ ] **Step 1: 在文件末尾追加**
```dart

/// User toggled the reader's translation switch on/off. When enabled, the
/// currently visible page is immediately queued for translation.
class TranslateChapterToggled extends ReaderEvent {
  final bool enabled;
  const TranslateChapterToggled({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

/// Dispatched (e.g. from scroll callbacks) when a page becomes visible and
/// may need translating. Idempotent: ignored if translation is disabled or
/// the page is already idle/loading/done/error.
class TranslatePageRequested extends ReaderEvent {
  final int pageIndex;
  const TranslatePageRequested({required this.pageIndex});

  @override
  List<Object?> get props => [pageIndex];
}

/// User tapped the error badge's retry action. Unlike
/// [TranslatePageRequested], this unconditionally re-queues the page even if
/// it's currently in an `error` state.
class TranslatePageRetried extends ReaderEvent {
  final int pageIndex;
  const TranslatePageRetried({required this.pageIndex});

  @override
  List<Object?> get props => [pageIndex];
}
```

- [ ] **Step 2: 静态检查**

Run: `flutter analyze lib/presentation/reader/bloc/reader_event.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**
```bash
git add lib/presentation/reader/bloc/reader_event.dart
git commit -m "feat(reader): add translation events"
```

---

### Task 3: `ReaderBloc` 构造函数支持依赖注入（为测试铺路）

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`

- [ ] **Step 1: 新增 imports**

在现有 import 块中，`import 'package:comic_reader/data/local/settings_store.dart' as settings;` 之后、`import '../widgets/manga_image_loader.dart';` 之前插入：
```dart
import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show Size;

import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:comic_reader/data/translation/translation_pipeline.dart';
```

- [ ] **Step 2: 新增私有字段（class 字段区，`_prefetchedChapterIds` 之后）**
```dart
  final TranslationPipeline _translationPipeline;

  /// Injectable for testing; defaults to the real network+cache loader.
  final Future<Uint8List> Function({
    required ChapterImage image,
    String? sourceId,
    String? mangaId,
    String? chapterId,
    int? imageIndex,
  }) _loadImageBytes;

  /// Page index currently being translated, or null if the queue is idle.
  int? _translatingPage;
  final Queue<int> _translationQueue = Queue<int>();
```

- [ ] **Step 3: 改写构造函数**
```dart
  ReaderBloc({
    required MangaRepository repository,
    required ReadingHistoryStore readingHistoryStore,
    required settings.SettingsStore settingsStore,
    TranslationPipeline? translationPipeline,
    Future<Uint8List> Function({
      required ChapterImage image,
      String? sourceId,
      String? mangaId,
      String? chapterId,
      int? imageIndex,
    }) loadImageBytes = loadAndCacheImageBytes,
  })  : _repository = repository,
        _historyStore = readingHistoryStore,
        _settingsStore = settingsStore,
        _translationPipeline =
            translationPipeline ?? GetIt.instance<TranslationPipeline>(),
        _loadImageBytes = loadImageBytes,
        super(const ReaderState()) {
    on<LoadChapter>(_onLoadChapter);
    on<PageChanged>(_onPageChanged);
    on<ToggleControls>(_onToggleControls);
    on<HideControls>(_onHideControls);
    on<ChangeLayoutMode>(_onChangeLayoutMode);
    on<ChangeDirection>(_onChangeDirection);
    on<LoadNextChapter>(_onLoadNextChapter);
    on<LoadPreviousChapter>(_onLoadPreviousChapter);
    on<AppendNextChapter>(_onAppendNextChapter);
    on<PrefetchNextChapter>(_onPrefetchNextChapter);
    on<SeekToPage>(_onSeekToPage);
    on<StartAutoPageTurn>(_onStartAutoPageTurn);
    on<StopAutoPageTurn>(_onStopAutoPageTurn);
    on<AutoPageTick>(_onAutoPageTick);
    on<RefreshChapter>(_onRefreshChapter);
    on<ImagesUpdated>(_onImagesUpdated);
    on<TranslateChapterToggled>(_onTranslateChapterToggled);
    on<TranslatePageRequested>(_onTranslatePageRequested);
    on<TranslatePageRetried>(_onTranslatePageRetried);
    _applySettings();
  }
```

- [ ] **Step 4: 静态检查（此时 handler 方法还不存在，预期会报错，这是中间状态，不要 commit）**

Run: `flutter analyze lib/presentation/reader/bloc/reader_bloc.dart`
Expected: 报 `_onTranslateChapterToggled` 等未定义的错误 —— 这是预期的，Task 4 会补上，先不 commit。

---

### Task 4: 实现翻译开关 `_onTranslateChapterToggled` + 串行队列核心

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`
- Test: `test/presentation/reader/bloc/reader_bloc_test.dart`

- [ ] **Step 1: 在 `close()` 方法之前插入队列核心逻辑与三个 handler**
```dart
  Future<void> _onTranslateChapterToggled(
      TranslateChapterToggled event, Emitter<ReaderState> emit) async {
    emit(state.copyWith(translationEnabled: event.enabled));
    if (event.enabled) {
      _enqueueTranslate(state.currentPage);
    } else {
      // Drop anything not yet started; let an in-flight translation finish
      // normally (its result still lands via _updatePageStatus).
      _translationQueue.clear();
    }
  }

  Future<void> _onTranslatePageRequested(
      TranslatePageRequested event, Emitter<ReaderState> emit) async {
    if (!state.translationEnabled) return;
    final info =
        state.pageTranslations[event.pageIndex] ?? PageTranslationInfo.idle;
    if (info.status != PageTranslationStatus.idle) return;
    _enqueueTranslate(event.pageIndex);
  }

  Future<void> _onTranslatePageRetried(
      TranslatePageRetried event, Emitter<ReaderState> emit) async {
    // Unconditional: bypasses the idle-only guard so a page stuck in
    // `error` can be retried.
    _enqueueTranslate(event.pageIndex);
  }

  void _enqueueTranslate(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= state.images.length) return;
    if (_translationQueue.contains(pageIndex)) return;
    _translationQueue.add(pageIndex);
    unawaited(_drainTranslationQueue());
  }

  Future<void> _drainTranslationQueue() async {
    if (_translatingPage != null || _translationQueue.isEmpty) return;
    final pageIndex = _translationQueue.removeFirst();
    _translatingPage = pageIndex;
    _updatePageStatus(
      pageIndex,
      const PageTranslationInfo(status: PageTranslationStatus.loading),
    );
    try {
      final image = state.images[pageIndex];
      final bytes = await _loadImageBytes(
        image: image,
        sourceId: state.sourceId,
        mangaId: state.mangaId,
        chapterId: state.chapterId,
        imageIndex: pageIndex,
      );
      final decoded = img.decodeImage(bytes);
      final imageSize = decoded != null
          ? Size(decoded.width.toDouble(), decoded.height.toDouble())
          : null;
      final result = await _translationPipeline.translatePage(
        state.sourceId,
        state.mangaId,
        state.chapterId,
        pageIndex,
        bytes,
      );
      _updatePageStatus(
        pageIndex,
        PageTranslationInfo(
          status: PageTranslationStatus.done,
          translation: result,
          imageSize: imageSize,
        ),
      );
    } catch (e) {
      _updatePageStatus(
        pageIndex,
        PageTranslationInfo(
          status: PageTranslationStatus.error,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      _translatingPage = null;
      unawaited(_drainTranslationQueue());
    }
  }

  /// Emits directly via the bloc-level `emit` (rather than a handler's
  /// scoped [Emitter]) because this is invoked from a detached async chain
  /// ([_drainTranslationQueue] is fire-and-forget, mirroring the existing
  /// [_applySettings] pattern below).
  void _updatePageStatus(int pageIndex, PageTranslationInfo info) {
    if (isClosed) return;
    // ignore: invalid_use_of_visible_for_testing_member
    emit(state.copyWith(
      pageTranslations: {...state.pageTranslations, pageIndex: info},
    ));
  }

```

- [ ] **Step 2: 静态检查**

Run: `flutter analyze lib/presentation/reader/bloc/reader_bloc.dart`
Expected: `No issues found!`

- [ ] **Step 3: 在测试文件新增 mock 类和测试用例**

在 `test/presentation/reader/bloc/reader_bloc_test.dart` 顶部 import 区追加（保留原有全部 import）：
```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:comic_reader/data/translation/models/page_translation.dart';
import 'package:comic_reader/data/translation/translation_pipeline.dart';
```

在 `_MockSettingsStore` 类之后新增 mock 类：
```dart
class _MockTranslationPipeline extends Mock implements TranslationPipeline {}
```

在 `main()` 内、`buildBloc()` 定义之后新增共享 fixture 和 helper：
```dart
  late _MockTranslationPipeline translationPipeline;

  const samplePageTranslation = PageTranslation(
    sourceId: 'copy',
    mangaId: 'manga',
    chapterId: 'c1',
    pageIndex: 0,
    regions: [],
    translatedAt: 0,
  );

  Future<Uint8List> fakeLoadImageBytes({
    required ChapterImage image,
    String? sourceId,
    String? mangaId,
    String? chapterId,
    int? imageIndex,
  }) async =>
      Uint8List(0);

  ReaderBloc buildBlocWithTranslation() => ReaderBloc(
        repository: repository,
        readingHistoryStore: readingHistoryStore,
        settingsStore: settingsStore,
        translationPipeline: translationPipeline,
        loadImageBytes: fakeLoadImageBytes,
      );
```
并在 `setUp(() { ... })` 内部追加一行初始化：
```dart
    translationPipeline = _MockTranslationPipeline();
```

新增测试 group（放在文件末尾，`group('PrefetchNextChapter', ...)` 的闭合 `});` 之后，`main()` 函数结束的 `}` 之前）：
```dart

  group('Translation', () {
    const chapterOne = ChapterItem(id: 'c1', mangaId: 'manga', title: 'Ch 1');

    ReaderState seedState({List<ChapterImage>? images}) {
      return ReaderState(
        sourceId: 'copy',
        mangaId: 'manga',
        chapterId: chapterOne.id,
        chapterList: const [chapterOne],
        images: images ?? const [ChapterImage(url: 'a')],
      );
    }

    blocTest<ReaderBloc, ReaderState>(
      'enabling translation immediately queues the current page',
      build: () {
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).thenAnswer((_) async => samplePageTranslation);
        return buildBlocWithTranslation();
      },
      seed: seedState,
      act: (bloc) => bloc.add(const TranslateChapterToggled(enabled: true)),
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.translationEnabled, isTrue);
        expect(
          bloc.state.pageTranslations[0]?.status,
          PageTranslationStatus.done,
        );
        expect(
          bloc.state.pageTranslations[0]?.translation,
          samplePageTranslation,
        );
      },
    );

    blocTest<ReaderBloc, ReaderState>(
      'disabling translation clears queued-but-not-started pages without '
      'cancelling the in-flight one',
      build: () {
        final completer = Completer<PageTranslation>();
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).thenAnswer((_) => completer.future);
        addTearDown(() {
          if (!completer.isCompleted) completer.complete(samplePageTranslation);
        });
        return buildBlocWithTranslation();
      },
      seed: () => seedState(
        images: const [ChapterImage(url: 'a'), ChapterImage(url: 'b')],
      ),
      act: (bloc) async {
        bloc.add(const TranslateChapterToggled(enabled: true)); // page 0: loading, blocked
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TranslatePageRequested(pageIndex: 1)); // queued, not started
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TranslateChapterToggled(enabled: false));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(
          bloc.state.pageTranslations[0]?.status,
          PageTranslationStatus.loading,
        );
        expect(bloc.state.pageTranslations.containsKey(1), isFalse);
      },
    );
  });
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/presentation/reader/bloc/reader_bloc_test.dart`
Expected: 全部 PASS（包括原有测试 + 新增 2 条）

- [ ] **Step 5: Commit**
```bash
git add lib/presentation/reader/bloc/reader_bloc.dart test/presentation/reader/bloc/reader_bloc_test.dart
git commit -m "feat(reader): implement translation toggle + serial queue in ReaderBloc"
```

---

### Task 5: 补充"去重请求"测试（`TranslatePageRequested` 幂等性）

**Files:**
- Test: `test/presentation/reader/bloc/reader_bloc_test.dart`

- [ ] **Step 1: 在 `group('Translation', ...)` 内追加两条测试**
```dart

    blocTest<ReaderBloc, ReaderState>(
      'ignores TranslatePageRequested when translation is disabled',
      build: buildBlocWithTranslation,
      seed: seedState,
      act: (bloc) => bloc.add(const TranslatePageRequested(pageIndex: 0)),
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        verifyNever(
          () => translationPipeline.translatePage(any(), any(), any(), any(), any()),
        );
      },
    );

    blocTest<ReaderBloc, ReaderState>(
      'does not re-translate a page that already finished',
      build: () {
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).thenAnswer((_) async => samplePageTranslation);
        return buildBlocWithTranslation();
      },
      seed: seedState,
      act: (bloc) async {
        bloc.add(const TranslateChapterToggled(enabled: true));
        await Future.delayed(const Duration(milliseconds: 20));
        bloc.add(const TranslatePageRequested(pageIndex: 0)); // no-op: already done
      },
      wait: const Duration(milliseconds: 20),
      verify: (_) {
        verify(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).called(1);
      },
    );
```

- [ ] **Step 2:** Run `flutter test test/presentation/reader/bloc/reader_bloc_test.dart` → 全部 PASS。
- [ ] **Step 3:** Commit: `git add test/presentation/reader/bloc/reader_bloc_test.dart && git commit -m "test(reader): cover TranslatePageRequested idempotency"`

---

### Task 6: 补充"严格串行处理"测试

**Files:** Test: `test/presentation/reader/bloc/reader_bloc_test.dart`

- [ ] **Step 1:** 在 `group('Translation', ...)` 顶部（`seedState` 定义之后）新增一个 `late` 变量，再追加测试：
```dart
    late Completer<PageTranslation> firstCompleter;

    blocTest<ReaderBloc, ReaderState>(
      'processes queued pages strictly one at a time, resuming once the '
      'current page finishes',
      build: () {
        firstCompleter = Completer<PageTranslation>();
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).thenAnswer((_) => firstCompleter.future);
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              1,
              any(),
            )).thenAnswer((_) async => samplePageTranslation);
        addTearDown(() {
          if (!firstCompleter.isCompleted) {
            firstCompleter.complete(samplePageTranslation);
          }
        });
        return buildBlocWithTranslation();
      },
      seed: () => seedState(
        images: const [ChapterImage(url: 'a'), ChapterImage(url: 'b')],
      ),
      act: (bloc) async {
        bloc.add(const TranslateChapterToggled(enabled: true)); // starts page 0, blocked
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TranslatePageRequested(pageIndex: 1)); // queued, waits for page 0
        await Future.delayed(const Duration(milliseconds: 10));
        verify(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).called(1);
        verifyNever(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              1,
              any(),
            ));
        expect(bloc.state.pageTranslations.containsKey(1), isFalse);
        firstCompleter.complete(samplePageTranslation); // page 0 finishes -> queue advances
        await Future.delayed(const Duration(milliseconds: 20));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(
          bloc.state.pageTranslations[0]?.status,
          PageTranslationStatus.done,
        );
        expect(
          bloc.state.pageTranslations[1]?.status,
          PageTranslationStatus.done,
        );
        verify(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              1,
              any(),
            )).called(1);
      },
    );
```

**注意**：`late Completer<PageTranslation> firstCompleter;` 必须声明在 `group` 作用域内（不能放在 `build`/`act` 各自的函数字面量里，否则 `act`/`verify` 无法访问同一个变量），`build:` 回调内重新赋值，`act:`/`verify:` 直接引用外部的 `firstCompleter`。

- [ ] **Step 2:** Run `flutter test test/presentation/reader/bloc/reader_bloc_test.dart` → 全部 PASS。
- [ ] **Step 3:** Commit: `git add test/presentation/reader/bloc/reader_bloc_test.dart && git commit -m "test(reader): cover strict serial translation queue processing"`

---

### Task 7: 错误处理测试

**Files:** Test：同上文件，同 group 内追加：
```dart

    blocTest<ReaderBloc, ReaderState>(
      'marks a page as error when translatePage throws, and still processes '
      'the next queued page',
      build: () {
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).thenThrow(Exception('boom'));
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              1,
              any(),
            )).thenAnswer((_) async => samplePageTranslation);
        return buildBlocWithTranslation();
      },
      seed: () => seedState(
        images: const [ChapterImage(url: 'a'), ChapterImage(url: 'b')],
      ),
      act: (bloc) async {
        bloc.add(const TranslateChapterToggled(enabled: true));
        await Future.delayed(const Duration(milliseconds: 10));
        bloc.add(const TranslatePageRequested(pageIndex: 1));
      },
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(
          bloc.state.pageTranslations[0]?.status,
          PageTranslationStatus.error,
        );
        expect(
          bloc.state.pageTranslations[0]?.errorMessage,
          contains('boom'),
        );
        expect(
          bloc.state.pageTranslations[1]?.status,
          PageTranslationStatus.done,
        );
      },
    );
```
- [ ] **Step 2:** Run test file → PASS。
- [ ] **Step 3:** Commit: `git commit -m "test(reader): cover translation error handling and queue continuation"`

---

### Task 8: 重试测试

**Files:** 同上，同 group 内追加：
```dart

    blocTest<ReaderBloc, ReaderState>(
      'TranslatePageRetried re-translates a page that previously errored',
      build: () {
        var attempt = 0;
        when(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).thenAnswer((_) {
          attempt++;
          if (attempt == 1) throw Exception('boom');
          return Future.value(samplePageTranslation);
        });
        return buildBlocWithTranslation();
      },
      seed: seedState,
      act: (bloc) async {
        bloc.add(const TranslateChapterToggled(enabled: true)); // -> error
        await Future.delayed(const Duration(milliseconds: 20));
        bloc.add(const TranslatePageRetried(pageIndex: 0)); // forced retry
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(
          bloc.state.pageTranslations[0]?.status,
          PageTranslationStatus.done,
        );
        verify(() => translationPipeline.translatePage(
              'copy',
              'manga',
              'c1',
              0,
              any(),
            )).called(2);
      },
    );
```
- [ ] **Step 2:** Run full test file, confirm ALL tests in `reader_bloc_test.dart`（旧+新）PASS。
- [ ] **Step 3:** Commit: `git commit -m "test(reader): cover forced retry of a failed translation"`

---

### Task 9: 新建 `TranslationBadge` 组件（无自动化测试，UI层排除在测试范围外）

**Files:** Create: `lib/presentation/reader/widgets/translation_badge.dart`
```dart
import 'package:flutter/material.dart';

/// Small circular badge shown over a page while it's being translated
/// (loading spinner) or after translation failed (tappable error icon).
class TranslationBadge extends StatelessWidget {
  const TranslationBadge.loading({super.key})
      : onTap = null,
        isError = false;
  const TranslationBadge.error({super.key, required VoidCallback this.onTap})
      : isError = true;

  final bool isError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: isError
          ? const Icon(Icons.error_outline, color: Colors.redAccent, size: 16)
          : const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
    );
    return isError ? GestureDetector(onTap: onTap, child: content) : content;
  }
}
```
- [ ] **Step 2:** `flutter analyze lib/presentation/reader/widgets/translation_badge.dart` → `No issues found!`
- [ ] **Step 3:** Commit: `git add lib/presentation/reader/widgets/translation_badge.dart && git commit -m "feat(reader): add TranslationBadge loading/error indicator"`

---

### Task 10: 新建 `ReaderTranslationOverlayPainter`（从 PoC 搬迁核心绘制逻辑）

**Files:** Create: `lib/presentation/reader/widgets/reader_translation_overlay_painter.dart`
```dart
import 'package:flutter/material.dart';

import 'package:comic_reader/data/translation/models/text_region.dart';

/// Paints translated (or original) text over each detected [TextRegion] on
/// top of an already-rendered page image. Unlike the PoC's
/// `TranslationOverlayPainter`, this does not decode/redraw the base image
/// itself — it's meant to sit in a [Stack] on top of the existing
/// [MangaImage] widget, using [imageSize] only to scale region coordinates.
class ReaderTranslationOverlayPainter extends CustomPainter {
  const ReaderTranslationOverlayPainter({required this.imageSize, required this.regions});

  final Size imageSize;
  final List<TextRegion> regions;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / imageSize.width;
    for (final region in regions) {
      if (region.box.length < 4) continue;
      final rect = Rect.fromLTWH(
        region.box[0] * scale,
        region.box[1] * scale,
        region.box[2] * scale,
        region.box[3] * scale,
      );
      if (rect.width <= 0 || rect.height <= 0) continue;

      _paintMask(canvas, rect);

      final text = (region.translatedText != null && region.translatedText!.trim().isNotEmpty)
          ? region.translatedText!
          : region.originalText;
      if (text.trim().isEmpty) continue;

      if (region.box[2] < region.box[3]) {
        _paintVertical(canvas, rect, text);
      } else {
        _paintHorizontal(canvas, rect, text);
      }
    }
  }

  void _paintMask(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFDDDDDD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintHorizontal(Canvas canvas, Rect rect, String text) {
    var fontSize = _clamp(rect.width / 4, 10, 34);
    fontSize = _clamp(fontSize, 10, rect.height / 2);

    List<String> lines = const [];
    while (true) {
      lines = _wrapHorizontal(text, fontSize, rect.width - 8);
      final totalHeight = lines.length * fontSize * 1.3;
      if (totalHeight <= rect.height - 4 || fontSize <= 10) break;
      fontSize -= 1;
    }

    var dy = rect.top + (rect.height - lines.length * fontSize * 1.3) / 2;
    for (final line in lines) {
      final tp = TextPainter(
        text: TextSpan(text: line, style: TextStyle(color: Colors.black, fontSize: fontSize)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 4);
      tp.paint(canvas, Offset(rect.left + (rect.width - tp.width) / 2, dy));
      dy += fontSize * 1.3;
    }
  }

  List<String> _wrapHorizontal(String text, double fontSize, double maxWidth) {
    final maxChars = (maxWidth / fontSize).floor().clamp(1, 999);
    final lines = <String>[];
    var buffer = StringBuffer();
    for (final ch in text.runes.map(String.fromCharCode)) {
      buffer.write(ch);
      if (buffer.length >= maxChars) {
        lines.add(buffer.toString());
        buffer = StringBuffer();
      }
    }
    if (buffer.isNotEmpty) lines.add(buffer.toString());
    return lines.isEmpty ? [text] : lines;
  }

  void _paintVertical(Canvas canvas, Rect rect, String text) {
    final chars = text.runes.map(String.fromCharCode).toList();
    var fontSize = _clamp(rect.width / 2.4, 10, 34);
    fontSize = _clamp(fontSize, 10, rect.height / 3);

    List<List<String>> columns = const [];
    while (true) {
      columns = _columnsFor(chars, rect.height, fontSize);
      final colWidth = fontSize * 1.15;
      final totalWidth = columns.length * colWidth;
      if (totalWidth <= rect.width - 4 || fontSize <= 10) break;
      fontSize -= 1;
    }

    final colWidth = fontSize * 1.15;
    final totalWidth = columns.length * colWidth;
    var colRight = rect.right - (rect.width - totalWidth) / 2;
    for (final col in columns) {
      final colLeft = colRight - colWidth;
      var dy = rect.top + (rect.height - col.length * fontSize * 1.15) / 2;
      for (final ch in col) {
        final tp = TextPainter(
          text: TextSpan(text: ch, style: TextStyle(color: Colors.black, fontSize: fontSize)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(colLeft + (colWidth - tp.width) / 2, dy));
        dy += fontSize * 1.15;
      }
      colRight = colLeft;
    }
  }

  List<List<String>> _columnsFor(List<String> chars, double height, double fontSize) {
    final perCol = (height / (fontSize * 1.15)).floor().clamp(1, 999);
    final columns = <List<String>>[];
    for (var i = 0; i < chars.length; i += perCol) {
      columns.add(chars.sublist(i, (i + perCol).clamp(0, chars.length)));
    }
    return columns;
  }

  double _clamp(double value, double min, double max) {
    if (max < min) return min;
    return value.clamp(min, max);
  }

  @override
  bool shouldRepaint(covariant ReaderTranslationOverlayPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize || oldDelegate.regions != regions;
  }
}
```
- [ ] **Step 2:** `flutter analyze lib/presentation/reader/widgets/reader_translation_overlay_painter.dart` → `No issues found!`
- [ ] **Step 3:** Commit: `git add lib/presentation/reader/widgets/reader_translation_overlay_painter.dart && git commit -m "feat(reader): add ReaderTranslationOverlayPainter (ported from PoC)"`

---

### Task 11: 接入 `vertical_reader.dart`（触发 + 叠加层渲染）

**Files:** Modify: `lib/presentation/reader/widgets/vertical_reader.dart`

- [ ] **Step 1:** 新增 import（在现有 `import 'manga_image_loader.dart';` 之后）：
```dart
import 'translation_badge.dart';
import 'reader_translation_overlay_painter.dart';
```

- [ ] **Step 2:** 重写 `_onScroll()` 为：
```dart
  void _onScroll() {
    if (_scrollController.hasClients && widget.images.isNotEmpty) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final scrollOffset = _scrollController.offset;
      final screenWidth = MediaQuery.of(context).size.width;
      final estimatedImageHeight = screenWidth * 1.4;
      final estimatedPage = (scrollOffset / estimatedImageHeight).floor();
      final page = estimatedPage.clamp(0, widget.images.length - 1);
      final bloc = context.read<ReaderBloc>();
      bloc.add(PageChanged(page));
      _prefetchWindow(page);
      if (bloc.state.translationEnabled) {
        bloc.add(TranslatePageRequested(pageIndex: page));
      }

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (scrollOffset >= maxScroll - viewportHeight * 0.5) {
        if (!bloc.state.isAppendingNext && bloc.state.canAppendNext) {
          bloc.add(const AppendNextChapter());
        }
      }
    }
  }
```
（去掉了原来在 bottom-check 块里重复的 `final bloc = context.read<ReaderBloc>();`，复用同一个变量。）

- [ ] **Step 3:** 在 `_prefetchWindow` 方法之后新增：
```dart
  void _showTranslationError(BuildContext context, int pageIndex, String? errorMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage ?? '翻译失败'),
        action: SnackBarAction(
          label: '重试',
          onPressed: () => context.read<ReaderBloc>().add(TranslatePageRetried(pageIndex: pageIndex)),
        ),
      ),
    );
  }
```

- [ ] **Step 4:** `buildWhen` 新加一行：
```dart
        buildWhen: (prev, curr) =>
            prev.isAppendingNext != curr.isAppendingNext ||
            prev.images != curr.images ||
            prev.pageTranslations != curr.pageTranslations,
```

- [ ] **Step 5:** `itemBuilder` 内部改为：
```dart
                final info = state.pageTranslations[index] ?? PageTranslationInfo.idle;
                return SizedBox(
                  width: double.infinity,
                  child: Stack(
                    children: [
                      MangaImage(
                        image: widget.images[index],
                        fit: BoxFit.fitWidth,
                        disableGesture: true,
                        sourceId: state.sourceId,
                        mangaId: state.mangaId,
                        chapterId: state.chapterId,
                        imageIndex: index,
                      ),
                      if (info.status == PageTranslationStatus.done &&
                          info.translation != null &&
                          info.imageSize != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: ReaderTranslationOverlayPainter(
                                imageSize: info.imageSize!,
                                regions: info.translation!.regions,
                              ),
                            ),
                          ),
                        ),
                      if (info.status == PageTranslationStatus.loading)
                        const Positioned(top: 8, right: 8, child: TranslationBadge.loading()),
                      if (info.status == PageTranslationStatus.error)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: TranslationBadge.error(
                            onTap: () => _showTranslationError(context, index, info.errorMessage),
                          ),
                        ),
                    ],
                  ),
                );
```

- [ ] **Step 6:** `flutter analyze lib/presentation/reader/widgets/vertical_reader.dart` → `No issues found!`
- [ ] **Step 7:** Commit: `git add lib/presentation/reader/widgets/vertical_reader.dart && git commit -m "feat(reader): wire translation trigger + overlay into VerticalReader"`

---

### Task 12: 接入 `reader_controls.dart` 翻译开关按钮

**Files:** Modify: `lib/presentation/reader/widgets/reader_controls.dart`

- [ ] **Step 1:** `ReaderControls.build()` 中新增传参：
```dart
            _TopBar(
              title: state.chapterTitle ?? '',
              sourceId: state.sourceId,
              mangaId: state.mangaId,
              chapterId: state.chapterId,
              translationEnabled: state.translationEnabled,
            ),
```

- [ ] **Step 2:** `_TopBar` 类字段+构造函数新增：
```dart
class _TopBar extends StatelessWidget {
  final String title;
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final bool translationEnabled;
  const _TopBar({
    required this.title,
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    required this.translationEnabled,
  });
```

- [ ] **Step 3:** 在 `build()` 中现有 `open_in_browser` `IconButton` **之前**插入：
```dart
          IconButton(
            icon: Icon(
              translationEnabled ? Icons.translate : Icons.translate_outlined,
              color: translationEnabled ? Colors.lightBlueAccent : Colors.white,
            ),
            tooltip: translationEnabled ? '关闭翻译' : '翻译本章',
            onPressed: () => context
                .read<ReaderBloc>()
                .add(TranslateChapterToggled(enabled: !translationEnabled)),
          ),
```

- [ ] **Step 4:** `flutter analyze lib/presentation/reader/widgets/reader_controls.dart` → `No issues found!`
- [ ] **Step 5:** Commit: `git add lib/presentation/reader/widgets/reader_controls.dart && git commit -m "feat(reader): add translation toggle button to reader top bar"`

---

### Task 13（收尾）：全量静态检查 + 测试 + 手动验证指南

- [ ] Run: `flutter analyze` （全仓）→ 无新增 issue。
- [ ] Run: `flutter test test/presentation/reader/bloc/reader_bloc_test.dart` → 全部 PASS。
- [ ] 手动验证步骤（无自动化测试覆盖 UI 层，与设计文档一致）：
  1. `flutter run` 进入任意漫画章节阅读页（确保布局为纵向）；
  2. 点击顶部新的"翻译"图标开启；
  3. 观察当前可见页出现 loading 角标，滚动到下一页自动追加翻译任务；
  4. 翻译完成后气泡区域浮现白底遮盖+译文，不阻塞继续滚动；
  5. 断网或未配置 AI 时验证错误角标 + SnackBar"重试"流程；
  6. 关闭开关验证未开始的排队被清空但正在进行的不中断。
- [ ] 用 Jestful 源（日语生肉漫画，已在 PoC 手动验证过翻译效果）实际找一章测试完整流程。

---

## 自审

1. **规格覆盖**：设计文档 1-9 条决定均已映射到具体 Task（Task4=开关/触发，Task5=去重，Task6=串行，Task7=错误处理，Task8=重试，Task9-10=UI组件，Task11-12=接入UI）。
2. **无占位符**：所有代码块均为完整可运行代码。
3. **类型一致性**：`PageTranslationStatus`/`PageTranslationInfo`/`TranslateChapterToggled`/`TranslatePageRequested`/`TranslatePageRetried` 等命名在各 Task 中完全一致；`_translationPipeline`/`_loadImageBytes` 字段名前后一致。
4. **测试覆盖**：Task4-8 共 9 个 bloc 单测，覆盖开关启用/关闭、禁用时忽略、去重、严格串行、失败转 error 且队列继续、强制重试。UI 层（Task9-12）按设计文档明确排除自动化测试，用手动验证清单（Task13）补位。

## 执行方式

**1. Subagent-Driven（推荐）** - 每个 Task 新开一个 subagent 执行，两阶段审查
**2. Inline Execution** - 在当前 session 内用 executing-plans 技能批量执行，每个检查点停下审查
