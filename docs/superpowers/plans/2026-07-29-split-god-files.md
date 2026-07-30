# 拆分三个上帝文件 (ROADMAP #24) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把三个超过700行、职责混杂的"上帝文件"（`manga_image.dart`、`settings_screen.dart`、`manga_repository_impl.dart`）按职责拆分成多个聚焦的小文件，且不改变任何对外可见的类名/构造签名/公开方法行为，同时在拆 `manga_repository_impl.dart` 时顺手消除 `getChapter`/`getChapterStream` 之间重复的三段业务逻辑。

**Architecture:** 纯内部重构（move + rename private→ 部分 public），每个子任务先跑一遍全量测试建立基线，move 完成后再跑一遍确认零回归，再 commit。不使用继承/mixin 改变现有类层级——`manga_repository_impl.dart` 用"组合+委托对象"，`manga_image.dart`/`settings_screen.dart` 用"提取独立文件+去掉下划线"。

**Tech Stack:** Flutter/Dart, flutter_bloc（settings_cubit 已存在，不改）, dio, extended_image。

**执行前提：先完成 `docs/superpowers/plans/2026-07-29-cleanup-debt.md`（#25）**，因为下面 Task 4-7 会新增 `debugPrint` 调用点，若在 #25 之前执行会与 #25 的空 catch 修改产生不必要的 diff 冲突（非必须依赖，但建议顺序执行）。

---

## Part A: `manga_image.dart`（730行 → 5个文件）

### Task 1: 建立测试基线 + 抽取 `manga_image_loader.dart`（网络字节加载+缓存，供 #20 复用）

**Files:**
- Modify: `lib/presentation/reader/widgets/manga_image.dart`
- Create: `lib/presentation/reader/widgets/manga_image_loader.dart`

- [ ] **Step 1: 记录当前基线**

Run: `flutter analyze lib/presentation/reader/widgets/manga_image.dart`
Expected: `No issues found!`（记下这个基线，后续每步都要保持）

Run: `grep -rln "MangaImage" test/`
Expected: 无输出（确认无直接单测耦合，可安全重构）

- [ ] **Step 2: 创建 `manga_image_loader.dart`，定义可复用的顶层字节加载函数**

`_MangaImageState` 里原有的 `_canCache`（61-66行）、`_checkCache`（97-112行）、`_usesWebDirectImage`（119-123行）、`_maxLoadAttempts`（133行）、`_loadEncodedImage`（141-188行）、`_verifyResponseIntegrity`（192-201行）目前是绑定 `State`/`widget` 的私有方法。把其中"纯字节下载+缓存"的核心逻辑（`_loadEncodedImage`+`_verifyResponseIntegrity`+重试常量）提炼成不依赖 `State`/`BuildContext` 的顶层函数：

```dart
import 'dart:typed_data';

import 'package:dio/dio.dart' show Headers, Response, ResponseType;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get_it/get_it.dart' hide Disposable;

import '../../../data/local/chapter_cache_service.dart';
import '../../../data/remote/http_client.dart';
import '../../../core/models/fetch_config.dart';
import '../../../core/utils/image_response_decoder.dart';
import '../../../domain/entities/chapter.dart';

const int kMangaImageMaxLoadAttempts = 3;

/// Whether this image is eligible for disk caching via [ChapterCacheService].
/// Mirrors the original `_MangaImageState._canCache` getter: caching only
/// applies on native platforms when all four identifying IDs are known.
bool canCacheMangaImage({
  required String? sourceId,
  required String? mangaId,
  required String? chapterId,
  required int? imageIndex,
}) {
  // ignore: avoid_web_libraries_in_flutter -- kIsWeb import lives with caller
  return sourceId != null &&
      mangaId != null &&
      chapterId != null &&
      imageIndex != null;
}

/// Downloads [image]'s bytes through the shared [HttpClient], retrying on
/// failure (with exponential backoff) and verifying that the number of
/// bytes received matches the server-declared Content-Length. This guards
/// against proxies/upstreams that close the connection early while still
/// returning a 2xx status, which would otherwise be silently decoded as a
/// (corrupt) truncated image. On success, if [sourceId]/[mangaId]/
/// [chapterId]/[imageIndex] are all provided (native-only), the decoded
/// bytes are also persisted via [ChapterCacheService.saveImage] so that
/// future reads (including precache/prefetch call sites) hit the disk
/// cache instead of re-downloading.
Future<Uint8List> loadAndCacheImageBytes({
  required ChapterImage image,
  String? sourceId,
  String? mangaId,
  String? chapterId,
  int? imageIndex,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= kMangaImageMaxLoadAttempts; attempt++) {
    try {
      final response = await GetIt.instance<HttpClient>().execute(
        FetchConfig(
          url: image.url,
          headers: image.headers,
          responseType: ResponseType.bytes,
        ),
      );
      final responseData = response.data;
      if (responseData is! List<int>) {
        throw const FormatException('Image response did not contain bytes');
      }
      final rawBytes = Uint8List.fromList(responseData);
      _verifyResponseIntegrity(response, rawBytes);
      final bytes = decodeImageResponseBytes(rawBytes, image.responseEncoding);
      if (bytes.isEmpty) {
        throw const FormatException('Decoded image is empty');
      }
      final canCache = !identical(sourceId, null) &&
          sourceId != null &&
          mangaId != null &&
          chapterId != null &&
          imageIndex != null;
      if (canCache) {
        await GetIt.instance<ChapterCacheService>().saveImage(
          sourceId,
          mangaId!,
          chapterId!,
          imageIndex!,
          bytes,
        );
      }
      return bytes;
    } catch (e) {
      lastError = e;
      debugPrint(
        '[MangaImageLoader] load attempt $attempt/$kMangaImageMaxLoadAttempts '
        'failed: ${image.url} - $e',
      );
      if (attempt == kMangaImageMaxLoadAttempts) break;
      await Future.delayed(Duration(milliseconds: 300 * (1 << (attempt - 1))));
    }
  }
  throw lastError ?? const FormatException('Failed to load image');
}

/// Throws if the downloaded [bytes] don't match the response's declared
/// Content-Length (when present), catching truncated-but-200 responses.
void _verifyResponseIntegrity(Response response, Uint8List bytes) {
  final declared = response.headers.value(Headers.contentLengthHeader);
  final declaredLength = declared != null ? int.tryParse(declared) : null;
  if (declaredLength != null && declaredLength != bytes.length) {
    throw FormatException(
      'Image response truncated: expected $declaredLength bytes, got '
      '${bytes.length}',
    );
  }
}
```

注意：上面 `canCacheMangaImage` 帮助函数在这一步暂时不接 `kIsWeb`（Web 平台判断留在调用方 `_MangaImageState._canCache`，因为顶层文件不便随意 import `dart:io` 相关条件），`loadAndCacheImageBytes` 内部改用"四个 ID 都非空"作为 canCache 条件（与原 `_canCache` 唯一差异是去掉了 `!kIsWeb`——调用方 `_MangaImageState._canCache` 在决定要不要传 sourceId 等参数时，自己先判断 `!kIsWeb`，等价保留了原行为）。

- [ ] **Step 3: 修改 `manga_image.dart`，让 `_MangaImageState` 调用新函数**

把原 141-201 行的 `_loadEncodedImage`/`_verifyResponseIntegrity` 方法体替换为：
```dart
  Future<Uint8List> _loadEncodedImage() {
    return loadAndCacheImageBytes(
      image: widget.image,
      sourceId: _canCache ? widget.sourceId : null,
      mangaId: _canCache ? widget.mangaId : null,
      chapterId: _canCache ? widget.chapterId : null,
      imageIndex: _canCache ? widget.imageIndex : null,
    );
  }
```
删除原来独立的 `_verifyResponseIntegrity`方法和 `_maxLoadAttempts` 常量（已迁移到新文件）。在文件顶部添加：
```dart
import 'manga_image_loader.dart';
```

- [ ] **Step 4: 验证**

Run: `flutter analyze lib/presentation/reader/widgets/manga_image.dart lib/presentation/reader/widgets/manga_image_loader.dart`
Expected: `No issues found!`

Run: `flutter analyze` (全量，确认没有其他文件因为方法签名变化报错)
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/reader/widgets/manga_image.dart lib/presentation/reader/widgets/manga_image_loader.dart
git commit -m "refactor: extract manga_image_loader.dart for reusable byte loading+caching"
```

---

### Task 2: 抽取 `jmc_unscramble.dart`（JMC解密算法，被2条路径共享）

**Files:**
- Modify: `lib/presentation/reader/widgets/manga_image.dart`
- Create: `lib/presentation/reader/widgets/jmc_unscramble.dart`

- [ ] **Step 1: 创建新文件，迁入并去下划线**

把原 `manga_image.dart` 里的 `_calculateSegments`（204-231行，`_MangaImageState` 的方法，改成不依赖 State 的纯函数）、`_UnscrambledImage`（540-577行）、`_JmcUnscramblePainter`（585-634行）迁入：

```dart
import 'package:flutter/material.dart';

/// Computes the number of horizontal strips a JMC-scrambled image was cut
/// into, based on the image's pixel height and the source's configured
/// scramble threshold. Pure function — mirrors the original
/// `_MangaImageState._calculateSegments`.
int calculateJmcSegments(int imageHeight, int scrambleThreshold) {
  // NOTE: paste the original body from manga_image.dart:204-231 verbatim,
  // replacing any `widget.xxx`/`this.xxx` references with the corresponding
  // parameter (imageHeight, scrambleThreshold) passed in above.
}

/// Renders a JMC-scrambled image by unscrambling its strips via
/// [JmcUnscramblePainter]. Was `_UnscrambledImage`.
class JmcUnscrambledImage extends StatelessWidget {
  const JmcUnscrambledImage({
    super.key,
    required this.image,
    required this.calculateSegments,
  });

  final ui.Image image; // import 'dart:ui' as ui; add at top if missing
  final int Function(int imageHeight) calculateSegments;

  @override
  Widget build(BuildContext context) {
    // paste original _UnscrambledImage.build body verbatim (553-576行)
  }
}

/// Paints a scrambled image's strips back into their unscrambled order.
/// Shared by both the JMC unscramble path (via [JmcUnscrambledImage]) and
/// the wu55 memory-image path (via `Wu55MemoryImage` in
/// wu55_memory_image.dart) — do not rename this file to imply JMC-only
/// ownership without updating both call sites.
class JmcUnscramblePainter extends CustomPainter {
  const JmcUnscramblePainter({required this.image, required this.segments});

  final ui.Image image;
  final int segments;

  @override
  void paint(Canvas canvas, Size size) {
    // paste original _JmcUnscramblePainter.paint body verbatim (591-628行)
  }

  @override
  bool shouldRepaint(covariant JmcUnscramblePainter oldDelegate) {
    // paste original shouldRepaint body verbatim (630-633行)
  }
}
```

实际执行时用编辑器把原文件对应行号的方法体原样剪切粘贴进来（不要凭记忆重写算法逻辑，必须是逐字迁移，只改类名/去下划线/去 State 依赖）。

- [ ] **Step 2: 修改 `manga_image.dart` 中的调用点**

原文件里调用 `_calculateSegments(...)`/`_UnscrambledImage(...)`/`_JmcUnscramblePainter(...)` 的地方（`_buildImageContent` 第369行附近，`_buildEncodedNetworkImage` 第519/525行附近）改为调用 `calculateJmcSegments(...)`/`JmcUnscrambledImage(...)`。在文件顶部添加：
```dart
import 'jmc_unscramble.dart';
```

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/presentation/reader/widgets/manga_image.dart lib/presentation/reader/widgets/jmc_unscramble.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/reader/widgets/manga_image.dart lib/presentation/reader/widgets/jmc_unscramble.dart
git commit -m "refactor: extract jmc_unscramble.dart (shared by JMC and wu55 paths)"
```

---

### Task 3: 抽取 `wu55_memory_image.dart`

**Files:**
- Modify: `lib/presentation/reader/widgets/manga_image.dart`
- Create: `lib/presentation/reader/widgets/wu55_memory_image.dart`

- [ ] **Step 1: 创建新文件**

把原 `_Wu55MemoryImage`/`_Wu55MemoryImageState`（638-730行）迁入，去下划线改为 `Wu55MemoryImage`/`_Wu55MemoryImageState`（State 类保留下划线，因为它不需要跨文件可见——只有 `Wu55MemoryImage` 这个 Widget 本身需要 public）：

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'jmc_unscramble.dart';

class Wu55MemoryImage extends StatefulWidget {
  // paste original _Wu55MemoryImage fields/constructor verbatim (638-655行)

  @override
  State<Wu55MemoryImage> createState() => _Wu55MemoryImageState();
}

class _Wu55MemoryImageState extends State<Wu55MemoryImage> {
  // paste original _Wu55MemoryImageState body verbatim (657-730行)
  // 注意第725行原来引用 _JmcUnscramblePainter(...)，改为 JmcUnscramblePainter(...)
}
```

- [ ] **Step 2: 修改 `manga_image.dart` 调用点**

`_buildMemoryImage`（276-326行）里构造 `_Wu55MemoryImage(...)` 的地方改为 `Wu55MemoryImage(...)`，文件顶部添加：
```dart
import 'wu55_memory_image.dart';
```

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/presentation/reader/widgets/manga_image.dart lib/presentation/reader/widgets/wu55_memory_image.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/reader/widgets/manga_image.dart lib/presentation/reader/widgets/wu55_memory_image.dart
git commit -m "refactor: extract wu55_memory_image.dart"
```

---

### Task 4: 抽取 `manga_image_network_view.dart`

**Files:**
- Modify: `lib/presentation/reader/widgets/manga_image.dart`
- Create: `lib/presentation/reader/widgets/manga_image_network_view.dart`

- [ ] **Step 1: 创建新文件**

把 `_buildEncodedNetworkImage`（411-536行）迁出，改成一个独立的 `StatefulWidget`（因为它内部用了 `FutureBuilder` 但依赖 `widget.image`/`widget.fit`/`widget.disableGesture`/`_loadEncodedImage`/`_calculateSegments` 等好几个 State 成员，需要把这些作为构造参数传入）：

```dart
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/chapter.dart';
import 'jmc_unscramble.dart';
import 'manga_image_loader.dart';

class MangaImageNetworkView extends StatefulWidget {
  const MangaImageNetworkView({
    super.key,
    required this.image,
    required this.fit,
    required this.disableGesture,
    this.sourceId,
    this.mangaId,
    this.chapterId,
    this.imageIndex,
  });

  final ChapterImage image;
  final BoxFit fit;
  final bool disableGesture;
  final String? sourceId;
  final String? mangaId;
  final String? chapterId;
  final int? imageIndex;

  @override
  State<MangaImageNetworkView> createState() => _MangaImageNetworkViewState();
}

class _MangaImageNetworkViewState extends State<MangaImageNetworkView> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = loadAndCacheImageBytes(
      image: widget.image,
      sourceId: widget.sourceId,
      mangaId: widget.mangaId,
      chapterId: widget.chapterId,
      imageIndex: widget.imageIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // paste original _buildEncodedNetworkImage body verbatim (411-536行),
    // replacing `widget.image`/`widget.fit`/`_calculateSegments(...)` calls
    // with `widget.image`/`widget.fit`/`calculateJmcSegments(...)`, and
    // replacing the FutureBuilder's `future: _loadEncodedImage()` with
    // `future: _future`.
  }
}
```

- [ ] **Step 2: 修改 `manga_image.dart` 调用点**

`_buildImageContent`（328-409行）里原来调用 `_buildEncodedNetworkImage()` 的地方（第408行附近）改为：
```dart
return MangaImageNetworkView(
  image: widget.image,
  fit: widget.fit,
  disableGesture: widget.disableGesture,
  sourceId: widget.sourceId,
  mangaId: widget.mangaId,
  chapterId: widget.chapterId,
  imageIndex: widget.imageIndex,
);
```
删除原 `_buildEncodedNetworkImage` 方法体。文件顶部添加：
```dart
import 'manga_image_network_view.dart';
```

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/presentation/reader/widgets/manga_image.dart lib/presentation/reader/widgets/manga_image_network_view.dart`
Expected: `No issues found!`

手动验证（因无自动化测试覆盖）：在模拟器/设备上打开任意一部漫画的阅读器，翻到需要网络加载的页面，确认图片正常显示、双指缩放正常工作、JMC/wu55 加密源的图片正常解密显示。

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/reader/widgets/manga_image.dart lib/presentation/reader/widgets/manga_image_network_view.dart
git commit -m "refactor: extract manga_image_network_view.dart"
```

- [ ] **Step 5: 最终检查 `manga_image.dart` 行数**

Run: `wc -l lib/presentation/reader/widgets/manga_image.dart`
Expected: 应显著小于原730行（目标 < 250行，仅剩 `MangaImage`/`_MangaImageState` 的编排逻辑：`initState`/`didUpdateWidget`/`_checkCache`/`_canCache`/`build`/`_buildImageContent`/`_buildMemoryImage`/`_showSaveDialog`）

---

## Part B: `settings_screen.dart`（850行 → 9个 section 文件）

### Task 5: 抽取共享 helper（`_buildSectionHeader`、`_showConfirmDialog`）

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Create: `lib/presentation/settings/sections/section_widgets.dart`

- [ ] **Step 1: 记录基线**

Run: `flutter analyze lib/presentation/settings/settings_screen.dart`
Expected: `No issues found!`

Run: `grep -rln "SettingsScreen" test/`
Expected: 无输出（确认无直接单测耦合）

- [ ] **Step 2: 创建 `lib/presentation/settings/sections/section_widgets.dart`**

```dart
import 'package:flutter/material.dart';

/// Section header used by every settings section (was
/// `_SettingsView._buildSectionHeader`).
Widget buildSettingsSectionHeader(BuildContext context, String title) {
  // paste original _buildSectionHeader body verbatim (59-71行)
}

/// Generic confirm/cancel dialog used by data-management actions (was
/// `_SettingsView._showConfirmDialog`).
void showSettingsConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required VoidCallback onConfirm,
}) {
  // paste original _showConfirmDialog body verbatim (660-691行)
}
```

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/presentation/settings/sections/section_widgets.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
mkdir -p lib/presentation/settings/sections
git add lib/presentation/settings/sections/section_widgets.dart
git commit -m "refactor: extract shared settings section helpers"
```

(此时旧的 `_buildSectionHeader`/`_showConfirmDialog` 暂时在 `settings_screen.dart` 里保留不删——留到 Task 13 统一清理，避免中间态编译失败。)

---

### Task 6: 抽取 `sections/reading_section.dart`

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Create: `lib/presentation/settings/sections/reading_section.dart`

- [ ] **Step 1: 创建新文件**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/settings_cubit.dart';
import 'section_widgets.dart';

class ReadingSection extends StatelessWidget {
  const ReadingSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    // paste original _buildReadingSection body verbatim (73-147行),
    // replacing `_buildSectionHeader(context, ...)` calls with
    // `buildSettingsSectionHeader(context, ...)`
  }
}
```
（`import '../bloc/settings_cubit.dart';` 的具体相对路径需按实际项目目录核实：`settings_screen.dart` 现在在 `lib/presentation/settings/`，`settings_cubit.dart` 在 `lib/presentation/settings/bloc/`，从新的 `sections/` 子目录访问应为 `../bloc/settings_cubit.dart`。）

- [ ] **Step 2: 修改 `settings_screen.dart`**

在 `_SettingsView.build()`（31-57行）里，把内联的 `_buildReadingSection(context, state)` 调用替换为 `ReadingSection(state: state)`，文件顶部添加 `import 'sections/reading_section.dart';`。**暂时不删除** 原 `_buildReadingSection` 方法体（留到 Task 13 统一清理）。

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/presentation/settings/settings_screen.dart lib/presentation/settings/sections/reading_section.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/settings/settings_screen.dart lib/presentation/settings/sections/reading_section.dart
git commit -m "refactor: extract sections/reading_section.dart"
```

---

### Task 7: 抽取 `sections/reader_enhancements_section.dart`

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Create: `lib/presentation/settings/sections/reader_enhancements_section.dart`

- [ ] **Step 1-4**：重复 Task 6 的模式，源为 `_buildReaderEnhancementsSection`（149-230行），新类名 `ReaderEnhancementsSection`。

Commit message: `refactor: extract sections/reader_enhancements_section.dart`

---

### Task 8: 抽取 `sections/theme_section.dart`

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Create: `lib/presentation/settings/sections/theme_section.dart`

- [ ] **Step 1-4**：重复 Task 6 的模式，源为 `_buildThemeSection`（232-264行），新类名 `ThemeSection`。

Commit message: `refactor: extract sections/theme_section.dart`

---

### Task 9: 抽取 `sections/proxy_section.dart`（含 web 专用子组件）

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Create: `lib/presentation/settings/sections/proxy_section.dart`

- [ ] **Step 1: 创建新文件，合并 native 与 web 两条路径**

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/settings_cubit.dart';
import 'section_widgets.dart';

/// Native proxy toggle + address dialog (was `_buildNativeProxySection` +
/// `_showProxyAddressDialog`), or the web-only live proxy config editor
/// (was `_ProxySettingsSection`/`_ProxySettingsSectionState`), selected via
/// [kIsWeb] at the call site in settings_screen.dart.
class ProxySection extends StatelessWidget {
  const ProxySection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    // paste original _buildNativeProxySection body verbatim (266-290行),
    // replacing _showProxyAddressDialog(...) calls with the private
    // _showProxyAddressDialog function below (moved verbatim, 451-480行,
    // keep it private to this file — only called from within this file)
  }
}

void _showProxyAddressDialog(BuildContext context, String currentAddress) {
  // paste original _showProxyAddressDialog body verbatim (451-480行)
}

/// Was `_ProxySettingsSection`/`_ProxySettingsSectionState` (web-only).
class WebProxySection extends StatefulWidget {
  const WebProxySection({super.key});

  @override
  State<WebProxySection> createState() => _WebProxySectionState();
}

class _WebProxySectionState extends State<WebProxySection> {
  // paste original _ProxySettingsSectionState body verbatim (704-849行)
}
```

- [ ] **Step 2: 修改 `settings_screen.dart`**

在 `_SettingsView.build()` 里找到原来判断 `if (kIsWeb) ... _ProxySettingsSection() ... else ... _buildNativeProxySection(...)` 的位置，改为：
```dart
if (kIsWeb) const WebProxySection() else ProxySection(state: state),
```
添加 `import 'sections/proxy_section.dart';`。

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/presentation/settings/settings_screen.dart lib/presentation/settings/sections/proxy_section.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/settings/settings_screen.dart lib/presentation/settings/sections/proxy_section.dart
git commit -m "refactor: extract sections/proxy_section.dart (native + web)"
```

---

### Task 10: 抽取 `sections/adult_content_section.dart`

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Create: `lib/presentation/settings/sections/adult_content_section.dart`

- [ ] **Step 1: 创建新文件**

合并 `_buildAdultSection`（292-322行）、`_showActivationDialog`（345-426行）、`_showLockConfirmDialog`（428-449行）三者（后两者只被这个 section 用，设为 private 顶层函数）：
```dart
class AdultContentSection extends StatelessWidget {
  const AdultContentSection({super.key, required this.state});
  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    // paste original _buildAdultSection body verbatim (292-322行)
  }
}

void _showActivationDialog(BuildContext context, SettingsCubit cubit) {
  // paste original _showActivationDialog body verbatim (345-426行)
}

void _showLockConfirmDialog(BuildContext context, SettingsCubit cubit) {
  // paste original _showLockConfirmDialog body verbatim (428-449行)
}
```

- [ ] **Step 2-4**：同 Task 6 模式（改调用点、验证、commit）。

Commit message: `refactor: extract sections/adult_content_section.dart`

---

### Task 11: 抽取 `sections/ai_section.dart`、`sections/plugin_section.dart`、`sections/data_management_section.dart`、`sections/about_section.dart`

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Create: `lib/presentation/settings/sections/ai_section.dart`（源 `_buildAiSection`，324-343行）
- Create: `lib/presentation/settings/sections/plugin_section.dart`（源 `_buildPluginSection`+`_navigateToVerify`，482-544行）
- Create: `lib/presentation/settings/sections/data_management_section.dart`（源 `_buildDataSection`，546-643行，调用 `showSettingsConfirmDialog` 而不是本地 `_showConfirmDialog`）
- Create: `lib/presentation/settings/sections/about_section.dart`（源 `_buildAboutSection`，645-658行）

对这4个文件逐一重复 Task 6 的模式（每个单独一个 commit，共4次 commit）：
- [ ] 创建文件、迁入对应方法体、转成 `StatelessWidget`
- [ ] 修改 `settings_screen.dart` 调用点
- [ ] `flutter analyze` 验证
- [ ] Commit（分别）：
  - `refactor: extract sections/ai_section.dart`
  - `refactor: extract sections/plugin_section.dart`
  - `refactor: extract sections/data_management_section.dart`
  - `refactor: extract sections/about_section.dart`

---

### Task 12: 清理 `settings_screen.dart`，删除已迁移的旧方法体

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`

- [ ] **Step 1: 删除所有已迁移的私有方法**

确认 Task 5-11 迁移过的以下方法体已在新文件中且调用点已切换后，从 `settings_screen.dart` 里删除原方法定义：`_buildSectionHeader`、`_showConfirmDialog`、`_buildReadingSection`、`_buildReaderEnhancementsSection`、`_buildThemeSection`、`_buildNativeProxySection`、`_showProxyAddressDialog`、`_buildAdultSection`、`_showActivationDialog`、`_showLockConfirmDialog`、`_buildAiSection`、`_buildPluginSection`、`_navigateToVerify`、`_buildDataSection`、`_buildAboutSection`、`_ProxySettingsSection`/`_ProxySettingsSectionState`。

保留：`SettingsScreen`、`_SettingsView`（仅剩 `build()` 编排 9 个 section widget）。

- [ ] **Step 2: 验证**

Run: `flutter analyze lib/presentation/settings/`
Expected: `No issues found!`

Run: `wc -l lib/presentation/settings/settings_screen.dart`
Expected: 应显著小于原850行（目标 < 100行）

手动验证：打开设置页，逐个滚动确认全部 section（阅读/增强/主题/代理/成人内容/AI/插件/数据管理/关于）UI 与之前一致，各按钮/对话框正常工作。

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/settings/settings_screen.dart
git commit -m "refactor: settings_screen.dart now purely orchestrates section widgets"
```

---

## Part C: `manga_repository_impl.dart`（713行 → 4个文件，含去重）

### Task 13: 建立测试基线

**Files:**
- (无修改，仅验证)

- [ ] **Step 1: 运行现有单测，记录基线**

Run: `flutter test test/data/repositories/manga_repository_impl_test.dart -r expanded`
Expected: 全部 PASS（记下具体测例数量，后续每个 Task 完成后都要重新跑这个命令，数量和结果必须保持一致）

Run: `flutter analyze lib/data/repositories/manga_repository_impl.dart`
Expected: `No issues found!`

---

### Task 14: 抽取 `fetch_pipeline.dart`

**Files:**
- Modify: `lib/data/repositories/manga_repository_impl.dart`
- Create: `lib/data/repositories/fetch_pipeline.dart`

- [ ] **Step 1: 创建新文件**

```dart
import 'package:dio/dio.dart';

import '../remote/http_client.dart';
import '../sources/manga_source.dart';
import '../../core/models/fetch_config.dart';
import '../../domain/entities/chapter.dart';

/// Handles header merging, domain-fallback retry, and Cloudflare preflight
/// checks shared by every [MangaRepositoryImpl] method. Extracted from
/// `MangaRepositoryImpl` to isolate the "transport resilience" concern from
/// per-endpoint business logic.
class FetchPipeline {
  FetchPipeline(this._httpClient);

  final HttpClient _httpClient;

  /// Was `MangaRepositoryImpl._mergeHeaders`. Public because
  /// `ChapterImagePipeline` also needs it directly (not every header-merge
  /// call site goes through [executeWithFallback]).
  FetchConfig mergeHeaders(FetchConfig config, MangaSource source) {
    // paste original _mergeHeaders body verbatim (30-46行)
  }

  Future<void> preflightImageCf(MangaSource source, ChapterImage image) {
    // paste original _preflightImageCf body verbatim (50-89行)
  }

  Future<Response> executeWithFallback(
    FetchConfig config,
    MangaSource source,
    FetchConfig Function() rebuildConfig,
  ) {
    // paste original _executeWithFallback body verbatim (93-152行),
    // replacing internal `_mergeHeaders(...)` calls with `mergeHeaders(...)`
  }
}
```

- [ ] **Step 2: 修改 `manga_repository_impl.dart`**

在类字段区添加：
```dart
late final FetchPipeline _pipeline = FetchPipeline(_httpClient);
```
把原来直接调用 `_mergeHeaders(...)`/`_executeWithFallback(...)`/`_preflightImageCf(...)` 的地方（分布在 `getDiscovery`/`searchManga`/`getMangaInfo`/`getChapterList`/`getChapter`/`getChapterStream` 里）全部改成 `_pipeline.mergeHeaders(...)`/`_pipeline.executeWithFallback(...)`/`_pipeline.preflightImageCf(...)`。删除原 `_mergeHeaders`/`_executeWithFallback`/`_preflightImageCf` 方法定义（30-152行）。文件顶部添加 `import 'fetch_pipeline.dart';`。

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/data/repositories/`
Expected: `No issues found!`

Run: `flutter test test/data/repositories/manga_repository_impl_test.dart -r expanded`
Expected: 与 Task 13 基线完全一致（相同测例数量全部 PASS）

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/manga_repository_impl.dart lib/data/repositories/fetch_pipeline.dart
git commit -m "refactor: extract fetch_pipeline.dart (header merge, domain fallback, CF preflight)"
```

---

### Task 15: 抽取 `wu55_chapter_decryptor.dart`

**Files:**
- Modify: `lib/data/repositories/manga_repository_impl.dart`
- Create: `lib/data/repositories/wu55_chapter_decryptor.dart`

- [ ] **Step 1: 创建新文件**

```dart
import '../remote/http_client.dart';
import '../sources/wu55_comic.dart'; // 核实实际文件路径/类名 Wu55Comic
import '../../domain/entities/chapter.dart';

/// Decrypts a single wu55comic AES-encrypted chapter image into a
/// directly-renderable data-URI `ChapterImage`. Extracted verbatim from
/// `MangaRepositoryImpl._decryptWu55Image`.
class Wu55ChapterDecryptor {
  Wu55ChapterDecryptor(this._httpClient);

  final HttpClient _httpClient;

  Future<ChapterImage> decrypt(
    ChapterImage image,
    int index,
    Wu55Comic source,
  ) {
    // paste original _decryptWu55Image body verbatim (640-678行)
  }
}
```

- [ ] **Step 2: 修改 `manga_repository_impl.dart`**

添加字段 `late final Wu55ChapterDecryptor _wu55Decryptor = Wu55ChapterDecryptor(_httpClient);`，把 `getChapter`/`getChapterStream` 里调用 `_decryptWu55Image(...)` 的地方改为 `_wu55Decryptor.decrypt(...)`，删除原 `_decryptWu55Image` 方法（640-678行）。添加 `import 'wu55_chapter_decryptor.dart';`。

- [ ] **Step 3: 验证与 Commit**（同 Task 14 模式）

Run: `flutter test test/data/repositories/manga_repository_impl_test.dart -r expanded`
Expected: 与基线一致

```bash
git add lib/data/repositories/manga_repository_impl.dart lib/data/repositories/wu55_chapter_decryptor.dart
git commit -m "refactor: extract wu55_chapter_decryptor.dart"
```

---

### Task 16: 抽取 `hitomi_enrichment.dart`

**Files:**
- Modify: `lib/data/repositories/manga_repository_impl.dart`
- Create: `lib/data/repositories/hitomi_enrichment.dart`

- [ ] **Step 1: 创建新文件**

```dart
import '../sources/hitomi.dart'; // 核实实际文件路径/类名 Hitomi
import '../../domain/entities/manga.dart';

/// Hitomi-specific search-result enrichment (gg.js metadata refresh, etc.).
/// Extracted verbatim from `MangaRepositoryImpl._enrichHitomiResults`.
Future<List<MangaSummary>> enrichHitomiResults(
  Hitomi source,
  dynamic rawResults,
) {
  // paste original _enrichHitomiResults body verbatim (682-712行)
}
```

- [ ] **Step 2: 修改 `manga_repository_impl.dart`**

把 `getDiscovery`/`searchManga` 里调用 `_enrichHitomiResults(...)` 的地方改为顶层函数调用 `enrichHitomiResults(...)`，删除原方法（682-712行）。添加 `import 'hitomi_enrichment.dart';`。

- [ ] **Step 3: 验证与 Commit**（同上模式）

```bash
git add lib/data/repositories/manga_repository_impl.dart lib/data/repositories/hitomi_enrichment.dart
git commit -m "refactor: extract hitomi_enrichment.dart"
```

---

### Task 17: 抽取 `chapter_image_pipeline.dart` 并去重 `getChapter`/`getChapterStream`

这是本计划里风险最高、收益最大的一步：`getChapter`（236-446行）与 `getChapterStream`（448-637行）里的 PicaComic 分页展开、wu55解密调用、E-Hentai resolve 三段逻辑几乎逐行复制。目标是把这三段共用逻辑各提炼成一个私有辅助方法，非流式版本 `return`，流式版本 `yield`/`add` 调用同一份逻辑。

**Files:**
- Modify: `lib/data/repositories/manga_repository_impl.dart`
- Create: `lib/data/repositories/chapter_image_pipeline.dart`

- [ ] **Step 1: 先只做"原样搬移"（不去重），确认零回归**

创建 `chapter_image_pipeline.dart`：
```dart
import 'dart:async';

import '../remote/http_client.dart';
import '../sources/manga_source.dart';
import '../../domain/entities/chapter.dart';
import 'fetch_pipeline.dart';
import 'wu55_chapter_decryptor.dart';

/// Orchestrates fetching a chapter's images, including source-specific
/// pagination/decryption strategies (PicaComic-style multi-page expansion,
/// wu55 AES decryption, E-Hentai image-page resolution). Extracted from
/// `MangaRepositoryImpl.getChapter`/`getChapterStream`.
class ChapterImagePipeline {
  ChapterImagePipeline(this._httpClient, this._fetchPipeline, this._wu55Decryptor);

  final HttpClient _httpClient;
  final FetchPipeline _fetchPipeline;
  final Wu55ChapterDecryptor _wu55Decryptor;

  Future<ChapterResult> getChapter(
    String sourceId,
    String mangaId,
    String chapterId,
    int page,
    MangaSource source, {
    dynamic extra,
  }) async {
    // Step 1（本步）：把原 getChapter 方法体（236-446行）原样搬进来，
    // 内部 _mergeHeaders/_executeWithFallback/_decryptWu55Image 调用
    // 改为 _fetchPipeline.mergeHeaders/_fetchPipeline.executeWithFallback/
    // _wu55Decryptor.decrypt。不做任何去重，先保证行为100%等价。
  }

  Stream<ChapterResult> getChapterStream(
    String sourceId,
    String mangaId,
    String chapterId,
    int page,
    MangaSource source, {
    dynamic extra,
  }) async* {
    // Step 1（本步）：把原 getChapterStream 方法体（448-637行）原样搬进来，
    // 同样只替换依赖调用，不做去重。
  }
}
```

修改 `manga_repository_impl.dart`：添加字段 `late final ChapterImagePipeline _chapterPipeline = ChapterImagePipeline(_httpClient, _pipeline, _wu55Decryptor);`，把 `@override Future<ChapterResult> getChapter(...)` 方法体改为：
```dart
@override
Future<ChapterResult> getChapter(
  String sourceId, String mangaId, String chapterId, int page,
  {dynamic extra}
) {
  final source = _sourceRegistry.get(sourceId); // 核实实际获取 source 的方式，参照原方法体第一行
  return _chapterPipeline.getChapter(sourceId, mangaId, chapterId, page, source, extra: extra);
}
```
`getChapterStream` 同理委托给 `_chapterPipeline.getChapterStream(...)`。删除原 `manga_repository_impl.dart` 里 236-637 行的方法体（已迁移）。

- [ ] **Step 2: 验证搬移零回归**

Run: `flutter analyze lib/data/repositories/`
Expected: `No issues found!`

Run: `flutter test test/data/repositories/manga_repository_impl_test.dart -r expanded`
Expected: 与 Task 13 基线完全一致

- [ ] **Step 3: Commit（搬移阶段）**

```bash
git add lib/data/repositories/manga_repository_impl.dart lib/data/repositories/chapter_image_pipeline.dart
git commit -m "refactor: extract chapter_image_pipeline.dart (verbatim move, no dedup yet)"
```

- [ ] **Step 4: 在 `chapter_image_pipeline.dart` 内部去重三段共用逻辑**

对比 `getChapter`（非流式）和 `getChapterStream`（流式）里的三段逻辑，各提炼成一个 `_expand*`私有辅助方法：

```dart
  /// Expands a PicaComic-style chapter response into a flat list of
  /// per-page `ChapterImage`s by looping through all pages. Shared by both
  /// [getChapter] and [getChapterStream] (previously duplicated verbatim in
  /// both methods).
  Future<List<ChapterImage>> _expandPicaPages(
    /* 核实实际所需参数：source, chapterId, 首页响应等，
       参照 getChapter 原304-326行与 getChapterStream 原477-498行的
       共同输入 */
  ) async {
    // 用两处重复代码中较完整的一份作为基准合并，删除另一份的重复实现
  }

  /// Resolves wu55comic AES-encrypted images for a full chapter by calling
  /// [_wu55Decryptor] per image. Shared by both [getChapter] and
  /// [getChapterStream] (previously duplicated in getChapter 330-359行 and
  /// getChapterStream 603-633行).
  Future<List<ChapterImage>> _resolveWu55Images(
    /* 核实实际所需参数 */
  ) async {
    // 合并两处重复实现
  }

  /// Resolves E-Hentai-style index pages into real image URLs via a
  /// secondary fetch per page. Shared by both [getChapter] and
  /// [getChapterStream] (previously duplicated in getChapter 361-443行 and
  /// getChapterStream 500-601行).
  Future<List<ChapterImage>> _resolveEhentaiImages(
    /* 核实实际所需参数 */
  ) async {
    // 合并两处重复实现
  }
```

把 `getChapter`/`getChapterStream` 方法体里对应的三段内联逻辑替换成对这三个私有方法的调用（`getChapterStream` 里如果原来是逐步 `yield` 渐进式输出，去重后如果 `_expand*`/`_resolve*` 返回的是"一次性拿到全部结果"的 `Future<List<ChapterImage>>`，`getChapterStream` 可以在拿到结果后自己决定要不要拆成多次 `yield`——**如果流式版本的渐进式输出对用户体验有意义（比如 E-Hentai 逐页 resolve 后立即展示），不要为了去重牺牲这个渐进式体验**：可以让 `_resolveEhentaiImages` 改造成返回 `Stream<ChapterImage>`（每 resolve 一张就 emit 一张），`getChapter`（非流式）用 `.toList()` 收集全部结果，`getChapterStream` 直接 `yield*` 转发这个 stream，这样两边都复用同一份 resolve 逻辑且不牺牲流式体验。视实际原代码的具体行为决定用哪种去重形态，本步骤的硬性要求是：去重后 `getChapter`/`getChapterStream` 的对外行为（返回的图片顺序、图片数量、错误传播时机）与去重前必须完全一致。

- [ ] **Step 5: 验证去重后零回归**

Run: `flutter analyze lib/data/repositories/`
Expected: `No issues found!`

Run: `flutter test test/data/repositories/manga_repository_impl_test.dart -r expanded`
Expected: 与 Task 13 基线完全一致

手动验证（因去重涉及三个不同数据源的分页/解密/resolve逻辑，单测覆盖有限，需要重点手动走查）：
1. 打开一部 PicaComic 来源的漫画章节，确认全部分页图片正常加载、顺序正确
2. 打开一部 wu55comic 来源的漫画章节，确认加密图片正常解密显示
3. 打开一部 E-Hentai 来源的画廊，确认图片索引页正常 resolve 出真实图片并按顺序显示
4. 分别在"点开章节直接看"（走 `getChapterStream`，`_onLoadChapter`）与"垂直阅读器无限滚动追加下一章"（走 `getChapter`，`_onAppendNextChapter`）两条路径各测一次，确认三种数据源在两条路径下行为一致

- [ ] **Step 6: Commit（去重阶段）**

```bash
git add lib/data/repositories/chapter_image_pipeline.dart
git commit -m "refactor: dedupe PicaComic/wu55/E-Hentai logic shared by getChapter and getChapterStream"
```

- [ ] **Step 7: 最终检查 `manga_repository_impl.dart` 行数与外部签名**

Run: `wc -l lib/data/repositories/manga_repository_impl.dart`
Expected: 应显著小于原713行（目标 < 150行，仅剩字段+构造器+4个标准CRUD编排+2个委托方法）

Run: `grep -n "class MangaRepositoryImpl" lib/data/repositories/manga_repository_impl.dart`
Expected: 确认仍是 `class MangaRepositoryImpl implements MangaRepository`，构造器仍接受具名参数 `httpClient`/`sourceRegistry`（`lib/app/di/injection.dart:172-177` 和 `test/data/repositories/manga_repository_impl_test.dart:131-132` 都依赖这个不变的外部签名，不能改）

- [ ] **Step 8: 全量回归**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全部 PASS
