# 漫画正文翻译集成设计（后端管道阶段）

> 日期：2026-08-07
> 分支基线：feat/manga-translation-poc（PoC 已端到端验证）
> 本设计范围：把 PoC 验证过的「气泡定位 + 日文 OCR + LLM 翻译 + 永久缓存」正式化为 app 内的后端翻译管道 `lib/data/translation/`，**不含阅读器 UI 叠加层**（留待下一阶段单独设计）。

## 背景与目标

comic-reader 是一个 Flutter 多平台漫画阅读器，聚合大量日语/韩语生肉源。用户需求是「漫画正文翻译」：识别漫画图片里对话气泡的日/韩文 → 翻译成简体中文 → 后续叠加显示（生肉转熟肉）。目标语言固定为简体中文（硬编码，不做多目标语言 UI，不做语言检测）。

三段式流水线已在 PoC 阶段端到端验证跑通（一张真实日语漫画页 1487×2048）：

1. **气泡定位** Manga-Bubble-YOLO（yolo26n）本地 ONNX 推理，~0.08s，得到 13 个气泡级框（旧的 comic-text-detector seg 连通块方案会过度分割成 185 个碎字，已废弃）。
2. **日文识别** manga-ocr（encoder/decoder 双文件 VisionEncoderDecoder）本地 ONNX，~1.7s。
3. **翻译中文** 复用现有 BYOK `AiClient.chat`，整页气泡打包一次请求，~9.2s（PoC 用 Gemini，实际由用户在 AI 设置页自配 provider）。
4. **永久缓存** 按页持久化，命中直接返回。

**本阶段目标**：把 PoC 代码（`lib/data/translation/poc/` + `tools/translation_service/`）重构为 app 内正式的 `lib/data/translation/` 后端管道，用纯函数单测 + 调试页手动验证，**不集成进阅读器 UI**。

## 范围决策（已确认）

1. **实现范围** = 只做后端管道 `TranslationPipeline`，不带阅读器 UI 叠加层（下一阶段另出计划）。
2. **LLM / 代理** = 复用现有 `AiClient.chat`（用户在 AI 设置页自配 provider/key/baseUrl/model），不锁定 provider、不写死代理。用户用 DeepSeek/Kimi 等 openai 兼容国内直连 LLM 即无需代理；用 Gemini 则自行负责网络。
3. **平台** = 首发只 native（macOS/iOS/Android，进程内 `flutter_onnxruntime` 跑 ONNX），web 留待后续。
4. **管道接口 / 缓存** = 沿用 2026-07-29 旧 spec 的整体设计。
5. **翻译粒度** = 整页气泡打包成一次 `AiClient.chat` 请求（带序号）。
6. **模型分发** = 模型权重（~460M）首次使用时从远程下载到 app 文档目录，带进度提示与校验，不打包进 app（bundle 太大）。

## Global Constraints

- 平台：仅 native（macOS/iOS/Android）。web 端此阶段不实现。
- 目标语言硬编码简体中文；源语言日文/韩文。
- 翻译通道复用 `lib/core/ai/`（`AiClient`/`AiConfig`/`AiConfigStore`，已实现且已在 DI 注册），不新建 LLM 通道。
- 模型权重不入 git（`.gitignore` 覆盖 `*.onnx`/`*.bin`）。
- 纯算法函数（YOLO 解析、OCR 解码、OCR 预处理）必须可在 CI 无模型权重、无网络下单测。
- DI 沿用 `injection.dart` 的 `registerLazySingleton` 手动注册模式。
- 本地持久化沿用 native app-docs 目录文件模式。

## 模块结构与文件布局

新建 `lib/data/translation/`（替代 PoC 的 `lib/data/translation/poc/`）：

```
lib/data/translation/
├── models/
│   ├── text_region.dart          // TextRegion{box:[x,y,w,h], originalText, translatedText?}
│   └── page_translation.dart     // PageTranslation{sourceId,mangaId,chapterId,pageIndex,regions,translatedAt}
├── yolo_detections.dart          // 纯函数 parseYoloDetections + 单测
├── ocr_decoder.dart              // 纯函数 argmaxLastRow/decodeTokens + 常量
├── ocr_preprocess.dart           // 纯函数 imageToOcrTensor
├── manga_text_extractor.dart     // 抽象 MangaTextExtractor + NativeMangaTextExtractor 实现
├── translation_model_manager.dart // 模型文件下载 / 校验 / 路径解析
├── translation_pipeline.dart     // 编排：查缓存 → extractor → AiClient 整页翻 → 存缓存
└── translation_cache_store.dart  // 永久缓存（per-page 文件）
```

纯算法函数各自独立文件并各带单测，CI 无需模型权重。`TranslationPipeline` 是唯一对外编排入口，构造函数注入 `extractor` / `aiClient` / `configStore` / `cacheStore` / `modelManager`。全部按 `registerLazySingleton` 在 `injection.dart` 注册。

## 核心接口与数据流

### 数据模型（手写 toJson/fromJson，与项目一致，无 codegen）

```dart
class TextRegion {
  final List<int> box;          // [x, y, w, h] 原图像素坐标
  final String originalText;    // 识别出的日/韩文
  final String? translatedText; // 中文译文；识别阶段为 null，翻译阶段回填
}

class PageTranslation {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final int pageIndex;
  final List<TextRegion> regions;
  final int translatedAt;       // epoch ms
}
```

### 抽象接口

```dart
abstract class MangaTextExtractor {
  Future<void> loadModels();
  Future<List<TextRegion>> extract(Uint8List imageBytes); // 只填 box + originalText
}

class TranslationPipeline {
  Future<PageTranslation> translatePage(
    String sourceId, String mangaId, String chapterId,
    int pageIndex, Uint8List imageBytes,
  );
}
```

### translatePage 数据流

1. `cacheStore.get(key)` 命中 → 直接返回 `PageTranslation`。
2. 未命中：`modelManager.ensureReady()`（模型缺失则抛异常，供上层引导下载）→ `extractor.extract(imageBytes)` → `List<TextRegion>`（仅原文）。
3. `regions` 为空（该页无气泡）→ 存空结果并返回。
4. 组装整页 prompt（带序号）→ `aiClient.chat(config, [system, user], json: true)` → 解析中文数组 → 回填每个 region 的 `translatedText`。
5. 组装 `PageTranslation` → `cacheStore.save(key)` → 返回。

缓存 key = `"${sourceId}_${mangaId}_${chapterId}_${pageIndex}"`。

**错误处理**：`AiClient` 抛异常时，pipeline 不缓存、向上抛（提示「翻译失败，请检查 AI 配置/网络」），已识别的原文不丢失。`AiConfig` 不可用（未配 key）时提前抛明确异常。

## 模型下载管理（translation_model_manager.dart）

native-only，用 `path_provider` 拿目录 `$appDocDir/models/translation/`：

- `comic-bubble-yolo.onnx`（5.8M）
- `manga-ocr/encoder_model.onnx`（~327M）
- `manga-ocr/decoder_model.onnx`（~112M）
- `manga-ocr/vocab.txt`（~30K）

模型清单硬编码为常量列表，每项 `{相对路径, 下载 URL, sha256, 字节数}`：

| 相对路径 | 下载 URL |
|---|---|
| `comic-bubble-yolo.onnx` | `https://huggingface.co/Kiuyha/Manga-Bubble-YOLO/resolve/main/onnx/yolo26n.onnx` |
| `manga-ocr/encoder_model.onnx` | `https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/encoder_model.onnx` |
| `manga-ocr/decoder_model.onnx` | `https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/decoder_model.onnx` |
| `manga-ocr/vocab.txt` | `https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/vocab.txt` |

```dart
class ModelFileSpec {
  final String relativePath;
  final String url;
  final String sha256;
  final int sizeBytes;
}

class TranslationModelManager {
  Future<String> modelsDir();
  Future<bool> isReady();
  Future<void> ensureReady(); // 缺文件抛 ModelNotReadyException(列缺哪些)
  Future<void> downloadAll({void Function(String file, int received, int total)? onProgress});
  Future<String> pathFor(String relativePath);
}
```

- 下载走 `dart:io` `HttpClient` 流式写文件 + 进度回调（**不走项目 `HttpClient.execute()`**，那是为 API/JSON 设计，不适合几百 MB 大文件流式落盘）。
- sha256 校验：本阶段先「只校验文件存在 + 字节数」，完整 sha256 校验可选；中断/损坏则删除重下。
- `ensureReady()` 缺文件抛 `ModelNotReadyException`（列出缺哪些），`TranslationPipeline` 直接向上抛，将来 UI 层捕获引导「下载模型」触发 `downloadAll`。

## 翻译 Prompt 设计

`translation_pipeline.dart` 组装 prompt 并调 `AiClient.chat`。

**System message（固定角色）**：

> 你是专业的漫画翻译。将日文或韩文的漫画对话翻译成简体中文，要求自然、口语化，符合中文漫画阅读习惯，结合整页语境。严格按输入的序号返回，条数必须完全一致，只返回一个 JSON 数组，每个元素是对应序号气泡的中文译文字符串，不要任何解释或额外字段。

**User message（整页气泡带序号打包）**：

```
请翻译以下 N 个漫画气泡文字（按序号）：
1. <气泡1原文>
2. <气泡2原文>
...
N. <气泡N原文>
```

调用 `aiClient.chat(config, [system, user], json: true, temperature: 0.3)`。

**解析**：复用 `AiService._parseJsonObject` 风格的防御性解析（从 ```json 围栏或裸 `[...]` 切片提取）得到中文数组。

**长度不匹配兜底**：LLM 返回数组长度 ≠ 气泡数时，按 index 逐条回填，缺的 `translatedText` 留 null（原文不丢），不整页失败。

## 缓存持久化（translation_cache_store.dart）

native-only。采用 **per-page 文件**（参照现有 `ChapterCacheService` 模式，非整表 JSON blob——一页译文可能几十个 region，整表会随阅读量线性膨胀且每次写入要重写整个文件）。

目录：`$appDocDir/translation_cache/$sourceId/$mangaId/$chapterId/$pageIndex.json`，内容为 `PageTranslation.toJson()`。

```dart
class TranslationCacheStore {
  Future<PageTranslation?> get(String sourceId, String mangaId, String chapterId, int pageIndex);
  Future<void> save(PageTranslation translation);
  Future<void> clearChapter(String sourceId, String mangaId, String chapterId);
}
```

- `get`：拼路径 → 文件存在则读取 + `PageTranslation.fromJson`，不存在返回 null。
- `save`：确保父目录存在 → 写 `translation.toJson()` 到 `$pageIndex.json` 直接覆盖，不涉及其他页。

## NativeMangaTextExtractor 实现

`lib/data/translation/manga_text_extractor.dart` 里的 `NativeMangaTextExtractor`（从 PoC `native_poc_extractor.dart` 搬迁重构，核心推理逻辑已端到端验证）：

```dart
NativeMangaTextExtractor({
  required OnnxRuntime runtime,
  required TranslationModelManager modelManager,
});
```

**关键改动**：模型从「下载后的文档目录」读而非 asset。PoC 用 `createSessionFromAsset('assets/models/...')`，正式版改用 `createSession(await modelManager.pathFor('comic-bubble-yolo.onnx'))` 从 `$appDocDir/models/translation/` 读。

- `loadModels()`：建三个 session（detector + ocrEncoder + ocrDecoder），读 `vocab.txt` 按 `\n` split 并去 `\r`（PoC 验证过的 CRLF 修复）。仅首次建 session，重复调用跳过。
- `extract(Uint8List imageBytes)` 数据流（与 PoC 一致，已验证）：
  1. decode 拿原始宽高；
  2. detector resize 1280×1280 → CHW float32 `/255`（无 mean/std）→ run 取 `output0` → `parseYoloDetections(output, 0.3, scaleX=origW/1280, scaleY=origH/1280)` 得原图坐标 box（xyxy→xywh 在纯函数内做）；
  3. 逐 box：clamp 防越界 → copyCrop → resize 224×224 → `imageToOcrTensor`（`(v/255-0.5)/0.5`）→ OCR encoder 跑一次拿 `last_hidden_state` → decoder 贪婪循环（`tokens=[START]` 逐步 `input_ids` + `encoder_hidden_states` → logits 取最后一行 argmax，`==EOS` 停）→ `decodeTokens` 得日文原文；
  4. 返回 `List<TextRegion>`，每个只填 box + originalText（translatedText 留 null，由 Pipeline 阶段 AiClient 回填）。

**职责边界**：Extractor 只管「图片 → 带原文的区域」，不碰翻译/LLM/缓存。可独立单测（真推理需模型权重，但纯函数 `parseYoloDetections`/`argmaxLastRow`/`decodeTokens`/`imageToOcrTensor` 已各自独立单测覆盖）。

### 模型 IO 契约（已用真实推理确认）

- **Manga-Bubble-YOLO**：input `images`[1,3,1280,1280] CHW float32 `/255` 无 mean/std；output `output0`[1,300,6] 每行 `[x1,y1,x2,y2,conf,cls]`（xyxy 角点，相对 1280 空间，免 NMS，cls=0）。
- **manga-ocr ENCODER**：input `pixel_values`[1,3,224,224] → output `last_hidden_state`[1,197,768]。
- **manga-ocr DECODER**：inputs `input_ids`[1,seq](int64) + `encoder_hidden_states`[1,197,768] → output `logits`[1,seq,6144]。
- 常量：START=2、EOS=3、SPECIAL=5、MAX_STEPS=300、VOCAB=6144；OCR 预处理 size=224、mean=std=0.5。

## DI 注册

`injection.dart` 追加四个 `registerLazySingleton`（依赖已有的 `OnnxRuntime`/`AiClient`/`AiConfigStore`/`LocalStorage`）：

```dart
getIt.registerLazySingleton<TranslationModelManager>(() => TranslationModelManager());
getIt.registerLazySingleton<MangaTextExtractor>(() => NativeMangaTextExtractor(
      runtime: OnnxRuntime(),
      modelManager: getIt<TranslationModelManager>(),
    ));
getIt.registerLazySingleton<TranslationCacheStore>(() => TranslationCacheStore());
getIt.registerLazySingleton<TranslationPipeline>(() => TranslationPipeline(
      extractor: getIt<MangaTextExtractor>(),
      aiClient: getIt<AiClient>(),
      configStore: getIt<AiConfigStore>(),
      cacheStore: getIt<TranslationCacheStore>(),
      modelManager: getIt<TranslationModelManager>(),
    ));
```

## 测试策略

- **纯函数单测**（CI 无需权重、无网络）：`yolo_detections`（parseYoloDetections 过滤 conf + xyxy→xywh）、`ocr_decoder`（argmaxLastRow / decodeTokens / 常量）、`ocr_preprocess`（imageToOcrTensor CHW 归一化）。从 PoC 单测搬迁，已验证 12/12 通过。
- **调试页**（手动验证端到端）：`lib/presentation/poc/translation_pipeline_debug_screen.dart`（或改造现有 `translation_poc_screen.dart`）挂 `/poc/translation`，提供「下载模型」按钮（`modelManager.downloadAll` 带进度条）+「选图翻译」按钮（ImagePicker → `TranslationPipeline.translatePage` → 列出 region 的 originalText + translatedText）。
- **不做** widget/集成测试（真推理需 460M 权重 + 网络，CI 跑不了）。

## 明确排除（YAGNI / 后续阶段）

- 阅读器 UI 叠加层（遮盖块 + 叠字 + 横竖排 + 手势坐标同步）——下一阶段单独设计。
- web 端本地推理服务集成。
- 多目标语言 / 语言检测。
- 拟声词等气泡外手绘字识别（YOLO 只框对话气泡，属正常）。
- inpaint 背景重绘。
- 完整 sha256 强校验（本阶段先字节数校验）。
