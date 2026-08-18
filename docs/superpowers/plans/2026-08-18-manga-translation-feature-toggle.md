# 漫画翻译功能总开关 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给漫画翻译功能加一个默认关闭的全局开关，并把 460MB 模型下载入口从 debug 调试页搬到正式设置页的「漫画翻译」二级页（含断点续传）。

**Architecture:** 一个持久化布尔字段 `AppSettings.mangaTranslationEnabled`（默认 `false`）→ `ReaderBloc._applySettings()` 构造时镜像进 `ReaderState.translationFeatureEnabled` → `reader_controls.dart` 的 `_TopBar` 用它决定是否渲染 translate 按钮。设置侧新增一个 section 入口 + 一个 `TranslationSettingsScreen` 二级页，页内承载开关、模型下载状态/进度、AI 配置跳转、清空翻译缓存。`TranslationModelManager.downloadAll` 改为写 `.part` 临时文件 + `Range` 续传。

**Tech Stack:** Flutter / flutter_bloc（`SettingsCubit`、`ReaderBloc`）/ GetIt / `dart:io HttpClient` / mocktail + bloc_test。

**Spec:** `docs/superpowers/specs/2026-08-18-manga-translation-feature-toggle-design.md`

---

## File Structure

| 文件 | 动作 | 责任 |
|---|---|---|
| `lib/data/local/settings_store.dart` | 修改 | 新增 `mangaTranslationEnabled` 字段（5 处：声明/构造/copyWith/toJson/fromJson） |
| `lib/presentation/settings/bloc/settings_cubit.dart` | 修改 | 新增 `setMangaTranslationEnabled` setter |
| `lib/data/translation/translation_cache_store.dart` | 修改 | 新增 `clearAll()` |
| `lib/data/translation/translation_model_manager.dart` | 修改 | 新增续传决策纯函数 + `downloadAll` 改 `.part` + `Range` |
| `lib/presentation/settings/translation_settings_screen.dart` | 新建 | 二级页：开关 + 模型状态/下载 + AI 跳转 + 清缓存 |
| `lib/presentation/settings/sections/translation_section.dart` | 新建 | 设置页「漫画翻译」入口 section |
| `lib/presentation/settings/settings_screen.dart` | 修改 | 插入 section（`if (!kIsWeb)`） |
| `lib/presentation/reader/bloc/reader_state.dart` | 修改 | 新增 `translationFeatureEnabled`（5 处） |
| `lib/presentation/reader/bloc/reader_bloc.dart` | 修改 | `_applySettings()` 镜像一行 + `_onTranslateChapterToggled` 守卫一行 |
| `lib/presentation/reader/widgets/reader_controls.dart` | 修改 | `_TopBar` 新增参数 + 按钮可见性条件 |
| `test/data/local/settings_store_test.dart` | 修改 | +1 group / 4 test |
| `test/data/translation/translation_model_manager_test.dart` | 修改 | +3 test（续传决策纯函数） |
| `test/data/translation/translation_cache_store_test.dart` | 修改 | +2 test（`clearAll`） |
| `test/presentation/reader/bloc/reader_bloc_test.dart` | 修改 | +2 blocTest |

**不改动**：`lib/app/di/injection.dart`（`SettingsStore` / `TranslationModelManager` / `TranslationCacheStore` 均已注册）、`lib/app/app.dart`、`lib/main.dart`、`lib/presentation/reader/widgets/vertical_reader.dart`、两个 painter、`translation_pipeline.dart`、`reader_event.dart`、`settings_screen.dart` 里的 `kDebugMode` 调试页入口（保留）。

---

### Task 1: `AppSettings.mangaTranslationEnabled`

**Files:**
- Modify: `lib/data/local/settings_store.dart:36,56,77,97,119,146`
- Test: `test/data/local/settings_store_test.dart`

- [ ] **Step 1: 写失败的测试**

在 `test/data/local/settings_store_test.dart` 的 `main()` 里，现有 `group('AppSettings.discoveryViewMode', ...)` 之后追加：

```dart
  group('AppSettings.mangaTranslationEnabled', () {
    test('defaults to false', () {
      const settings = AppSettings();
      expect(settings.mangaTranslationEnabled, isFalse);
    });

    test('copyWith updates mangaTranslationEnabled', () {
      const settings = AppSettings();
      final updated = settings.copyWith(mangaTranslationEnabled: true);
      expect(updated.mangaTranslationEnabled, isTrue);
    });

    test('toJson/fromJson round-trip preserves mangaTranslationEnabled', () {
      const settings = AppSettings(mangaTranslationEnabled: true);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.mangaTranslationEnabled, isTrue);
    });

    test('fromJson defaults to false when field is missing', () {
      final restored = AppSettings.fromJson(<String, dynamic>{});
      expect(restored.mangaTranslationEnabled, isFalse);
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/local/settings_store_test.dart`
Expected: 编译失败，`The named parameter 'mangaTranslationEnabled' isn't defined` / `isn't a member`

- [ ] **Step 3: 加字段（5 处）**

`lib/data/local/settings_store.dart`，在 `discoveryViewMode` 声明（第 36 行）之后插入：

```dart
  // --- Manga translation feature toggle ---
  /// 漫画翻译功能总开关。关闭时阅读器顶栏不显示翻译按钮，功能入口对用户隐身。
  /// 默认关闭：需要下载约 460MB 模型 + 自备 AI API Key。
  final bool mangaTranslationEnabled;
```

const 构造（第 56 行 `this.discoveryViewMode = DiscoveryViewMode.grid,` 之后）插入：

```dart
    this.mangaTranslationEnabled = false,
```

`copyWith` 参数列表（第 77 行 `DiscoveryViewMode? discoveryViewMode,` 之后）插入：

```dart
    bool? mangaTranslationEnabled,
```

`copyWith` 返回体（第 97 行 `discoveryViewMode: discoveryViewMode ?? this.discoveryViewMode,` 之后）插入：

```dart
      mangaTranslationEnabled:
          mangaTranslationEnabled ?? this.mangaTranslationEnabled,
```

`toJson`（第 119 行 `'discoveryViewMode': discoveryViewMode.index,` 之后）插入：

```dart
      'mangaTranslationEnabled': mangaTranslationEnabled,
```

`fromJson`（第 145-146 行的 `discoveryViewMode:` 之后）插入：

```dart
      mangaTranslationEnabled:
          json['mangaTranslationEnabled'] as bool? ?? false,
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/local/settings_store_test.dart`
Expected: All tests passed（原有 4 个 + 新增 4 个）

- [ ] **Step 5: 提交**

```bash
git add lib/data/local/settings_store.dart test/data/local/settings_store_test.dart
git commit -m "feat(settings): 新增 mangaTranslationEnabled 持久化字段"
```

---

### Task 2: `SettingsCubit.setMangaTranslationEnabled`

**Files:**
- Modify: `lib/presentation/settings/bloc/settings_cubit.dart`（紧跟 `setShowPageNumber`，第 100 行之后）

无新增测试：这是与 `setShowPageNumber`（`settings_cubit.dart:96-100`）逐字同构的三行 setter，无副作用，Task 1 已锁住持久化语义，仓库也没有 `settings_cubit_test.dart`。

- [ ] **Step 1: 加 setter**

在 `lib/presentation/settings/bloc/settings_cubit.dart` 的 `setShowPageNumber` 方法（第 96-100 行）之后插入：

```dart

  Future<void> setMangaTranslationEnabled(bool enabled) async {
    final updated = state.settings.copyWith(mangaTranslationEnabled: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }
```

- [ ] **Step 2: 静态检查**

Run: `flutter analyze lib/presentation/settings/bloc/settings_cubit.dart`
Expected: No issues found!

- [ ] **Step 3: 提交**

```bash
git add lib/presentation/settings/bloc/settings_cubit.dart
git commit -m "feat(settings): SettingsCubit 新增 setMangaTranslationEnabled"
```

---

### Task 3: `TranslationCacheStore.clearAll()`

**Files:**
- Modify: `lib/data/translation/translation_cache_store.dart:81`（在 `clearChapter` 之后、类右括号之前）
- Test: `test/data/translation/translation_cache_store_test.dart`

- [ ] **Step 1: 写失败的测试**

在 `test/data/translation/translation_cache_store_test.dart` 的最后一个 `test(...)` 之后（同一个 `group` 内，复用文件已有的 `store` / `tempDir` fixture）追加：

```dart
    test('clearAll removes every cached page', () async {
      await store.save(const PageTranslation(
        sourceId: 's',
        mangaId: 'm',
        chapterId: 'c',
        pageIndex: 0,
        regions: [],
      ));
      await store.save(const PageTranslation(
        sourceId: 's2',
        mangaId: 'm2',
        chapterId: 'c2',
        pageIndex: 3,
        regions: [],
      ));

      await store.clearAll();

      expect(await store.get('s', 'm', 'c', 0), isNull);
      expect(await store.get('s2', 'm2', 'c2', 3), isNull);
    });

    test('clearAll is a no-op when the cache directory does not exist',
        () async {
      await store.clearAll();
      await expectLater(store.clearAll(), completes);
    });
```

> 注意：`PageTranslation` 的构造参数以本文件已有的 `store.save(...)` 调用为准。先跑
> `rtk grep -n "PageTranslation(" test/data/translation/translation_cache_store_test.dart`
> 把已有那次构造整段复制过来改 id/pageIndex，避免参数名/`translatedAt` 是否必填猜错。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/translation/translation_cache_store_test.dart`
Expected: 编译失败，`The method 'clearAll' isn't defined for the type 'TranslationCacheStore'`

- [ ] **Step 3: 实现 `clearAll`**

`lib/data/translation/translation_cache_store.dart`，在 `clearChapter`（第 71-80 行）之后插入：

```dart

  /// 删除整个翻译缓存目录。Web 上是 no-op（本类在 web 全程 no-op）。
  Future<void> clearAll() async {
    if (kIsWeb) return;
    final base = await _cachePath;
    final dir = Directory(base);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/translation/translation_cache_store_test.dart`
Expected: All tests passed（原有 5 个 + 新增 2 个）

- [ ] **Step 5: 提交**

```bash
git add lib/data/translation/translation_cache_store.dart test/data/translation/translation_cache_store_test.dart
git commit -m "feat(translation): TranslationCacheStore 新增 clearAll"
```

---

### Task 4: 断点续传决策纯函数

**Files:**
- Modify: `lib/data/translation/translation_model_manager.dart`（在 `ModelNotReadyException` 之后、`TranslationModelManager` 类之前，即第 66 行附近）
- Test: `test/data/translation/translation_model_manager_test.dart`

`downloadAll` 内部用的是裸 `io.HttpClient()`，不可注入 mock，所以把「已有多少字节 → 怎么继续」的判断抽成纯函数单独测试，网络部分靠 Task 10 的手工验证覆盖。

- [ ] **Step 1: 写失败的测试**

在 `test/data/translation/translation_model_manager_test.dart` 的 `main()` 末尾追加：

```dart
  group('decideResume', () {
    test('skips when the partial file already has every byte', () {
      final d = decideResume(existingBytes: 100, totalBytes: 100);
      expect(d.action, ResumeAction.skip);
      expect(d.startOffset, 0);
    });

    test('resumes from the existing byte count when partially downloaded', () {
      final d = decideResume(existingBytes: 40, totalBytes: 100);
      expect(d.action, ResumeAction.resume);
      expect(d.startOffset, 40);
    });

    test('restarts when the partial file is longer than expected', () {
      final d = decideResume(existingBytes: 140, totalBytes: 100);
      expect(d.action, ResumeAction.restart);
      expect(d.startOffset, 0);
    });

    test('restarts when nothing has been downloaded yet', () {
      final d = decideResume(existingBytes: 0, totalBytes: 100);
      expect(d.action, ResumeAction.restart);
      expect(d.startOffset, 0);
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/translation/translation_model_manager_test.dart`
Expected: 编译失败，`Undefined name 'decideResume'` / `ResumeAction`

- [ ] **Step 3: 实现纯函数**

`lib/data/translation/translation_model_manager.dart`，在 `ModelNotReadyException` 类（第 60-65 行）之后插入：

```dart

/// 断点续传的三种走向。
enum ResumeAction {
  /// `.part` 已经是完整文件，直接改名转正。
  skip,

  /// `.part` 是有效前缀，带 `Range: bytes=<offset>-` 续下。
  resume,

  /// 没有 `.part`，或 `.part` 比目标还长（脏数据），从 0 重下。
  restart,
}

/// 续传决策结果。[startOffset] 只在 [ResumeAction.resume] 时有意义。
class ResumeDecision {
  const ResumeDecision(this.action, this.startOffset);
  final ResumeAction action;
  final int startOffset;
}

/// 纯函数：根据本地 `.part` 已有字节数 [existingBytes] 与目标总字节数
/// [totalBytes] 决定如何继续下载。抽成纯函数是为了可单测——[downloadAll]
/// 内部用的是裸 `HttpClient`，无法注入 mock。
ResumeDecision decideResume({
  required int existingBytes,
  required int totalBytes,
}) {
  if (existingBytes == totalBytes) {
    return const ResumeDecision(ResumeAction.skip, 0);
  }
  if (existingBytes <= 0 || existingBytes > totalBytes) {
    return const ResumeDecision(ResumeAction.restart, 0);
  }
  return ResumeDecision(ResumeAction.resume, existingBytes);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/translation/translation_model_manager_test.dart`
Expected: All tests passed（原有测试 + 新增 4 个）

- [ ] **Step 5: 提交**

```bash
git add lib/data/translation/translation_model_manager.dart test/data/translation/translation_model_manager_test.dart
git commit -m "feat(translation): 新增断点续传决策纯函数"
```

---

### Task 5: `downloadAll` 改为 `.part` + `Range` 续传

**Files:**
- Modify: `lib/data/translation/translation_model_manager.dart:118-159`（整段替换 `downloadAll`）

- [ ] **Step 1: 替换 `downloadAll`**

把 `lib/data/translation/translation_model_manager.dart` 第 118-159 行（`/// Downloads every model file...` 注释 + 整个 `downloadAll` 方法）整段替换为：

```dart
  /// 下载缺失/字节数不符的模型文件，流式写入 `<name>.part` 后改名转正。
  ///
  /// 断点续传：`.part` 在失败时**保留**，下次调用带 `Range: bytes=N-` 从中断处
  /// 继续；服务器忽略 Range（返回 200 而非 206）时退化为从头重下。
  /// [onProgress] 报告 `(relativePath, receivedBytes, totalBytes)`，已就绪的
  /// 文件会立刻回调一次 received == total。
  ///
  /// 无互斥锁：调用方必须保证同一时刻只有一个 [downloadAll] 在跑（UI 侧用
  /// `PopScope(canPop: false)` + 禁用按钮实现）。
  Future<void> downloadAll({
    void Function(String file, int received, int total)? onProgress,
  }) async {
    for (final spec in _files) {
      final path = await pathFor(spec.relativePath);
      final file = io.File(path);
      if (await file.exists() && await file.length() == spec.sizeBytes) {
        onProgress?.call(spec.relativePath, spec.sizeBytes, spec.sizeBytes);
        continue;
      }
      await file.parent.create(recursive: true);

      final part = io.File('$path.part');
      final existing = await part.exists() ? await part.length() : 0;
      final decision = decideResume(
        existingBytes: existing,
        totalBytes: spec.sizeBytes,
      );
      if (decision.action == ResumeAction.skip) {
        await part.rename(path);
        onProgress?.call(spec.relativePath, spec.sizeBytes, spec.sizeBytes);
        continue;
      }
      if (decision.action == ResumeAction.restart && existing > 0) {
        await part.delete();
      }

      var received = decision.startOffset;
      final client = io.HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(spec.url));
        if (received > 0) {
          request.headers.set(io.HttpHeaders.rangeHeader, 'bytes=$received-');
        }
        final response = await request.close();
        final code = response.statusCode;
        if (code != 200 && code != 206) {
          throw StateError(
              '下载失败 ${spec.relativePath}: HTTP ${response.statusCode}');
        }
        // 服务器忽略了 Range：只能丢掉已有前缀从头写。
        if (code == 200 && received > 0) received = 0;

        final sink = part.openWrite(
          mode: received > 0 ? io.FileMode.append : io.FileMode.write,
        );
        try {
          onProgress?.call(spec.relativePath, received, spec.sizeBytes);
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(spec.relativePath, received, spec.sizeBytes);
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close(force: true);
      }

      // 失败时不删 `.part`（留给下次续传），只有长度达标才转正。
      final downloaded = await part.length();
      if (downloaded != spec.sizeBytes) {
        throw StateError(
            '下载不完整 ${spec.relativePath}: $downloaded/${spec.sizeBytes}');
      }
      await part.rename(path);
      onProgress?.call(spec.relativePath, spec.sizeBytes, spec.sizeBytes);
    }
  }
```

- [ ] **Step 2: 静态检查 + 回归已有测试**

Run: `flutter analyze lib/data/translation/translation_model_manager.dart && flutter test test/data/translation/translation_model_manager_test.dart`
Expected: No issues found! + All tests passed

- [ ] **Step 3: 提交**

```bash
git add lib/data/translation/translation_model_manager.dart
git commit -m "feat(translation): 模型下载支持 .part 断点续传"
```

---

### Task 6: `TranslationSettingsScreen` 二级页

**Files:**
- Create: `lib/presentation/settings/translation_settings_screen.dart`

与 `AiSettingsScreen` 刻意不同：**没有「保存」按钮，开关即时落盘**（走 `SettingsCubit`）。`StatefulWidget` 只是为了持有模型下载进度这类瞬时状态。

- [ ] **Step 1: 创建文件**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../core/ai/ai_config.dart';
import '../../data/translation/translation_cache_store.dart';
import '../../data/translation/translation_model_manager.dart';
import 'ai_settings_screen.dart';
import 'bloc/settings_cubit.dart';
import 'bloc/settings_state.dart';
import 'sections/section_widgets.dart';

/// 「漫画翻译」二级设置页：功能总开关 + 模型下载 + AI 配置入口 + 清缓存。
class TranslationSettingsScreen extends StatefulWidget {
  const TranslationSettingsScreen({super.key});

  @override
  State<TranslationSettingsScreen> createState() =>
      _TranslationSettingsScreenState();
}

class _TranslationSettingsScreenState extends State<TranslationSettingsScreen> {
  final TranslationModelManager _models =
      GetIt.instance<TranslationModelManager>();
  final TranslationCacheStore _cache = GetIt.instance<TranslationCacheStore>();
  final AiConfigStore _aiStore = GetIt.instance<AiConfigStore>();

  /// null = 检测中
  bool? _modelsReady;
  String? _modelsError;
  bool _downloading = false;
  int _received = 0;
  int _total = 0;
  bool _aiUsable = false;

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
    _refreshAiStatus();
  }

  Future<void> _refreshModelStatus() async {
    setState(() {
      _modelsReady = null;
      _modelsError = null;
    });
    try {
      final ready = await _models.isReady();
      if (!mounted) return;
      setState(() => _modelsReady = ready);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelsReady = false;
        _modelsError = '$e';
      });
    }
  }

  Future<void> _refreshAiStatus() async {
    final config = await _aiStore.load();
    if (!mounted) return;
    setState(() => _aiUsable = config.isUsable);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _received = 0;
      _total = 0;
    });
    try {
      await _models.downloadAll(onProgress: (file, received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          _total = total;
        });
      });
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _modelsReady = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('模型下载完成')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _modelsReady = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('下载失败：$e')));
    }
  }

  void _clearCache() {
    showSettingsConfirmDialog(
      context,
      title: '清空翻译缓存',
      content: '删除所有已缓存的翻译结果。已翻译过的页面下次阅读时需要重新调用 AI 翻译。',
      onConfirm: () async {
        try {
          await _cache.clearAll();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('清空失败：$e')));
        }
      },
    );
  }

  String get _modelStatusText {
    if (_downloading) {
      final pct = _total > 0 ? (_received * 100 / _total).floor() : 0;
      return '下载中 $pct%';
    }
    if (_modelsError != null) return '无法检测（$_modelsError）';
    if (_modelsReady == null) return '检测中…';
    return _modelsReady! ? '已就绪' : '未下载（约 460MB）';
  }

  Widget? _modelTrailing() {
    if (_downloading) {
      final pct = _total > 0 ? (_received * 100 / _total).floor() : 0;
      return Text('$pct%');
    }
    if (_modelsReady == true) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (_modelsReady == null) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return TextButton(
      onPressed: _download,
      child: Text(_modelsError == null ? '下载' : '重试下载'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 下载中禁止退出：downloadAll 没有互斥锁，重入会让两个 sink 写同一个
      // .part 文件。
      canPop: !_downloading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _downloading) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('模型下载中，请等待完成')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('漫画翻译')),
        body: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            final cubit = context.read<SettingsCubit>();
            final enabled = state.settings.mangaTranslationEnabled;
            return ListView(
              children: [
                SwitchListTile(
                  title: const Text('启用漫画翻译'),
                  subtitle:
                      const Text('开启后，竖向滚动阅读时顶栏会出现翻译按钮'),
                  value: enabled,
                  onChanged: _downloading
                      ? null
                      : cubit.setMangaTranslationEnabled,
                ),
                if (enabled) ...[
                  buildSettingsSectionHeader('翻译模型'),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('模型状态'),
                    subtitle: Text(_modelStatusText),
                    trailing: _modelTrailing(),
                  ),
                  if (_downloading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(
                        value: _total > 0 ? _received / _total : null,
                      ),
                    ),
                  buildSettingsSectionHeader('AI 服务'),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('AI 设置'),
                    subtitle:
                        Text(_aiUsable ? '已配置' : '未启用或未填 API Key'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AiSettingsScreen(),
                        ),
                      );
                      await _refreshAiStatus();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    title: const Text('清空翻译缓存',
                        style: TextStyle(color: Colors.redAccent)),
                    subtitle: const Text('不会删除已下载的模型'),
                    onTap: _downloading ? null : _clearCache,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 静态检查**

Run: `flutter analyze lib/presentation/settings/translation_settings_screen.dart`
Expected: No issues found!

如果报 `AiConfigStore` / `TranslationCacheStore` 未注册到 GetIt，跑
`rtk grep -n "AiConfigStore\|TranslationCacheStore\|TranslationModelManager" lib/app/di/injection.dart`
确认三者都在（预期分别在 126 / 153 / 144 行附近），无需新增注册。

- [ ] **Step 3: 提交**

```bash
git add lib/presentation/settings/translation_settings_screen.dart
git commit -m "feat(settings): 新增漫画翻译二级设置页"
```

---

### Task 7: 设置页「漫画翻译」入口 section

**Files:**
- Create: `lib/presentation/settings/sections/translation_section.dart`
- Modify: `lib/presentation/settings/settings_screen.dart:47`（`const AiSection(),` 之后）

- [ ] **Step 1: 创建 section**

```dart
import 'package:flutter/material.dart';

import '../bloc/settings_state.dart';
import '../translation_settings_screen.dart';
import 'section_widgets.dart';

/// 「漫画翻译」入口。照 `ai_section.dart` 的跳转型写法（原生 Navigator，
/// 不走 go_router）。
class TranslationSection extends StatelessWidget {
  const TranslationSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final enabled = state.settings.mangaTranslationEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('漫画翻译'),
        ListTile(
          leading: const Icon(Icons.translate),
          title: const Text('漫画翻译'),
          subtitle: Text(enabled ? '已启用' : '未启用'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TranslationSettingsScreen(),
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}
```

- [ ] **Step 2: 接入设置页**

`lib/presentation/settings/settings_screen.dart`：加 import

```dart
import 'sections/translation_section.dart';
```

在 `ListView` 的 `const AiSection(),`（第 47 行）之后插入：

```dart
          // Web 端翻译跑不起来（TranslationCacheStore 全 no-op、
          // NativeMangaTextExtractor 依赖 dart:io），整段隐藏。
          if (!kIsWeb) TranslationSection(state: state),
```

（`kIsWeb` 已在本文件 import，第 45 行的 `if (kIsWeb)` 就在用。）

- [ ] **Step 3: 静态检查**

Run: `flutter analyze lib/presentation/settings/`
Expected: No issues found!

- [ ] **Step 4: 提交**

```bash
git add lib/presentation/settings/sections/translation_section.dart lib/presentation/settings/settings_screen.dart
git commit -m "feat(settings): 设置页新增漫画翻译入口"
```

---

### Task 8: `ReaderState.translationFeatureEnabled` + Bloc 镜像与守卫

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_state.dart:96,128,160,191,251`
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`（`_applySettings()` 的 emit、`_onTranslateChapterToggled` 首行）
- Test: `test/presentation/reader/bloc/reader_bloc_test.dart`

- [ ] **Step 1: 写失败的测试**

在 `test/presentation/reader/bloc/reader_bloc_test.dart` 的 `group('Translation', ...)`（第 282 行起）**内部末尾**追加两个 blocTest。先跑

```bash
rtk grep -n "translatePage\|buildBlocWithTranslation\|MockTranslationPipeline" test/presentation/reader/bloc/reader_bloc_test.dart
```

确认 pipeline mock 的变量名与 `translatePage` 的具名参数形式，然后照抄到下面 `verifyNever` 的 matcher 里：

```dart
    blocTest<ReaderBloc, ReaderState>(
      'mirrors AppSettings.mangaTranslationEnabled into translationFeatureEnabled',
      setUp: () {
        when(() => settingsStore.load()).thenAnswer(
          (_) async => const settings.AppSettings(
            layoutMode: settings.LayoutMode.vertical,
            mangaTranslationEnabled: true,
          ),
        );
      },
      build: buildBlocWithTranslation,
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.translationFeatureEnabled, isTrue);
      },
    );

    blocTest<ReaderBloc, ReaderState>(
      'ignores TranslateChapterToggled while the feature toggle is off',
      build: buildBlocWithTranslation,
      wait: const Duration(milliseconds: 10),
      act: (bloc) => bloc.add(const TranslateChapterToggled(enabled: true)),
      verify: (bloc) {
        expect(bloc.state.translationFeatureEnabled, isFalse);
        expect(bloc.state.translationEnabled, isFalse);
        // 把这里替换成本文件已有 translatePage stub 的同款具名参数 matcher
        verifyNever(() => pipeline.translatePage(
              sourceId: any(named: 'sourceId'),
              mangaId: any(named: 'mangaId'),
              chapterId: any(named: 'chapterId'),
              pageIndex: any(named: 'pageIndex'),
              imageBytes: any(named: 'imageBytes'),
            ));
      },
    );
```

> 第一个测试的 `setUp` 覆盖了外层 `setUp` 里的 `settingsStore.load()` stub；`wait` 是必须的，因为 `_applySettings()` 是 fire-and-forget。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/presentation/reader/bloc/reader_bloc_test.dart`
Expected: 编译失败，`'translationFeatureEnabled' isn't defined` / `mangaTranslationEnabled` 未定义（若 Task 1 未先完成）

- [ ] **Step 3: 加 state 字段（5 处）**

`lib/presentation/reader/bloc/reader_state.dart`：

第 96 行 `final bool translationEnabled;` 之前插入：

```dart
  /// 漫画翻译功能总开关（AppSettings.mangaTranslationEnabled 的镜像）。
  /// 由 ReaderBloc 构造时读一次，决定顶栏是否渲染翻译按钮。
  final bool translationFeatureEnabled;
```

第 128 行 `this.translationEnabled = false,` 之前插入：

```dart
    this.translationFeatureEnabled = false,
```

第 160 行 `bool? translationEnabled,` 之前插入：

```dart
    bool? translationFeatureEnabled,
```

第 191 行 `translationEnabled: translationEnabled ?? this.translationEnabled,` 之前插入：

```dart
      translationFeatureEnabled:
          translationFeatureEnabled ?? this.translationFeatureEnabled,
```

第 251 行 props 列表里 `translationEnabled,` 之前插入：

```dart
        translationFeatureEnabled,
```

- [ ] **Step 4: Bloc 镜像 + 守卫（两行）**

`lib/presentation/reader/bloc/reader_bloc.dart`：

`_applySettings()` 里那个 `emit(state.copyWith(...))`，在 `showTapZones: s.showTapZones,` 之后加一行：

```dart
      translationFeatureEnabled: s.mangaTranslationEnabled,
```

`_onTranslateChapterToggled` 方法体第一行插入：

```dart
    // 总开关关闭时忽略事件（按钮本就不该渲染，这是纵深防御）。
    if (!state.translationFeatureEnabled) return;
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/presentation/reader/bloc/reader_bloc_test.dart`
Expected: All tests passed（原有 9 个 Translation 用例 + 新增 2 个）

- [ ] **Step 6: 提交**

```bash
git add lib/presentation/reader/bloc/reader_state.dart lib/presentation/reader/bloc/reader_bloc.dart test/presentation/reader/bloc/reader_bloc_test.dart
git commit -m "feat(reader): ReaderState 镜像翻译功能总开关"
```

---

### Task 9: 顶栏按钮可见性 gate

**Files:**
- Modify: `lib/presentation/reader/widgets/reader_controls.dart:28,52,59,101`

- [ ] **Step 1: `_TopBar` 新增参数并接线**

第 52 行 `final bool translationEnabled;` 之前插入：

```dart
  final bool translationFeatureEnabled;
```

第 59 行 `required this.translationEnabled,` 之前插入：

```dart
    required this.translationFeatureEnabled,
```

第 28 行 `translationEnabled: state.translationEnabled,` 之前插入：

```dart
            translationFeatureEnabled: state.translationFeatureEnabled,
```

- [ ] **Step 2: 改按钮可见性条件**

把第 98-101 行的注释 + 条件：

```dart
          // Translation toggle: manga translation overlay is vertical-reader
          // only (see reader_state.dart LayoutMode doc), so hide the button
          // entirely in horizontal mode to avoid wasted translation calls.
          if (layoutMode == LayoutMode.vertical)
```

替换为：

```dart
          // Translation toggle: hidden unless the global feature toggle
          // (settings → 漫画翻译) is on, since the feature needs a ~460MB
          // model download and a user-supplied AI key. Also vertical-reader
          // only (see reader_state.dart LayoutMode doc), so hide the button
          // entirely in horizontal mode to avoid wasted translation calls.
          if (translationFeatureEnabled && layoutMode == LayoutMode.vertical)
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze lib/presentation/reader/`
Expected: No issues found!

- [ ] **Step 4: 提交**

```bash
git add lib/presentation/reader/widgets/reader_controls.dart
git commit -m "feat(reader): 总开关关闭时隐藏顶栏翻译按钮"
```

---

### Task 10: 全量验证与手工冒烟

**Files:** 无代码改动

- [ ] **Step 1: 静态检查全仓**

Run: `flutter analyze`
Expected: No issues found!（若有既存告警，确认与本次改动文件无关）

- [ ] **Step 2: 跑相关单测**

Run: `flutter test test/data/local/ test/data/translation/ test/presentation/reader/`
Expected: All tests passed

> 不要跑全仓 `flutter test`：`test/verify_*.dart` / `test/check_jmc_chapters.dart` 是手工联网脚本，`test/widget_test.dart` 既有失败（见 AGENTS.md）。

- [ ] **Step 3: 手工验证（8 步，需真机/模拟器 + 日语生肉漫画）**

Run: `flutter run -d macos`（或 Android 设备）

1. 全新安装（或删掉 app documents 下的 `settings.json`）→ 设置页出现「漫画翻译」section，subtitle 显示「未启用」。
2. 打开任意漫画竖向滚动阅读，点屏幕中央唤出控制层 → 顶栏**没有** translate 图标。
3. 设置 → 漫画翻译 → 打开「启用漫画翻译」→ 返回并重新进入章节 → translate 图标出现。
4. 二级页「模型状态」显示「未下载（约 460MB）」+「下载」按钮；点下载 → 百分比与进度条走动 → 按返回键被拦住并弹「模型下载中，请等待完成」。
5. 下载中断网 → SnackBar「下载失败：…」、状态回落「未下载」、按钮变「重试下载」→ 恢复网络点重试 → **百分比从中断处继续，不回零**。
6. 下完 → 「已就绪」+绿色对勾；配好 AI Key（AI 设置 subtitle 变「已配置」）→ 回阅读器点 translate → 气泡上出现中文。
7. 关掉总开关 → 重新进入阅读器，translate 按钮消失；再打开 → 模型仍「已就绪」，之前翻译过的页仍直接命中缓存（无 loading 角标）。
8. 点「清空翻译缓存」→ 确认对话框 → 确认后重进已翻译过的页 → loading 角标再次出现（重新调用 AI）。

- [ ] **Step 4: 刷新知识图谱**

Run: `graphify update .`
Expected: 更新完成，无报错

- [ ] **Step 5: 提交（若 graphify 产物入库则一并提交）**

```bash
git status --short
git commit -am "chore: refresh graphify after translation toggle" || true
```

---

## 自审记录

- **Spec 覆盖**：第1节数据层 → Task 1/2；第2节设置UI → Task 6/7（含 `clearAll` = Task 3）；第3节 Reader gate 3.1-3.3 → Task 8/9，3.4/3.5 是「不做」决策无需任务；第4节 4.1 进度归属+续传 → Task 4/5/6（`PopScope`），4.2 三类失败 → Task 6 的 `_download` catch + `_refreshModelStatus` catch，4.3 → Task 3 + Task 6 的 `_clearCache`，4.4/4.5 是「不做」决策；第5节测试 → Task 1/3/4/8 的测试步骤 + Task 10。
- **命名一致性**：`mangaTranslationEnabled`（AppSettings/JSON key/cubit setter）、`translationFeatureEnabled`（ReaderState/`_TopBar` 参数）、`translationEnabled`（ReaderState 既有的本章状态，未改名）、`clearAll`、`decideResume`/`ResumeAction`/`ResumeDecision` 全文一致。
- **依赖顺序**：Task 1 必须先于 Task 8（测试用到 `AppSettings.mangaTranslationEnabled`）；Task 4 必须先于 Task 5；Task 6 必须先于 Task 7（import）；Task 8 必须先于 Task 9（`state.translationFeatureEnabled`）。
