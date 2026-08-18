# Comic Reader 产品化路线图

> 目标：从「31 源多平台漫画聚合器」演进为**正式产品**，核心方向 = 跨源聚合智能 + 成人内容激活码门禁 + AI 功能（BYOK）。
> 本文档是执行清单，逐条完成后勾选。仍未开始的项标 `[ ]`，完成标 `[x]`。

> **并行计划**：`docs/plans/2026-08-11-mihon-gap-improvement-plan.md` 是对标 mihon 后产出的**工程质量与书架体验**补齐计划（阶段 0 CI gate / 阶段 1 四个 bug / 阶段 2 书架排序筛选 / 阶段 3 未读徽章，共 12 项）。它与本文档 #22/#23 是**并列关系**，不是替代：本文档管产品方向，那份管工程债与书架基础体验。两处交集见 #23 与「执行约定」下的注。

## 已定案的关键决策

| 决策项 | 选择 | 理由 |
|---|---|---|
| AI 后端 | **BYOK（用户自带 API Key）** | 零成本、零后端、上架最简单；付费代理后端可后续加 |
| AI 首发形态 | **① 自然语言搜索/推荐 + ② 智能元数据/标签归一化** | 都直接服务跨源聚合主线，复用同一 LLM 通道，ROI 最高 |
| AI 功能A 意图解析 | **LLM 只做关键词/标签/意图抽取，零幻觉** | 真实作品永远来自源抓取，LLM 不直接推荐具体作品名 |
| 激活码验证 | **先本地算法（签名/HMAC/Ed25519），预留远程接口** | 无需服务器即可上线；后续要吊销/统计再接远程 |
| 安全存储 | **flutter_secure_storage（native）+ web 端 encrypt AES 降级** | 激活码 token / BYOK key 不能明文存储 |

## 架构约束（务必遵守）

- **源是纯函数**：`prepare*Fetch()` 构建 `FetchConfig`（无网络 IO），`parse*()` 解析响应。源永不碰 `HttpClient`。
- **单一网络出口**：所有请求走 `HttpClient.execute(FetchConfig)`（`lib/data/remote/http_client.dart:26`）。AI 请求也复用它，自动继承超时/重试/代理。
- **唯一成人门禁点**：`SourceRegistry.enabled` getter（`source_registry.dart:33-39`）。激活后调 `registry.setAdultUnlocked(true)`。
- **手动 DI**：新服务在 `lib/app/di/injection.dart` 手动注册（injectable 未启用）。
- **Web 网络**：所有请求被强制走 `localhost:9090` CORS 代理，AI/外部 API 域名需放行。
- **本地持久化**：native = app-docs JSON 文件；web = localStorage（前缀 `comic_reader_`）。均**明文未加密**。

---

## 依赖关系（顺序不可随意打乱）

- `#1 → #2`：SecureStore 先有才能迁移敏感数据
- `#1 → #9 / #12`：激活码 token、AI key 都依赖安全存储
- `#5/#6 → #15`：AI 功能A 依赖跨源搜索
- `#17 → #18`：altTitles 先有才好做 WorkGroup 匹配

同一优先级内、无依赖的项可并行。

---

## P0 · 产品化基线（阻塞后续）

- [x] **#1 安全存储层**
  - 加依赖 `flutter_secure_storage: ^9.x`
  - 新建 `lib/data/local/secure_store.dart`（仿 `local_storage.dart` 抽象 + 条件导入模式）
    - `secure_store_io.dart`：`FlutterSecureStorage`（Keychain/Keystore）
    - `secure_store_web.dart`：`encrypt` AES 加密后写 localStorage（前缀 `comic_reader_sec_`），密钥由设备指纹派生
  - API：`read(key)` / `write(key,value)` / `delete(key)`
  - `injection.dart` 注册单例
- [x] **#2 敏感数据迁移到 SecureStore**
  - `auth_store` per-source cookie/token 已迁移：写走 SecureStore（key `auth`，JSON 编码），init 优先读 SecureStore → 回退旧明文 LocalStorage → 迁移后删明文
  - `AuthStore` 构造增加可选 `secureStore` 参数（默认 `SecureStore()`），injection.dart 注入 `getIt<SecureStore>()`
  - BYOK API key / 激活码 unlockToken 待 #12/#9 写入时直接用 SecureStore（迁移约定已确立：secure→明文回退→迁移→删明文）
- [x] **#3 修 `test/widget_test.dart`**
  - `pumpWidget` 前先 `await configureDependencies()` 注册 GetIt
  - 已完成:setUp 中 `GetIt.instance.reset()` + `configureDependencies()`,断言改为 `find.byType(MaterialApp)` findsOneWidget;单 `pump()`(不 pumpAndSettle 避免 async 挂起)。tearDown reset。flutter test 通过。
- [x] **#4 repository 核心 pipeline 单测**
  - 新建 `test/data/repositories/manga_repository_impl_test.dart`
  - mock `HttpClient` + `SourceRegistry`，测 `searchManga` dispatch / `_mergeHeaders` 注入
  - 已完成:`MockHttpClient extends Mock implements HttpClient` + 真实 `SourceRegistry` 注册 `_FakeSource`(非 JmComic/Wu55Comic→走普通 execute 单次路径)。4 测例:(a)dispatch 返 parseSearch 结果 + execute 调一次;(b)source not found→throwsA;(c)captureAny 断言 extra['sourceId']/['needsCloudflare'] + defaultHeaders/config.headers 合并;(d)usesWebViewFetch+cloudflareUrl→extra['useWebViewFetch']/['cloudflareUrl'] 注入。setUpAll registerFallbackValue(FetchConfig(url:''))。analyze + test 全通过(+4)。

---

## P1 · 三大核心功能

### 跨源聚合搜索（不动 source 契约 / repository，改动集中在 cubit 层）

- [x] **#5 改 `search_state.dart`**
  - 新增 `SourceSearchSlice`（per-source：`sourceId / results / currentPage / hasMore / status / error`）
  - `SearchState` 新增 `Map<String,SourceSearchSlice> slices` + `bool aggregateMode` + `aggregatedResults` getter
  - **保留** 原 `sourceId/results` 字段（单源模式向后兼容）
- [x] **#6 改 `search_cubit.dart`**
  - 新增 `searchAll(keyword)`：`registry.enabled` 扇出 + `Future.wait` 并发 `searchManga` + 单源失败只标记该 slice.error 不阻塞
  - 新增 `loadMoreSource(sourceId)`：仅对某源翻页
  - `_normalizeTitle`：去空格/大小写/全半角，用于去重（为 WorkGroup 打基础）
- [x] **#7 改 `search_screen.dart`**（聚合/单源 SegmentedButton 切换；聚合模式按源分组 `_SourceGroup`：源名+计数/loading小转圈/error+重试按钮 retrySource/加载更多 loadMoreSource；单源模式保留原选择器+列表；提交按 aggregateMode 选 searchAll vs search。analyze 通过）
  - 顶部「聚合/单源」切换；聚合模式按源分组展示 + 各源 loading/失败态 + 单源重试
  - 保留现有单源选择器入口
- [x] **#8 新增 `search_cubit_test.dart`**（13 测例全通过：searchAll 扇出/空keyword no-op/无启用源报错/per-source firstPage；单源失败不阻塞其他+retrySource；dedup 折叠同作品(全半角+大小写)、保留不同作品、同名不同作者不折叠；loadMoreSource 翻页+重复页停止；成人门禁 registry.enabled 锁/解锁。MockMangaRepository+真实 SourceRegistry+_FakeSource(id/isAdult/firstPage)）
  - 测扇出/合并/去重/单源失败不阻塞

### 成人内容激活码门禁

- [x] **#9 ActivationService 本地验签**
  - `AppSettings` 加 `unlockToken`（存 SecureStore）
  - 新建 `ActivationService.verify(code)`：本地验签（Ed25519/HMAC，app 内置公钥）→ 成功写 token
- [x] **#10 接入门禁钩子**
  - 验证成功 → `registry.setAdultUnlocked(true)`
  - `main.dart:97` 启动读 token 决定解锁
  - 预留 `RemoteActivationValidator` 接口（先空实现走本地）
- [x] **#11 改 `settings_screen.dart` `_buildAdultSection`**
  - 开关改为「输入激活码」入口（dialog），错误提示 / 已激活态展示

### AI 功能（BYOK）

- [x] **#12 新建 `core/ai/` 三件套**（ai_config.dart: AiProvider openai/gemini + AiConfig + AiConfigStore(apiKey→SecureStore, 其余→LocalStorage 'ai_config'); ai_client.dart: AiClient.chat 适配 OpenAI /v1/chat/completions + Gemini :generateContent; ai_service.dart: SearchIntent/AiMetadata + parseSearchIntent(#15)/normalizeMetadata(#16), 未配置降级; DI 三 lazySingleton; analyze No issues）
  - `AiConfig`：provider(openai/gemini/自定义) / apiKey(SecureStore) / baseUrl / model / enabled
  - `AiClient`：`chat(messages,{json})` → 组装 body → `FetchConfig(post)` → `HttpClient.execute` → 解析文本；provider body 差异在此适配
  - `AiService`：业务编排 / 缓存 / 降级
- [x] **#13 AI 设置页**
  - 填 provider/key/baseUrl/model，总开关；key 写 SecureStore
- [x] **#14 Web CORS 代理放行 AI 域名**
  - `cors_proxy_interceptor` 白名单直连，或 web 走 `fetch` 直连；验证 OpenAI/Gemini CORS
- [x] **#15 功能A 自然语言搜索**（SearchState 加 aiMode/aiInterpretation; SearchCubit 加 AiService? + setAiMode + submitQuery(query)：AI模式先 parseSearchIntent→primaryQuery 喂 search/searchAll，失败/未配置降级原文搜索; search_screen 加 _AiToggle + 解释横幅; 现有 13 测例仍通过; analyze No issues）
  - `AiService.parseSearchIntent(query)` → LLM 返回 `{keywords,tags,excludes}`（仅关键词抽取，零幻觉）→ 喂 #5/#6 跨源搜索
  - 未配置/失败 → 降级普通搜索，不阻断
- [x] **#16 功能B 智能元数据归一化**
  - `AiService.normalizeMetadata(detail)` → LLM 归一化标签 + 生成简介 + 提取原作名
  - 新建 `ai_metadata_store`（key = `${sourceId}_${mangaId}`）永久缓存，详情页展示

---

## P2 · 聚合深化

- [x] **#17 实体扩展 altTitles**
  - `MangaSummary` / `MangaDetail` 加 `altTitles(List<String>)`
  - 改每个源 parser 填充（能拿到原名的）
- [x] **#18 WorkGroup 分组层**
  - 新建 WorkGroup store：canonical work → `[(sourceId,mangaId)]`
  - title/author/altTitles 归一化匹配启发式（可叠加 AI 归一化结果）
- [x] **#19 同作品多源**
  - 详情页展示其他源同作品；某源失效自动切备用源阅读

---

## P3 · 体验 & 长期

- [x] **#20 统一 precache 与 byte-cache 路径**
  - `horizontal_reader._precacheAdjacent` 改走 `MangaImage` 同一 `HttpClient` byte-loader / `ChapterCacheService`
- [x] **#21 预测性预取**
  - 垂直 reader 加预取窗口；`reader_bloc` 加后台预取下一章（读当前章时提前拉下一章）
- [ ] **#22 i18n 基础设施**
  - 加 `flutter_localizations` + arb；`app.dart` 接 `localizationsDelegates`/`supportedLocales`
  - 外部化 `presentation/` 硬编码中文串（中/英至少）
- [ ] **#23 云同步 WebDAV**
  - 扩 `backup_service._storageKeys` 补 categories/auth/download_tasks/reading_timeline
  - 版本迁移 + merge 策略；包 WebDAV/坚果云（复用 export/import string 缝隙）
  - ⚠️ **第一条与 `docs/plans/2026-08-11-mihon-gap-improvement-plan.md` 阶段 1.2 重叠**。那份计划会先把 `_storageKeys` 补齐（categories / work_groups / ai_metadata / reading_timeline，并在恢复时清理孤儿 `categoryIds`），且明确**不加** `auth`（含凭据，走 SecureStore）和 `download_tasks`（本机瞬时状态）。做 #23 时按那份的结论走，只补版本迁移 + merge + WebDAV 传输层。
- [x] **#24 拆上帝文件**
  - `manga_image.dart`(730) / `settings_screen.dart`(719) / `manga_repository_impl.dart`(713)
  - 已完成（2026-07-29）：拆分为 `manga_image.dart`(313行)+4个新文件、`settings_screen.dart`(55行)+9个section文件、`manga_repository_impl.dart`(130行)+4个新文件（含 getChapter/getChapterStream 共用逻辑去重）
- [x] **#25 清理债务**
  - 修 3 处空 catch 加日志（`webview_fetcher_native.dart:474` / `local_storage.dart:18` / `backup_service.dart:61`）
  - 移除未用 injectable/build_runner；评估合并两图片库（cached_network_image + extended_image）
  - 已评估（2026-07-29）：`cached_network_image`（封面缩略图，唯一用点 `lib/presentation/common/manga_cover_image.dart`，核心是磁盘缓存+placeholder/imageBuilder/errorWidget 三段式声明）与 `extended_image`（阅读器大图，5个用点，核心是手势缩放 `ExtendedImageMode.gesture` + 本地文件/内存字节渲染 `ExtendedImage.file/.memory`）职责正交，无法合并为同一个库而不产生返工/体验回退。结论：维持现状，不合并。
- [x] **#26 依赖升级扫描**
  - flutter_bloc 9 / go_router 15 / flutter_lints 5 等，逐个验证不破坏
  - 已完成（2026-07-29）：flutter_lints 5.x / flutter_bloc 9.x / go_router 15.x

---

## 已知债务 / 风险速查

| 严重度 | 问题 | 位置 |
|---|---|---|
| 🔴 | 无 i18n，UI 全硬编码中文 | 遍布 `presentation/` |
| 🔴 | 敏感数据明文存储 | `local_storage_io/web.dart` |
| 🟠 | 测试覆盖 6/31 源，核心 pipeline/UI 零测试 | `test/` |
| 🟠 | 3 个上帝文件 | manga_image 730 / settings 719 / repository 713 |
| 🟠 | 阅读预取弱：垂直零预取；水平 precache 走错缓存路径 | `horizontal_reader.dart:124` |
| 🟡 | 3 处空 catch 静默吞错误 | webview_fetcher:474 等 |
| 🟡 | injectable/build_runner 引了没用；两图片库重叠 | pubspec |
| 🟡 | backup 漏 categories/auth/downloads/timeline | `backup_service.dart:13` |
| 🔴 | JSON 落盘非原子（无 tmp+rename+flush），写入中崩溃丢整个文件 | `local_storage_io.dart:22` |
| 🟠 | 章节分页中途失败会静默丢弃已累积的全部章节 | `detail_cubit.dart:115-117` |
| 🟠 | PR 无任何 CI 门禁（零 analyze / 零 test / 无 pull_request 触发） | `.github/workflows/` |
| 🟡 | `splitWidePages` / `cropBorders` 是死设置：可开关、能持久化、渲染层零引用 | `settings_store.dart:29,31` |

> 下半部分 4 条来自 `docs/plans/2026-08-11-mihon-gap-improvement-plan.md`（阶段 0/1 覆盖）。

---

## 执行约定

每条 TODO 完成需满足：
1. 实现代码
2. `flutter analyze <改动文件>` 通过
3. 相关测试通过（`flutter test <test 文件>`）
4. 勾选本文档对应项 + 更新 TODO 状态

> 第 2/3 条目前只是**口头约定**，没有任何 CI 强制（三个 workflow 都不跑 analyze/test，也没有一个由 `pull_request` 触发）。`docs/plans/2026-08-11-mihon-gap-improvement-plan.md` 阶段 0 会新增 `.github/workflows/ci.yml` 把这两条变成 PR 硬门禁。届时本节改为「CI 自动校验，本地可选预跑」。
