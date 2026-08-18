# 漫画翻译本地推理 PoC 验证清单与结论

## 前置
- [x] `./tools/download_models.sh` 下载气泡检测器 comic-bubble-yolo（Manga-Bubble-YOLO / yolo26n，5.8M，来自 `Kiuyha/Manga-Bubble-YOLO`）+ 旧 comic-text-detector（保留下载但已不用）
- [x] manga-ocr 现成 ONNX 权重下载到 assets/models/manga-ocr/ 与 tools/translation_service/models/manga-ocr/（**双文件** encoder_model.onnx 327.5M + decoder_model.onnx 112M，来自 `mayocream/manga-ocr-onnx`；未走 optimum 本地导出，见结论）
- [x] `flutter pub get` 成功
- [x] `cd tools/translation_service && npm install` 成功

## 单元测试（纯算法，无需模型）
- [x] `flutter test test/data/translation/` 全绿（12/12，含 parseYoloDetections 2 例）
- [x] `cd tools/translation_service && node --test decode.test.js` 全绿（5/5，含 parseYoloDetections）；`node --check extractor.js` 通过

## Native 链路（macOS 优先，其次 Android/iOS）
- [~] 代码就绪、与 web 链路逐点等价、`flutter analyze` 无问题；未做交互式 GUI 手动跑通（`flutter run -d macos` 需人工驱动 ImagePicker 选图，无法 headless）
- 关键风险已从源码层面排除：查 flutter_onnxruntime-1.8.3 源码确认 OrtValue 是按 `valueId`(String) 索引原生全局 value store 的轻量句柄，与产生它的 session 无关，故 encoder 输出的 `last_hidden_state` 可直接喂 decoder.run（跨 session 复用合法）
- 记录：检测到区域数 = 待手动确认（预期与 web 一致 ≈185），单图总耗时 = 待手动确认 ms，内存峰值 = 待手动确认 MB
- 识别文字肉眼质量（对/大致对/错）= 待手动确认（web 侧同代码逻辑+同模型为“大致对”）

## Web 链路
- [x] 推理服务在 9091 启动成功（loadModels 加载 detector(yolo)+ocrEncoder+ocrDecoder 三 session 无错，GET /health 返回 `{"ok":true}`）
- [x] `curl -F image=@/tmp/opencode/manga_test.png http://127.0.0.1:9091/extract` 返回 regions
- [x] 记录（**换 Manga-Bubble-YOLO 后**）：区域数 = **13**（气泡级，非碎字），单图耗时 = **~1.8s**，识别质量 = **好**（整句完整日文，如「ねえねえ、めいは坂本のことどう思う?」）
- 记录（旧 comic-text-detector seg，供对比）：区域数 = 185（过度分割碎字），单图耗时 = ~15.1s

## 结论（回填）
- comic-text-detector 后处理是否需要更复杂的 NMS/seg 解码？= **已改用气泡检测模型规避**。旧 comic-text-detector 的 seg 分割图直接连通块（BFS 洪泛）+ 外接框存在**严重过度分割**（单页 185 个 1-2 字碎片，未按气泡聚合）。验证期间**完整替换为 Manga-Bubble-YOLO（yolo26n）**：输入 1280、输出 `output0`[1,300,6]（每行 xyxy+conf+cls，免 NMS），直接得气泡级框。实测单页从 185 碎字降到 **13 个完整气泡**，耗时从 ~15.1s 降到 **~1.8s**，OCR 输出为整句对话（见纠偏记录④）。
- manga-ocr 单 model.onnx vs encoder/decoder 双文件，实际用了哪种？= **encoder/decoder 双文件**。现成 ONNX 权重（VisionEncoderDecoder 架构）导出为 `encoder_model.onnx`（input `pixel_values`[1,3,224,224] → `last_hidden_state`[1,197,768]）+ `decoder_model.onnx`（inputs `input_ids`[1,seq]int64 + `encoder_hidden_states`[1,197,768] → `logits`[1,seq,6144]）。计划原假设的单 model.onnx 不成立，native/web 两侧均已改为 encoder→decoder 两步串联（见纠偏记录③）。
- 各平台是否达到可接受耗时（目标 < 3s/页）？= **是（web 已达标）**。换气泡检测模型后 web 单页 **~1.8s < 3s**（detector ~81ms + 13 次 OCR 贪婪解码）。OCR 仍无 KV cache（O(n²)），region 数进一步增大时会退化，正式阶段仍建议加 KV cache。
- 是否推荐进入正式翻译主体实现？= **强烈推荐**。PoC 已验证 Manga-Bubble-YOLO（气泡定位）+ manga-ocr（识别）双模型在 native（进程内 ONNX，源码层确认 OrtValue 跨 session 可复用）与 web（Node+onnxruntime-node）两链路均能真实跑通，产出气泡级完整日文原文，耗时达标（web ~1.8s）。最大技术不确定性（本地推理可行性、模型选型、双文件串联、过度分割）已全部消除。进入正式实现前建议：①（可选）OCR 解码 KV cache 进一步提速 ②接 core/ai LLM 翻译 + UI 叠加渲染 + 缓存。

## 对计划的纠偏记录（实现期间发现并修正的计划文件缺陷）
以下是执行 PoC 及本地验证期间发现的、计划文件本身的缺陷，已在对应 commit / 验证轮修正，实现的代码与计划文本略有偏离，属有意纠偏：

- **Task 8 — Web extractor 裁剪框上界 clamp**（commit `50cde98`）：计划中 `tools/translation_service/extractor.js` 的 `extractRegions` 只对裁剪框做了下界 `Math.max(1, ...)`，遗漏了 Dart 版 `native_poc_extractor.dart` 里有的上界 clamp。贴边文字框会使 `sharp().extract(...)` 抛 `extract_area: bad extract area`。已改为 `const ow = Math.max(1, Math.min(Math.round(b[2] * scaleX), meta.width - ox)); const oh = Math.max(1, Math.min(Math.round(b[3] * scaleY), meta.height - oy));`，与 Dart 的 `.clamp(1, decoded.width - ox)` 语义一致。
- **Task 9 — run_web.sh 翻译服务 PID 捕获**（commit `58355f5`）：计划中 `(cd "$TRANSLATION_DIR" && node server.js &)` 在子 shell 内后台启动 node，父 shell 的 `TRANSLATION_PID=$!` 捕获不到 node 的真实 PID，退出时无法 kill，导致 9091 端口进程泄漏。已改为 `(cd "$TRANSLATION_DIR" && exec node server.js) &`，并把 `TRANSLATION_DIR` 由相对 `$(dirname "$0")` 改为与文件其余处一致的绝对 `$SCRIPT_DIR`。
- **本地验证轮 — manga-ocr 单文件→双文件串联 + detector 输出头 + vocab CRLF**（native `native_poc_extractor.dart` + web `tools/translation_service/extractor.js`，本轮修改）：
  1. **OCR 双文件串联**：计划假设 manga-ocr 是单 `model.onnx`（image+token_ids→logits），实际现成 ONNX 是 encoder/decoder 双文件。两侧 `loadModels()` 改为建 encoder+decoder 两 session；OCR 改为先跑 encoder(`pixel_values`→`last_hidden_state`) 一次、再喂 decoder 贪婪循环(`input_ids`+`encoder_hidden_states`→`logits`)；资产路径由 `manga-ocr/model.onnx` 改为 `manga-ocr/encoder_model.onnx`+`manga-ocr/decoder_model.onnx`。
  2. **detector 按名取 seg 输出**：detector 有三个输出头 `blk`/`seg`/`det`，计划代码取 `outputNames.first`（=`blk`[1,64512,7]）是错的，应取分割图 `seg`[1,1,1024,1024] 喂连通块后处理。两侧改为按名取 `seg`（native `detOut['seg']!`，web `detOut.seg.data`）。
  3. **vocab 去 CRLF**：`vocab.txt` 为 CRLF 文件，`split('\n')` 后每 token 尾部残留 `\r` 混入识别输出。两侧改为 split 后 map 去掉每行 `\r`（native `.replaceAll('\r','')`，web `.replace(/\r/g,'')`）。
- **本地验证轮 ④ — detector 完整替换为 Manga-Bubble-YOLO（气泡检测）**（native `native_poc_extractor.dart` + web `tools/translation_service/{decode.js,extractor.js}` + `tools/download_models.sh`）：旧 comic-text-detector seg 连通块严重过度分割（185 碎字/页）。用户拍板"完整替换 native+web"，改用 `Kiuyha/Manga-Bubble-YOLO`（yolo26n，5.8M，apache-2.0）：
  - detector 资产改为 `assets/models/comic-bubble-yolo.onnx`（web `tools/translation_service/models/` 同名），`download_models.sh` 加其下载（URL `https://huggingface.co/Kiuyha/Manga-Bubble-YOLO/resolve/main/onnx/yolo26n.onnx`）。
  - detector 输入尺寸 1024→**1280**（CHW float32 仅 /255，无 mean/std，复用原归一化路径），输出取 `output0`[1,300,6] 而非 seg。
  - 新增纯函数 `parseYoloDetections(output, threshold, scaleX, scaleY)`（Dart 顶层 + JS decode.js，均带单测）：逐行 6 值，`conf=output[base+4]>=threshold` 才保留，xyxy 角点按 `scaleX/Y=origW/H÷1280` 映射回原图并转 xywh。替代 `postprocessBoxes`/`postprocessDetectorBoxes`（保留未删）。
  - crop 循环：因 boxes 已是原图 xywh，不再乘 scale，仅 clamp 防越界。
  - 效果：单页 185 碎字→**13 气泡级框**，耗时 ~15.1s→**~1.8s**，OCR 输出整句对话。

## 已知限制 / 后续改进项
- ~~过度分割~~：**已通过换 Manga-Bubble-YOLO 气泡检测解决**（185 碎字→13 气泡级框，耗时 ~15.1s→~1.8s）。
- **OCR 解码性能**：贪婪解码无 KV cache，O(n²)；当前 13 个气泡耗时 ~1.8s 达标，但 region 数进一步增大时会退化，正式阶段建议加 KV cache。
- **native GUI 未交互式跑通**：代码就绪且与 web 等价、源码层确认可行，但未手动在 macOS 上选图跑通完整链路。
