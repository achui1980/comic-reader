# 漫画翻译功能总开关设计

日期：2026-08-18
分支：`feat/manga-translation-poc`
状态：设计已确认，待生成实施计划

## 背景

漫画翻译功能（本地 ONNX 气泡检测 + manga-ocr + LLM 翻译）已在本分支完成后端管道与阅读器 UI 集成，但存在两个可用性问题：

1. **功能入口无条件暴露**。阅读器顶栏的 translate 按钮对所有用户可见，而该功能需要用户自备 AI API Key、下载约 460MB ONNX 模型、单页翻译约 10 秒。多数用户点下去只会得到一个红色错误角标。
2. **模型下载入口只存在于 debug 构建**。`settings_screen.dart` 里那个 `if (kDebugMode)` 包裹的「翻译管道调试页（临时）」是唯一能触发 `TranslationModelManager.downloadAll()` 的地方。release 构建的用户没有任何途径下载模型。

本设计引入一个默认关闭的全局功能总开关，并把模型下载与相关维护操作迁移到正式的设置页路径，让翻译功能成为一个「用户主动启用的重量级可选功能」。

## 目标与非目标

**目标**
- 新增持久化的全局开关，默认关闭；关闭时阅读器顶栏 translate 按钮完全不渲染，功能对普通用户隐身。
- 提供正式（非 debug）的模型下载入口，含进度显示与失败重试。
- 模型下载支持字节级断点续传，避免弱网下重下 327MB 的 encoder。
- 提供「清空翻译缓存」维护操作。

**非目标（YAGNI）**
- 不做模型删除/卸载功能。
- 不做通用 feature flag 注册表（仓库无此先例，当前只有一个功能需要开关）。
- 不做阅读器内的「去下载模型」引导对话框。
- 不改动 `vertical_reader.dart` 与两个 `TranslationOverlayPainter`。
- 不改变翻译管道本身的行为（串行队列、epoch 守卫、缓存策略、prompt 全部不动）。
- 不移除 `kDebugMode` 调试页入口（保留作为开发工具）。

## 已否决的替代方案

| 方案 | 否决理由 |
|---|---|
| 只加开关，不动模型下载入口 | 用户打开开关后在 release 构建里依然无法下载模型，点翻译只得到红色错误角标——等于开了一扇通往死路的门。 |
| 通用 feature flag 体系 / `TranslationSettings` 子对象 | YAGNI。仓库惯例是「一个 bool 进 `AppSettings` + 一个 cubit setter + 一个 SwitchListTile」，无集中式 flag 注册表先例。 |
| 只把阅读器内的 translate toggle 持久化 | 方向相反。`ReaderState.translationEnabled` 现状已是默认 false 且不持久化，问题不在这一层。 |
| 用 `kDebugMode` 包住 translate 按钮，零设置项 | release 用户完全无法使用该功能，等于放弃已实现的功能。 |

---

## 1. 数据层与命名

开关字段放 `AppSettings`（`lib/data/local/settings_store.dart`）而非 `AiConfig`。理由：`AiConfig` 的语义是「AI 通道凭据与端点」，本开关是用户偏好，同 `adultUnlocked` / `showPageNumber`，且走 `LocalStorage` 无需 SecureStore。

命名必须避开与现有 `ReaderState.translationEnabled` 的混淆，三层职责如下：

| 层 | 字段名 | 语义 | 持久化 |
|---|---|---|---|
| `AppSettings` | `mangaTranslationEnabled` | 功能总开关，控制入口是否存在 | 是（`settings` key） |
| `ReaderState` | `translationEnabled` | 本章翻译是否进行中（现有字段，不改名） | 否 |
| `ReaderState` | `translationFeatureEnabled` | 总开关的镜像，供 widget 读取 | 否（ReaderBloc 构造时从 store 拷入） |

**改动点**

`lib/data/local/settings_store.dart` 5 处，与相邻的 phase-2 布尔字段完全同构：
1. 字段声明 `final bool mangaTranslationEnabled;`
2. const 构造默认 `this.mangaTranslationEnabled = false,`
3. `copyWith` 参数 + `mangaTranslationEnabled ?? this.mangaTranslationEnabled`
4. `toJson` 加 `'mangaTranslationEnabled': mangaTranslationEnabled,`
5. `fromJson` 加 `mangaTranslationEnabled: json['mangaTranslationEnabled'] as bool? ?? false,`

`lib/presentation/settings/bloc/settings_cubit.dart` 新增三行 setter，与 `setShowPageNumber` 同构（乐观 `emit` 后 `save`，无副作用）：

```dart
Future<void> setMangaTranslationEnabled(bool value) async {
  final updated = state.settings.copyWith(mangaTranslationEnabled: value);
  emit(state.copyWith(settings: updated));
  await _settingsStore.save(updated);
}
```

**不加** `SettingsState` shortcut getter——沿用 phase-2 字段的惯例，UI 里直接写 `state.settings.mangaTranslationEnabled`。JSON key 即字段名（camelCase）。

---

## 2. 设置 UI

### 2.1 入口 section

新文件 `lib/presentation/settings/sections/translation_section.dart`，标准 section 骨架（`StatelessWidget`，签名 `({super.key, required this.state})`）：

- `buildSettingsSectionHeader('漫画翻译')`
- 单个跳转 `ListTile`：`leading: Icon(Icons.translate)`、`title: '漫画翻译'`、`subtitle` 根据 `state.settings.mangaTranslationEnabled` 显示「已启用」/「未启用」、`trailing: Icon(Icons.chevron_right)`、`onTap` 推 `TranslationSettingsScreen`
- `Divider()`

完全照 `ai_section.dart` 的写法，用原生 `Navigator.of(context).push(MaterialPageRoute(...))`，不走 go_router。

插入位置：`settings_screen.dart` 的 `AiSection()` 之后、`PluginSection` 之前，并用 `if (!kIsWeb)` 包住整个 section。Web 端 `TranslationCacheStore` 全 no-op、`NativeMangaTextExtractor` 依赖 `dart:io`，功能跑不起来，隐藏整个 section 比让用户开一个无效开关更诚实（同 `data_management_section.dart` 对备份/恢复的做法）。

### 2.2 二级页

新文件 `lib/presentation/settings/translation_settings_screen.dart`，`StatefulWidget`（需本地持有模型状态与下载进度）。

与 `AiSettingsScreen` 刻意不同：**不做「本地暂存 + 顶部保存按钮」，开关即时生效**。`AiSettingsScreen` 用暂存是因为要一次提交 5 个字段（含 API Key）；本页只有一个布尔，走 `SettingsCubit` 的即时落盘语义更自然。

页面结构：

```
AppBar: 漫画翻译

SwitchListTile 启用漫画翻译
  subtitle: 开启后，竖向滚动阅读时顶栏会出现翻译按钮
  value:     state.settings.mangaTranslationEnabled   (BlocBuilder<SettingsCubit, SettingsState>)
  onChanged: cubit.setMangaTranslationEnabled

── 以下子项仅在开关打开时显示 ──
   （照 reading_section.dart 里 autoPageTurn 联动子项的先例）

buildSettingsSectionHeader('翻译模型')
  ListTile 模型状态
    subtitle: 检测中… / 已就绪 / 未下载（约 460MB） / 无法检测（$e）
    trailing: 已就绪 → Icon(Icons.check_circle, green)
              未下载 → TextButton「下载」（失败后文案变「重试下载」）
              下载中 → 百分比文字
    下载中额外一行 LinearProgressIndicator

buildSettingsSectionHeader('AI 服务')
  ListTile AI 设置
    subtitle: 已配置 / 未启用或未填 API Key      (读 AiConfigStore)
    trailing: Icon(Icons.chevron_right) → AiSettingsScreen

Divider
ListTile 清空翻译缓存（红色文字）
```

模型状态检测与下载走 `GetIt.instance<TranslationModelManager>()`（`injection.dart` 已注册）的 `isReady()` / `downloadAll(onProgress:)`。AI 配置状态读 `GetIt.instance<AiConfigStore>()`，判据是 `AiConfig.isUsable`（`enabled && apiKey.trim().isNotEmpty`）。

### 2.3 对 `lib/data/translation/` 的改动

本设计只碰两个文件：

- `translation_cache_store.dart`：新增 `clearAll()`（见 4.3）
- `translation_model_manager.dart`：`downloadAll` 加断点续传（见 4.1）

---

## 3. Reader 侧 gate

### 3.1 状态镜像

`ReaderState` 新增 `translationFeatureEnabled`，默认 `false`，改动位置与现有 `translationEnabled` 完全平行（字段声明 / 构造默认 / `copyWith` 参数 / `copyWith` 赋值 / `props`，共 5 处），放在同一个 `// --- Manga translation overlay ---` 注释块内。

`ReaderBloc._applySettings()` 的 `emit(state.copyWith(...))` 加一行：

```dart
translationFeatureEnabled: s.mangaTranslationEnabled,
```

不新增事件、不新增 handler。总开关只在 ReaderBloc 构造时读一次，生命周期与 `layoutMode` / `cropBorders` / `showPageNumber` 等 phase-2 字段一致。

### 3.2 按钮可见性

`reader_controls.dart` 的 `_TopBar` 新增构造参数 `required this.translationFeatureEnabled`，由 `ReaderControls` 传 `state.translationFeatureEnabled`。按钮条件从

```dart
if (layoutMode == LayoutMode.vertical)
```

改为

```dart
if (translationFeatureEnabled && layoutMode == LayoutMode.vertical)
```

总开关放前：先判功能是否启用，再判当前布局是否支持。现有解释「横向模式为何隐藏」的注释保留，另加一行说明总开关。

### 3.3 纵深防御

`_onTranslateChapterToggled` 首行加：

```dart
if (!state.translationFeatureEnabled) return;
```

`TranslatePageRequested` 已有 `if (!state.translationEnabled) return;`，而 `translationEnabled` 只能由 `_onTranslateChapterToggled` 置 true，所以守卫一处即足。`TranslatePageRetried` 不加守卫——它只能由已存在的 error 角标触发，而角标存在即证明当时功能是开启的。

### 3.4 首帧空窗不处理

`_applySettings()` 是 `void ... async` 的 fire-and-forget，构造那一帧 `translationFeatureEnabled` 仍为 `false`。两个事实让这个空窗不可观察：

1. `ReaderState.showControls` 默认 `false`——进入阅读器时顶栏根本未渲染，用户必须先点击屏幕中央。
2. `SettingsStore.load()` 有内存缓存，且 App 启动时 `SettingsCubit.init()` 已读过盘，此次是缓存命中，`emit` 发生在构造后第一个 microtask。

方向也是安全的：空窗期的表现是「按钮不显示」而非「误显示」。

### 3.5 阅读中途改开关

不做实时同步。阅读器内部没有任何通往设置页的路径（`reader_controls.dart` 里唯一的 `context.push` 是「浏览器阅读」的 webview 路由）。用户改开关必须先退出阅读器，`ReaderScreen.dispose()` 会 close 掉 ReaderBloc，下次进入是全新 bloc + 全新 `_applySettings()`。

---

## 4. 错误处理与边界

### 4.1 模型下载：进度归属与断点续传

**进度状态放 `TranslationSettingsScreen` 自己的 State**（`_downloading` / `_receivedBytes` / `_totalBytes`），不做单例。`DownloadManager` 那种 `ChangeNotifier` 单例是为「离开页面后仍需继续、多任务并行、在别处查看进度」设计的；模型下载是一次性、用户守着看的、单任务，引入 GetIt 注册 + `main.dart` init 的成本更大。

**下载中不可退出**：`_downloading == true` 时用 `PopScope(canPop: false)` 拦住返回，同时禁用下载按钮。这直接消灭了 `downloadAll` 无互斥锁导致的双 sink 写同一文件的数据破坏风险（场景：下载中退出 → 进度丢失显示「未下载」→ 用户再点下载）。

**两级恢复能力**：

- *文件级跳过*（现有行为，不改）：`downloadAll` 对每个文件先判 `exists && length == sizeBytes`，命中则回调一次 100% 进度后 `continue`。所以任何中断后再点「下载」，已下完的文件不会重下。
- *字节级续传*（本设计新增）：`kTranslationModelFiles` 里 `encoder_model.onnx` 单体 327MB（decoder 112MB、yolo 6MB、vocab 30KB），弱网下断在 90% 若从头重下 300MB 是不可接受的。

续传实现：

1. 下载写到 `<name>.part`；失败时**保留** `.part`（现有代码是删除半成品，改为保留）。
2. 重试时读 `.part` 长度 N，请求带 `Range: bytes=N-`。
3. 服务器返 206 → `FileMode.append` 续写；返 200（不支持 Range）→ 丢弃 `.part` 从头写。
4. 长度达标后 `rename` 成正式文件名。
5. `isReady()` / `ensureReady()` 不受影响——`.part` 不在 `kTranslationModelFiles` 清单里，天然不算就绪。

HuggingFace 走 CloudFront，Range 支持良好。

**可测性权衡**：`downloadAll` 内部是裸 `io.HttpClient()`，不可注入。本设计**不**把 HttpClient 抽成构造参数（成本更小的选择），而是把「给定已有字节数 + 总字节数 → 决定跳过 / 续传 / 从头重下」抽成纯函数做单测，网络部分靠手工验证覆盖。

改动量估计：`translation_model_manager.dart` 约 +40 行，新增一个纯函数 + 3 个单测。

### 4.2 三类失败的呈现

| 失败 | 异常 | 呈现 |
|---|---|---|
| HTTP 非 200 / 网络断 | `StateError` / `SocketException` | SnackBar `'下载失败：$e'`，状态回落「未下载」，按钮变「重试下载」 |
| 磁盘写失败 | `FileSystemException` | 同上，不区分文案 |
| `isReady()` 自身抛（如异常沙箱下 `getApplicationDocumentsDirectory` 失败） | 任意 | 状态行显示「无法检测（$e）」，仍允许点下载 |

不做重试次数限制、不做指数退避——用户面前有明确的重试按钮，自动重试只会掩盖问题。

### 4.3 清空翻译缓存

`TranslationCacheStore` 新增 `clearAll()`：`kIsWeb` 直接 return；目录不存在时静默返回；`Directory.delete(recursive: true)` 包 try/catch，失败弹 SnackBar。

删除前走 `section_widgets.dart` 已有的确认对话框，文案说明「已翻译的页面需要重新调用 AI 翻译」。此操作**不清模型**。

### 4.4 关闭总开关时不做任何清理

模型留着、翻译缓存留着。开关语义是「暂时不用」不是「卸载」，重新打开应立刻可用。模型删除功能不做（YAGNI）。

### 4.5 开关打开但依赖未就绪

三种不完整状态——模型未下载 / AI 未配置 / 两者都缺（后者先撞 AI 校验，因为 `translatePage` 里 AI 判断在 `ensureReady()` 之前）——全部**允许开关处于打开状态**，只在二级页用状态行提示，不阻止开启。

阅读器侧走现有链路：`ModelNotReadyException` / `TranslationConfigException` → 红色 error 角标 → 点击出 SnackBar + 重试。阅读器侧**不新增任何引导 UI**（不弹「去下载模型」对话框）——引导入口就在开关旁边的二级页，而且不该把 460MB 下载塞进沉浸式阅读场景。这也让本次改动完全不触碰 `vertical_reader.dart` 和两个 painter。

---

## 5. 测试策略与验证

### 5.1 自动化测试

| 文件 | 新增 | 内容 |
|---|---|---|
| `test/data/local/settings_store_test.dart` | +1 group / 4 test | 照 `discoveryViewMode` 那组的四段套路：默认 `false` / `copyWith` 生效 / `toJson`→`fromJson` round-trip / `fromJson({})` 缺字段回退 `false` |
| `test/data/translation/translation_model_manager_test.dart` | +3 test | 续传决策纯函数：已有字节 == 总字节 → 跳过；`0 < 已有 < 总` → 续传（起始偏移 = 已有）；已有 > 总（脏 `.part`）→ 从头重下 |
| `test/data/translation/translation_cache_store_test.dart` | +2 test | `clearAll()` 删掉整棵 `translation_cache/` 后 `get()` 返 null；目录不存在时调用不抛 |
| `test/presentation/reader/bloc/reader_bloc_test.dart` | +2 blocTest | ① `SettingsStore.load()` 返 `mangaTranslationEnabled: true` → state 的 `translationFeatureEnabled` 变 true（需 `wait: Duration(milliseconds: 10)`，因 `_applySettings()` 是 fire-and-forget）；② 总开关为 false 时发 `TranslateChapterToggled(enabled: true)` → 不 emit、`verifyNever` pipeline 被调用 |

### 5.2 不写 widget test

`test/presentation/` 目前只有一个 `manga_card_test.dart`，`2026-08-10-manga-translation-reader-ui-design.md` 的测试策略段也明确把翻译 UI 排除在自动化之外。新增的 `translation_section.dart` / `translation_settings_screen.dart` 以及 `_TopBar` 的可见性 gate 都靠手工验证覆盖——gate 的核心逻辑已由 5.1 的 bloc 测试锁住，widget 层只剩一个布尔与运算。

### 5.3 手工验证清单

1. 全新安装（或删掉 `settings.json`）→ 设置页出现「漫画翻译」section，subtitle 显示「未启用」。
2. 竖向滚动阅读，点屏幕中央唤出控制层 → 顶栏**没有** translate 图标。
3. 二级页打开开关 → 退出并重新进入章节 → translate 图标出现。
4. 模型未下载时状态行显示「未下载（约 460MB）」+「下载」按钮；点下载后进度条走动、返回键被拦住。
5. 下载中断开网络 → SnackBar 报错、状态回「未下载」、按钮变「重试下载」→ 恢复网络点重试 → **进度从中断处继续**（百分比不回零）。
6. 下载完成 → 状态「已就绪」+ 绿勾；配好 AI Key → 阅读器点 translate → 气泡出现中文。
7. 关闭开关 → 重进阅读器按钮消失；再打开 → 模型仍显示「已就绪」、之前翻译过的页仍命中缓存。
8. 点「清空翻译缓存」→ 确认对话框 → 确认后重进已翻译过的页 → 重新调用 AI（loading 角标再次出现）。

### 5.4 静态检查

- `flutter analyze` 覆盖全部改动文件
- `flutter test test/data/local/ test/data/translation/ test/presentation/reader/`

---

## 附：文件改动清单

**新增（2）**
- `lib/presentation/settings/sections/translation_section.dart`
- `lib/presentation/settings/translation_settings_screen.dart`

**修改（8）**
- `lib/data/local/settings_store.dart`（`AppSettings` 5 处）
- `lib/presentation/settings/bloc/settings_cubit.dart`（+1 setter）
- `lib/presentation/settings/settings_screen.dart`（插入 section，`if (!kIsWeb)`）
- `lib/data/translation/translation_model_manager.dart`（断点续传 + 纯函数）
- `lib/data/translation/translation_cache_store.dart`（+`clearAll()`）
- `lib/presentation/reader/bloc/reader_state.dart`（新字段 5 处）
- `lib/presentation/reader/bloc/reader_bloc.dart`（`_applySettings` +1 行，`_onTranslateChapterToggled` +1 行守卫）
- `lib/presentation/reader/widgets/reader_controls.dart`（`_TopBar` 参数 + 可见性条件）

**测试修改（4）**
- `test/data/local/settings_store_test.dart`
- `test/data/translation/translation_model_manager_test.dart`
- `test/data/translation/translation_cache_store_test.dart`
- `test/presentation/reader/bloc/reader_bloc_test.dart`

**不改动**
`injection.dart`（相关单例均已注册）、`app.dart`（`SettingsCubit` 已全局 provide）、`main.dart`（无启动时副作用）、`vertical_reader.dart`、两个 `TranslationOverlayPainter`、`translation_pipeline.dart`、`manga_text_extractor.dart`、`reader_event.dart`。
