# 漫画正文翻译功能 — 设计文档

- 日期：2026-07-29
- 状态：设计已确认，待进入实现计划（writing-plans）
- 范围：comic-reader（Flutter 多平台漫画阅读器）

## 1. 背景与目标

comic-reader 聚合了 31 个漫画源，其中包含大量日语/韩语生肉源（E-Hentai、Hitomi.la、NHentai、JComic、HComic、Manga18.Club、Manhuaren 等），这些源没有汉化，中文用户阅读困难。

本功能要做的是**漫画正文翻译**（"生肉转熟肉"）：识别漫画图片里对话气泡/文字区域的原文（日/韩），翻译成中文，并在原图上叠加显示译文。

**明确的范围约束：**

- 只做**日/韩 → 中**翻译。目标语言固定为中文，不做语言检测、不做多目标语言选择 UI。
- 与以下功能**无关**，本设计不涉及：
  - 元数据/标签翻译（ROADMAP #16）
  - UI 国际化 i18n（ROADMAP #22）
- 当前代码库对 OCR / 翻译渲染完全空白（全文 grep `translat` 仅命中两处源文件里的"翻译者/汉化组"署名字段，与本功能无关）。这是一个全新功能。

## 2. 技术路线（已确认）

采用**三段式流水线**：

1. **定位**：YOLO 系模型检测漫画页面中的对话气泡/文字区域坐标。
2. **识别**：专用 OCR 对检测到的区域裁剪后识别出原文。
3. **翻译**：LLM 纯文本翻译成中文，走 BYOK `AiClient`（用户自带 API Key）。

**抝弃的方案：**

- 单一多模态 LLM 一体化（定位不精准）。
- 全云端 API 方案（成本/依赖）。

**模型运行位置：本地推理为主。** 四个平台（iOS/Android/macOS/Web）都不依赖云端做 YOLO/OCR，只有翻译这一步依赖 BYOK 用户自己的 LLM API。

- **原生平台（iOS/Android/macOS）**：应用进程内集成 ONNX Runtime 插件直接跑 YOLO + OCR 模型。
- **Web 平台**：不在浏览器 wasm 跑模型（包体积/性能差），而是用户本机单独启动一个**新建的专用本地推理服务**（Node.js + onnxruntime-node），Web 前端通过 HTTP 调用它完成推理。该服务与现有 `tools/cors_proxy.js` 平行独立，只供 Web 端使用。

**模型选型：** 直接使用现成开源预训练权重，不自训练。

- 定位：`comic-text-detector`（YOLO 基础的漫画文字区域检测）。
- 识别：`manga-ocr`（基于 Transformer 的日语专用 OCR，对手写体/拟声词优化）。
- 两者均来自 `manga-image-translator` 开源项目、经社区验证，需转 ONNX 格式接入。

**触发时机：手动触发。** 需要 UI 显式按钮，用户主动点击才处理某页/某章，不自动进行。

**译文呈现：遮盖块 + 叠加译文。** 在检测到的气泡区域用半透明白色背景块遮盖原文，上面叠加中文译文，不做 inpaint 背景重绘。

**缓存策略：永久缓存。** 按 sourceId + mangaId + chapterId + pageIndex 作为 key 永久缓存到本地，命中缓存直接返回，不重跑流水线。

## 3. 总体架构与数据流

```
用户点击"翻译此页"按钮
  → TranslationPipeline.translatePage(sourceId, mangaId, chapterId, pageIndex, imageBytes)
    ① 查缓存 TranslationCacheStore.get(key) → 命中则直接返回 PageTranslation
    未命中：
    ② MangaTextExtractor.extract(imageBytes)
       - Native：进程内 ONNX Runtime 跑 comic-text-detector(定位) + manga-ocr(识别)
       - Web：HTTP POST 到本机 Node 推理服务(localhost:9091)，服务里跑同样两个模型
       返回 List<TextRegion{box, originalText}>
    ③ AiClient.chat(...) — 复用 ROADMAP #12 的 BYOK 基础设施
       把本页所有 originalText 批量组装成一次翻译请求，返回中文译文数组
    ④ 组装 PageTranslation{regions: List<{box, originalText, translatedText}>}
    ⑤ TranslationCacheStore.save(key, pageTranslation) — 永久缓存
  → 返回给 UI 层渲染叠加层
```

**关键设计点：**

- 定位 + 识别合并成单一 `MangaTextExtractor` 接口（不拆两个，因为无论 native 还是 web 两步都在同一处发生）。
- 翻译步骤平台无关，统一走 `AiClient`。
- 实现顺序上需要先把 ROADMAP #12 的 `AiClient` 最小版做出来，才能接翻译流水线。

## 4. 核心模块与接口

新建目录 `lib/data/translation/`（与现有 `lib/data/local/`、`lib/data/remote/` 平级）：

```
lib/data/translation/
├── models/
│   ├── text_region.dart          // { box: Rect, originalText: String }
│   └── page_translation.dart     // { sourceId, mangaId, chapterId, pageIndex,
│                                  //   regions: List<TranslatedRegion>, translatedAt }
│                                  // TranslatedRegion = { box, originalText, translatedText }
├── manga_text_extractor.dart     // 抽象接口
├── manga_text_extractor_native.dart  // ONNX Runtime 进程内实现
├── manga_text_extractor_web.dart     // HTTP 调本机 Node 推理服务
├── translation_pipeline.dart     // 编排：查缓存 → extractor → AiClient → 存缓存
└── translation_cache_store.dart  // 持久化（复用 LocalStorage 模式）
```

**抽象接口：**

```dart
abstract class MangaTextExtractor {
  Future<List<TextRegion>> extract(Uint8List imageBytes);
}
```

Native/Web 实现通过 conditional import 择一，与现有 `local_storage.dart` 平台分流写法一致：

```dart
import 'manga_text_extractor_native.dart'
    if (dart.library.html) 'manga_text_extractor_web.dart';
```

`TranslationPipeline` 是唯一对外暴露的编排入口，构造函数接收 `extractor / aiClient / cacheStore` 三个依赖，`translatePage()` 方法内部依次：查缓存 → `extractor.extract` → `aiClient.chat(_buildTranslationPrompt(regions))` → 组装 `PageTranslation` → `cacheStore.save`。

**DI 注册**（跟现有 `injection.dart` 的 `registerLazySingleton` 模式一致）：

```dart
getIt.registerLazySingleton<MangaTextExtractor>(() => MangaTextExtractor.create());
getIt.registerLazySingleton<TranslationCacheStore>(
  () => TranslationCacheStore(storage: getIt<LocalStorage>()),
);
getIt.registerLazySingleton<TranslationPipeline>(() => TranslationPipeline(
  extractor: getIt<MangaTextExtractor>(),
  aiClient: getIt<AiClient>(), // 依赖 #12 先注册
  cacheStore: getIt<TranslationCacheStore>(),
));
```

## 5. 坐标映射与 UI 叠加渲染

这是技术风险最高的一段。

**纵向滚动模式（`vertical_reader.dart`）— 简单情况：**

固定 `BoxFit.fitWidth`，禁用手势（`disableGesture: true`），换算是纯静态公式：

```
displayScale = containerWidth / imageOriginalWidth
叠加框屏幕坐标 = originalBox * displayScale
```

y 方向偏移由 Flutter `Positioned` 在 ListView 里天然处理，不用手算。需把 `vertical_reader.dart` 每个 item 从裸的 `SizedBox(child: MangaImage(...))` 改成：

```dart
Stack(children: [
  MangaImage(...),
  if (hasTranslation) Positioned.fill(child: TranslationOverlay(...)),
])
```

参照 `horizontal_reader.dart` 里 `_TapZonesOverlay`（第 234-271 行）的现成"半透明遮罩 + 文字"写法。

**横向翻页模式（`horizontal_reader.dart`）— 复杂情况：**

用户可 pinch 缩放/拖动（`ExtendedImageMode.gesture`），叠加框必须跟手势变换矩阵一起动。`extended_image` 库暴露了 `GestureDetails`（含当前 scale/offset），可通过 `ExtendedImageGestureState` 拿到当前 `Matrix4`，用 `Transform` 应用同一矩阵到 `TranslationOverlay`。

**决策：** 先尝试跟手势矩阵同步叠加框；如果实现复杂度超预期，再降级为"缩放时隐藏叠加层"（仅 scale ≈ 1.0 时显示）。具体走哪条路留待实现阶段验证后决定，不在设计阶段固化降级方案。

## 6. 缓存持久化

**Key 结构：**

```
key = "${sourceId}_${mangaId}_${chapterId}_${pageIndex}"
```

**Native 端**（per-file 模式，参照 `ChapterCacheService` 目录习惯）：

```
$appDocDir/translation_cache/$sourceId/$mangaId/$chapterId/$pageIndex.json
```

每页一个独立 JSON 文件（`PageTranslation.toJson()`）。读 = 检查文件存在 + 读取；写 = 直接覆盖该文件，不涉及其他页面数据，避免整表读写开销（不采用 `ReadingHistoryStore` 的整表 JSON blob 模式，因为一页可能有几十个文字区域，整表会随阅读量线性膨胀）。

**Web 端**（复用现有 `LocalStorage` 抽象）：

key 沿用相同结构，实际落地为 `localStorage['comic_reader_translation_${key}']`。采用 `ReadingHistoryStore` 式的 in-memory cache + lazy load 模式。

- **已知风险（接受）：** `localStorage` 有 5-10MB 容量限制且是同步阻塞型 API，重度使用可能触顶。作为 v1 方案先用，超限问题（如加 LRU 淘汰或提示用户清理）留给后续，不在本次范围。

**统一接口：**

```dart
abstract class TranslationCacheStore {
  Future<PageTranslation?> get(String sourceId, String mangaId, String chapterId, int pageIndex);
  Future<void> save(PageTranslation translation);
}
```

Native/Web 各自实现内部存储细节（文件 vs LocalStorage），对 `TranslationPipeline` 透明。

## 7. UI/UX 集成点

**触发按钮位置：** `reader_controls.dart` 的 `_TopBar`（第 45-109 行），紧挨现有 `open_in_browser` 图标（第 87-104 行）新增一个 `IconButton`（建议 `Icons.translate`），点击触发当前页翻译。整章翻译可做成长按手势，或在 `_BottomBar` 加"翻译本章"按钮（把当前章节所有未缓存页面依次跑 pipeline）。具体交互形式留待实现阶段用可视化工具确认。

**状态字段扩展**（`ReaderState`，通过现有 `copyWith` 模式）：

```dart
final bool translationEnabled;                    // 全局开关：是否显示翻译叠加层
final Map<int, PageTranslation> translatedPages;  // pageIndex -> 结果（内存态）
final Set<int> translatingPages;                  // 正在处理中的页码（loading 状态）
```

**事件扩展**（`ReaderEvent`）：`TranslatePageRequested(int pageIndex)` / `TranslateChapterRequested()` / `ToggleTranslationOverlay()`。`ReaderBloc` 对应 handler 调用 `TranslationPipeline.translatePage(...)`，成功后 emit 新 state（结果塞入 `translatedPages`），失败显示错误提示（SnackBar/按钮短暂变红）不阻断阅读。

**叠加层渲染：**

- `vertical_reader.dart`：每个 item 从裸 `SizedBox` 改为 `Stack`，参照 `_TapZonesOverlay` 叠加 `TranslationOverlay`（`BlocBuilder` 读 `translatedPages[index]`，按 `displayScale` 换算画框 + 译文）。
- `horizontal_reader.dart`：Stack 内已有的 `Positioned.fill` 叠加层旁再加一层 `TranslationOverlay`，横向坐标同步方案按第 5 段所定。

**Loading/错误反馈：** 处理中显示按钮 spinner 态或页面角落小 loading 指示；失败给出可重试提示（如 Toast/SnackBar「翻译失败，点击重试」）。

## 8. Web 本地推理服务

新建独立 Node.js 服务目录（建议 `tools/translation_service/`），与 `tools/cors_proxy.js` 平行独立：

- 技术栈：Node.js + `onnxruntime-node`（用户只需装 Node.js，与现有工具链一致）。
- 暴露单一 HTTP 接口，例如 `POST /extract`：接收图片字节，返回 `List<TextRegion>` 的 JSON。
- 端口：使用与 cors_proxy（9090）不同的端口，例如 **9091**。
- **`run_web.sh` 集成**：按现有 cors_proxy 的模式加一段结构相同的逻辑——`lsof -i :9091` 检测服务是否已在跑，未跑则启动并后台，脚本退出时 kill 该进程 PID。
- **首次初始化**：手动初始化 + 脚本仅提示。`run_web.sh` 检测到 `node_modules` 或模型文件缺失时，给出清晰的中断提示（如"请先运行 npm install 并下载模型"），但**不**自动执行安装/下载，保持脚本简单可控，避免静默网络下载行为。

## 9. 依赖前提

**实现顺序要求（硬依赖）：**

1. **ROADMAP #12（`core/ai/` 三件套：`AiConfig` / `AiClient` / `AiService`）** — 当前完全未实现，是本功能翻译步骤的硬依赖。必须先完成最小可用版（能配置 provider/key/baseUrl + 发一次 chat 请求拿到文本）才能接入 `TranslationPipeline`。
2. **本地推理能力接入：**
   - Native：选定并集成 ONNX Runtime Flutter 插件，把 `comic-text-detector` + `manga-ocr` 转 ONNX 后跑通最小 demo（单图 → 区域 + 文字）。
   - Web：新建 `tools/translation_service/` Node 服务，装 `onnxruntime-node`，跑通 `POST /extract`，并集成到 `run_web.sh`。

## 10. 开放问题（留待实现阶段）

- **模型资产管理：** 权重文件来源、大小、分发方式（打进 App Bundle/安装包 vs 首次使用按需下载）。Web 端 Node 服务的模型文件同理。需先找到/转换好 ONNX 文件、确认实际体积后再定。
- **横向翻页手势矩阵同步**（第 5 段）：先尝试同步，超预期则降级为缩放时隐藏。
- **Web localStorage 容量**（第 6 段）：v1 先不处理，后续可加 LRU 淘汰。
- **ONNX 各平台推理耗时/内存**未知，低端设备可能需降级（提示等待/限制并发）。
- **权重许可证：** `comic-text-detector` / `manga-ocr` 权重的下载来源与许可证条款，需确认可合规分发。

## 11. 明确排除（YAGNI）

- 语言检测、多目标语言支持（固定日/韩 → 中）。
- 元数据翻译（#16）、UI i18n（#22）。
- inpaint 背景重绘（只做遮盖块）。
- 自动触发/预翻译（仅手动触发）。
