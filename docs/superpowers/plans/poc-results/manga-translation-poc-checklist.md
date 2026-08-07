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

## 对计划的纠偏记录（实现期间发现并修正的计划文件缺陷）
以下两处是执行 PoC 期间代码审查发现的、计划文件本身的缺陷，已在对应 commit 中修正，实现的代码与计划文本略有偏离，属有意纠偏：

- **Task 8 — Web extractor 裁剪框上界 clamp**（commit `50cde98`）：计划中 `tools/translation_service/extractor.js` 的 `extractRegions` 只对裁剪框做了下界 `Math.max(1, ...)`，遗漏了 Dart 版 `native_poc_extractor.dart` 里有的上界 clamp。贴边文字框会使 `sharp().extract(...)` 抛 `extract_area: bad extract area`。已改为 `const ow = Math.max(1, Math.min(Math.round(b[2] * scaleX), meta.width - ox)); const oh = Math.max(1, Math.min(Math.round(b[3] * scaleY), meta.height - oy));`，与 Dart 的 `.clamp(1, decoded.width - ox)` 语义一致。
- **Task 9 — run_web.sh 翻译服务 PID 捕获**（commit `58355f5`）：计划中 `(cd "$TRANSLATION_DIR" && node server.js &)` 在子 shell 内后台启动 node，父 shell 的 `TRANSLATION_PID=$!` 捕获不到 node 的真实 PID，退出时无法 kill，导致 9091 端口进程泄漏。已改为 `(cd "$TRANSLATION_DIR" && exec node server.js) &`，并把 `TRANSLATION_DIR` 由相对 `$(dirname "$0")` 改为与文件其余处一致的绝对 `$SCRIPT_DIR`。
