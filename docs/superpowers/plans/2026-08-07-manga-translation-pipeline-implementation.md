# Manga Translation Pipeline (Backend-Only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the validated PoC (Manga-Bubble-YOLO bubble detection + manga-ocr Japanese OCR + BYOK LLM translation) out of `lib/data/translation/poc/` into a production `lib/data/translation/` module: on-device text extraction, whole-page LLM translation via the existing `AiClient`, and persistent per-page caching — with no reader UI integration yet (that is a separate future plan).

**Architecture:** `TranslationPipeline.translatePage()` orchestrates: check `TranslationCacheStore` → `TranslationModelManager.ensureReady()` → `MangaTextExtractor.extract()` (on-device ONNX: YOLO bubble boxes + manga-ocr greedy-decoded Japanese text) → one batched `AiClient.chat()` call translating all bubbles on the page to Chinese → `TranslationCacheStore.save()`. Model weights (~460MB) are downloaded to the app documents directory on first use instead of being bundled as Flutter assets. A debug screen at `/poc/translation` exercises the whole pipeline manually.

**Tech Stack:** Flutter/Dart, `flutter_onnxruntime` (on-device ONNX inference), `image` (pixel manipulation), `path_provider` (documents directory), `mocktail` (test doubles), existing `lib/core/ai/` BYOK client (`AiClient`/`AiConfig`/`AiConfigStore`).

## Global Constraints

- Package name is `comic_reader`; all `package:comic_reader/...` imports must match this.
- This plan targets **native platforms only** (macOS/iOS/Android). Web is explicitly out of scope (per spec decision #3); do not touch `tools/translation_service/`.
- Model weights (`*.onnx`, `vocab.txt`) are **never bundled as Flutter assets** and **never committed to git** — they are downloaded at runtime to `$appDocDir/models/translation/`. Do not add anything under `assets/models/` back to `pubspec.yaml`.
- No widget/integration tests for this plan (real ONNX inference needs real ~460MB weights + real images, which cannot run in CI). Every task's automated tests are pure-Dart unit tests that never load real model weights and never hit the network.
- Translation prompt/target language is fixed: Japanese/Korean → Simplified Chinese. Do not add language selection UI or logic.
- Do not modify `lib/core/ai/*.dart` — reuse `AiClient`/`AiConfig`/`AiConfigStore` exactly as they exist today.
- Every task ends with a git commit containing only the files listed in that task's Files section.

---

### Task 1: Data models — `TextRegion` and `PageTranslation`

**Files:**
- Create: `lib/data/translation/models/text_region.dart`
- Create: `lib/data/translation/models/page_translation.dart`
- Test: `test/data/translation/models/text_region_test.dart`
- Test: `test/data/translation/models/page_translation_test.dart`

**Interfaces:**
- Produces: `class TextRegion { final List<int> box; final String originalText; final String? translatedText; TextRegion copyWith({String? translatedText}); Map<String,dynamic> toJson(); factory TextRegion.fromJson(Map<String,dynamic>); }`
- Produces: `class PageTranslation { final String sourceId, mangaId, chapterId; final int pageIndex; final List<TextRegion> regions; final int translatedAt; Map<String,dynamic> toJson(); factory PageTranslation.fromJson(Map<String,dynamic>); }`

- [ ] **Step 1: Write the failing tests**

Create `test/data/translation/models/text_region_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/models/text_region.dart';

void main() {
  test('toJson/fromJson round-trip preserves all fields', () {
    const region = TextRegion(
      box: [10, 20, 100, 50],
      originalText: 'こんにちは',
      translatedText: '你好',
    );
    final decoded = TextRegion.fromJson(region.toJson());
    expect(decoded.box, [10, 20, 100, 50]);
    expect(decoded.originalText, 'こんにちは');
    expect(decoded.translatedText, '你好');
  });

  test('translatedText defaults to null when absent from JSON', () {
    final decoded = TextRegion.fromJson({
      'box': [0, 0, 1, 1],
      'originalText': 'x',
    });
    expect(decoded.translatedText, isNull);
  });

  test('copyWith sets translatedText without mutating the original', () {
    const region = TextRegion(box: [0, 0, 1, 1], originalText: 'x');
    final updated = region.copyWith(translatedText: 'y');
    expect(region.translatedText, isNull);
    expect(updated.translatedText, 'y');
    expect(updated.originalText, 'x');
    expect(updated.box, [0, 0, 1, 1]);
  });
}
```

Create `test/data/translation/models/page_translation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/models/page_translation.dart';
import 'package:comic_reader/data/translation/models/text_region.dart';

void main() {
  test('toJson/fromJson round-trip preserves all fields', () {
    final page = PageTranslation(
      sourceId: 'srcA',
      mangaId: 'mangaB',
      chapterId: 'chC',
      pageIndex: 3,
      regions: const [
        TextRegion(box: [1, 2, 3, 4], originalText: 'あ', translatedText: '啊'),
      ],
      translatedAt: 1700000000000,
    );
    final decoded = PageTranslation.fromJson(page.toJson());
    expect(decoded.sourceId, 'srcA');
    expect(decoded.mangaId, 'mangaB');
    expect(decoded.chapterId, 'chC');
    expect(decoded.pageIndex, 3);
    expect(decoded.translatedAt, 1700000000000);
    expect(decoded.regions.length, 1);
    expect(decoded.regions.first.originalText, 'あ');
    expect(decoded.regions.first.translatedText, '啊');
  });

  test('fromJson tolerates a missing regions list', () {
    final decoded = PageTranslation.fromJson({
      'sourceId': 's',
      'mangaId': 'm',
      'chapterId': 'c',
      'pageIndex': 0,
      'translatedAt': 0,
    });
    expect(decoded.regions, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/translation/models/text_region_test.dart test/data/translation/models/page_translation_test.dart`
Expected: FAIL — both files report `Error when reading '...text_region.dart'/'...page_translation.dart': No such file or directory` (the source modules don't exist yet).

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/translation/models/text_region.dart`:

```dart
/// A single detected (and optionally translated) text region on a manga
/// page. [box] is `[x, y, w, h]` in original-image pixel coordinates.
/// [translatedText] is null until [TranslationPipeline] fills it in.
class TextRegion {
  const TextRegion({
    required this.box,
    required this.originalText,
    this.translatedText,
  });

  final List<int> box;
  final String originalText;
  final String? translatedText;

  TextRegion copyWith({String? translatedText}) => TextRegion(
        box: box,
        originalText: originalText,
        translatedText: translatedText,
      );

  Map<String, dynamic> toJson() => {
        'box': box,
        'originalText': originalText,
        'translatedText': translatedText,
      };

  factory TextRegion.fromJson(Map<String, dynamic> json) {
    final rawBox = json['box'] as List? ?? const [];
    return TextRegion(
      box: rawBox.map((e) => (e as num).toInt()).toList(),
      originalText: json['originalText'] as String? ?? '',
      translatedText: json['translatedText'] as String?,
    );
  }
}
```

Create `lib/data/translation/models/page_translation.dart`:

```dart
import 'text_region.dart';

/// Translation result for one manga page, persisted by
/// [TranslationCacheStore] and looked up before re-running the pipeline.
class PageTranslation {
  const PageTranslation({
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    required this.pageIndex,
    required this.regions,
    required this.translatedAt,
  });

  final String sourceId;
  final String mangaId;
  final String chapterId;
  final int pageIndex;
  final List<TextRegion> regions;

  /// Epoch milliseconds when this translation was produced.
  final int translatedAt;

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'mangaId': mangaId,
        'chapterId': chapterId,
        'pageIndex': pageIndex,
        'regions': regions.map((r) => r.toJson()).toList(),
        'translatedAt': translatedAt,
      };

  factory PageTranslation.fromJson(Map<String, dynamic> json) {
    final rawRegions = json['regions'] as List? ?? const [];
    return PageTranslation(
      sourceId: json['sourceId'] as String? ?? '',
      mangaId: json['mangaId'] as String? ?? '',
      chapterId: json['chapterId'] as String? ?? '',
      pageIndex: json['pageIndex'] as int? ?? 0,
      regions: rawRegions
          .map((e) => TextRegion.fromJson(e as Map<String, dynamic>))
          .toList(),
      translatedAt: json['translatedAt'] as int? ?? 0,
    );
  }
}
```

Note: `copyWith` here intentionally *replaces* `translatedText` with whatever is passed (including `null`), rather than falling back to `this.translatedText` via `??`. This matches the only real call site (Task 8), which always calls it exactly once per freshly-extracted region.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/translation/models/text_region_test.dart test/data/translation/models/page_translation_test.dart`
Expected: PASS — `+5: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/translation/models/text_region.dart lib/data/translation/models/page_translation.dart test/data/translation/models/text_region_test.dart test/data/translation/models/page_translation_test.dart
git commit -m "feat: 新增 TextRegion/PageTranslation 数据模型"
```

---

### Task 2: `yolo_detections.dart` — bubble-box parsing (migrated from PoC)

**Files:**
- Create: `lib/data/translation/yolo_detections.dart`
- Test: `test/data/translation/yolo_detections_test.dart`

**Interfaces:**
- Produces: `List<List<int>> parseYoloDetections(List<double> output, double threshold, double scaleX, double scaleY)`

- [ ] **Step 1: Write the failing test**

Create `test/data/translation/yolo_detections_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/yolo_detections.dart';

void main() {
  group('parseYoloDetections', () {
    test('按 conf 阈值过滤并把 xyxy 映射回原图 xywh', () {
      // 两行：第一行 conf=0.9 保留，第二行 conf=0.1 过滤。
      // scaleX=scaleY=2：x1=100->ox=200, ow=(300-100)*2=400 等。
      final out = <double>[
        100, 200, 300, 500, 0.9, 0,
        10, 10, 20, 20, 0.1, 0,
      ];
      final boxes = parseYoloDetections(out, 0.3, 2.0, 2.0);
      expect(boxes.length, 1);
      expect(boxes.first, [200, 400, 400, 600]);
    });

    test('全部低于阈值返回空', () {
      final out = <double>[0, 0, 10, 10, 0.2, 0];
      expect(parseYoloDetections(out, 0.3, 1.0, 1.0), isEmpty);
    });

    test('多行时保留每一行满足阈值的框', () {
      final out = <double>[
        0, 0, 10, 10, 0.5, 0,
        20, 20, 30, 30, 0.6, 0,
      ];
      final boxes = parseYoloDetections(out, 0.4, 1.0, 1.0);
      expect(boxes.length, 2);
      expect(boxes[0], [0, 0, 10, 10]);
      expect(boxes[1], [20, 20, 10, 10]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/translation/yolo_detections_test.dart`
Expected: FAIL with `Error when reading '...yolo_detections.dart': No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/translation/yolo_detections.dart`:

```dart
/// Parses Manga-Bubble-YOLO's `output0` tensor: flattened `[1, 300, 6]`,
/// each row `[x1, y1, x2, y2, conf, cls]` in xyxy corner coordinates
/// relative to the 1280x1280 input space (NMS-free model). Rows with
/// `conf < threshold` are dropped; surviving boxes are mapped back to
/// original-image coordinates via [scaleX]/[scaleY] and converted from
/// xyxy to xywh. Returns `[x, y, w, h]` boxes in original-image pixels.
List<List<int>> parseYoloDetections(
    List<double> output, double threshold, double scaleX, double scaleY) {
  final boxes = <List<int>>[];
  final rows = output.length ~/ 6;
  for (var i = 0; i < rows; i++) {
    final base = i * 6;
    final conf = output[base + 4];
    if (conf < threshold) continue;
    final x1 = output[base], y1 = output[base + 1];
    final x2 = output[base + 2], y2 = output[base + 3];
    final ox = (x1 * scaleX).round();
    final oy = (y1 * scaleY).round();
    final ow = ((x2 - x1) * scaleX).round();
    final oh = ((y2 - y1) * scaleY).round();
    boxes.add([ox, oy, ow, oh]);
  }
  return boxes;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/translation/yolo_detections_test.dart`
Expected: PASS — `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/translation/yolo_detections.dart test/data/translation/yolo_detections_test.dart
git commit -m "feat: 新增 yolo_detections.dart（从 PoC 迁移）"
```

---

### Task 3: `ocr_decoder.dart` — greedy-decode primitives (migrated from PoC)

**Files:**
- Create: `lib/data/translation/ocr_decoder.dart`
- Test: `test/data/translation/ocr_decoder_test.dart`

**Interfaces:**
- Produces: constants `kOcrStartToken=2`, `kOcrEosToken=3`, `kOcrSpecialTokenThreshold=5`, `kOcrMaxSteps=300`, `kOcrVocabSize=6144`
- Produces: `int argmaxLastRow(List<double> logitsFlat, int vocabSize)`
- Produces: `String decodeTokens(List<int> tokenIds, List<String> vocab)`

- [ ] **Step 1: Write the failing test**

Create `test/data/translation/ocr_decoder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/ocr_decoder.dart';

void main() {
  group('argmaxLastRow', () {
    test('返回最大值下标', () {
      final logits = [0.1, 0.9, 0.3, 0.2];
      expect(argmaxLastRow(logits, 4), 1);
    });
    test('平局取第一个', () {
      final logits = [0.5, 0.5, 0.1];
      expect(argmaxLastRow(logits, 3), 0);
    });
  });

  group('decodeTokens', () {
    final vocab = List<String>.generate(10, (i) => 'T$i');
    test('跳过 <5 的特殊 token', () {
      expect(decodeTokens([2, 5, 6, 3], vocab), 'T5T6');
    });
    test('遇到 EOS(3) 停止', () {
      expect(decodeTokens([7, 3, 8], vocab), 'T7');
    });
    test('空序列返回空串', () {
      expect(decodeTokens([], vocab), '');
    });
  });

  test('常量值正确', () {
    expect(kOcrStartToken, 2);
    expect(kOcrEosToken, 3);
    expect(kOcrSpecialTokenThreshold, 5);
    expect(kOcrMaxSteps, 300);
    expect(kOcrVocabSize, 6144);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/translation/ocr_decoder_test.dart`
Expected: FAIL with `Error when reading '...ocr_decoder.dart': No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/translation/ocr_decoder.dart`:

```dart
/// manga-ocr 贪婪解码相关常量与纯函数。
const int kOcrStartToken = 2;
const int kOcrEosToken = 3;
const int kOcrSpecialTokenThreshold = 5;
const int kOcrMaxSteps = 300;
const int kOcrVocabSize = 6144;

/// 在一行 logits（长度 vocabSize）里取 argmax token id。平局取第一个。
int argmaxLastRow(List<double> logitsFlat, int vocabSize) {
  var best = 0;
  var bestVal = logitsFlat[0];
  for (var i = 1; i < vocabSize; i++) {
    if (logitsFlat[i] > bestVal) {
      bestVal = logitsFlat[i];
      best = i;
    }
  }
  return best;
}

/// 把 token id 序列转成字符串：遇到 EOS(3) 停止，<5 的特殊 token 跳过，
/// 其余查 vocab 拼接。
String decodeTokens(List<int> tokenIds, List<String> vocab) {
  final buffer = StringBuffer();
  for (final id in tokenIds) {
    if (id == kOcrEosToken) break;
    if (id < kOcrSpecialTokenThreshold) continue;
    if (id < vocab.length) buffer.write(vocab[id]);
  }
  return buffer.toString();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/translation/ocr_decoder_test.dart`
Expected: PASS — `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/translation/ocr_decoder.dart test/data/translation/ocr_decoder_test.dart
git commit -m "feat: 新增 ocr_decoder.dart（从 PoC 迁移）"
```

---

### Task 4: `ocr_preprocess.dart` — OCR tensor preprocessing (migrated from PoC, replaces old test)

**Files:**
- Create: `lib/data/translation/ocr_preprocess.dart`
- Modify: `test/data/translation/ocr_preprocess_test.dart` (currently tests `lib/data/translation/poc/ocr_preprocess.dart`; this task repoints it at the new module)

**Interfaces:**
- Produces: `const int kOcrInputSize = 224;`
- Produces: `Float32List imageToOcrTensor(List<int> rgbPixels, int width, int height)`

- [ ] **Step 1: Modify the test to point at the new (not-yet-existing) module**

Replace the entire contents of `test/data/translation/ocr_preprocess_test.dart` with:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/ocr_preprocess.dart';

void main() {
  test('kOcrInputSize 为 224', () {
    expect(kOcrInputSize, 224);
  });

  test('输出长度为 3*H*W 且 CHW 归一化正确', () {
    // 2x1 图（宽2高1），像素: (255,0,0) (0,255,0)
    final rgb = [255, 0, 0, 0, 255, 0];
    final t = imageToOcrTensor(rgb, 2, 1);
    expect(t.length, 3 * 1 * 2);
    // R 平面: 255->(1-0.5)/0.5=1.0 ; 0->-1.0
    expect(t[0], closeTo(1.0, 1e-6));
    expect(t[1], closeTo(-1.0, 1e-6));
    // G 平面(偏移 H*W=2): 0->-1.0 ; 255->1.0
    expect(t[2], closeTo(-1.0, 1e-6));
    expect(t[3], closeTo(1.0, 1e-6));
    // B 平面(偏移 2*H*W=4): 都是 0->-1.0
    expect(t[4], closeTo(-1.0, 1e-6));
    expect(t[5], closeTo(-1.0, 1e-6));
  });
}
```

(Only the import path changed from `package:comic_reader/data/translation/poc/ocr_preprocess.dart` to `package:comic_reader/data/translation/ocr_preprocess.dart`; the test bodies are otherwise identical since the algorithm is unchanged.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/translation/ocr_preprocess_test.dart`
Expected: FAIL with `Error when reading '...lib/data/translation/ocr_preprocess.dart': No such file or directory` (the new module doesn't exist yet; the old `lib/data/translation/poc/ocr_preprocess.dart` is untouched but no longer referenced by this test).

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/translation/ocr_preprocess.dart`:

```dart
import 'dart:typed_data';

const int kOcrInputSize = 224;

/// 把 RGB 交错像素（R,G,B,R,G,B...）转成 CHW 排列、归一化的张量。
/// 归一化: (v/255 - 0.5) / 0.5。通道顺序 R 平面 -> G 平面 -> B 平面。
Float32List imageToOcrTensor(List<int> rgbPixels, int width, int height) {
  final plane = width * height;
  final out = Float32List(3 * plane);
  for (var i = 0; i < plane; i++) {
    final r = rgbPixels[i * 3];
    final g = rgbPixels[i * 3 + 1];
    final b = rgbPixels[i * 3 + 2];
    out[i] = (r / 255.0 - 0.5) / 0.5;
    out[plane + i] = (g / 255.0 - 0.5) / 0.5;
    out[2 * plane + i] = (b / 255.0 - 0.5) / 0.5;
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/translation/ocr_preprocess_test.dart`
Expected: PASS — `+2: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/translation/ocr_preprocess.dart test/data/translation/ocr_preprocess_test.dart
git commit -m "feat: 新增 ocr_preprocess.dart（从 PoC 迁移，改测试指向新模块）"
```

---

### Task 5: `translation_model_manager.dart` — model file catalog + download manager

**Files:**
- Create: `lib/data/translation/translation_model_manager.dart`
- Test: `test/data/translation/translation_model_manager_test.dart`

**Interfaces:**
- Consumes: none (new leaf module; only depends on `path_provider` and `dart:io`)
- Produces: `class ModelFileSpec { final String relativePath, url, sha256; final int sizeBytes; }`
- Produces: `const List<ModelFileSpec> kTranslationModelFiles;` (4 entries)
- Produces: `class ModelNotReadyException implements Exception { final List<String> missing; }`
- Produces: `class TranslationModelManager { TranslationModelManager({List<ModelFileSpec>? files, Future<String> Function()? baseDirResolver}); Future<String> modelsDir(); Future<String> pathFor(String relativePath); Future<bool> isReady(); Future<void> ensureReady(); Future<void> downloadAll({void Function(String file, int received, int total)? onProgress}); }`

- [ ] **Step 1: Write the failing test**

Create `test/data/translation/translation_model_manager_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/translation_model_manager.dart';

void main() {
  group('kTranslationModelFiles', () {
    test('lists exactly the 4 required model files', () {
      final paths =
          kTranslationModelFiles.map((f) => f.relativePath).toList();
      expect(paths, [
        'comic-bubble-yolo.onnx',
        'manga-ocr/encoder_model.onnx',
        'manga-ocr/decoder_model.onnx',
        'manga-ocr/vocab.txt',
      ]);
    });

    test('every spec has a positive size, sha256 and https url', () {
      for (final spec in kTranslationModelFiles) {
        expect(spec.sizeBytes, greaterThan(0));
        expect(spec.sha256, isNotEmpty);
        expect(spec.url, startsWith('https://'));
      }
    });
  });

  group('TranslationModelManager with small fake specs in a temp dir', () {
    late Directory tempDir;
    late TranslationModelManager manager;
    const specs = [
      ModelFileSpec(
        relativePath: 'a.onnx',
        url: 'https://example.com/a.onnx',
        sha256: 'x',
        sizeBytes: 4,
      ),
      ModelFileSpec(
        relativePath: 'sub/b.onnx',
        url: 'https://example.com/b.onnx',
        sha256: 'y',
        sizeBytes: 8,
      ),
    ];

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('translation_model_test_');
      manager = TranslationModelManager(
        files: specs,
        baseDirResolver: () async => tempDir.path,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('modelsDir points under baseDir/models/translation', () async {
      final dir = await manager.modelsDir();
      expect(dir, '${tempDir.path}/models/translation');
    });

    test('pathFor joins modelsDir with the relative path', () async {
      final path = await manager.pathFor('a.onnx');
      expect(path, '${tempDir.path}/models/translation/a.onnx');
    });

    test('isReady is false when no files exist', () async {
      expect(await manager.isReady(), isFalse);
    });

    test('ensureReady throws ModelNotReadyException listing all missing files',
        () async {
      await expectLater(
        manager.ensureReady(),
        throwsA(isA<ModelNotReadyException>()
            .having((e) => e.missing, 'missing', ['a.onnx', 'sub/b.onnx'])),
      );
    });

    test('isReady is true once every file exists with the right size',
        () async {
      for (final spec in specs) {
        final path = await manager.pathFor(spec.relativePath);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(List<int>.filled(spec.sizeBytes, 0));
      }
      expect(await manager.isReady(), isTrue);
      await manager.ensureReady(); // should not throw
    });

    test('isReady is false when a file exists with the wrong size',
        () async {
      for (final spec in specs) {
        final path = await manager.pathFor(spec.relativePath);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(List<int>.filled(spec.sizeBytes + 1, 0));
      }
      expect(await manager.isReady(), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/translation/translation_model_manager_test.dart`
Expected: FAIL with `Error when reading '...translation_model_manager.dart': No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/translation/translation_model_manager.dart`:

```dart
import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';

/// Describes one downloadable model asset used by the translation pipeline.
class ModelFileSpec {
  const ModelFileSpec({
    required this.relativePath,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  /// Path relative to the models directory, e.g. `comic-bubble-yolo.onnx`
  /// or `manga-ocr/encoder_model.onnx`.
  final String relativePath;
  final String url;
  final String sha256;
  final int sizeBytes;
}

/// The four model files required by `NativeMangaTextExtractor`.
const List<ModelFileSpec> kTranslationModelFiles = [
  ModelFileSpec(
    relativePath: 'comic-bubble-yolo.onnx',
    url:
        'https://huggingface.co/Kiuyha/Manga-Bubble-YOLO/resolve/main/onnx/yolo26n.onnx',
    sha256:
        'b45c2e12cf0c3c1d2abfbbb9123c9f96f040f2ac36a0842382ecd9d859c851c7',
    sizeBytes: 6069760,
  ),
  ModelFileSpec(
    relativePath: 'manga-ocr/encoder_model.onnx',
    url:
        'https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/encoder_model.onnx',
    sha256:
        '15fa8155fe9bc1a7d25d9bb353debaa4def033d0174e907dbd2dd6d995def85f',
    sizeBytes: 343454249,
  ),
  ModelFileSpec(
    relativePath: 'manga-ocr/decoder_model.onnx',
    url:
        'https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/decoder_model.onnx',
    sha256:
        'ef7765261e9d1cdc34d89356986c2bbc2a082897f753a89605ae80fdfa61f5e8',
    sizeBytes: 117480262,
  ),
  ModelFileSpec(
    relativePath: 'manga-ocr/vocab.txt',
    url:
        'https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/vocab.txt',
    sha256:
        '5cb5c5586d98a2f331d9f8828e4586479b0611bfba5d8c3b6dadffc84d6a36a3',
    sizeBytes: 30216,
  ),
];

/// Thrown by [TranslationModelManager.ensureReady] when one or more model
/// files are missing (or have the wrong size) in local storage.
class ModelNotReadyException implements Exception {
  ModelNotReadyException(this.missing);
  final List<String> missing;
  @override
  String toString() => 'ModelNotReadyException: missing ${missing.join(", ")}';
}

/// Downloads and verifies the ONNX model files used for on-device manga
/// translation, storing them under the app's documents directory (not
/// bundled as assets — they total ~460MB).
class TranslationModelManager {
  TranslationModelManager({
    List<ModelFileSpec>? files,
    Future<String> Function()? baseDirResolver,
  })  : _files = files ?? kTranslationModelFiles,
        _baseDirResolver = baseDirResolver ?? _defaultBaseDir;

  final List<ModelFileSpec> _files;
  final Future<String> Function() _baseDirResolver;

  static Future<String> _defaultBaseDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> modelsDir() async {
    final base = await _baseDirResolver();
    return '$base/models/translation';
  }

  Future<String> pathFor(String relativePath) async {
    final dir = await modelsDir();
    return '$dir/$relativePath';
  }

  /// Checks whether every model file exists and has the expected size.
  Future<bool> isReady() async {
    for (final spec in _files) {
      final path = await pathFor(spec.relativePath);
      final file = io.File(path);
      if (!await file.exists()) return false;
      if (await file.length() != spec.sizeBytes) return false;
    }
    return true;
  }

  /// Throws [ModelNotReadyException] listing every missing/invalid file.
  Future<void> ensureReady() async {
    final missing = <String>[];
    for (final spec in _files) {
      final path = await pathFor(spec.relativePath);
      final file = io.File(path);
      final ok = await file.exists() && await file.length() == spec.sizeBytes;
      if (!ok) missing.add(spec.relativePath);
    }
    if (missing.isNotEmpty) throw ModelNotReadyException(missing);
  }

  /// Downloads every model file that is missing or has the wrong size,
  /// streaming to disk. [onProgress] reports `(relativePath, receivedBytes,
  /// totalBytes)` for each file as it downloads (and once immediately, with
  /// received==total, for files that are already present).
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
      final client = io.HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(spec.url));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw StateError(
              '下载失败 ${spec.relativePath}: HTTP ${response.statusCode}');
        }
        final sink = file.openWrite();
        var received = 0;
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(spec.relativePath, received, spec.sizeBytes);
          }
        } finally {
          await sink.close();
        }
      } catch (e) {
        if (await file.exists()) await file.delete();
        rethrow;
      } finally {
        client.close(force: true);
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/translation/translation_model_manager_test.dart`
Expected: PASS — `+7: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/translation/translation_model_manager.dart test/data/translation/translation_model_manager_test.dart
git commit -m "feat: 新增 TranslationModelManager（模型下载/校验/路径管理）"
```

---

### Task 6: `translation_cache_store.dart` — per-page persistent cache

**Files:**
- Create: `lib/data/translation/translation_cache_store.dart`
- Test: `test/data/translation/translation_cache_store_test.dart`

**Interfaces:**
- Consumes: `PageTranslation` and `TextRegion` from Task 1 (`toJson`/`fromJson`)
- Produces: `class TranslationCacheStore { TranslationCacheStore({Future<String> Function()? baseDirResolver}); Future<PageTranslation?> get(String sourceId, String mangaId, String chapterId, int pageIndex); Future<void> save(PageTranslation translation); Future<void> clearChapter(String sourceId, String mangaId, String chapterId); }`

- [ ] **Step 1: Write the failing test**

Create `test/data/translation/translation_cache_store_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/translation_cache_store.dart';
import 'package:comic_reader/data/translation/models/page_translation.dart';
import 'package:comic_reader/data/translation/models/text_region.dart';

void main() {
  late Directory tempDir;
  late TranslationCacheStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('translation_cache_test_');
    store = TranslationCacheStore(baseDirResolver: () async => tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('get returns null when nothing cached', () async {
    expect(await store.get('src', 'manga', 'ch1', 0), isNull);
  });

  test('save then get round-trips the same data', () async {
    final page = PageTranslation(
      sourceId: 'src',
      mangaId: 'manga',
      chapterId: 'ch1',
      pageIndex: 2,
      regions: const [
        TextRegion(box: [1, 2, 3, 4], originalText: 'あ', translatedText: '啊'),
      ],
      translatedAt: 123,
    );
    await store.save(page);
    final loaded = await store.get('src', 'manga', 'ch1', 2);
    expect(loaded, isNotNull);
    expect(loaded!.regions.single.originalText, 'あ');
    expect(loaded.regions.single.translatedText, '啊');
    expect(loaded.pageIndex, 2);
  });

  test('save writes one file per page under sourceId/mangaId/chapterId',
      () async {
    final page = PageTranslation(
      sourceId: 'src',
      mangaId: 'manga',
      chapterId: 'ch1',
      pageIndex: 5,
      regions: const [],
      translatedAt: 1,
    );
    await store.save(page);
    final file =
        File('${tempDir.path}/translation_cache/src/manga/ch1/5.json');
    expect(await file.exists(), isTrue);
  });

  test('clearChapter deletes all cached pages for that chapter',
      () async {
    final page = PageTranslation(
      sourceId: 'src',
      mangaId: 'manga',
      chapterId: 'ch1',
      pageIndex: 0,
      regions: const [],
      translatedAt: 1,
    );
    await store.save(page);
    expect(await store.get('src', 'manga', 'ch1', 0), isNotNull);
    await store.clearChapter('src', 'manga', 'ch1');
    expect(await store.get('src', 'manga', 'ch1', 0), isNull);
  });

  test('get returns null when the cached file has invalid JSON',
      () async {
    final dir = Directory('${tempDir.path}/translation_cache/src/manga/ch1');
    await dir.create(recursive: true);
    await File('${dir.path}/9.json').writeAsString('not json');
    expect(await store.get('src', 'manga', 'ch1', 9), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/translation/translation_cache_store_test.dart`
Expected: FAIL with `Error when reading '...translation_cache_store.dart': No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/translation/translation_cache_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'models/page_translation.dart';

/// Persists [PageTranslation] results as one JSON file per page, mirroring
/// the on-disk layout of `ChapterCacheService`. Native-only: every method
/// is a no-op / returns null on web.
class TranslationCacheStore {
  TranslationCacheStore({Future<String> Function()? baseDirResolver})
      : _baseDirResolver = baseDirResolver ?? _defaultBaseDir;

  final Future<String> Function() _baseDirResolver;
  String? _basePath;

  static Future<String> _defaultBaseDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> get _cachePath async {
    if (_basePath != null) return _basePath!;
    if (kIsWeb) {
      _basePath = '';
      return '';
    }
    final base = await _baseDirResolver();
    _basePath = '$base/translation_cache';
    return _basePath!;
  }

  String _safe(String id) => id.replaceAll(RegExp(r'[^\w\-.]'), '_');

  Future<String> _pagePath(
      String sourceId, String mangaId, String chapterId, int pageIndex) async {
    final base = await _cachePath;
    final dir =
        '$base/${_safe(sourceId)}/${_safe(mangaId)}/${_safe(chapterId)}';
    return '$dir/$pageIndex.json';
  }

  Future<PageTranslation?> get(
      String sourceId, String mangaId, String chapterId, int pageIndex) async {
    if (kIsWeb) return null;
    final path = await _pagePath(sourceId, mangaId, chapterId, pageIndex);
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return PageTranslation.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PageTranslation translation) async {
    if (kIsWeb) return;
    final path = await _pagePath(translation.sourceId, translation.mangaId,
        translation.chapterId, translation.pageIndex);
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(translation.toJson()));
  }

  Future<void> clearChapter(
      String sourceId, String mangaId, String chapterId) async {
    if (kIsWeb) return;
    final base = await _cachePath;
    final dir = Directory(
        '$base/${_safe(sourceId)}/${_safe(mangaId)}/${_safe(chapterId)}');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/translation/translation_cache_store_test.dart`
Expected: PASS — `+5: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/translation/translation_cache_store.dart test/data/translation/translation_cache_store_test.dart
git commit -m "feat: 新增 TranslationCacheStore（per-page 持久化缓存）"
```

---

### Task 7: `manga_text_extractor.dart` — abstract extractor + on-device implementation

**Files:**
- Create: `lib/data/translation/manga_text_extractor.dart`
- Test: `test/data/translation/manga_text_extractor_test.dart`

**Interfaces:**
- Consumes: `TextRegion` (Task 1), `parseYoloDetections` (Task 2), `argmaxLastRow`/`decodeTokens`/`kOcr*` constants (Task 3), `imageToOcrTensor`/`kOcrInputSize` (Task 4), `TranslationModelManager.pathFor` (Task 5)
- Produces: `abstract class MangaTextExtractor { Future<void> loadModels(); Future<List<TextRegion>> extract(Uint8List imageBytes); }`
- Produces: `class NativeMangaTextExtractor implements MangaTextExtractor { NativeMangaTextExtractor({required OnnxRuntime runtime, required TranslationModelManager modelManager}); }`

- [ ] **Step 1: Write the failing test**

Create `test/data/translation/manga_text_extractor_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:comic_reader/data/translation/manga_text_extractor.dart';
import 'package:comic_reader/data/translation/translation_model_manager.dart';

void main() {
  test('extract() throws StateError before loadModels() is called', () async {
    final extractor = NativeMangaTextExtractor(
      runtime: OnnxRuntime(),
      modelManager: TranslationModelManager(
        baseDirResolver: () async => '/tmp/translation-extractor-test',
      ),
    );

    await expectLater(
      extractor.extract(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<StateError>()),
    );
  });
}
```

(This test never loads real model weights or runs real inference: `_detector`/`_ocrEncoder`/`_ocrDecoder` are `null` until `loadModels()` is called, and `extract()` throws `StateError` before touching `runtime` or the file system.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/translation/manga_text_extractor_test.dart`
Expected: FAIL with `Error when reading '...manga_text_extractor.dart': No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/translation/manga_text_extractor.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'models/text_region.dart';
import 'ocr_decoder.dart';
import 'ocr_preprocess.dart';
import 'translation_model_manager.dart';
import 'yolo_detections.dart';

/// Extracts text regions (bubble box + original-language text) from a
/// manga page image. Implementations do not translate — that is
/// `TranslationPipeline`'s job, via the app-wide BYOK `AiClient`.
abstract class MangaTextExtractor {
  Future<void> loadModels();
  Future<List<TextRegion>> extract(Uint8List imageBytes);
}

/// On-device implementation using Manga-Bubble-YOLO (bubble detection) +
/// manga-ocr (VisionEncoderDecoder Japanese OCR), both running through
/// flutter_onnxruntime. Model weights are downloaded to the app's
/// documents directory by [TranslationModelManager] (not bundled as
/// Flutter assets).
class NativeMangaTextExtractor implements MangaTextExtractor {
  NativeMangaTextExtractor({
    required this.runtime,
    required this.modelManager,
  });

  final OnnxRuntime runtime;
  final TranslationModelManager modelManager;

  OrtSession? _detector;
  OrtSession? _ocrEncoder;
  OrtSession? _ocrDecoder;
  List<String> _vocab = const [];

  @override
  Future<void> loadModels() async {
    final detectorPath = await modelManager.pathFor('comic-bubble-yolo.onnx');
    final encoderPath =
        await modelManager.pathFor('manga-ocr/encoder_model.onnx');
    final decoderPath =
        await modelManager.pathFor('manga-ocr/decoder_model.onnx');
    final vocabPath = await modelManager.pathFor('manga-ocr/vocab.txt');

    _detector = await runtime.createSession(detectorPath);
    _ocrEncoder = await runtime.createSession(encoderPath);
    _ocrDecoder = await runtime.createSession(decoderPath);

    final vocabRaw = await File(vocabPath).readAsString();
    _vocab = vocabRaw.split('\n').map((l) => l.replaceAll('\r', '')).toList();
  }

  @override
  Future<List<TextRegion>> extract(Uint8List imageBytes) async {
    final detector = _detector;
    final encoder = _ocrEncoder;
    final decoder = _ocrDecoder;
    if (detector == null || encoder == null || decoder == null) {
      throw StateError('模型未加载，请先调用 loadModels()');
    }
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw StateError('图片解码失败');

    // 1. detector: Manga-Bubble-YOLO，resize 到 1280，跑气泡检测。
    //    输出 output0[1,300,6]，每行 [x1,y1,x2,y2,conf,cls]（xyxy，相对 1280，免 NMS）。
    final detResized = img.copyResize(decoded, width: 1280, height: 1280);
    final detInput = _imageToChwFloat32(detResized, 1280, 1280);
    final detTensor = await OrtValue.fromList(detInput, [1, 3, 1280, 1280]);
    final detOut = await detector.run({detector.inputNames.first: detTensor});
    final yoloOut = (await detOut['output0']!.asList()).cast<double>();
    final scaleX = decoded.width / 1280.0;
    final scaleY = decoded.height / 1280.0;
    // parseYoloDetections 已把坐标映射回原图并转成 xywh。
    final boxes = parseYoloDetections(yoloOut, 0.3, scaleX, scaleY);

    // 2. 逐 box 裁剪 -> resize 224 -> manga-ocr 贪婪解码
    final regions = <TextRegion>[];
    for (final b in boxes) {
      final ox = b[0].clamp(0, decoded.width - 1);
      final oy = b[1].clamp(0, decoded.height - 1);
      final ow = b[2].clamp(1, decoded.width - ox);
      final oh = b[3].clamp(1, decoded.height - oy);
      final crop = img.copyCrop(decoded, x: ox, y: oy, width: ow, height: oh);
      final ocrResized =
          img.copyResize(crop, width: kOcrInputSize, height: kOcrInputSize);
      final rgb = _extractRgb(ocrResized);
      final ocrTensor = imageToOcrTensor(rgb, kOcrInputSize, kOcrInputSize);
      final text = await _runOcrGreedy(encoder, decoder, ocrTensor);
      regions.add(TextRegion(box: [ox, oy, ow, oh], originalText: text));
    }
    return regions;
  }

  /// manga-ocr 是 VisionEncoderDecoder 双文件模型：
  /// 先 encoder(pixel_values -> last_hidden_state[1,197,768])，
  /// 再 decoder 贪婪循环(input_ids + encoder_hidden_states -> logits[1,seq,6144])。
  Future<String> _runOcrGreedy(
      OrtSession encoder, OrtSession decoder, Float32List imageTensor) async {
    // encoder 只跑一次，hidden 复用于每一步 decoder。
    final pixelValues = await OrtValue.fromList(
        imageTensor, [1, 3, kOcrInputSize, kOcrInputSize]);
    final encOut = await encoder.run({encoder.inputNames.first: pixelValues});
    final hidden = encOut['last_hidden_state']!;

    final tokens = <int>[kOcrStartToken];
    for (var step = 0; step < kOcrMaxSteps; step++) {
      final idsVal = await OrtValue.fromList(
          Int64List.fromList(tokens), [1, tokens.length]);
      final out = await decoder.run({
        'input_ids': idsVal,
        'encoder_hidden_states': hidden,
      });
      final logits = (await out['logits']!.asList()).cast<double>();
      // logits 形状 [1, seq, 6144]，取最后一步(最后一行)的 vocab logits。
      final lastRow =
          logits.sublist(logits.length - kOcrVocabSize, logits.length);
      final next = argmaxLastRow(lastRow, kOcrVocabSize);
      if (next == kOcrEosToken) break;
      tokens.add(next);
    }
    return decodeTokens(tokens.sublist(1), _vocab);
  }

  Float32List _imageToChwFloat32(img.Image im, int w, int h) {
    final plane = w * h;
    final out = Float32List(3 * plane);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final i = y * w + x;
        out[i] = p.r / 255.0;
        out[plane + i] = p.g / 255.0;
        out[2 * plane + i] = p.b / 255.0;
      }
    }
    return out;
  }

  List<int> _extractRgb(img.Image im) {
    final out = <int>[];
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        out.add(p.r.toInt());
        out.add(p.g.toInt());
        out.add(p.b.toInt());
      }
    }
    return out;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/translation/manga_text_extractor_test.dart`
Expected: PASS — `+1: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/translation/manga_text_extractor.dart test/data/translation/manga_text_extractor_test.dart
git commit -m "feat: 新增 MangaTextExtractor 抽象与 NativeMangaTextExtractor（从 PoC 迁移）"
```

---

### Task 8: `translation_pipeline.dart` — orchestration + LLM prompt + JSON parsing

**Files:**
- Create: `lib/data/translation/translation_pipeline.dart`
- Test: `test/data/translation/translation_pipeline_test.dart`

**Interfaces:**
- Consumes: `MangaTextExtractor` (Task 7), `TextRegion`/`PageTranslation` (Task 1), `TranslationCacheStore` (Task 6), `TranslationModelManager.ensureReady` (Task 5), `AiClient.chat`/`AiMessage`/`AiClientException` and `AiConfig`/`AiConfigStore` (existing `lib/core/ai/`)
- Produces: `List<String>? parseJsonStringArray(String reply)`
- Produces: `class TranslationConfigException implements Exception { final String message; }`
- Produces: `class TranslationPipeline { TranslationPipeline({required MangaTextExtractor extractor, required AiClient aiClient, required AiConfigStore configStore, required TranslationCacheStore cacheStore, required TranslationModelManager modelManager}); Future<PageTranslation> translatePage(String sourceId, String mangaId, String chapterId, int pageIndex, Uint8List imageBytes); }`

- [ ] **Step 1: Write the failing test**

Create `test/data/translation/translation_pipeline_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/core/ai/ai_client.dart';
import 'package:comic_reader/core/ai/ai_config.dart';
import 'package:comic_reader/data/translation/manga_text_extractor.dart';
import 'package:comic_reader/data/translation/models/page_translation.dart';
import 'package:comic_reader/data/translation/models/text_region.dart';
import 'package:comic_reader/data/translation/translation_cache_store.dart';
import 'package:comic_reader/data/translation/translation_model_manager.dart';
import 'package:comic_reader/data/translation/translation_pipeline.dart';

class MockMangaTextExtractor extends Mock implements MangaTextExtractor {}

class MockAiClient extends Mock implements AiClient {}

class MockAiConfigStore extends Mock implements AiConfigStore {}

class MockTranslationCacheStore extends Mock implements TranslationCacheStore {}

class MockTranslationModelManager extends Mock
    implements TranslationModelManager {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AiConfig());
    registerFallbackValue(<AiMessage>[]);
  });

  late MockMangaTextExtractor extractor;
  late MockAiClient aiClient;
  late MockAiConfigStore configStore;
  late MockTranslationCacheStore cacheStore;
  late MockTranslationModelManager modelManager;
  late TranslationPipeline pipeline;
  const usableConfig = AiConfig(enabled: true, apiKey: 'k');

  setUp(() {
    extractor = MockMangaTextExtractor();
    aiClient = MockAiClient();
    configStore = MockAiConfigStore();
    cacheStore = MockTranslationCacheStore();
    modelManager = MockTranslationModelManager();
    pipeline = TranslationPipeline(
      extractor: extractor,
      aiClient: aiClient,
      configStore: configStore,
      cacheStore: cacheStore,
      modelManager: modelManager,
    );

    when(() => configStore.isLoaded).thenReturn(true);
    when(() => configStore.current).thenReturn(usableConfig);
    when(() => modelManager.ensureReady()).thenAnswer((_) async {});
    when(() => cacheStore.save(any())).thenAnswer((_) async {});
  });

  test('returns the cached result without touching extractor/aiClient',
      () async {
    final cached = PageTranslation(
      sourceId: 's',
      mangaId: 'm',
      chapterId: 'c',
      pageIndex: 0,
      regions: const [],
      translatedAt: 1,
    );
    when(() => cacheStore.get('s', 'm', 'c', 0))
        .thenAnswer((_) async => cached);

    final result =
        await pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0));

    expect(result, same(cached));
    verifyNever(() => extractor.extract(any()));
    verifyNever(() => aiClient.chat(any(), any(),
        json: any(named: 'json'), temperature: any(named: 'temperature')));
  });

  test('throws TranslationConfigException when AI is not usable', () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => configStore.current)
        .thenReturn(const AiConfig(enabled: false));

    await expectLater(
      pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0)),
      throwsA(isA<TranslationConfigException>()),
    );
  });

  test('extracts regions, translates via aiClient, and caches the result',
      () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => extractor.extract(any())).thenAnswer((_) async => const [
          TextRegion(box: [0, 0, 1, 1], originalText: 'あ'),
          TextRegion(box: [1, 1, 1, 1], originalText: 'い'),
        ]);
    when(() => aiClient.chat(any(), any(),
            json: any(named: 'json'), temperature: any(named: 'temperature')))
        .thenAnswer((_) async => '["啊", "咦"]');

    final result =
        await pipeline.translatePage('s', 'm', 'c', 7, Uint8List(0));

    expect(result.regions.length, 2);
    expect(result.regions[0].translatedText, '啊');
    expect(result.regions[1].translatedText, '咦');
    expect(result.pageIndex, 7);
    verify(() => cacheStore.save(any())).called(1);
  });

  test(
      'mismatched reply length leaves missing entries with null translatedText',
      () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => extractor.extract(any())).thenAnswer((_) async => const [
          TextRegion(box: [0, 0, 1, 1], originalText: 'あ'),
          TextRegion(box: [1, 1, 1, 1], originalText: 'い'),
        ]);
    when(() => aiClient.chat(any(), any(),
            json: any(named: 'json'), temperature: any(named: 'temperature')))
        .thenAnswer((_) async => '["啊"]');

    final result =
        await pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0));

    expect(result.regions[0].translatedText, '啊');
    expect(result.regions[1].translatedText, isNull);
  });

  test('empty extraction result skips the LLM call and caches an empty page',
      () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => extractor.extract(any())).thenAnswer((_) async => const []);

    final result =
        await pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0));

    expect(result.regions, isEmpty);
    verifyNever(() => aiClient.chat(any(), any(),
        json: any(named: 'json'), temperature: any(named: 'temperature')));
    verify(() => cacheStore.save(any())).called(1);
  });

  test('aiClient failure propagates and the page is not cached', () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => extractor.extract(any())).thenAnswer((_) async => const [
          TextRegion(box: [0, 0, 1, 1], originalText: 'あ'),
        ]);
    when(() => aiClient.chat(any(), any(),
            json: any(named: 'json'), temperature: any(named: 'temperature')))
        .thenThrow(AiClientException('boom'));

    await expectLater(
      pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0)),
      throwsA(isA<AiClientException>()),
    );
    verifyNever(() => cacheStore.save(any()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/translation/translation_pipeline_test.dart`
Expected: FAIL with `Error when reading '...translation_pipeline.dart': No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/translation/translation_pipeline.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:comic_reader/core/ai/ai_client.dart';
import 'package:comic_reader/core/ai/ai_config.dart';

import 'manga_text_extractor.dart';
import 'models/page_translation.dart';
import 'models/text_region.dart';
import 'translation_cache_store.dart';
import 'translation_model_manager.dart';

/// Thrown by [TranslationPipeline.translatePage] when the app-wide AI
/// config is disabled or missing an API key.
class TranslationConfigException implements Exception {
  TranslationConfigException(this.message);
  final String message;
  @override
  String toString() => 'TranslationConfigException: $message';
}

const _systemPrompt = '你是专业的漫画翻译。将日文或韩文的漫画对话翻译成简体中文，'
    '要求自然、口语化，符合中文漫画阅读习惯，结合整页语境。'
    '严格按输入的序号返回，条数必须完全一致，只返回一个 JSON 数组，'
    '每个元素是对应序号气泡的中文译文字符串，不要任何解释或额外字段。';

String _buildUserPrompt(List<TextRegion> regions) {
  final buffer =
      StringBuffer('请翻译以下 ${regions.length} 个漫画气泡文字（按序号）：\n');
  for (var i = 0; i < regions.length; i++) {
    buffer.writeln('${i + 1}. ${regions[i].originalText}');
  }
  return buffer.toString();
}

/// Defensively extracts a JSON array of strings from an LLM reply that may
/// be wrapped in prose or a ```json fenced block. Returns null when no
/// array can be parsed out.
List<String>? parseJsonStringArray(String reply) {
  var text = reply.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('```')) {
    final firstNewline = text.indexOf('\n');
    if (firstNewline != -1) text = text.substring(firstNewline + 1);
    final fenceEnd = text.lastIndexOf('```');
    if (fenceEnd != -1) text = text.substring(0, fenceEnd);
    text = text.trim();
  }
  if (!text.startsWith('[')) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start != -1 && end > start) {
      text = text.substring(start, end + 1);
    }
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded.map((e) => e?.toString() ?? '').toList();
    }
  } catch (_) {
    // ignore
  }
  return null;
}

/// Orchestrates: cache lookup -> on-device text extraction -> whole-page
/// LLM translation (via the app-wide BYOK [AiClient]) -> persistent cache
/// write.
class TranslationPipeline {
  TranslationPipeline({
    required this.extractor,
    required this.aiClient,
    required this.configStore,
    required this.cacheStore,
    required this.modelManager,
  });

  final MangaTextExtractor extractor;
  final AiClient aiClient;
  final AiConfigStore configStore;
  final TranslationCacheStore cacheStore;
  final TranslationModelManager modelManager;

  Future<PageTranslation> translatePage(
    String sourceId,
    String mangaId,
    String chapterId,
    int pageIndex,
    Uint8List imageBytes,
  ) async {
    final cached =
        await cacheStore.get(sourceId, mangaId, chapterId, pageIndex);
    if (cached != null) return cached;

    final config =
        configStore.isLoaded ? configStore.current : await configStore.load();
    if (!config.isUsable) {
      throw TranslationConfigException('AI 未启用或未配置 API Key');
    }

    await modelManager.ensureReady();
    final regions = await extractor.extract(imageBytes);

    final translatedRegions =
        regions.isEmpty ? regions : await _translate(config, regions);

    final result = PageTranslation(
      sourceId: sourceId,
      mangaId: mangaId,
      chapterId: chapterId,
      pageIndex: pageIndex,
      regions: translatedRegions,
      translatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await cacheStore.save(result);
    return result;
  }

  Future<List<TextRegion>> _translate(
      AiConfig config, List<TextRegion> regions) async {
    final reply = await aiClient.chat(
      config,
      [
        AiMessage.system(_systemPrompt),
        AiMessage.user(_buildUserPrompt(regions)),
      ],
      json: true,
      temperature: 0.3,
    );
    final translations = parseJsonStringArray(reply);
    return [
      for (var i = 0; i < regions.length; i++)
        regions[i].copyWith(
          translatedText: translations != null && i < translations.length
              ? translations[i]
              : null,
        ),
    ];
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/translation/translation_pipeline_test.dart`
Expected: PASS — `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/translation/translation_pipeline.dart test/data/translation/translation_pipeline_test.dart
git commit -m "feat: 新增 TranslationPipeline（编排 + 翻译 prompt + JSON 解析）"
```

---

### Task 9: DI registration in `injection.dart`

**Files:**
- Modify: `lib/app/di/injection.dart`

**Interfaces:**
- Consumes: `TranslationModelManager` (Task 5), `MangaTextExtractor`/`NativeMangaTextExtractor` (Task 7), `TranslationCacheStore` (Task 6), `TranslationPipeline` (Task 8), plus existing `AiClient`/`AiConfigStore` registrations
- Produces: `getIt<TranslationPipeline>()`, `getIt<MangaTextExtractor>()`, `getIt<TranslationModelManager>()`, `getIt<TranslationCacheStore>()` resolvable app-wide

- [ ] **Step 1: Add the imports**

At the top of `lib/app/di/injection.dart`, alongside the other `package:comic_reader/...` imports, add:

```dart
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:comic_reader/data/translation/manga_text_extractor.dart';
import 'package:comic_reader/data/translation/translation_cache_store.dart';
import 'package:comic_reader/data/translation/translation_model_manager.dart';
import 'package:comic_reader/data/translation/translation_pipeline.dart';
```

- [ ] **Step 2: Insert the four registrations after the AI block**

Find this existing block (currently ending the AI section, right before `// Source Registry`):

```dart
  getIt.registerLazySingleton<AiService>(
    () => AiService(
      client: getIt<AiClient>(),
      configStore: getIt<AiConfigStore>(),
    ),
  );

  // Source Registry
```

Replace it with:

```dart
  getIt.registerLazySingleton<AiService>(
    () => AiService(
      client: getIt<AiClient>(),
      configStore: getIt<AiConfigStore>(),
    ),
  );

  // Manga translation pipeline (on-device YOLO+OCR detection, BYOK
  // translation via the AiClient registered above).
  getIt.registerLazySingleton<TranslationModelManager>(
    () => TranslationModelManager(),
  );
  getIt.registerLazySingleton<MangaTextExtractor>(
    () => NativeMangaTextExtractor(
      runtime: OnnxRuntime(),
      modelManager: getIt<TranslationModelManager>(),
    ),
  );
  getIt.registerLazySingleton<TranslationCacheStore>(
    () => TranslationCacheStore(),
  );
  getIt.registerLazySingleton<TranslationPipeline>(
    () => TranslationPipeline(
      extractor: getIt<MangaTextExtractor>(),
      aiClient: getIt<AiClient>(),
      configStore: getIt<AiConfigStore>(),
      cacheStore: getIt<TranslationCacheStore>(),
      modelManager: getIt<TranslationModelManager>(),
    ),
  );

  // Source Registry
```

- [ ] **Step 3: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/app/di/injection.dart`
Expected: `No issues found!`

Run: `flutter test test/data/translation/`
Expected: PASS — all tests from Tasks 1–8 still green (this change only adds new registrations; it does not touch any tested module).

(No new automated test is added for this task: `configureDependencies()` wires in `SourceRegistry`/`HttpClient`/`WebViewFetcher` and is not currently safely callable outside a running app — `test/widget_test.dart` already fails for the same reason per `AGENTS.md`. This matches the spec's explicit "no widget/integration tests" testing strategy.)

- [ ] **Step 4: Commit**

```bash
git add lib/app/di/injection.dart
git commit -m "feat: 在 DI 中注册 TranslationPipeline 及其依赖"
```

---

### Task 10: Debug screen — wire `TranslationPocScreen` to the real pipeline

**Files:**
- Modify: `lib/presentation/poc/translation_poc_screen.dart`

**Interfaces:**
- Consumes: `GetIt.instance<TranslationModelManager>()`, `GetIt.instance<TranslationPipeline>()` (both registered in Task 9), `PageTranslation`/`TextRegion` (Task 1)
- Produces: no new public API — the route `AppRoutes.pocTranslation` (`/poc/translation`) and the class name `TranslationPocScreen` are unchanged, so `lib/app/router/app_router.dart` and `lib/app/router/routes.dart` require no edits.

- [ ] **Step 1: Replace the screen's implementation**

Replace the entire contents of `lib/presentation/poc/translation_poc_screen.dart` with:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/translation/models/page_translation.dart';
import '../../data/translation/translation_model_manager.dart';
import '../../data/translation/translation_pipeline.dart';

class TranslationPocScreen extends StatefulWidget {
  const TranslationPocScreen({super.key});
  @override
  State<TranslationPocScreen> createState() => _TranslationPocScreenState();
}

class _TranslationPocScreenState extends State<TranslationPocScreen> {
  bool _busy = false;
  String _status = '点击"下载模型"（首次使用），然后选图并翻译';
  PageTranslation? _result;

  Future<void> _downloadModels() async {
    setState(() {
      _busy = true;
      _status = '下载模型中...';
    });
    try {
      final manager = GetIt.instance<TranslationModelManager>();
      await manager.downloadAll(onProgress: (file, received, total) {
        setState(() => _status = '下载 $file: $received / $total');
      });
      setState(() => _status = '模型已就绪');
    } catch (e) {
      setState(() => _status = '下载失败: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickAndTranslate() async {
    setState(() {
      _busy = true;
      _status = '选择图片...';
    });
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) {
        setState(() {
          _busy = false;
          _status = '已取消';
        });
        return;
      }
      setState(() => _status = '识别 + 翻译中...');
      final bytes = await picked.readAsBytes();
      final pipeline = GetIt.instance<TranslationPipeline>();
      final result = await pipeline.translatePage(
        'debug_source',
        'debug_manga',
        'debug_chapter',
        0,
        Uint8List.fromList(bytes),
      );
      setState(() {
        _result = result;
        _status = '完成，共 ${result.regions.length} 区域';
      });
    } catch (e) {
      setState(() => _status = '出错: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final regions = _result?.regions ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('翻译管道调试页')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _downloadModels,
                  child: const Text('下载模型'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : _pickAndTranslate,
                  child: const Text('选图并翻译'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_status),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: regions.length,
              itemBuilder: (_, i) {
                final r = regions[i];
                return ListTile(
                  dense: true,
                  isThreeLine: true,
                  title: Text(r.translatedText ?? '(未翻译)'),
                  subtitle: Text('原文: ${r.originalText}\nbox=${r.box}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/presentation/poc/translation_poc_screen.dart`
Expected: `No issues found!`

(No new automated test: this is a manual debug screen exercising real ONNX inference + a real network LLM call, which cannot run in CI. It is verified by hand: launch the app, navigate to `/poc/translation`, tap "下载模型", wait for weights to download, tap "选图并翻译", pick a real manga page, and confirm regions with both original and translated text appear.)

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/poc/translation_poc_screen.dart
git commit -m "feat: 翻译调试页改接正式 TranslationPipeline"
```

---

### Task 11: Remove the old PoC module and its asset bundling

**Files:**
- Delete: `lib/data/translation/poc/manga_ocr_decoder.dart`
- Delete: `lib/data/translation/poc/ocr_preprocess.dart`
- Delete: `lib/data/translation/poc/native_poc_extractor.dart`
- Delete: `lib/data/translation/poc/` (now-empty directory)
- Delete: `test/data/translation/native_poc_extractor_test.dart` (content already migrated to `yolo_detections_test.dart` in Task 2)
- Delete: `test/data/translation/manga_ocr_decoder_test.dart` (content already migrated to `ocr_decoder_test.dart` in Task 3)
- Delete: `assets/models/.gitignore` (the directory is no longer a Flutter asset dir; model weights are never bundled or committed)
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: nothing new — this task only removes dead code now that Tasks 1–10 fully replace it.
- Produces: nothing new.

- [ ] **Step 1: Delete the obsolete PoC source, tests, and asset marker files**

```bash
rm -rf lib/data/translation/poc
rm test/data/translation/native_poc_extractor_test.dart
rm test/data/translation/manga_ocr_decoder_test.dart
rm -f assets/models/.gitignore
```

- [ ] **Step 2: Remove the `assets/models/` declaration from `pubspec.yaml`**

Find this block:

```yaml
  assets:
    - assets/fonts/
    - assets/models/
```

Change it to:

```yaml
  assets:
    - assets/fonts/
```

- [ ] **Step 3: Verify the whole translation test suite and static analysis are clean**

Run: `flutter pub get`
Expected: `Got dependencies!` (no asset-directory errors; removing a directory from the `assets:` list is always valid even if the directory still exists on disk).

Run: `flutter test test/data/translation/`
Expected: PASS — every remaining test (models, `yolo_detections`, `ocr_decoder`, `ocr_preprocess`, `translation_model_manager`, `translation_cache_store`, `manga_text_extractor`, `translation_pipeline`) is green, with none pointing at the removed `poc/` files.

Run: `flutter analyze lib/data/translation/ lib/presentation/poc/ lib/app/di/injection.dart`
Expected: `No issues found!` (no dangling references to `lib/data/translation/poc/*` remain anywhere in `lib/`).

- [ ] **Step 4: Commit**

```bash
git add -A lib/data/translation/poc test/data/translation/native_poc_extractor_test.dart test/data/translation/manga_ocr_decoder_test.dart assets/models/.gitignore pubspec.yaml
git commit -m "chore: 移除已迁移的翻译 PoC 代码与 assets/models 声明"
```

(`tools/translation_service/` — the Node.js web-side inference service from the PoC — is intentionally left untouched. Per the spec's range decision #3, web support is out of scope for this plan and will be addressed in a future one.)

---

## Self-Review

**1. Spec coverage:**
- Module layout (`models/`, `yolo_detections.dart`, `ocr_decoder.dart`, `ocr_preprocess.dart`, `manga_text_extractor.dart`, `translation_model_manager.dart`, `translation_pipeline.dart`, `translation_cache_store.dart`) — Tasks 1–8. ✅
- `TextRegion`/`PageTranslation` shape and `MangaTextExtractor`/`TranslationPipeline.translatePage` five-step data flow, cache key semantics — Tasks 1, 7, 8. ✅
- Model download manager (`ModelFileSpec`, 4-file catalog with sizes, `ensureReady`/`downloadAll`/`pathFor`, streaming `dart:io` download, not the project `HttpClient`) — Task 5. ✅
- Translation prompt (fixed system/user text, whole-page batching, JSON-array parsing, length-mismatch fallback) — Task 8. ✅
- Persistent per-page cache (`$appDocDir/translation_cache/.../$pageIndex.json`, native-only) — Task 6. ✅
- `NativeMangaTextExtractor` migrated from the PoC with model paths switched from Flutter assets to `TranslationModelManager.pathFor` + `createSession` — Task 7. ✅
- DI registration of all four new services — Task 9. ✅
- Debug screen exercising the full pipeline manually — Task 10. ✅
- Removal of the PoC module and `assets/models/` bundling — Task 11. ✅
- Native-only scope; web/`tools/translation_service/` untouched — enforced via Global Constraints and explicitly noted in Task 11. ✅
- No widget/integration tests; only pure-Dart unit tests, none loading real weights or hitting the network — enforced throughout Tasks 1–8, explicitly noted in Tasks 9–10. ✅

**2. Placeholder scan:** No `TBD`/`TODO`/"add appropriate error handling" phrases anywhere above; every code step contains complete, runnable code; every "Run" step has an exact command and expected output.

**3. Type consistency:**
- `TextRegion.box` is `List<int> [x, y, w, h]` everywhere it's produced (Task 1) and consumed (Task 7's `NativeMangaTextExtractor.extract`, Task 8's prompt builder) — consistent.
- `MangaTextExtractor.extract(Uint8List) -> Future<List<TextRegion>>` (Task 7) matches exactly what `TranslationPipeline.translatePage` calls in Task 8.
- `TranslationModelManager.pathFor(String) -> Future<String>` (Task 5) matches exactly how Task 7's `NativeMangaTextExtractor.loadModels()` calls it, with the same four relative-path strings (`comic-bubble-yolo.onnx`, `manga-ocr/encoder_model.onnx`, `manga-ocr/decoder_model.onnx`, `manga-ocr/vocab.txt`) as `kTranslationModelFiles` in Task 5.
- `TranslationCacheStore.get/save/clearChapter` signatures (Task 6) match exactly how Task 8's `TranslationPipeline.translatePage` calls them, and how Task 10's debug screen indirectly exercises them through the pipeline.
- `PageTranslation`/`TextRegion` field names (`sourceId`, `mangaId`, `chapterId`, `pageIndex`, `regions`, `translatedAt`, `box`, `originalText`, `translatedText`) are identical across Tasks 1, 6, 7, 8, and 10 — no renames introduced anywhere.
- `TranslationPipeline` constructor parameter names (`extractor`, `aiClient`, `configStore`, `cacheStore`, `modelManager`) match exactly between Task 8's class definition, Task 8's own test, and Task 9's DI registration.

No gaps found; no fixes needed.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-07-manga-translation-pipeline-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
