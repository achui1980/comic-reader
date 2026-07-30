# 清理债务 (ROADMAP #25) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复3处吞异常的空 catch 块（补充调试日志）、从 pubspec.yaml 移除零使用的 injectable/build_runner/injectable_generator 依赖、在 ROADMAP.md 中记录 cached_network_image 与 extended_image 的评估结论（维持现状不合并）。

**Architecture:** 三个互相独立的小任务，各自单独 commit。不涉及任何结构性重构，风险极低。

**Tech Stack:** Flutter/Dart, pubspec.yaml, debugPrint（项目现有的事实标准日志方式，88处已在使用；package:logging 已引入但没有挂 root listener，实际不输出内容，因此本次不采用它）。

---

### Task 1: `webview_fetcher_native.dart` 空 catch 加日志

**Files:**
- Modify: `lib/data/remote/webview_fetcher_native.dart:472-474`

- [ ] **Step 1: 确认现状**

Run: `grep -n "catch (_) {}" lib/data/remote/webview_fetcher_native.dart`
Expected: 输出包含第474行 `      } catch (_) {}`

- [ ] **Step 2: 修改代码**

原代码（472-474行）：
```dart
      try {
        await headless.dispose();
      } catch (_) {}
```

改为：
```dart
      try {
        await headless.dispose();
      } catch (e) {
        debugPrint('[WebViewFetcher] Failed to dispose headless webview: $e');
      }
```

若文件顶部尚未 import `package:flutter/foundation.dart`（`debugPrint` 所在包），检查：
Run: `grep -n "import 'package:flutter/foundation.dart'" lib/data/remote/webview_fetcher_native.dart`
若无输出，在文件顶部 import 区添加：
```dart
import 'package:flutter/foundation.dart' show debugPrint;
```

- [ ] **Step 3: 静态分析验证**

Run: `flutter analyze lib/data/remote/webview_fetcher_native.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/data/remote/webview_fetcher_native.dart
git commit -m "fix: log headless webview dispose failures instead of silently swallowing"
```

---

### Task 2: `local_storage.dart` 空 catch 加日志

**Files:**
- Modify: `lib/data/local/local_storage.dart:12-19`

- [ ] **Step 1: 确认现状**

Run: `grep -n "catch (_) {}" lib/data/local/local_storage.dart`
Expected: 输出包含第18行 `    } catch (_) {}`

- [ ] **Step 2: 修改代码**

原代码（12-19行）：
```dart
  Future<Map<String, dynamic>?> read(String name) async {
    try {
      final content = await _backend.readString(name);
      if (content != null) {
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
```

改为：
```dart
  Future<Map<String, dynamic>?> read(String name) async {
    try {
      final content = await _backend.readString(name);
      if (content != null) {
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[LocalStorage] Failed to read "$name": $e');
    }
    return null;
  }
```

在文件顶部 import 区添加（若无）：
```dart
import 'package:flutter/foundation.dart' show debugPrint;
```

- [ ] **Step 3: 静态分析验证**

Run: `flutter analyze lib/data/local/local_storage.dart`
Expected: `No issues found!`

- [ ] **Step 4: 运行相关测试确认无回归**

Run: `flutter test --plain-name "LocalStorage"`（若不存在专属测试文件，运行依赖它的 store 测试，例如 `flutter test test/data/local/`）
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/local/local_storage.dart
git commit -m "fix: log local storage read failures instead of silently swallowing"
```

---

### Task 3: `backup_service.dart` 空 catch 加日志

**Files:**
- Modify: `lib/data/local/backup_service.dart:58-61`

- [ ] **Step 1: 确认现状**

Run: `grep -n "catch (_) {}" lib/data/local/backup_service.dart`
Expected: 输出包含第61行 `    } catch (_) {}`

- [ ] **Step 2: 修改代码**

原代码（58-61行）：
```dart
    // Clean up temp file after sharing
    try {
      await file.delete();
    } catch (_) {}
```

改为：
```dart
    // Clean up temp file after sharing
    try {
      await file.delete();
    } catch (e) {
      debugPrint('[BackupService] Failed to delete temp backup file: $e');
    }
```

在文件顶部 import 区添加（若无）：
```dart
import 'package:flutter/foundation.dart' show debugPrint;
```

注意：不要改动同文件第64-85行 `importData` 里的 `catch (_) { return false; }`——那一处不是空 catch（有明确的返回值处理），不在本任务范围内。

- [ ] **Step 3: 静态分析验证**

Run: `flutter analyze lib/data/local/backup_service.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/data/local/backup_service.dart
git commit -m "fix: log temp backup file cleanup failures instead of silently swallowing"
```

---

### Task 4: 移除未使用的 injectable/build_runner 依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 二次确认零使用（防止误删）**

Run: `grep -rn "@injectable\|@singleton\|@Injectable\|@Singleton\|package:injectable" lib/`
Expected: 无输出（空）

Run: `find lib -name "*.g.dart" -o -name "*.config.dart"`
Expected: 无输出（空）

- [ ] **Step 2: 编辑 pubspec.yaml**

在 `dependencies:` 部分删除这一行：
```yaml
  injectable: ^2.3.5
```

在 `dev_dependencies:` 部分删除这两行：
```yaml
  build_runner: ^2.4.8
  injectable_generator: ^2.4.2
```

保留 `get_it: ^7.6.7`（仍在大量使用，不删除）。

- [ ] **Step 3: 更新依赖锁文件**

Run: `flutter pub get`
Expected: 成功执行，`pubspec.lock` 中不再包含 `injectable`/`build_runner`/`injectable_generator` 及其专属传递依赖

- [ ] **Step 4: 全量静态分析确认无引用报错**

Run: `flutter analyze`
Expected: `No issues found!`（若之前已有历史遗留 warning，确认新增数量为 0，不是因为本次改动引入）

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: remove unused injectable/build_runner/injectable_generator dependencies"
```

---

### Task 5: 文档记录图片库评估结论（不合并代码）

**Files:**
- Modify: `ROADMAP.md`（找到 #25 对应条目所在行）

- [ ] **Step 1: 定位 ROADMAP.md 中 #25 的图片库合并条目**

Run: `grep -n "cached_network_image\|extended_image" ROADMAP.md`

- [ ] **Step 2: 在该条目后追加评估结论**

在原条目文字后面追加一行（保持原有 `- [ ]` 复选框列表格式，具体缩进跟随文件已有风格）：
```markdown
  - 已评估（2026-07-29）：`cached_network_image`（封面缩略图，唯一用点 `lib/presentation/common/manga_cover_image.dart`，核心是磁盘缓存+placeholder/imageBuilder/errorWidget 三段式声明）与 `extended_image`（阅读器大图，5个用点，核心是手势缩放 `ExtendedImageMode.gesture` + 本地文件/内存字节渲染 `ExtendedImage.file/.memory`）职责正交，无法合并为同一个库而不产生返工/体验回退。结论：维持现状，不合并。
```

- [ ] **Step 3: Commit**

```bash
git add ROADMAP.md
git commit -m "docs: record image library merge evaluation for #25 (keep as-is)"
```
