# 漫画正文翻译 - 本地推理可行性验证 (PoC) 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 来逐任务实现本计划。所有 Step 使用 checkbox（`- [ ]`）语法追踪进度。

**Goal:** 验证在 comic-reader 项目里用现成开源 ONNX 权重（comic-text-detector + manga-ocr）跑通「单张漫画图片 → 文字区域坐标 + 日语原文」的最小 demo，native 端（flutter_onnxruntime 进程内）和 web 端（Node onnxruntime-node 本地服务）各跑通一条，消除整个翻译功能最大的技术不确定性。

**Architecture:** 两条独立验证链路。Native：Flutter 集成 `flutter_onnxruntime` 插件，把两个 ONNX 模型作为 asset 打包，在一个独立的 PoC 调试页里加载单图 → comic-text-detector 出文字区域 box → 逐区域裁剪 resize 到 224×224 → manga-ocr（VisionEncoderDecoder + 自实现贪婪解码循环）出日文 → 屏幕列出 box+文字。Web：新建 `tools/translation_service/`（Node + onnxruntime-node + express + multer + sharp），暴露单个 `POST /extract` 接口，接收图片字节，服务端跑同样两个模型，返回 `{regions:[{box,text}]}` JSON。两链路共享同一套模型文件与同一套解码算法逻辑（分别用 Dart / JS 实现一次）。

**Tech Stack:** Flutter (Dart)、`flutter_onnxruntime` ^1.8.1、`image` 包（Dart 图像裁剪/resize）、Node.js、`onnxruntime-node`、`express`、`multer`、`sharp`。模型：`comictextdetector.pt.onnx`（zyddnys/manga-image-translator beta-0.3，~92MB）、`manga-ocr-base` ONNX（onnx-community/manga-ocr-base-ONNX 或 optimum 导出）。

## Global Constraints

- 本 PoC 是**验证性**代码，不接入正式阅读器流程、不接 core/ai/、不接翻译（翻译是后续独立计划）。PoC 只输出**日文原文**，不翻译成中文。
- 模型文件**不提交进 git**（体积过大）：模型放 `assets/models/`（native）与 `tools/translation_service/models/`（web），两处均加入各自 `.gitignore`；仓库只提交下载脚本与校验（sha256）。
- comic-text-detector 权重 sha256 = `1a86ace74961413cbd650002e7bb4dcec4980ffa21b2f19b86933372071d718f`，下载 URL = `https://github.com/zyddnys/manga-image-translator/releases/download/beta-0.3/comictextdetector.pt.onnx`。
- manga-ocr 贪婪解码：起始 token_id=2，最多循环 300 次，argmax 取 token，token_id==3 (EOS) 停止，token_id<5 跳过不计入文本，vocab 大小 6144。
- manga-ocr 图像预处理：resize 到 224×224，RGB，归一化 mean=0.5/std=0.5（即 `(pixel/255 - 0.5)/0.5`）。
- comic-text-detector 输入尺寸 1024×1024。
- 命令：`flutter pub get` 装依赖；`flutter analyze <file>` 静态检查；`flutter test <path>` 单测；Node 测试在 `tools/translation_service/` 内 `npm test`（node --test）。
- Native 测试禁止依赖真实模型文件下载（CI 无网络/无 92MB 权重）：所有 Dart 单测针对**纯算法函数**（解码循环、坐标换算、预处理张量生成），用内联小数组/伪 logits 验证，不加载真实 .onnx。
- 修改代码后运行 `graphify update .` 刷新知识图（AST-only 无 API 成本）。

---

### Task 1: 模型下载脚本与目录骨架

**Files:**
- Create: `tools/download_models.sh`
- Create: `assets/models/.gitignore`
- Create: `tools/translation_service/models/.gitignore`
- Create: `tools/translation_service/README.md`

**Interfaces:**
- Consumes: 无（首个任务）。
- Produces: `tools/download_models.sh`（下载两个模型到 `assets/models/` 与 `tools/translation_service/models/`，带 sha256 校验）；两个 `.gitignore`（忽略 `*.onnx`）。

- [ ] **Step 1: 创建 native 模型目录 gitignore**

`assets/models/.gitignore`:
```
# 模型权重体积过大，不入库，用 tools/download_models.sh 下载
*.onnx
*.bin
```

- [ ] **Step 2: 创建 web 服务模型目录 gitignore**

`tools/translation_service/models/.gitignore`:
```
*.onnx
*.bin
```

- [ ] **Step 3: 编写下载脚本**

`tools/download_models.sh`:
```bash
#!/usr/bin/env bash
# 下载 PoC 所需的 ONNX 模型权重到 native 与 web 两处。
# 用法: ./tools/download_models.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/assets/models"
WEB_DIR="$REPO_ROOT/tools/translation_service/models"

CTD_URL="https://github.com/zyddnys/manga-image-translator/releases/download/beta-0.3/comictextdetector.pt.onnx"
CTD_SHA="1a86ace74961413cbd650002e7bb4dcec4980ffa21b2f19b86933372071d718f"
CTD_NAME="comictextdetector.onnx"

mkdir -p "$NATIVE_DIR" "$WEB_DIR"

download_and_verify() {
  local url="$1" sha="$2" dest="$3"
  if [ -f "$dest" ]; then
    echo "已存在，跳过: $dest"
    return
  fi
  echo "下载 $url -> $dest"
  curl -L --fail -o "$dest" "$url"
  local got
  got="$(shasum -a 256 "$dest" | awk '{print $1}')"
  if [ "$got" != "$sha" ]; then
    echo "sha256 校验失败: 期望 $sha 实际 $got" >&2
    rm -f "$dest"
    exit 1
  fi
  echo "校验通过: $dest"
}

download_and_verify "$CTD_URL" "$CTD_SHA" "$NATIVE_DIR/$CTD_NAME"
cp "$NATIVE_DIR/$CTD_NAME" "$WEB_DIR/$CTD_NAME"

echo ""
echo "comic-text-detector 已就位。"
echo "manga-ocr 请手动导出后放到 $NATIVE_DIR/manga-ocr/ 与 $WEB_DIR/manga-ocr/："
echo "  pip install optimum[exporters]"
echo "  optimum-cli export onnx --model kha-white/manga-ocr-base --task vision2seq-lm $NATIVE_DIR/manga-ocr/"
echo "  cp -r $NATIVE_DIR/manga-ocr $WEB_DIR/manga-ocr"
```

- [ ] **Step 4: 赋可执行权限并试跑检查语法**

Run: `chmod +x tools/download_models.sh && bash -n tools/download_models.sh`
Expected: 无输出（语法正确，退出码 0）

- [ ] **Step 5: 写 web 服务 README 说明初始化步骤**

`tools/translation_service/README.md`:
```markdown
# 漫画翻译本地推理服务 (PoC)

Web 端专用。Native 端不依赖本服务（用 flutter_onnxruntime 进程内推理）。

## 首次初始化（手动，脚本不自动执行）

1. 安装依赖：`cd tools/translation_service && npm install`
2. 下载模型：在仓库根目录运行 `./tools/download_models.sh`
3. 启动服务：`node server.js`（默认端口 9091）

## 接口

POST /extract  (multipart/form-data, 字段名 image)
返回: {"regions": [{"box": [x, y, w, h], "text": "日文原文"}]}
```

- [ ] **Step 6: 提交**

```bash
git add tools/download_models.sh assets/models/.gitignore tools/translation_service/models/.gitignore tools/translation_service/README.md
git commit -m "chore: PoC 模型下载脚本与目录骨架"
```

---

### Task 2: manga-ocr 贪婪解码算法（纯 Dart，可测试）

**Files:**
- Create: `lib/data/translation/poc/manga_ocr_decoder.dart`
- Test: `test/data/translation/manga_ocr_decoder_test.dart`

**Interfaces:**
- Consumes: 无外部依赖（纯函数）。
- Produces:
  - `int argmaxLastRow(List<double> logitsFlat, int vocabSize)` — 输入某一步 decoder 输出的最后一行 logits（长度=vocabSize），返回 argmax 的 token id。
  - `String decodeTokens(List<int> tokenIds, List<String> vocab)` — 把解码出的 token id 序列（不含起始/EOS/特殊）转成字符串，规则：token_id<5 跳过，token_id==3 停止，其余查 vocab 拼接。
  - 常量 `kOcrStartToken=2`、`kOcrEosToken=3`、`kOcrSpecialTokenThreshold=5`、`kOcrMaxSteps=300`、`kOcrVocabSize=6144`。

- [ ] **Step 1: 写失败测试**

`test/data/translation/manga_ocr_decoder_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/poc/manga_ocr_decoder.dart';

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

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/data/translation/manga_ocr_decoder_test.dart`
Expected: FAIL（`Target of URI doesn't exist` / 编译错误，manga_ocr_decoder.dart 尚不存在）

- [ ] **Step 3: 最小实现**

`lib/data/translation/poc/manga_ocr_decoder.dart`:
```dart
/// manga-ocr 贪婪解码相关常量与纯函数（PoC）。
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

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/data/translation/manga_ocr_decoder_test.dart`
Expected: PASS（所有 test 通过）

- [ ] **Step 5: 提交**

```bash
git add lib/data/translation/poc/manga_ocr_decoder.dart test/data/translation/manga_ocr_decoder_test.dart
git commit -m "feat: PoC manga-ocr 贪婪解码纯函数"
```

---

### Task 3: manga-ocr 图像预处理张量（纯 Dart，可测试）

**Files:**
- Create: `lib/data/translation/poc/ocr_preprocess.dart`
- Test: `test/data/translation/ocr_preprocess_test.dart`

**Interfaces:**
- Consumes: 无（用内联 RGB 值测试，不加载真实图片）。
- Produces:
  - `Float32List imageToOcrTensor(List<int> rgbPixels, int width, int height)` — 输入已 resize 到 224×224 的 RGB 像素（长度=width*height*3，顺序 R,G,B,R,G,B...），输出 CHW 排列、归一化 `(v/255-0.5)/0.5` 的 Float32List（长度=3*224*224），通道顺序 R 平面、G 平面、B 平面。
  - 常量 `kOcrInputSize=224`。

- [ ] **Step 1: 写失败测试**

`test/data/translation/ocr_preprocess_test.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/poc/ocr_preprocess.dart';

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

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/data/translation/ocr_preprocess_test.dart`
Expected: FAIL（ocr_preprocess.dart 不存在，编译错误）

- [ ] **Step 3: 最小实现**

`lib/data/translation/poc/ocr_preprocess.dart`:
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

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/data/translation/ocr_preprocess_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/data/translation/poc/ocr_preprocess.dart test/data/translation/ocr_preprocess_test.dart
git commit -m "feat: PoC manga-ocr 图像预处理张量函数"
```

---

### Task 4: 添加 flutter_onnxruntime 依赖与模型 asset 声明

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/proguard-rules.pro`（若不存在则 Create）

**Interfaces:**
- Consumes: 无。
- Produces: 项目可 `import 'package:flutter_onnxruntime/flutter_onnxruntime.dart'`；`assets/models/` 声明为 asset 目录。

- [ ] **Step 1: 加依赖**

Run: `flutter pub add flutter_onnxruntime && flutter pub add image`
Expected: pubspec.yaml 的 dependencies 出现 `flutter_onnxruntime:` 与 `image:`，`flutter pub get` 成功

- [ ] **Step 2: 声明模型 asset 目录**

在 `pubspec.yaml` 的 `flutter:` -> `assets:` 列表下加一行（若 assets 段不存在则新建）：
```yaml
flutter:
  assets:
    - assets/models/
```

- [ ] **Step 3: 加 Android proguard 规则**

`android/app/proguard-rules.pro`（追加，文件不存在则创建）:
```
# flutter_onnxruntime / ONNX Runtime
-keep class ai.onnxruntime.** { *; }
-keep class com.microsoft.onnxruntime.** { *; }
```

- [ ] **Step 4: 验证依赖解析与编译**

Run: `flutter pub get && flutter analyze lib/data/translation/poc/`
Expected: `No issues found!`（依赖就绪，PoC 纯函数目录无告警）

- [ ] **Step 5: 提交**

```bash
git add pubspec.yaml pubspec.lock android/app/proguard-rules.pro
git commit -m "chore: 引入 flutter_onnxruntime 与 image 依赖，声明模型 asset"
```

---

### Task 5: Native 推理封装（comic-text-detector + manga-ocr 串联）

**Files:**
- Create: `lib/data/translation/poc/native_poc_extractor.dart`
- Test: `test/data/translation/native_poc_extractor_test.dart`

**Interfaces:**
- Consumes: `manga_ocr_decoder.dart`（`argmaxLastRow`/`decodeTokens`/常量）、`ocr_preprocess.dart`（`imageToOcrTensor`/`kOcrInputSize`）。
- Produces:
  - class `PocTextRegion { final List<int> box; final String text; }`（box=[x,y,w,h]）。
  - class `NativePocExtractor`，构造 `NativePocExtractor({required OnnxRuntime runtime})`；方法 `Future<void> loadModels()`（从 asset 加载两个 session）；`Future<List<PocTextRegion>> extract(Uint8List imageBytes)`。
  - 静态纯函数 `List<List<int>> postprocessDetectorBoxes(List<double> segMap, int mapW, int mapH, double thresh)` — 把 detector 输出的分割图阈值化后提取连通区域 bounding box（简化版：阈值+行列投影求外接框），返回 box 列表。**此函数可单测**。

- [ ] **Step 1: 写失败测试（只测纯函数 postprocessDetectorBoxes）**

`test/data/translation/native_poc_extractor_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/poc/native_poc_extractor.dart';

void main() {
  group('postprocessDetectorBoxes', () {
    test('全 0 分割图返回空', () {
      final seg = List<double>.filled(16, 0.0);
      expect(postprocessDetectorBoxes(seg, 4, 4, 0.3), isEmpty);
    });

    test('单个高亮块提取出外接框', () {
      // 4x4 图，中间 2x2 (行1-2 列1-2) 为高亮
      final seg = <double>[
        0, 0, 0, 0,
        0, 1, 1, 0,
        0, 1, 1, 0,
        0, 0, 0, 0,
      ];
      final boxes = postprocessDetectorBoxes(seg, 4, 4, 0.3);
      expect(boxes.length, 1);
      // box = [x, y, w, h] = [1, 1, 2, 2]
      expect(boxes.first, [1, 1, 2, 2]);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/data/translation/native_poc_extractor_test.dart`
Expected: FAIL（native_poc_extractor.dart 不存在）

- [ ] **Step 3: 实现（含纯函数 + ONNX 串联）**

`lib/data/translation/poc/native_poc_extractor.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'manga_ocr_decoder.dart';
import 'ocr_preprocess.dart';

/// 检测到的文字区域: box=[x,y,w,h]，text=OCR 出的日文。
class PocTextRegion {
  final List<int> box;
  final String text;
  const PocTextRegion({required this.box, required this.text});
}

/// 把 detector 分割图阈值化后，用简单连通块外接矩形提取 box 列表。
/// segMap: 长度 mapW*mapH 的置信度；thresh: 阈值。
/// 简化版：把所有 >thresh 的像素视为前景，做一次 4-邻接洪泛聚类，
/// 每个连通块取外接框 [x,y,w,h]。
List<List<int>> postprocessDetectorBoxes(
    List<double> segMap, int mapW, int mapH, double thresh) {
  final visited = List<bool>.filled(mapW * mapH, false);
  final boxes = <List<int>>[];
  int idx(int x, int y) => y * mapW + x;

  for (var y = 0; y < mapH; y++) {
    for (var x = 0; x < mapW; x++) {
      if (visited[idx(x, y)] || segMap[idx(x, y)] <= thresh) continue;
      // BFS 洪泛
      var minX = x, maxX = x, minY = y, maxY = y;
      final queue = <List<int>>[[x, y]];
      visited[idx(x, y)] = true;
      while (queue.isNotEmpty) {
        final p = queue.removeLast();
        final px = p[0], py = p[1];
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
        for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          final nx = px + d[0], ny = py + d[1];
          if (nx < 0 || ny < 0 || nx >= mapW || ny >= mapH) continue;
          if (visited[idx(nx, ny)] || segMap[idx(nx, ny)] <= thresh) continue;
          visited[idx(nx, ny)] = true;
          queue.add([nx, ny]);
        }
      }
      boxes.add([minX, minY, maxX - minX + 1, maxY - minY + 1]);
    }
  }
  return boxes;
}

class NativePocExtractor {
  NativePocExtractor({required this.runtime});
  final OnnxRuntime runtime;

  OrtSession? _detector;
  OrtSession? _ocr;
  List<String> _vocab = const [];

  static const _detectorAsset = 'assets/models/comictextdetector.onnx';
  static const _ocrAsset = 'assets/models/manga-ocr/model.onnx';
  static const _vocabAsset = 'assets/models/manga-ocr/vocab.txt';

  Future<void> loadModels() async {
    _detector = await runtime.createSessionFromAsset(_detectorAsset);
    _ocr = await runtime.createSessionFromAsset(_ocrAsset);
    final vocabRaw = await rootBundle.loadString(_vocabAsset);
    _vocab = vocabRaw.split('\n');
  }

  Future<List<PocTextRegion>> extract(Uint8List imageBytes) async {
    final detector = _detector;
    final ocr = _ocr;
    if (detector == null || ocr == null) {
      throw StateError('模型未加载，请先调用 loadModels()');
    }
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw StateError('图片解码失败');

    // 1. detector: resize 到 1024，跑分割，后处理出 box
    final detResized = img.copyResize(decoded, width: 1024, height: 1024);
    final detInput = _imageToChwFloat32(detResized, 1024, 1024);
    final detTensor = await OrtValue.fromList(detInput, [1, 3, 1024, 1024]);
    final detOut = await detector.run({detector.inputNames.first: detTensor});
    final segName = detector.outputNames.first;
    final segMap = (await detOut[segName]!.asList()).cast<double>();
    final boxes = postprocessDetectorBoxes(segMap, 1024, 1024, 0.3);

    // 2. 逐 box 裁剪 -> resize 224 -> manga-ocr 贪婪解码
    final regions = <PocTextRegion>[];
    final scaleX = decoded.width / 1024.0;
    final scaleY = decoded.height / 1024.0;
    for (final b in boxes) {
      final ox = (b[0] * scaleX).round();
      final oy = (b[1] * scaleY).round();
      final ow = (b[2] * scaleX).round().clamp(1, decoded.width - ox);
      final oh = (b[3] * scaleY).round().clamp(1, decoded.height - oy);
      final crop = img.copyCrop(decoded, x: ox, y: oy, width: ow, height: oh);
      final ocrResized =
          img.copyResize(crop, width: kOcrInputSize, height: kOcrInputSize);
      final rgb = _extractRgb(ocrResized);
      final ocrTensor = imageToOcrTensor(rgb, kOcrInputSize, kOcrInputSize);
      final text = await _runOcrGreedy(ocr, ocrTensor);
      regions.add(PocTextRegion(box: [ox, oy, ow, oh], text: text));
    }
    return regions;
  }

  Future<String> _runOcrGreedy(OrtSession ocr, Float32List imageTensor) async {
    final imgName = ocr.inputNames[0];
    final tokName = ocr.inputNames[1];
    final logitsName = ocr.outputNames.first;
    final tokens = <int>[kOcrStartToken];
    final imgVal =
        await OrtValue.fromList(imageTensor, [1, 3, kOcrInputSize, kOcrInputSize]);
    for (var step = 0; step < kOcrMaxSteps; step++) {
      final tokVal = await OrtValue.fromList(
          Int64List.fromList(tokens.map((e) => e).toList()), [1, tokens.length]);
      final out = await ocr.run({imgName: imgVal, tokName: tokVal});
      final logits = (await out[logitsName]!.asList()).cast<double>();
      // 取最后一步(最后一行)的 logits
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

- [ ] **Step 4: 运行测试确认通过（纯函数）**

Run: `flutter test test/data/translation/native_poc_extractor_test.dart`
Expected: PASS（`postprocessDetectorBoxes` 两 test 通过）

- [ ] **Step 5: 静态检查整个文件**

Run: `flutter analyze lib/data/translation/poc/native_poc_extractor.dart`
Expected: `No issues found!`（若 flutter_onnxruntime API 名不符，按 analyze 报错据实修正 OrtValue.fromList/asList/run 的调用形态后再跑通）

- [ ] **Step 6: 提交**

```bash
git add lib/data/translation/poc/native_poc_extractor.dart test/data/translation/native_poc_extractor_test.dart
git commit -m "feat: PoC native 推理串联（detector 后处理可测 + OCR 贪婪循环）"
```

---

### Task 6: Native PoC 调试页（手动跑单图 demo）

**Files:**
- Create: `lib/presentation/poc/translation_poc_screen.dart`
- Modify: `lib/app/router/app_router.dart`
- Modify: `lib/app/router/routes.dart`

**Interfaces:**
- Consumes: `NativePocExtractor`、`PocTextRegion`（Task 5）；`OnnxRuntime`（flutter_onnxruntime）。
- Produces: 路由常量 `routePocTranslation`；一个可从 route 打开的 `TranslationPocScreen`，内部：选图按钮 → 跑 `extract` → 列出每个 region 的 box 与 text。

- [ ] **Step 1: 加路由常量**

在 `lib/app/router/routes.dart` 追加（与现有 route 常量并列）:
```dart
const String routePocTranslation = '/poc/translation';
```

- [ ] **Step 2: 注册路由**

在 `lib/app/router/app_router.dart` 的路由表里追加一条（照现有 GoRoute/其它 route 注册写法）:
```dart
GoRoute(
  path: routePocTranslation,
  builder: (context, state) => const TranslationPocScreen(),
),
```
（若 app_router 用的是 switch-case onGenerateRoute，则在 case 里加 `case routePocTranslation: return MaterialPageRoute(builder: (_) => const TranslationPocScreen());`——按文件现有风格二选一。）

- [ ] **Step 3: 实现调试页**

`lib/presentation/poc/translation_poc_screen.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/translation/poc/native_poc_extractor.dart';

class TranslationPocScreen extends StatefulWidget {
  const TranslationPocScreen({super.key});
  @override
  State<TranslationPocScreen> createState() => _TranslationPocScreenState();
}

class _TranslationPocScreenState extends State<TranslationPocScreen> {
  NativePocExtractor? _extractor;
  List<PocTextRegion> _regions = const [];
  bool _busy = false;
  String _status = '点击选图开始';

  Future<void> _ensureLoaded() async {
    if (_extractor != null) return;
    final ex = NativePocExtractor(runtime: OnnxRuntime());
    await ex.loadModels();
    _extractor = ex;
  }

  Future<void> _pickAndRun() async {
    setState(() { _busy = true; _status = '加载模型...'; });
    try {
      await _ensureLoaded();
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) { setState(() { _busy = false; _status = '已取消'; }); return; }
      setState(() => _status = '推理中...');
      final bytes = await picked.readAsBytes();
      final regions = await _extractor!.extract(Uint8List.fromList(bytes));
      setState(() { _regions = regions; _status = '完成，共 ${regions.length} 区域'; });
    } catch (e) {
      setState(() => _status = '出错: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('翻译 PoC（本地推理）')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _pickAndRun,
                  child: const Text('选图并识别'),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_status)),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _regions.length,
              itemBuilder: (_, i) {
                final r = _regions[i];
                return ListTile(
                  dense: true,
                  title: Text(r.text),
                  subtitle: Text('box=${r.box}'),
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

- [ ] **Step 4: 加 image_picker 依赖**

Run: `flutter pub add image_picker`
Expected: `flutter pub get` 成功

- [ ] **Step 5: 静态检查**

Run: `flutter analyze lib/presentation/poc/translation_poc_screen.dart lib/app/router/`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/presentation/poc/translation_poc_screen.dart lib/app/router/app_router.dart lib/app/router/routes.dart pubspec.yaml pubspec.lock
git commit -m "feat: PoC native 翻译调试页与路由"
```

---

### Task 7: Web 本地推理服务骨架（express + onnxruntime-node）

**Files:**
- Create: `tools/translation_service/package.json`
- Create: `tools/translation_service/server.js`
- Create: `tools/translation_service/.gitignore`

**Interfaces:**
- Consumes: 无。
- Produces: 可 `node server.js` 启动的服务，`POST /extract`（multipart，字段 image）返回 `{regions:[{box,text}]}`；`GET /health` 返回 `{ok:true}`。

- [ ] **Step 1: package.json**

`tools/translation_service/package.json`:
```json
{
  "name": "comic-translation-service",
  "version": "0.1.0",
  "private": true,
  "description": "Web 端漫画翻译本地推理服务 (PoC)",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "test": "node --test"
  },
  "dependencies": {
    "express": "^4.19.2",
    "multer": "^1.4.5-lts.1",
    "onnxruntime-node": "^1.19.2",
    "sharp": "^0.33.4"
  }
}
```

- [ ] **Step 2: .gitignore**

`tools/translation_service/.gitignore`:
```
node_modules/
```

- [ ] **Step 3: server.js**

`tools/translation_service/server.js`:
```js
'use strict';
const express = require('express');
const multer = require('multer');
const { extractRegions, loadModels } = require('./extractor');

const app = express();
const upload = multer({ storage: multer.memoryStorage() });
const PORT = process.env.TRANSLATION_PORT || 9091;

app.get('/health', (req, res) => res.json({ ok: true }));

app.post('/extract', upload.single('image'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'missing image field' });
  try {
    const regions = await extractRegions(req.file.buffer);
    res.json({ regions });
  } catch (e) {
    res.status(500).json({ error: String(e && e.message ? e.message : e) });
  }
});

async function main() {
  await loadModels();
  app.listen(PORT, '127.0.0.1', () => {
    console.log(`翻译推理服务已启动: http://127.0.0.1:${PORT}`);
  });
}

if (require.main === module) {
  main().catch((e) => { console.error('启动失败:', e); process.exit(1); });
}

module.exports = { app };
```

- [ ] **Step 4: 语法检查**

Run: `cd tools/translation_service && node --check server.js`
Expected: 无输出，退出码 0（注意此步 extractor.js 尚未创建，`node --check` 只查语法不解析 require，通过）

- [ ] **Step 5: 提交**

```bash
git add tools/translation_service/package.json tools/translation_service/server.js tools/translation_service/.gitignore
git commit -m "feat: PoC web 推理服务 express 骨架"
```

---

### Task 8: Web 推理核心（onnxruntime-node 串联 + 可测纯函数）

**Files:**
- Create: `tools/translation_service/extractor.js`
- Create: `tools/translation_service/decode.js`
- Test: `tools/translation_service/decode.test.js`

**Interfaces:**
- Consumes: `onnxruntime-node`、`sharp`；`decode.js`。
- Produces:
  - `decode.js`: `argmaxRow(logitsRow)`、`decodeTokens(tokenIds, vocab)`、常量 `START=2/EOS=3/SPECIAL=5/MAX_STEPS=300/VOCAB=6144`、`postprocessBoxes(segMap, w, h, thresh)`（与 Dart 版同算法，返回 `[[x,y,w,h],...]`）。
  - `extractor.js`: `async loadModels()`、`async extractRegions(imageBuffer)` → `[{box:[x,y,w,h], text}]`。

- [ ] **Step 1: 写失败测试**

`tools/translation_service/decode.test.js`:
```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { argmaxRow, decodeTokens, postprocessBoxes, START, EOS } = require('./decode');

test('argmaxRow 取最大下标', () => {
  assert.strictEqual(argmaxRow([0.1, 0.9, 0.3]), 1);
});

test('decodeTokens 跳过特殊 token 并在 EOS 停止', () => {
  const vocab = Array.from({ length: 10 }, (_, i) => 'T' + i);
  assert.strictEqual(decodeTokens([2, 5, 6, 3, 7], vocab), 'T5T6');
});

test('常量正确', () => {
  assert.strictEqual(START, 2);
  assert.strictEqual(EOS, 3);
});

test('postprocessBoxes 提取单块外接框', () => {
  const seg = [
    0, 0, 0, 0,
    0, 1, 1, 0,
    0, 1, 1, 0,
    0, 0, 0, 0,
  ];
  assert.deepStrictEqual(postprocessBoxes(seg, 4, 4, 0.3), [[1, 1, 2, 2]]);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd tools/translation_service && node --test`
Expected: FAIL（`Cannot find module './decode'`）

- [ ] **Step 3: 实现 decode.js**

`tools/translation_service/decode.js`:
```js
'use strict';
const START = 2;
const EOS = 3;
const SPECIAL = 5;
const MAX_STEPS = 300;
const VOCAB = 6144;

function argmaxRow(row) {
  let best = 0;
  let bestVal = row[0];
  for (let i = 1; i < row.length; i++) {
    if (row[i] > bestVal) { bestVal = row[i]; best = i; }
  }
  return best;
}

function decodeTokens(tokenIds, vocab) {
  let out = '';
  for (const id of tokenIds) {
    if (id === EOS) break;
    if (id < SPECIAL) continue;
    if (id < vocab.length) out += vocab[id];
  }
  return out;
}

function postprocessBoxes(segMap, w, h, thresh) {
  const visited = new Array(w * h).fill(false);
  const boxes = [];
  const idx = (x, y) => y * w + x;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (visited[idx(x, y)] || segMap[idx(x, y)] <= thresh) continue;
      let minX = x, maxX = x, minY = y, maxY = y;
      const stack = [[x, y]];
      visited[idx(x, y)] = true;
      while (stack.length) {
        const [px, py] = stack.pop();
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const nx = px + dx, ny = py + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          if (visited[idx(nx, ny)] || segMap[idx(nx, ny)] <= thresh) continue;
          visited[idx(nx, ny)] = true;
          stack.push([nx, ny]);
        }
      }
      boxes.push([minX, minY, maxX - minX + 1, maxY - minY + 1]);
    }
  }
  return boxes;
}

module.exports = { argmaxRow, decodeTokens, postprocessBoxes, START, EOS, SPECIAL, MAX_STEPS, VOCAB };
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd tools/translation_service && node --test`
Expected: PASS（4 tests）

- [ ] **Step 5: 实现 extractor.js**

`tools/translation_service/extractor.js`:
```js
'use strict';
const fs = require('fs');
const path = require('path');
const ort = require('onnxruntime-node');
const sharp = require('sharp');
const {
  argmaxRow, decodeTokens, postprocessBoxes,
  START, EOS, MAX_STEPS, VOCAB,
} = require('./decode');

const MODELS = path.join(__dirname, 'models');
const DETECTOR_PATH = path.join(MODELS, 'comictextdetector.onnx');
const OCR_PATH = path.join(MODELS, 'manga-ocr', 'model.onnx');
const VOCAB_PATH = path.join(MODELS, 'manga-ocr', 'vocab.txt');

let detector = null;
let ocr = null;
let vocab = [];

async function loadModels() {
  detector = await ort.InferenceSession.create(DETECTOR_PATH, {
    executionProviders: ['cpu'], graphOptimizationLevel: 'all', intraOpNumThreads: 4,
  });
  ocr = await ort.InferenceSession.create(OCR_PATH, {
    executionProviders: ['cpu'], graphOptimizationLevel: 'all', intraOpNumThreads: 4,
  });
  vocab = fs.readFileSync(VOCAB_PATH, 'utf8').split('\n');
}

// sharp raw RGB -> CHW float32，可选归一化 (v/255-mean)/std。
async function toChwTensor(buffer, size, normalize) {
  const { data } = await sharp(buffer).removeAlpha().resize(size, size, { fit: 'fill' })
    .raw().toBuffer({ resolveWithObject: true });
  const plane = size * size;
  const out = new Float32Array(3 * plane);
  for (let i = 0; i < plane; i++) {
    let r = data[i * 3] / 255, g = data[i * 3 + 1] / 255, b = data[i * 3 + 2] / 255;
    if (normalize) { r = (r - 0.5) / 0.5; g = (g - 0.5) / 0.5; b = (b - 0.5) / 0.5; }
    out[i] = r; out[plane + i] = g; out[2 * plane + i] = b;
  }
  return out;
}

async function extractRegions(imageBuffer) {
  if (!detector || !ocr) throw new Error('模型未加载');
  // 1. detector
  const detInput = await toChwTensor(imageBuffer, 1024, false);
  const detTensor = new ort.Tensor('float32', detInput, [1, 3, 1024, 1024]);
  const detOut = await detector.run({ [detector.inputNames[0]]: detTensor });
  const segMap = Array.from(detOut[detector.outputNames[0]].data);
  const boxes = postprocessBoxes(segMap, 1024, 1024, 0.3);

  const meta = await sharp(imageBuffer).metadata();
  const scaleX = meta.width / 1024, scaleY = meta.height / 1024;

  // 2. 逐 box OCR
  const regions = [];
  for (const b of boxes) {
    const ox = Math.round(b[0] * scaleX), oy = Math.round(b[1] * scaleY);
    const ow = Math.max(1, Math.round(b[2] * scaleX));
    const oh = Math.max(1, Math.round(b[3] * scaleY));
    const cropBuf = await sharp(imageBuffer)
      .extract({ left: ox, top: oy, width: ow, height: oh }).toBuffer();
    const text = await runOcr(cropBuf);
    regions.push({ box: [ox, oy, ow, oh], text });
  }
  return regions;
}

async function runOcr(cropBuffer) {
  const imgTensorData = await toChwTensor(cropBuffer, 224, true);
  const imgTensor = new ort.Tensor('float32', imgTensorData, [1, 3, 224, 224]);
  const tokens = [START];
  const imgName = ocr.inputNames[0], tokName = ocr.inputNames[1];
  const logitsName = ocr.outputNames[0];
  for (let step = 0; step < MAX_STEPS; step++) {
    const tokTensor = new ort.Tensor('int64',
      BigInt64Array.from(tokens.map((t) => BigInt(t))), [1, tokens.length]);
    const out = await ocr.run({ [imgName]: imgTensor, [tokName]: tokTensor });
    const logits = out[logitsName].data;
    const lastRow = Array.from(logits.slice(logits.length - VOCAB));
    const next = argmaxRow(lastRow);
    if (next === EOS) break;
    tokens.push(next);
  }
  return decodeTokens(tokens.slice(1), vocab);
}

module.exports = { loadModels, extractRegions };
```

- [ ] **Step 6: 语法检查**

Run: `cd tools/translation_service && node --check extractor.js && node --check decode.js`
Expected: 无输出，退出码 0

- [ ] **Step 7: 提交**

```bash
git add tools/translation_service/extractor.js tools/translation_service/decode.js tools/translation_service/decode.test.js
git commit -m "feat: PoC web 推理核心（decode 纯函数可测 + extractor 串联）"
```

---

### Task 9: run_web.sh 集成推理服务启动

**Files:**
- Modify: `tools/run_web.sh`

**Interfaces:**
- Consumes: `tools/translation_service/server.js`（Task 7）。
- Produces: `run_web.sh` 启动 flutter 前，检测并启动翻译推理服务（端口 9091），退出时清理；`node_modules` 或模型缺失时给出清晰中断提示且不自动安装/下载。

- [ ] **Step 1: 读现有 run_web.sh 确认结构**

Run: `rtk read tools/run_web.sh`
Expected: 看到现有 cors_proxy 的 `lsof -i :9090` 检测 + 后台启动 + trap kill 结构

- [ ] **Step 2: 在 cors_proxy 启动段之后插入推理服务启动段**

在 `tools/run_web.sh` 里 cors_proxy 启动逻辑之后、`flutter run` 之前插入：
```bash
# ---- 翻译推理服务 (PoC, 端口 9091) ----
TRANSLATION_DIR="$(dirname "$0")/translation_service"
if [ ! -d "$TRANSLATION_DIR/node_modules" ]; then
  echo "⚠️  翻译推理服务依赖未安装。请先运行:"
  echo "    cd tools/translation_service && npm install"
  echo "跳过翻译服务启动（web 端翻译功能将不可用）。"
elif [ ! -f "$TRANSLATION_DIR/models/comictextdetector.onnx" ]; then
  echo "⚠️  翻译模型缺失。请先运行: ./tools/download_models.sh"
  echo "跳过翻译服务启动。"
else
  if ! lsof -i :9091 >/dev/null 2>&1; then
    echo "启动翻译推理服务 (端口 9091)..."
    (cd "$TRANSLATION_DIR" && node server.js &)
    TRANSLATION_PID=$!
    sleep 1
  else
    echo "翻译推理服务已在 9091 运行。"
  fi
fi
```

- [ ] **Step 3: 在现有 trap 清理里追加 kill 推理服务**

在 `run_web.sh` 现有的 `trap '...' EXIT`（清理 cors_proxy 的那段）里追加对 `TRANSLATION_PID` 的 kill（若变量存在）：
```bash
# 在现有 cleanup 函数/trap 命令中追加：
[ -n "${TRANSLATION_PID:-}" ] && kill "$TRANSLATION_PID" 2>/dev/null || true
```

- [ ] **Step 4: 语法检查**

Run: `bash -n tools/run_web.sh`
Expected: 无输出，退出码 0

- [ ] **Step 5: 提交**

```bash
git add tools/run_web.sh
git commit -m "chore: run_web.sh 集成翻译推理服务启动与清理"
```

---

### Task 10: 手动验证脚本与 PoC 结论文档

**Files:**
- Create: `docs/superpowers/plans/poc-results/manga-translation-poc-checklist.md`

**Interfaces:**
- Consumes: 前 9 个 Task 的全部产物。
- Produces: 一份人工执行的验证清单 + 结论回填模板（记录 native/web 两链路是否跑通、单图耗时、识别质量、内存占用，供后续正式计划决策）。

- [ ] **Step 1: 写验证清单文档**

`docs/superpowers/plans/poc-results/manga-translation-poc-checklist.md`:
```markdown
# 漫画翻译本地推理 PoC 验证清单与结论

## 前置
- [ ] `./tools/download_models.sh` 下载 comic-text-detector 成功（sha256 校验通过）
- [ ] manga-ocr 已按 README 用 optimum 导出到 assets/models/manga-ocr/ 与 tools/translation_service/models/manga-ocr/
- [ ] `flutter pub get` 成功
- [ ] `cd tools/translation_service && npm install` 成功

## 单元测试（纯算法，无需模型）
- [ ] `flutter test test/data/translation/` 全绿
- [ ] `cd tools/translation_service && node --test` 全绿

## Native 链路（macOS 优先，其次 Android/iOS）
- [ ] 运行 app，导航到 /poc/translation
- [ ] 选一张日语生肉漫画页
- [ ] 记录：检测到区域数 = ___，单图总耗时 = ___ ms，内存峰值 = ___ MB
- [ ] 识别文字肉眼质量（对/大致对/错）= ___

## Web 链路
- [ ] `./tools/run_web.sh` 启动，确认推理服务在 9091（GET /health 返回 {ok:true}）
- [ ] `curl -F image=@<某张图> http://127.0.0.1:9091/extract` 返回 regions
- [ ] 记录：区域数 = ___，单图耗时 = ___ ms，识别质量 = ___

## 结论（回填）
- comic-text-detector 后处理是否需要更复杂的 NMS/seg 解码？= ___
- manga-ocr 单 model.onnx vs encoder/decoder 双文件，实际用了哪种？= ___
- 各平台是否达到可接受耗时（目标 < 3s/页）？= ___
- 是否推荐进入正式翻译主体实现？= ___
```

- [ ] **Step 2: 提交**

```bash
git add docs/superpowers/plans/poc-results/manga-translation-poc-checklist.md
git commit -m "docs: PoC 验证清单与结论回填模板"
```

- [ ] **Step 3: 刷新知识图**

Run: `graphify update .`
Expected: 增量更新完成（AST-only，无 API 成本）

---

## 依赖前提与开放问题

- **manga-ocr 模型导出需要 Python + optimum**：本计划的 native/web 都依赖导出后的 `manga-ocr/model.onnx` + `vocab.txt`。若 optimum 导出出的是 encoder/decoder 分离双文件（而非单 model.onnx），Task 5/8 的 OCR 串联需相应改成：先跑 encoder 出 hidden_state，再把 hidden_state + token_ids 喂 decoder 循环。此差异在验证阶段据实调整（属于 PoC 要消除的不确定性本身）。
- **flutter_onnxruntime 的 OrtValue/session API 具体签名**以实际 pub 版本为准；Task 5 Step 5 的 analyze 会暴露不符处，据实修正。
- **comic-text-detector 输出格式**：官方模型除分割图外还可能有额外输出头（线检测等），Task 5/8 只取分割图那一路做连通块，若精度不足在结论文档记录，正式实现时再引入官方 SegDetectorRepresenter 完整后处理。
- 本 PoC **不含**翻译（→中文）、不含 UI 叠加渲染、不含缓存、不接 core/ai/，这些是后续独立计划。
```