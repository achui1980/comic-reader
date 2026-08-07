# 漫画翻译本地推理 PoC 验证清单与结论

## 前置
- [x] `./tools/download_models.sh` 下载 comic-text-detector 成功（sha256 校验通过，90.3M，`1a86ace7…d718f`）
- [x] manga-ocr 现成 ONNX 权重下载到 assets/models/manga-ocr/ 与 tools/translation_service/models/manga-ocr/（**双文件** encoder_model.onnx 327.5M + decoder_model.onnx 112M，来自 `mayocream/manga-ocr-onnx`；未走 optimum 本地导出，见结论）
- [x] `flutter pub get` 成功
- [x] `cd tools/translation_service && npm install` 成功

## 单元测试（纯算法，无需模型）
- [x] `flutter test test/data/translation/` 全绿（10/10）
- [x] `cd tools/translation_service && node --test decode.test.js` 全绿（4/4）；`node --check extractor.js` 通过

## Native 链路（macOS 优先，其次 Android/iOS）
- [~] 代码就绪、与 web 链路逐点等价、`flutter analyze` 无问题；未做交互式 GUI 手动跑通（`flutter run -d macos` 需人工驱动 ImagePicker 选图，无法 headless）
- 关键风险已从源码层面排除：查 flutter_onnxruntime-1.8.3 源码确认 OrtValue 是按 `valueId`(String) 索引原生全局 value store 的轻量句柄，与产生它的 session 无关，故 encoder 输出的 `last_hidden_state` 可直接喂 decoder.run（跨 session 复用合法）
- 记录：检测到区域数 = 待手动确认（预期与 web 一致 ≈185），单图总耗时 = 待手动确认 ms，内存峰值 = 待手动确认 MB
- 识别文字肉眼质量（对/大致对/错）= 待手动确认（web 侧同代码逻辑+同模型为“大致对”）

## Web 链路
- [x] 推理服务在 9091 启动成功（loadModels 加载 detector+ocrEncoder+ocrDecoder 三 session 无错，GET /health 返回 `{"ok":true}`）
- [x] `curl -F image=@/tmp/opencode/manga_test.png http://127.0.0.1:9091/extract` 返回 regions
- [x] 记录：区域数 = **185**，单图耗时 = **~15100** ms，识别质量 = **大致对**（真实日文如 優し/そう/坂本/ねえ，CRLF 修复后无尾部回车）

## 结论（回填）
- comic-text-detector 后处理是否需要更复杂的 NMS/seg 解码？= **是（部分）**。当前 seg 分割图直接连通块（BFS 洪泛）+ 外接框可跑通，但存在**过度分割**：单张页面产出 185 个极小 region（每个 1-2 字），未按对话气泡聚合。正式实现需加气泡聚合/形态学 dilation（把邻近字符区域合并成整块气泡）再喂 OCR。
- manga-ocr 单 model.onnx vs encoder/decoder 双文件，实际用了哪种？= **encoder/decoder 双文件**。现成 ONNX 权重（VisionEncoderDecoder 架构）导出为 `encoder_model.onnx`（input `pixel_values`[1,3,224,224] → `last_hidden_state`[1,197,768]）+ `decoder_model.onnx`（inputs `input_ids`[1,seq]int64 + `encoder_hidden_states`[1,197,768] → `logits`[1,seq,6144]）。计划原假设的单 model.onnx 不成立，native/web 两侧均已改为 encoder→decoder 两步串联（见纠偏记录③）。
- 各平台是否达到可接受耗时（目标 < 3s/页）？= **否（当前）**。web 单图 ~15s，主因是过度分割导致 185 次 OCR 贪婪解码（每次 encoder+多步 decoder，无 KV cache 的 O(n²) 解码）。目标耗时依赖上一条的气泡聚合把 region 数降到 ~10-20，并加 OCR KV cache。链路本身正确，性能属优化项。
- 是否推荐进入正式翻译主体实现？= **推荐**。PoC 已验证 comic-text-detector + manga-ocr 双模型在 native（进程内 ONNX，源码层确认 OrtValue 跨 session 可复用）与 web（Node+onnxruntime-node）两链路均能真实跑通并产出正确日文原文，最大技术不确定性（本地推理可行性、模型选型、双文件串联）已消除。进入正式实现前需先解决：①气泡区域聚合（降 region 数、提耗时）②OCR 解码 KV cache ③（正式阶段）接 core/ai LLM 翻译 + UI 叠加渲染 + 缓存。

## 对计划的纠偏记录（实现期间发现并修正的计划文件缺陷）
以下是执行 PoC 及本地验证期间发现的、计划文件本身的缺陷，已在对应 commit / 验证轮修正，实现的代码与计划文本略有偏离，属有意纠偏：

- **Task 8 — Web extractor 裁剪框上界 clamp**（commit `50cde98`）：计划中 `tools/translation_service/extractor.js` 的 `extractRegions` 只对裁剪框做了下界 `Math.max(1, ...)`，遗漏了 Dart 版 `native_poc_extractor.dart` 里有的上界 clamp。贴边文字框会使 `sharp().extract(...)` 抛 `extract_area: bad extract area`。已改为 `const ow = Math.max(1, Math.min(Math.round(b[2] * scaleX), meta.width - ox)); const oh = Math.max(1, Math.min(Math.round(b[3] * scaleY), meta.height - oy));`，与 Dart 的 `.clamp(1, decoded.width - ox)` 语义一致。
- **Task 9 — run_web.sh 翻译服务 PID 捕获**（commit `58355f5`）：计划中 `(cd "$TRANSLATION_DIR" && node server.js &)` 在子 shell 内后台启动 node，父 shell 的 `TRANSLATION_PID=$!` 捕获不到 node 的真实 PID，退出时无法 kill，导致 9091 端口进程泄漏。已改为 `(cd "$TRANSLATION_DIR" && exec node server.js) &`，并把 `TRANSLATION_DIR` 由相对 `$(dirname "$0")` 改为与文件其余处一致的绝对 `$SCRIPT_DIR`。
- **本地验证轮 — manga-ocr 单文件→双文件串联 + detector 输出头 + vocab CRLF**（native `native_poc_extractor.dart` + web `tools/translation_service/extractor.js`，本轮修改）：
  1. **OCR 双文件串联**：计划假设 manga-ocr 是单 `model.onnx`（image+token_ids→logits），实际现成 ONNX 是 encoder/decoder 双文件。两侧 `loadModels()` 改为建 encoder+decoder 两 session；OCR 改为先跑 encoder(`pixel_values`→`last_hidden_state`) 一次、再喂 decoder 贪婪循环(`input_ids`+`encoder_hidden_states`→`logits`)；资产路径由 `manga-ocr/model.onnx` 改为 `manga-ocr/encoder_model.onnx`+`manga-ocr/decoder_model.onnx`。
  2. **detector 按名取 seg 输出**：detector 有三个输出头 `blk`/`seg`/`det`，计划代码取 `outputNames.first`（=`blk`[1,64512,7]）是错的，应取分割图 `seg`[1,1,1024,1024] 喂连通块后处理。两侧改为按名取 `seg`（native `detOut['seg']!`，web `detOut.seg.data`）。
  3. **vocab 去 CRLF**：`vocab.txt` 为 CRLF 文件，`split('\n')` 后每 token 尾部残留 `\r` 混入识别输出。两侧改为 split 后 map 去掉每行 `\r`（native `.replaceAll('\r','')`，web `.replace(/\r/g,'')`）。

## 已知限制 / 后续改进项
- **过度分割**：seg 连通块按字符拆开，单页 ~185 个 region，非按对话气泡分组。正式阶段需气泡聚合/形态学 dilation。
- **OCR 解码性能**：贪婪解码无 KV cache，O(n²)；region 数多时耗时显著（web 单页 ~15s）。
- **native GUI 未交互式跑通**：代码就绪且与 web 等价、源码层确认可行，但未手动在 macOS 上选图跑通完整链路。
