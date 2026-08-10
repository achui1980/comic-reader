# 漫画正文翻译功能——阅读器 UI 集成设计

## 背景

漫画正文翻译功能的后台管道（`lib/data/translation/` 下的 `TranslationPipeline`）已经完整实现并在本地 macOS 上验证通过：气泡定位（Manga-Bubble-YOLO）+ 日/韩文 OCR 识别（manga-ocr）+ LLM 翻译（复用现有 `AiClient`/BYOK 通道）全链路跑通，单页耗时约检测 139ms + OCR ~1.5s + LLM 翻译 ~8.45s，识别到 15 个气泡且日文→中文翻译准确。调试页 `translation_poc_screen.dart` 也已实现了"合成图预览"功能（`TranslationOverlayPainter`），验证了把译文按气泡框叠加回图片、并根据气泡宽高比自动选择横排/竖排的可行性。

本次设计的目标是：把已验证的翻译管道正式集成到真实的漫画阅读器 UI 中，让用户在阅读纵向滚动（webtoon 风格）漫画时，可以打开"翻译"开关，自动为可见页面生成翻译并叠加显示在原图上。

## 范围决策

以下决策均已与用户逐一确认：

1. **首发范围**：只做纵向滚动模式（`vertical_reader.dart`）。横向翻页模式因为需要与 `extended_image` 的 pinch 缩放手势矩阵同步坐标，技术风险和实现复杂度都更高，留到下一阶段单独规划。
2. **触发方式**：阅读器顶部工具栏加一个"翻译"总开关。开启后，当前可见的、尚未翻译过的页面会自动依次触发翻译，无需用户逐页手动点击。
3. **视觉反馈**：翻译进行中显示小角标 loading 指示器，不阻塞阅读——原图正常显示，用户可以继续滚动/阅读；翻译完成后气泡区域才会浮现白底遮盖和译文。
4. **开关位置与持久化**：放在阅读器顶部工具栏（`_TopBar`），与现有的"浏览器阅读"图标相邻。**不持久化**——只影响当前阅读会话，下次重新进入阅读器默认关闭。
5. **失败处理**：翻译失败的页面小角标变为错误图标；点击图标弹出 `SnackBar` 显示具体错误信息（如"AI 未配置"、网络错误等）并附带"重试"按钮。翻页时不自动重试。
6. **图片字节来源**：复用已有的 `loadAndCacheImageBytes` 函数获取图片字节，不新增独立的下载逻辑（该函数已在 `_prefetchWindow` 和 `_onPrefetchNextChapter` 中被使用，是项目内"字节获取与 UI 渲染解耦"的既有惯例）。
7. **并发控制**：串行队列，每次只处理一页翻译，避免 LLM 请求并发过多导致速率限制或费用激增。
8. **错误提示形式**：点击错误角标后弹出自动消失的 `SnackBar`，附带"重试"`SnackBarAction`。
9. **技术方案**：直接扩展现有 `ReaderBloc`（而不是新建独立的 Controller）。理由：新建独立 Controller 需要引入新概念并重复传递 `sourceId`/`mangaId`/`chapterId` 等参数，而 `ReaderBloc` 本身已经持有这些上下文，扩展它是最小改动路径。

## Global Constraints

- 只支持纵向滚动模式（`vertical_reader.dart`），横向翻页模式不在本次范围内。
- 翻译状态和结果**不持久化**，仅存在于当前 `ReaderBloc` 实例的内存中。
- 翻译请求必须严格串行执行，任意时刻最多一个页面在翻译中。
- 不修改 `manga_image.dart` / `manga_image_network_view.dart` 的任何渲染逻辑。
- 不新增网络下载逻辑，复用 `lib/presentation/reader/widgets/manga_image_loader.dart` 的 `loadAndCacheImageBytes`。
- 叠加层渲染不重新解码/持有完整的 `ui.Image`，只存储图片的宽高（`Size`）用于坐标换算，避免额外内存开销。

## 整体架构与数据流

新增一个"翻译"开关事件 `TranslateChapterToggled`。开关打开后，阅读器每当有新页面进入可视区域时会自动发出 `TranslatePageRequested(pageIndex)` 事件。`ReaderBloc` 内部维护一个串行队列处理这些请求：查找该页对应的 `ChapterImage` → 用 `loadAndCacheImageBytes` 拿到图片字节 → 调用已注册在 DI 中的 `TranslationPipeline.translatePage(...)` → 将结果（成功或失败）写入 `ReaderState.pageTranslations` 这个 `Map<int, PageTranslationInfo>`。UI 层（`vertical_reader.dart`）根据每页在这个 Map 中的状态，分别渲染：无记录/idle 时不显示任何叠加；loading 时显示小角标；done 时叠加白底遮盖+译文；error 时显示错误角标（点击可查看错误详情并重试）。

## ReaderState / ReaderEvent / ReaderBloc 具体设计

### `lib/presentation/reader/bloc/reader_event.dart` 新增事件

```dart
class TranslateChapterToggled extends ReaderEvent {
  const TranslateChapterToggled({required this.enabled});
  final bool enabled;
}

class TranslatePageRequested extends ReaderEvent {
  const TranslatePageRequested({required this.pageIndex});
  final int pageIndex;
}

class TranslatePageRetried extends ReaderEvent {
  const TranslatePageRetried({required this.pageIndex});
  final int pageIndex;
}
```

`TranslatePageRetried` 单独建事件而不复用 `TranslatePageRequested`，目的是让"重试"在 handler 里可以无条件强制入队，不受"是否 idle"的限制（`TranslatePageRequested` 对已经是 `loading`/`done`/`error` 状态的页面会直接忽略，这是防止自动触发重复入队的必要保护，但重试需要绕开这个保护）。

### `lib/presentation/reader/bloc/reader_state.dart` 新增

```dart
enum PageTranslationStatus { idle, loading, done, error }

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
  final Size? imageSize; // 原图宽高，用于叠加层坐标换算，不存整张解码图

  static const idle = PageTranslationInfo(status: PageTranslationStatus.idle);
}
```

`ReaderState` 新增两个字段（`copyWith` 同步扩展）：

```dart
final bool translationEnabled;                       // 默认 false
final Map<int, PageTranslationInfo> pageTranslations; // 默认 const {}
```

### `ReaderBloc` 新增 handler

内部维护一个私有 `int? _translatingPage`（当前是否有翻译任务在跑的串行锁）和一个私有 `Queue<int> _translationQueue`（待处理队列）：

```dart
Future<void> _onTranslateChapterToggled(
    TranslateChapterToggled event, Emitter<ReaderState> emit) async {
  emit(state.copyWith(translationEnabled: event.enabled));
  if (event.enabled) {
    _enqueueTranslate(state.currentPage); // 立即处理当前可见页
  } else {
    _translationQueue.clear(); // 关闭时清空未开始的排队任务，正在跑的那个不打断
  }
}

Future<void> _onTranslatePageRequested(
    TranslatePageRequested event, Emitter<ReaderState> emit) async {
  if (!state.translationEnabled) return;
  final info = state.pageTranslations[event.pageIndex] ?? PageTranslationInfo.idle;
  if (info.status != PageTranslationStatus.idle) return; // 已在处理/已完成/已出错，不重复入队
  _enqueueTranslate(event.pageIndex);
}

Future<void> _onTranslatePageRetried(
    TranslatePageRetried event, Emitter<ReaderState> emit) async {
  _enqueueTranslate(event.pageIndex); // 无条件强制重新入队，允许覆盖 error 状态重试
}

void _enqueueTranslate(int pageIndex) {
  if (_translationQueue.contains(pageIndex)) return;
  _translationQueue.add(pageIndex);
  _drainTranslationQueue();
}

Future<void> _drainTranslationQueue() async {
  if (_translatingPage != null || _translationQueue.isEmpty) return; // 串行：已有任务在跑就不启动新的
  final pageIndex = _translationQueue.removeFirst();
  _translatingPage = pageIndex;
  _updatePageStatus(pageIndex, const PageTranslationInfo(status: PageTranslationStatus.loading));

  try {
    final image = state.images[pageIndex];
    final bytes = await loadAndCacheImageBytes(
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
    final result = await GetIt.instance<TranslationPipeline>().translatePage(
      state.sourceId, state.mangaId, state.chapterId, pageIndex, bytes,
    );
    _updatePageStatus(pageIndex, PageTranslationInfo(
      status: PageTranslationStatus.done,
      translation: result,
      imageSize: imageSize,
    ));
  } catch (e) {
    _updatePageStatus(pageIndex, PageTranslationInfo(
      status: PageTranslationStatus.error, errorMessage: e.toString(),
    ));
  } finally {
    _translatingPage = null;
    _drainTranslationQueue(); // 继续处理队列里下一个
  }
}

void _updatePageStatus(int pageIndex, PageTranslationInfo info) {
  if (isClosed) return; // Bloc 可能已经 dispose（用户退出阅读器）
  emit(state.copyWith(
    pageTranslations: {...state.pageTranslations, pageIndex: info},
  ));
}
```

**接入现有可见性检测**：`vertical_reader.dart` 已有 `_prefetchWindow` 类似逻辑判断哪些页面进入可视区域（用于图片预取）。在同样的可见性回调里加一行：

```dart
if (state.translationEnabled) {
  context.read<ReaderBloc>().add(TranslatePageRequested(pageIndex: index));
}
```

这个调用是幂等的（`_onTranslatePageRequested` 内部已做状态检查防重复），可以在每次滚动位置变化时安全地重复调用。

## UI 集成

### 翻译开关（`reader_controls.dart` 的 `_TopBar`）

`_TopBar` 改为消费 `state.translationEnabled`（`ReaderControls` 已在 `BlocBuilder<ReaderBloc, ReaderState>` 内，直接把 `state` 传给 `_TopBar` 即可，无需单独加参数）。在现有的 `open_in_browser` 按钮**之前**插入一个新 `IconButton`：

```dart
IconButton(
  icon: Icon(
    state.translationEnabled ? Icons.translate : Icons.translate_outlined,
    color: state.translationEnabled ? Colors.lightBlueAccent : Colors.white,
  ),
  tooltip: state.translationEnabled ? '关闭翻译' : '翻译本章',
  onPressed: () => context.read<ReaderBloc>().add(
    TranslateChapterToggled(enabled: !state.translationEnabled),
  ),
),
SizedBox(width: 4),
IconButton(icon: const Icon(Icons.open_in_browser), ...), // 现有按钮不变
```

用图标本身变化（`translate_outlined` → `translate`）加颜色变化（白 → 亮蓝）区分开关状态，不新增文字标签，保持工具栏简洁。

### 叠加层插入（`vertical_reader.dart` 的 `itemBuilder`）

每个 list item 从裸的 `MangaImage(...)` 包一层 `Stack`：

```dart
itemBuilder: (context, index) {
  final image = widget.images[index];
  final info = state.pageTranslations[index] ?? PageTranslationInfo.idle;
  return Stack(
    children: [
      MangaImage(image: image, ...), // 现有渲染逻辑不变
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
          top: 8, right: 8,
          child: TranslationBadge.error(
            onTap: () => _showTranslationError(context, index, info.errorMessage),
          ),
        ),
    ],
  );
}
```

`_showTranslationError` 弹出一个 `SnackBar`，`content` 显示 `errorMessage`，`action` 是一个"重试"按钮，点击后 `context.read<ReaderBloc>().add(TranslatePageRetried(pageIndex: index))`。

### 角标组件（新建 `lib/presentation/reader/widgets/translation_badge.dart`）

```dart
class TranslationBadge extends StatelessWidget {
  const TranslationBadge.loading({super.key}) : onTap = null, isError = false;
  const TranslationBadge.error({super.key, required VoidCallback this.onTap}) : isError = true;

  final bool isError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
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

### 阅读器专用叠加层 painter（新建 `lib/presentation/reader/widgets/reader_translation_overlay_painter.dart`）

与调试页的 `TranslationOverlayPainter`（`lib/presentation/poc/translation_overlay_painter.dart`）逻辑基本一致（白底遮盖矩形 + 按气泡宽高比自动选择横排/竖排文字绘制），**唯一区别**是不接收 `ui.Image` 也不绘制底图——阅读器场景下原图已经由 `MangaImage` 渲染好，叠加层只需在其上叠加白底遮盖和译文：

```dart
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
      final text = (region.translatedText?.trim().isNotEmpty ?? false)
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

  // _paintMask / _paintHorizontal / _paintVertical / _wrapHorizontal /
  // _columnsFor / _clamp 的实现与 translation_overlay_painter.dart 中的
  // 对应私有方法完全一致（直接搬迁，不含底图绘制部分）。

  @override
  bool shouldRepaint(covariant ReaderTranslationOverlayPainter oldDelegate) =>
      oldDelegate.imageSize != imageSize || oldDelegate.regions != regions;
}
```

## 测试策略

**范围**：`ReaderBloc` 新增的翻译相关 handler 逻辑（串行队列/开关/重试）用纯 Bloc 单测覆盖。UI 层（`_TopBar` 图标、`vertical_reader.dart` 叠加层、角标组件、`ReaderTranslationOverlayPainter`）不写 widget/集成测试，沿用本项目现有测试哲学（真实渲染/真实推理/真实网络的组合难以在单测中低成本验证，且既有 `translation_pipeline` 等模块的测试策略也是如此）。

`test/presentation/reader/bloc/reader_bloc_test.dart` 新增用例（用 `mocktail` mock `TranslationPipeline`，并对 `loadAndCacheImageBytes` 提供可控的 fake 实现）：

1. `TranslateChapterToggled(enabled: true)` → 立即对 `state.currentPage` 发起翻译（状态变为 `loading`）。
2. `TranslateChapterToggled(enabled: false)` → 清空排队中但未开始的任务；不打断正在跑的那个（该任务完成后正常落地为 `done`/`error`，之后不会自动继续处理队列中剩余的项）。
3. `TranslatePageRequested` 对已经是 `loading`/`done`/`error` 状态的页面不重复入队；`translationEnabled == false` 时也应直接忽略。
4. 两个不同页面连续 `TranslatePageRequested` → 验证严格串行（用可控的 `Completer` 包裹 mock 的 `translatePage`，验证第二个请求的 `translatePage` 调用发生在第一个完成之后）。
5. `translatePage` 抛出异常 → 对应页面状态变为 `error` 且 `errorMessage` 非空；队列继续处理下一个排队项（不会因为一个失败而卡住整个队列）。
6. `TranslatePageRetried` 对已经是 `error` 状态的页面 → 无条件重新入队并最终转为 `done`（验证"重试不受 idle 限制"这一关键设计点）。

**已知的测试范围限制**（明确排除）：真实 ONNX 推理、真实网络请求、`loadAndCacheImageBytes` 的下载重试逻辑本身（这些已在各自模块的既有测试里覆盖，或依赖真实环境无法在单测中低成本验证）。

## 明确排除

- 横向翻页模式的叠加层坐标同步（需要与 `extended_image` 手势矩阵联动，留到下一阶段）。
- 翻译开关状态持久化。
- 整章批量预翻译（本次仅"当前可见页自动触发"，不做"打开开关后立即翻译全章"）。
- 翻译结果的图片导出/分享功能。
- 对 `manga_image.dart` / `manga_image_network_view.dart` 的任何修改。
