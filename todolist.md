# 花火（HanabiManga）优化清单

审查日期：2026-09-11 · 基线 commit：4207b9a · 测试基线：572/572 通过（第 1、2 项完成后 573/573）

> **移动端评估见文末「附：移动端（Android/iOS）可行性」**。结论：能跑（已实测构建 Android arm64 APK 成功），但第 3、4、7、8、9 项在手机上是**必然踩到**的，优先级高于桌面。

## P0 性能（解密链路全在 UI 线程）

- [x] **1. 图像解码/编码换 Flutter 原生（dart:ui / Skia）** — 已完成
  - 位置：`lib/data/repositories/hanabi_chapter_decryptor.dart`
  - 原状：`img.decodeImage`（package:image 纯 Dart WebP 解码）→ WASM → `img.encodePng`（纯 Dart zlib 压缩原始像素）→ `base64Encode`，三步全在主 isolate。
  - `chapter_image_pipeline.dart:404-450` 的 `maxConcurrent=4` 只并行网络，CPU 仍串行抢帧 → 翻页卡顿真正根因。
  - 实现：新增 `_decodeToRgba()`（`ui.ImmutableBuffer.fromUint8List` + `ui.instantiateImageCodecFromBuffer` + `toByteData(rawRgba)`）与 `_encodePng()`（`ui.ImageDescriptor.raw(rgba8888)` + `toByteData(png)`），均带 dispose；已移除本文件的 `package:image` 依赖。
  - **意外收获（正确性提升）**：新链路的输出 hash 精确等于 `9735c728f5…`，即当初逆向诊断时由 libwebp/Pillow 得出的原始 ground truth。旧的纯 Dart 解码器与 libwebp 不是 bit-exact（约 1.5% 像素有舍入偏差），task-7/task-9 当时是把断言改成了纯 Dart 的 `410f8598a9…`。现在测试断言重新变成真正的外部基准。

- [x] **2. 解密结果落盘，避免重复下载 + 重复 WASM 解密** — 已完成
  - 位置：`hanabi_chapter_decryptor.dart` + `chapter_image_pipeline.dart` `_resolveHanabiImages`
  - 原状：返回多 MB `data:` URI（`.superpowers/sdd/progress.md` 中记为 STILL OPEN 的架构缺陷），每次重进章节全量重算。
  - 实现：`decrypt()` 新增 `{mangaId, chapterId, imageIndex}` 与第 4 个可选位置参数 `ChapterCacheService`；命中 `getImageFile()` 直接返回 `file://` URI（零网络零 WASM），未命中则解密后 `saveImage(contentType:'image/png', scrambleType: none)` 并返回 `file://` URI；web/缺 identity 时回退原 `data:` URI。
  - 配套：`chapter_image_pipeline.dart` 两个调用点透传 mangaId/chapterId/index；`manga_repository_impl.dart` 新增可选命名参数 `chapterCache` 并在 `injection.dart` 注入单例；`manga_image.dart` 与 `manga_image_loader.dart` 各加 `file://` 分支（后者不加会让预加载用 HttpClient 请求 file:// 并失败 3 次）。
  - 测试：新增缓存命中回归测试（断言落盘字节是解密后的页、第二次调用不再走网络）。573/573 通过。


## P1 功能 bug

> 第 3、4 项是 **native-only 功能**（`ChapterCacheService` 与相册保存在 web 上是 no-op），所以桌面调试时不容易察觉，但在手机上是核心路径，必挂。**移动端应作为最高优先级。**

- [ ] **3. 花火/wu55 章节下载是坏的** 📱手机必踩
  - 位置：`lib/data/local/chapter_cache_service.dart:414-537` `downloadChapter`
  - 对每页无脑 `_dio.get(ImageProxy.url(url))`，而 `getChapter` 返回 `data:image/png;base64,...`（P0-2 完成后是 `file://`）→ dio 不支持这两种协议 → 每页 3 次重试后全部 failed。commit e30d8f4 只修了 `manga_image_loader` 的 precache 路径。
  - 改法：加 `data:` 分支（base64Decode 后直接 saveImage）**和 `file://` 分支**（若源文件已在缓存目标位置则直接跳过）。
  - 调用链：`download_manager.dart:276-291` → `_repository.getChapter()` → `_cacheService.downloadChapter(images: ...)`。

- [ ] **4. 长按保存到相册是坏的** 📱手机必踩
  - 位置：`lib/core/utils/save_image.dart` `saveImageToGallery`
  - 裸 `Dio().get(url)`，无 `data:` / `file://` 分支 → 花火与 wu55 保存必然失败。
  - 调用点：`manga_image.dart` 的长按菜单。

- [ ] **5. `extractHanabiChapters` 括号计数会崩**
  - 位置：`lib/data/sources/hanabi_manga.dart`（代码内自带 `KNOWN LATENT RISK` 注释）
  - 章节标题含字面量 `[` / `]` 会破坏 RSC flight payload 的深度计数。
  - 改法：改为带字符串状态的扫描（未转义 `"` 切换 inString，串内不计括号）。

- [ ] **6. 章节元数据被丢弃**
  - detail 页每个 chapter 是 `{id, title, idx, category, image_count, updated_at}`，`parseMangaInfo` 只用了 idx/title。
  - source description 声称「仅支持免费章节」，但用户要点进去才失败 → 用 `category` 过滤或标注付费；`updated_at` 可显示更新时间。

## P2 健壮性

- [ ] **7. `ensureLoaded()` 并发竞态** 📱手机代价更大
  - 位置：`lib/data/repositories/hanabi_wasm_unscrambler.dart`
  - `if (_instance != null) return;` 在 await 之前 → 4 路并发解密会各自下载并编译一次 WASM 模块，`_instance` 被覆盖、先前实例泄漏，`_libSetUp` 同理。
  - 手机上代价放大：4 次网络下载 + 4 次 `compileWasmModule`（macOS 实测单次 **90ms**，iOS/armv7 走 wasmi 解释器会更慢）+ 泄漏 3 个 WASM 实例的线性内存。
  - 改法：用 `Future<void>? _loading` 去重。

- [ ] **8. reader.wasm 每次冷启动重新下载且绕过 HttpClient** 📱手机必踩
  - 位置：`hanabi_wasm_unscrambler.dart:15` `_wasmUrl = 'https://web.hanabimanga.com/reader.wasm'`，`_downloadWasm()`（:91-98）用裸 `Dio()`。
  - 后果：不走项目代理设置 / CORS proxy / 超时 / 重试。手机网络下该域名不可达 → **花火完全不可用**，且叠加第 9 项后用户只看到花屏无提示。web 上大概率 CORS 失败。
  - 改法（推荐）：把 45KB 的 `reader.wasm` 打成 Flutter asset —— `test/fixtures/hanabi/reader.wasm` 已有现成文件，且 `WasmRunLibrary.setUp(isFlutter: true, loadAsset: rootBundle.load)` 已经接好 `rootBundle`。退一步：走项目 `HttpClient` 并落盘缓存（带长度或 ETag 校验）。

- [ ] **9. 解密失败静默返回乱码图** 📱手机必踩（配合第 8 项）
  - 只 `debugPrint` 后把原始乱码 WebP 抛给用户看花屏。应区分网络失败（可重试）与 WASM 失败，并给出可见提示。

- [ ] **10. 搜索分页 / 会话状态边界**
  - `items_per_page: 24` 硬编码且 `parseSearch` 不返回 hasMore（4207b9a 的 spinner 修复是 workaround）→ 用「返回条数 < 24 ⇒ hasMore=false」根治。
  - `needsSessionRefresh` 在 `_expiresAt == null` 时返回 false，而此时 `isAuthenticated` 也是 false → 冷启动只恢复 Cookie 未恢复 expiresAt 时会「既不刷新也不算已登录」。

## P3 移动端新增项（2026-09-11 实测发现）

- [ ] **11. PNG 缓存体积膨胀 10.3×，且 PNG 编码是新链路最慢的一步**
  - 位置：`hanabi_chapter_decryptor.dart` `_encodePng()`
  - 实测同一页 960×1372（`test/fixtures/hanabi/scrambled_page001.webp`）：

    | 格式 | 大小 |
    | --- | --- |
    | 原始 webp（站点下发） | 124,854 B |
    | 我们落盘的 PNG（dart:ui） | **1,301,858 B** |
    | Pillow PNG(RGBA) / PNG(RGB) 对照 | 1,281,117 / 1,181,492 B |
    | Pillow JPEG q90 对照 | 245,344 B |

  - 单章 15 页 ≈ **19.5MB 落盘**（原图约 1.9MB）。耗时上 `_encodePng` **111ms**，对比解码 13ms、unscramble 6.3ms —— 是整条链路的双重瓶颈。
  - 权衡（需拍板，故未动手）：`dart:ui` 只能编 PNG / rawRgba。要 JPEG 得用 `package:image` 的 `encodeJpg`（纯 Dart，慢，等于把刚砍掉的 CPU 开销加回来）或引入 `flutter_image_compress` 之类原生插件（新依赖）。也可以选择接受现状。

- [ ] **12. 移动端把 `maxConcurrent` 从 4 降到 2（OOM 防护）**
  - 位置：`lib/data/repositories/chapter_image_pipeline.dart` `_resolveHanabiImages` 的 `const maxConcurrent = 4`
  - 每页 RGBA = 5,268,480 B，一次解密过程中同时存在约 4 份拷贝（Dart 输入 / WASM 线性内存 / WASM 输出 / 拷回 Dart）≈ **21MB/页** → 4 路并发瞬时 **~84MB**。再叠加 PNG buffer 与 Flutter `ImageCache`（默认 100MB，每页解码后又占 5.27MB，约 19 页就填满）。
  - 3–4GB 内存的低端 Android 机器有被系统杀掉的风险。改法：按 `defaultTargetPlatform`（或直接 `!kIsWeb && (Platform.isAndroid || Platform.isIOS)`）降为 2。

---

## 附：移动端（Android/iOS）可行性

**结论：能跑。WASM 运行时在移动端可用，已实测验证。**

### 已验证的事实

- `flutter build apk --debug --target-platform android-arm64` **构建成功**（318s）；`unzip -l` 确认 APK 内含 `lib/arm64-v8a/libwasm_run_dart.so`（7,392,560 B）。
- `wasm_run` 的动态库不是靠 CMake 编译的（`wasm_run_flutter/android/CMakeLists.txt` 几乎为空、`ios/Frameworks/` 只有 `.gitkeep`），而是靠 **Dart native assets build hook**（`wasm_run-0.2.0+2/hook/build.dart`，`BuildModeEnum.fetch`）在构建时从 GitHub Release 下载预编译产物，带写死的 sha256 清单：
  `https://github.com/juancastillo0/wasm_run/releases/download/wasm_run-v0.2.0/wasm_run_dart-dynamic-<target>`
- 已用 GitHub API 确认该 release 的 15 个产物齐全，含 `aarch64-linux-android`(9.88MB)、`armv7-linux-androideabi`(3.00MB)、`x86_64-linux-android`(4.29MB)、`i686-linux-android`(4.34MB)、`aarch64-apple-ios`(3.38MB)、ios-sim、`x86_64-apple-ios`。
- 本机 Flutter 3.41.6 的 `--enable-native-assets` **默认开启**，hook 自动运行。
- 运行时库解析（`wasm_run/lib/src/ffi/io.dart` `createLibraryImpl()`）：iOS/macOS 先试 `ExternalLibrary.process()` 再 fallback `libwasm_run_dart.dylib`；**Android 走 `open('libwasm_run_dart.so')`**，靠 APK 内 jniLibs 名字解析，已就位。失败会报 `WasmRun library not found. Did you run 'dart run wasm_run:setup'?`

### 引擎差异（来自 `wasm_run/build_binaries.config.yaml` 的 outputs 段）

| 平台 | 引擎 | 单页 unscramble 估算 |
| --- | --- | --- |
| Android arm64 | wasmtime **JIT** | ~6ms（macOS 实测 6.3ms） |
| Android armv7 / x86_64 / i686 | wasmi **解释器** | ~130–300ms |
| iOS（全部 target，含模拟器） | wasmi **解释器** | ~130–300ms |

代码里 `ModuleConfig(wasmi: ..., wasmtime: ...)` 同时给了两套配置，两种引擎都能跑。iOS 因为系统不允许 JIT 只能用解释器，慢但可接受。Android arm64 的 wasmtime JIT 需要可执行内存映射（与 V8/ART 同类，应用进程允许，风险低）。

### 已实测性能基线

macOS（M 系，wasmtime JIT），固定输入 `test/fixtures/hanabi/scrambled_page001.webp`（960×1372，RGBA 5,268,480 B），cols=rows=4：

| 步骤 | 耗时 |
| --- | --- |
| `ensureLoaded`（`compileWasmModule`，不含下载） | 90ms |
| webp → rawRgba（`ui.instantiateImageCodecFromBuffer`） | 13ms |
| `unscramble`（WASM） | **6.3ms/页** |
| `_encodePng`（`ui.ImageDescriptor.raw` + `toByteData(png)`） | **111ms** ← 瓶颈 |

### 尚未验证 / 注意事项

- ⚠️ **花火从未在真机上实际运行过**。`flutter devices` 只有 macOS 与 Chrome，无 Android/iOS 设备。`.dart_tool/flutter_build` 里唯一的 Android 构建目录日期是 **8/19**（早于花火 9/11），其 `native_assets.json` 是 `{}`，无参考价值。**iOS 侧完全未构建验证。**
- 首次 Android 构建会自动下载安装 **NDK 21.4.7075529 + SDK Platform 31**（`wasm_run_flutter/android/build.gradle` 写死 compileSdk 31 / ndkVersion 21.4.7075529 / minSdk 16）。
- 构建**硬依赖 GitHub Release 可达** —— 国内 CI / 无梯子环境大概率卡在下载步骤。
- 包体积：全 ABI 发布时 wasm_run 增加约 **15MB**（arm64 7.4 + armv7 3.0 + x86_64 4.3）。只发 arm64 可规避。
- debug APK 162MB（其中 libonnxruntime.so 19MB、libflutter.so 37MB、VkLayer 15MB 属 debug 固有，release 会大幅缩小）。

### 移动端建议修复顺序

1. **第 3 + 第 4 项** — 下载 / 保存相册在手机上是坏的，且是手机专属功能
2. **第 8 + 第 7 项** — 一起改，同一文件（reader.wasm 打包成 asset + 竞态去重）
3. **第 9 项** — 失败要给用户可见反馈
4. **第 12 项** — maxConcurrent 降为 2
5. 第 11 项 PNG 体积 —— 需先拍板技术取向

