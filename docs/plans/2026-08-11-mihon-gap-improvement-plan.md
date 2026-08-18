# 对标 mihon 的改进计划（2026-08-11）

> 来源：对 [mihon](https://github.com/mihonapp/mihon) 跑 graphify 知识图谱后与 comic-reader 做功能/架构对比，经三轮代码核实产出。
>
> 状态：**待执行**。范围已收敛，四个阶段 12 个改动点，预计 4-6 天。**不引入数据库，不引入任何新 Dart 依赖。**

## 目录

- [背景与定位](#背景与定位)
- [阶段 0 — CI 质量门](#阶段-0--ci-质量门约半天1-个-pr)
- [阶段 1 — bug 修复](#阶段-1--bug-修复1-2-天拆-4-个-pr)
- [阶段 2 — 书架排序与筛选](#阶段-2--书架排序与筛选1-2-天1-2-个-pr)
- [阶段 3 — 未读计数徽章](#阶段-3--未读计数徽章1-2-天串行)
- [Web 的处置结论](#web-的处置结论)
- [依赖关系与 PR 拆分](#依赖关系与-pr-拆分)
- [明确不在本次范围](#明确不在本次范围)
- [附录 A：mihon 图谱要点](#附录-amihon-图谱要点)
- [附录 B：本计划依据的核实事实索引](#附录-b本计划依据的核实事实索引)

---

## 背景与定位

**目标形态已确认**：面向中文用户的开源项目，**不上架应用商店**。

这条定位直接决定了取舍：

| 项 | 结论 | 原因 |
|---|---|---|
| i18n（ROADMAP #22） | 低优先级 | 用户群是中文 |
| 成人内容分离构建变体 | 不需要 | 现有激活码门禁（`SourceRegistry.enabled`）已够，不上架就没有商店审核压力 |
| IPA 打包 / 使用文档 | 可提优先级 | 开源项目的分发与上手成本 |

mihon 有但**对 comic-reader 不适用**的东西（不要照搬）：

- **扩展 APK / Shizuku 安装器** — Flutter AOT 编译无法动态加载 Dart 代码，31 个源硬编码在 `lib/data/sources/` 是这个技术栈下的正确选择
- **baseline profile** — Android 专属的启动优化，多平台项目收益不成比例
- **telemetry + standard/FOSS 双构建变体** — 不上架就没有 Google Play 的 FOSS 合规诉求

comic-reader **领先于 mihon** 的地方（要保住，不要在重构中破坏）：

- 多平台（macOS / Windows / iOS / Android / Web），mihon 只有 Android
- 跳源聚合搜索 + WorkGroup 同作品多源分组（mihon 的 migration 是单向迁移，不是聚合）
- AI BYOK 三件套（自然语言搜索 + 元数据归一化）
- Cloudflare TLS 指纹绕过**内置在框架层**（`webview_fetcher_native.dart` 常驻无头 WebView 页内 fetch），源代码完全不用感知

---

## 阶段 0 — CI 质量门（约半天，1 个 PR）

### 现状

三个 workflow **没有任何一个**跑 `flutter analyze` 或 `flutter test`，**没有任何一个由 `pull_request` 触发**：

| 文件 | 触发 | 内容 |
|---|---|---|
| `.github/workflows/release.yml` | `workflow_dispatch` + `push: tags: v*` | 4 job，全部只构建不检查 |
| `.github/workflows/sync-gitee.yml` | `push: main` / `tags: v*` | 代码镜像 |
| `.github/workflows/sync-gitee-release.yml` | `release: published` | Release 附件同步 |

**PR 可以在零静态检查、零测试的情况下合并。** `ROADMAP.md:167` 只是口头约定人工跑 analyze。

### 0.1 先清 analyze（硬前置）

`flutter analyze` 实测（4.6s）：

```
244 issues = 237 info + 2 error
  237 在 test/     ← 全是那 10 个联网脚本
    2 在 lib/       ← 就两条 deprecated
```

| 问题 | 数量 | 位置 | 修法 |
|---|---|---|---|
| `avoid_print` | 233 | test/ 联网脚本 | 每个文件顶部加 `// ignore_for_file: avoid_print` |
| `undefined_identifier` + `expected_token` | 2 **error** | `test/verify_ehentai_chapter.dart:48` | 删掉写在函数体内的 `import 'dart:convert';` |
| `deprecated_member_use` | 2 | `lib/presentation/webview/webview_native.dart:150,153` | `onLoadError`→`onReceivedError`、`onLoadHttpError`→`onReceivedHttpError` |
| `depend_on_referenced_packages` | 1 | `test/verify_jcomic.dart:2` | `http` 在 `pubspec.lock:547-548` 是 transitive 未声明 → 改用 dio，或在 pubspec 声明 |
| `dangling_library_doc_comments` | 1 | — | 加空行或改 `//` |

**`lib/` 只有 2 个 info。约 30 分钟能把 244 清成 0。**

> **为什么不用 `continue-on-error` 先宽后严**：既然 30 分钟清得掉，就没必要留一个假门 —— 假门会一直是假门，没人会回来把它打开。
>
> 顺带一个白捡的收获：`verify_ehentai_chapter.dart:48` 那两个 error 是有人调试时把 `import` 写进了函数体（后面还跟着注释 `// Can't import above, let's use raw parsing`）。这文件**语法上就是坏的**，因为不叫 `_test.dart` 所以 `flutter test` 从不碰它，一直没人发现。上了 gate 才会暴露这类东西。

### 0.2 新增 `.github/workflows/ci.yml`

```yaml
on:
  pull_request:
  push:
    branches: [main]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '<pin 具体版本，对齐 pubspec sdk ^3.11.4>'
      - run: flutter pub get
      - run: flutter analyze      # 硬失败
      - run: flutter test         # 硬失败
```

三点说明：

1. **必须 pin flutter 版本。** 现有 3 处用 `channel: stable`（`release.yml:39/41, 121/123, 166/168`），上游发新版就可能突然红。CI gate 尤其不能这样。
2. **`dart format --set-exit-if-changed` 不进 gate。** 全仓从没格式化过，进 gate 会产生一个巨大的无意义 diff。想做就单独一个 PR 一次性格式化，之后再进 gate。
3. **`flutter test` 不会踩联网的雷**（已核实，见下）。不需要加 `@Tags` 或 `dart_test.yaml`。

#### `flutter test` 安全性核实

10 个联网脚本**全部不以 `_test.dart` 结尾**，而 `flutter test` 只 glob `test/**/*_test.dart`，所以它们不被收集、不编译、不执行：

```
test/check_jmc_chapters.dart      test/verify_hcomic.dart
test/test_cover_url.dart          test/verify_jcomic.dart
test/test_wu55_decrypt.dart       test/verify_jmc_api.dart
test/test_wu55_decrypt2.dart      test/verify_pica_images.dart
test/verify_ehentai_chapter.dart  test/verify_wu55comic.dart
```

32 个 `_test.dart` **全部离线**：

- 10 个数据源解析测试连 `dio`/`http` 都没 import，全是内联 HTML/JSON 喂 `parse*()` 或 `expect(config.url, ...)` 断言
- `app_update_service_test.dart:11` `MockHttpClient extends Mock implements HttpClient`，`:64,75,85,97,113` 全 `thenAnswer` 打桩
- `activation_service_test.dart:11-23` 手写 fake validator
- `manga_repository_impl_test.dart:12,17` MockHttpClient + `_FakeSource`
- `translation_model_manager_test.dart:46-51` 用 `Directory.systemTemp.createTemp` + baseDirResolver 注入

`widget_test.dart` 的 DI 问题**已经修好**（`:11-16` 有 `setUp` 做 `await GetIt.instance.reset(); configureDependencies();`，`:18-20` tearDown，`:24-26` 还特意注释了不用 `pumpAndSettle()` 避免 hang）。

### 0.3 顺手修 AGENTS.md 三处过期描述

| 位置 | 原文问题 | 事实 |
|---|---|---|
| `AGENTS.md:19` | 警告「`flutter test` 全跑会踩联网脚本」 | 因文件命名已自动失效，风险不存在 |
| `AGENTS.md:20` | 说 `widget_test.dart` 会失败 | 已修好 |
| `AGENTS.md:27` | 说 `manga_repository_impl.dart` "expands paginated chapter fetches" | **对章节列表是错的**。章节分页展开在 `detail_cubit.dart:84-107`，仓库层零展开；仓库层展开的是**图片页**（`chapter_image_pipeline.dart:288` `_expandPicaPages`，调用点 `:108/:209`） |

第三条会实质误导后来人，建议一起改。

---

## 阶段 1 — bug 修复（1-2 天，拆 4 个 PR）

### 1.1 摧掉两个死设置

`splitWidePages`（`settings_store.dart:31`）和 `cropBorders`（`:29`）：

- UI 可开关：`reader_enhancements_section.dart:81,87`
- 能持久化
- 能一路传进 `ReaderState`：`settings_cubit:91` → `reader_bloc:112` → `reader_state:88/124/156/187/247`
- **但 `horizontal_reader.dart` / `vertical_reader.dart` / `manga_image.dart` 零引用**

用户打开后不会有任何效果 —— 这是**可点、可保存、但完全不生效的 UI 假象**。

**决定：从 `reader_enhancements_section.dart` 摧掉这两个开关，保留 `AppSettings` 字段和整条传递链。**

- 保留字段 → 不破坏用户已有的配置文件
- 保留传递链 → 将来真正实现时不用重新接线
- `splitWidePages` 归到以后和双页模式一起设计（它本质是双页模式的一个子问题）

### 1.2 备份补齐 storage key

`backup_service.dart:13-18` 的 `_storageKeys` 只有 4 个：

```dart
'favorites', 'reading_history', 'settings', 'update_status'
```

**要加的 4 个**：

| key | 丢失后果 | 严重度 |
|---|---|---|
| `categories` | 分类定义（名字、顺序）全丢，只剩藏在 favorites 里的孤儿 `categoryIds` | **高** |
| `work_groups` | 同源作品分组全丢 | 中 |
| `ai_metadata` | AI 归一化过的元数据全丢，要重新烧 token | 中 |
| `reading_timeline` | 阅读时间线（200 条上限）全丢 | 低 |

`categories` 这个缺口 `category_store.dart:103` 的注释已经承认了 stale id 的存在，但没人回来补备份。

**明确不加的 2 个**：

- `ai_config` — 含 API key，走 `secure_store`（Keychain/Keystore），不该进明文备份 JSON
- `download_tasks` — 下载任务是本机瞬时状态，跨设备恢复无意义且会指向不存在的本地文件

**恢复逻辑要加一步孤儿清理**：导入后遍历 favorites 的 `categoryIds`，剔除指向不存在 category 的 id。否则旧备份（不含 categories）导入后会留下一批不可见的悬空引用。

> 注：`backup_service.dart:3,44-46` 在 web 上 `shareBackup()` 抛 `UnsupportedError`，这符合「Web 是 debug-only」的规则，不用改。

### 1.3 JSON 写入改原子

`local_storage_io.dart:22` 是裸的：

```dart
await file.writeAsString(content);
```

而每个 store 都是**全量覆盖**写：

- `favorites_store.dart:140-155` — 改一本漫画的分类 = 重写整个 `favorites.json`
- `category_store.dart:132-135` — 同理

写到一半崩溃或掉电 → **整个文件损坏，那个 key 的全部数据丢失**。

改成 `.tmp` → `flush` → `rename`：

```dart
final tmp = File('${file.path}.tmp');
await tmp.writeAsString(content, flush: true);
await tmp.rename(file.path);
```

POSIX `rename` 在同目录内是原子的。**三行代码，覆盖全部 10+ 个 storage key**（favorites / categories / reading_history / settings / update_status / work_groups / ai_metadata / ...），是这份计划里性价比最高的一项。

`local_storage_web.dart` 不动 —— `localStorage.setItem` 本身是同步原子的。

### 1.4 分页失败不再静默丢章节

`detail_cubit.dart:115-117` 的 catch 只 `emit(chaptersLoading: false)`，**已累积的 `allChapters` 不写回**。

所以贪婪循环（`:82-107`，最多 `maxPages = 200` 页）在第 8 页失败时，前 7 页拉到的章节**全部丢弃**，用户看到空章节列表。

**修法**：catch 里把 `allChapters` emit 出去 + 置 `canLoadMoreChapters: true`（表示还没拉完），并给个错误提示让用户能重试。

---

## 阶段 2 — 书架排序与筛选（1-2 天，1-2 个 PR）

### 现状：完全不存在

- `HomeState`（`home_state.dart:12-24`）**无任何 sort/filter 字段**
- `home_screen.dart:201` 直接把 `state.filteredFavorites` 喂 GridView，**零 sort 调用**，永远按插入顺序
- `AppSettings`（`settings_store.dart:17-36`）18 个字段无 `librarySort`/`libraryFilter`

唯一的筛选是分类 Tab（`home_screen.dart:233`）。

### 关键前提：不需要数据库

favorites 已全量在内存（`favorites_store.dart:11` 的 `List<MangaSummary>`），几百条 sort 是微秒级。**这个阶段是纯内存改动，零存储结构变化。**

### 2.1 `AppSettings` 加三个字段

```dart
LibrarySort librarySort;    // added / title / updateTime / lastRead
bool librarySortAsc;
LibraryFilter libraryFilter; // all / hasUpdate
```

### 2.2 `HomeState` 加对应字段

加上后在 `filteredFavorites`（`home_state.dart:72`）里接排序。

### 2.3 排序维度（能做的）

| 维度 | 数据来源 | 备注 |
|---|---|---|
| 添加顺序 | favorites 列表原序 | 默认，等于现状 |
| 标题 | `MangaSummary.title` | 中文排序用 `compareTo`，不引 intl |
| 更新时间 | `MangaSummary.updateTime` | **是 `String?`**，各源格式不统一，要容错解析；解析失败的排最后 |
| 最近阅读 | `reading_history` 进度表的 `timestamp` | 需要 `HomeCubit` 注入 `ReadingHistoryStore` |

### 2.4 筛选维度（能做的）

- 有新更新 — `home_state.dart:68` 的 `updatedKeys`（现成）
- 按分类 — 已有的 Tab（现成）

### 2.5 明确做不到、建议不做

**按连载状态筛选（完结 / 连载中）。**

`MangaSummary` 没有 `status` 字段 —— 只有 `MangaDetail` 有（`manga.dart` 里的 `MangaStatus` = `ongoing` / `completed` / `unknown`），而 favorites 存的是 `MangaSummary`。

要支持就得给 favorites 加字段 + 机会主义回填，跟阶段 3 的 `chapterCount` 是**同一类工程量**。建议等阶段 3 那条路走通、验证过回填覆盖率再决定。

### 2.6 UI

书架 AppBar 加一个排序/筛选按钮，弹 bottom sheet（排序维度单选 + 升降序 toggle + 筛选多选）。

参考 mihon 的 `Library Sort Flags` 社区（C25）的交互，但**不需要它那套 flag 位运算** —— 我们只有 4 个维度。

---

## 阶段 3 — 未读计数徽章（1-2 天，串行）

### 方案：用已有的已读章节集合

```
未读数 = chapterCount − getReadChapters().length
```

**关键发现：已读章节集合已经在存了。** `reading_history_store.dart:112-120` `markChapterRead()`，key = `'${sourceId}_${mangaId}_chapters'`，值是 `List<String>` chapterId；读取 `getReadChapters()` 在 `:93-109`。

所以放弃了「按序号算」的方案 —— `currentChapterIndex` 只活在内存（`reader_state.dart:72`，算于 `reader_bloc.dart:258-260` 的 `indexWhere`），**从未持久化**，而且序号语义在章节列表变动时很脆弱。

**缺的只有 `chapterCount`。**

### 3.1 让 favorites 记住 chapterCount

`MangaSummary` **已经有** `chapterCount` 字段（`manga.dart:20`，`int?`），但 favorites 全程丢弃它：

| 位置 | 问题 |
|---|---|
| `favorites_store.dart:144-153` `_save()` | 不写 |
| `favorites_store.dart:44-52` `fromJson` | 不读 |
| `favorites_store.dart:126-135` `updateLatestChapter` | 重建对象时丢 |
| `detail_cubit.dart:149-158` 收藏构造点 | 不传 |

要做：

1. `_save()` / `fromJson` 加上 `chapterCount`
2. **修 `updateLatestChapter` 改用 `copyWith`** —— 现在是重建对象，除 `chapterCount` 外还会丢 `altTitles` / `popularityText` / `description`
3. 新增 `updateChapterCount(sourceId, mangaId, count)`

### 3.2 机会主义回填

**全量章节数只有一个地方拿得到：`detail_cubit.dart:109-114`** —— 贪婪循环跑完后的 `allChapters`，是两条路径唯一的汇合点。在那里调 `updateChapterCount()`。

#### 为什么不能在库更新时批量拿

`detail_cubit.dart:57` 是个二选一分发器：

```
路径 A (:57-65)：state.manga!.chapters.isNotEmpty → 直接用，canLoadMoreChapters: false，:64 return
路径 B (:67 起)：getChapterList(page 1) → 贪婪循环 :82-107 拉完所有页
```

而 `detail.chapters` 对**大多数源是空的**：

| 源类型 | 数量 | `MangaDetail.chapters` |
|---|---|---|
| 内嵌型 | **只有 4 个** — `haokan_manhua.dart:194,203,206-208` / `manga18_club.dart` / `mmero.dart` / `vymanga.dart` | 全量 |
| 分页型 | 其余绝大多数 | `const []` |

`mangadex.dart:250-284` 不传 `chapters` → 默认 `const []`（`:288` `_feedPageSize = 100`，`:386` `canLoadMore = offset + limit < total`）。

`weeb_central.dart:342` 显式 `chapters: const []`，且 `:346-348` 的注释是决定性证据：

> `// Full chapter list lives at a dedicated endpoint (detail page only embeds the latest ~9 chapters).`

用 `detail.chapters.length` 会得到 0 或 9，**直接算出错误甚至负数的未读数**。

而 `LibraryUpdateService:63-65` 只用 `detail.latestChapter` 做字符串比对，`detail.chapters` 全程未引用。让它自己复刻 `detail_cubit.dart:57-107` 的分页逻辑，请求量会从每本 1 个涨到 1+N 个（MangaDex 每页 100 章，一部 500 章的作品要 5 个请求）。50 本收藏的一次库更新从 50 个请求变成 200+ 个，对源站不友好。**不做。**

#### 代价（要说清楚）

**只有用户打开过详情页的漫画才有 `chapterCount`。** 老收藏在用户点进去之前拿不到未读数。

这是这个方案的固有属性，不是 bug。

### 3.3 角标三态

`home_screen.dart:326-345` 现在是布尔红色 `NEW` 角标（硬编码文本，源于 `home_state.dart:68` 的 `hasUpdate()`）。`_buildMangaCard`（`:279-388`）的 Stack 里只有 NEW + 多选圆圈。

改成三态：

| 条件 | 显示 |
|---|---|
| `chapterCount != null` 且未读数 > 0 | 未读数字（如 `12`） |
| `chapterCount == null` 但 `hasUpdate()` | `NEW`（现状兜底） |
| 其余 | 无角标 |

这样老收藏退化到现在的行为，新数据显示数字，**不会出现「有的有数字有的没有」的困惑感** —— 至少有 NEW 兜着。

### 3.4 一个语义坑（先不改，但要知道）

`reader_bloc.dart:242` 在**章节流加载完成时**就调 `markChapterRead()`。

所以点开一章瞄一眼第一页就被算作已读，**未读数会偏低**。

真正的修法是改成基于阅读进度（比如翻到 80% 才算已读），但那会影响：

- 现有已读集合的语义
- 详情页章节列表的已读标记 UI

建议阶段 3 先不动，等未读数上线后看实际体感再决定。

> 相关：`reader_bloc.dart` 的写入点有 `:140`（自动翻页 saveProgress）、`:242`（markChapterRead）、`:243-252`（addHistory）、`:320`（页面变化）、`:475`（SeekToPage）。**没有「退出阅读器时写一次」的收口**，全靠翻页/加载事件增量写。

### 3.5 回填阶段 2

`chapterCount` 落盘后，阶段 2 可以补两项：

- 排序维度加「按未读数」
- 筛选维度加「只看有未读」

---

## Web 的处置结论

**不需要删任何代码，删了反而更麻烦。**

### 为什么不删

真正 web-only 的 6 个 Dart 文件全都 `import 'dart:html'`，在 native 编译路径下**根本不会被编译**：

```
lib/data/local/local_storage_web.dart
lib/data/local/secure_store_web.dart
lib/presentation/webview/webview_web.dart
lib/presentation/reader/widgets/web_direct_image_web.dart
lib/presentation/reader/widgets/manga_image_file.dart       (web stub)
lib/data/remote/webview_fetcher_stub.dart                   (web/兜底 stub)
```

它们躺在那里对 native 构建产物是**零成本**。删掉只会破坏 **7 处条件导入语句**，你得同时改 7 个入口文件：

`local_storage.dart:6` / `secure_store.dart:1-2` / `webview_fetcher.dart:1-2` / `manga_image.dart:10-11` / `manga_image.dart:12-13` / `manga_cover_image.dart:17-18` / `webview_screen.dart:4`

（注意 `webview_fetcher.dart` 和 `manga_image.dart:10-11` 的默认分支方向是**反的** —— 默认是 stub，native 才是条件分支。）

### 3 个共享文件不能删

| 文件 | 为什么不能删 |
|---|---|
| `lib/core/utils/image_proxy.dart` | **native 实际在调用**：`chapter_cache_service.dart:150`、`manga_cover_image.dart:249,252`。只是行为退化为直通 |
| `lib/data/remote/cors_proxy_interceptor.dart` | native 编译但不注册（`injection.dart:120-122` 只在 web 注册） |
| `lib/presentation/settings/sections/proxy_section.dart:79-86` 的 `WebProxySection` | 和 native 的 `ProxySection` 在同一个文件里，`settings_screen.dart:45` 运行时分流 |

### 正确做法：定一条规则

> **Web 是 debug-only。新功能默认只做 native，web 侧走 no-op stub。不为 web 做任何额外设计。**

这条规则项目里**已有现成先例**：整个 `chapter_cache_service.dart` 在 web 上就是 no-op（`:25,51,73,100,120,191,202,218` 八处 `kIsWeb` 守卫直接 return）。`translation_cache_store.dart:4,26,47,61,73` 同样。照抄这个模式即可。

> 全项目 `kIsWeb` 共 41 处 / 18 个文件。基础设施层是集中守卫，UI/业务层有 12 处散落。

### 可以顺手冻结的 web-only 资产

不删，标注为「web-only，不再维护」：

```
tools/cors_proxy.js          (23.6K)
tools/cors_proxy.test.js
tools/run_web.sh
tools/package.json / package-lock.json / node_modules/
tools/translation_service/   ← 整个目录
```

`tools/translation_service/README.md:3` 自己写明：「Web 端专用。Native 端不依赖本服务（用 flutter_onnxruntime 进程内推理）」。

`tools/download_models.sh` 是两边共用，可以去掉里面的 `WEB_DIR` 分支（`:2,:7-8`）。`tools/build_dmg.sh` 是 native-only，保留。

### 附带收益：躲过一个坑

`localStorage` 有 **5-10MB 硬上限、同步阻塞主线程、写满直接抛异常**。

阶段 3 的 `chapterCount` 会让 favorites.json 变大。如果还要认真支持 web，就得为它上 IndexedDB。定了「web 是 debug-only」之后，这个问题自动消失。

---

## 依赖关系与 PR 拆分

```
阶段 0 (CI)  ──┐
阶段 1 (bug) ──┼── 三者互相独立，可并行
阶段 2 (排序)──┘

阶段 3 (未读)：3.1 → 3.2 → 3.3 必须串行
              3.5 依赖 阶段2 + 3.1
```

建议 PR 顺序（阶段 0 先合，之后每个 PR 都自动过 gate）：

| # | 内容 | 规模 | 阶段 |
|---|---|---|---|
| 1 | 清 analyze 的 244 个问题 | 小，机械 | 0.1 |
| 2 | `ci.yml` + AGENTS.md 三处修正 | 小 | 0.2 / 0.3 |
| 3 | 摧掉两个死设置 | 极小 | 1.1 |
| 4 | JSON 原子写 | 极小（3 行） | 1.3 |
| 5 | backup 补 key + 孤儿清理 | 中 | 1.2 |
| 6 | 分页失败不丢章节 | 小 | 1.4 |
| 7 | 书架排序/筛选（state + 逻辑 + UI） | 中，可再拆 | 2.1-2.6 |
| 8 | favorites 存 chapterCount + updateChapterCount | 小 | 3.1 |
| 9 | detail_cubit 回填 + 角标三态 | 中 | 3.2 / 3.3 |
| 10 | 按未读排序 + 只看有未读 | 小 | 3.5 |

---

## 明确不在本次范围

以下都讨论过并明确推迟，记录原因以免以后重复讨论：

| 项 | 推迟原因 |
|---|---|
| **drift / 任何数据库** | 现阶段是过度工程。数据库的真正收益是「跳表事务 + 高频写局部性 + 并发安全」，comic-reader 只痛在「高频写局部性」，**原子写 + 按漫画分片就能解决**。典型用户 50 本×100 章 = 5000 条 ≈ 120KB，重度 200×200 = 4 万条 ≈ 1MB，native 全量重写 1MB ≈ 10ms。`lib/data/local/dao/` 和 `schemas/` 两个空目录（只有 .gitkeep）说明这事规划过但从未开工，不必急 |
| **真后台更新 worker** | pubspec 无 workmanager / background_fetch / android_alarm_manager / flutter_background_service；AndroidManifest 零 service/receiver/permission。现有 `LibraryUpdateService` 三个调用点全是前台：`main.dart:112`（启动 fire-and-forget，这就是 README:69「新章节更新提示」的真身）、`home_cubit.dart:123`（手动刷新）、`updates_cubit.dart:45`（下拉刷新）。**app 不开完全不检查，无系统通知**。要做是独立的一大块工程 |
| **本地文件源** | `cbz`/`cbr`/`ZipDecoder`/`ArchiveFile`/`.pdf` 全项目零命中，pubspec 无 `archive` 无 pdf 包。`MangaSource` 契约本身是纯网络模型（`prepare*Fetch` → HTTP → `parse*`），加本地分支要改契约 |
| **双页 / 跨页 spread** | `dualPage`/`doublePage`/`twoPage`/`spread` 零命中。横向阅读器是 1 图 = 1 PageView page。与 `splitWidePages` 一起做 |
| **亮度调节 / 护眼滤镜** | 无 `screen_brightness` 依赖，reader 目录 `brightness` 零命中（只有 `keepScreenOn` 走 wakelock_plus） |
| **i18n**（ROADMAP #22） | 目标用户是中文，优先级低 |
| **云同步 WebDAV**（ROADMAP #23） | 依赖阶段 1.2 的备份 key 补全先落地 |

---

## 附录 A：mihon 图谱要点

graphify 产物在 `mihon/graphify-out/`（**7346 节点 / 12328 边 / 557 社区**）。

值得借鉴或对照的几点：

### Import Cycles: None detected

922 个 Kotlin 文件**零循环依赖**。这是 12 个 Gradle 模块（`app` / `core` / `core-metadata` / `data` / `domain` / `i18n` / `presentation-core` / `presentation-widget` / `source-api` / `source-local` / `telemetry` / `baseline-profile`）强制出来的结果 —— Gradle 模块边界在编译期就禁止了循环。

comic-reader 是单 package，靠目录约定（`lib/data` / `lib/domain` / `lib/presentation` / `lib/core` / `lib/app`），编译器不强制。这是 Flutter 项目的常态，但值得知道差距来源。

### God Nodes 的构成很健康

| 节点 | 边数 | 性质 |
|---|---|---|
| `Text` | 174 | Compose 原语 |
| `logcat()` | 141 | 横切工具 |
| `withIOContext()` | 79 | 横切工具 |
| `Category` | 57 | 领域抽象 |
| `Scaffold()` | 52 | Compose 原语 |
| `Tracker` | 51 | 领域抽象 |
| `ReaderViewModel` | 51 | 领域抽象 |
| `Screen` | 49 | 导航原语 |
| `TrackSearch` | 49 | 领域抽象 |
| `TextButton()` | 49 | Compose 原语 |

前 5 里 3 个是 UI 原语 + 2 个横切工具，**领域抽象没有一个是超级枢纽**。这说明没有上帝类。

### 阅读器被拆成 10 个社区

`loader`(C13) / `archive loader`(C16) / `pager viewer`(C19) / `transition`(C35) / `page holder`(C47) / `gesture`(C17) / `image view`(C24) / `navigation regions`(C61) / `activity`(C60) / `viewmodel`(C46)

comic-reader 的 reader 目前是 `reader_bloc.dart` + `horizontal_reader.dart` / `vertical_reader.dart` / `manga_image.dart`。要做双页/切分/亮度这些之前，可以参考这个拆分方式。

### 7 个 tracker 各自成社区，共享 `BaseTracker`(C71) / `Tracker` 接口(C54)

AniList / MangaBaka / Shikimori / Bangumi / MyAnimeList / Suwayomi / Dummy。

comic-reader 目前无 tracker。如果以后要做 Bangumi tracker，这个「接口 + BaseTracker 模板方法 + 每个服务独立实现」的结构是可以直接照搬的。

### PR quality gate（27 组 hyperedge 之一）

mihon 的 PR gate：dependency review + spotless format check + unit tests + **SQLDelight migration 校验** + test report upload + app build。

阶段 0 的 `ci.yml` 是这个的最小版本（analyze + test）。

### 一个反面参照

`/Users/portz/js/comic/graphify-out/` 是 comic-reader 的**旧图谱**（3220 节点 / 220 社区，2026-06-30），**把 `ios/Pods/`、`windows/runner/`、`macos/` 扫进去了** —— God Nodes 前 10 里 8 个是第三方 iOS Pod（`SDImageCache` 57、`DKAssetGroupDetailVC` 51...），唯一项目自身的节点是 `entities.dart`（40 边）。

这份图谱基本无架构诊断价值。**如果要重跑 comic-reader 的图谱，必须排除 `ios/Pods`、`macos`、`windows`、`build`、`.dart_tool`。**

它唯一有价值的信号：标出了 `HComic --semantically_similar_to--> NHentai`、`Wnacg --semantically_similar_to--> NHentai`，印证 31 个源之间有大量同构样板重复 —— 这提示未来可以抽一层 source 模板，但不在本次范围。

---

## 附录 B：本计划依据的核实事实索引

所有事实均经 explore agent 读实际代码验证，非推测。按主题索引，便于执行时快速定位。

### 持久化

| 事实 | 位置 |
|---|---|
| 无任何数据库依赖 | pubspec 无 sqflite/drift/hive/isar/objectbox/shared_preferences |
| read/write 是整个文件 jsonDecode/jsonEncode | `local_storage.dart:11` |
| native 裸 writeAsString，非原子 | `local_storage_io.dart:22` |
| web 用 localStorage 前缀 `comic_reader_` | `local_storage_web.dart` |
| favorites 全量重写 | `favorites_store.dart:140-155` |
| categories 全量重写 | `category_store.dart:132-135` |
| dao/ 和 schemas/ 是空目录 | 只有 `.gitkeep` |
| 敏感凭据走 Keychain/Keystore | `secure_store.dart` + flutter_secure_storage |

### 未读计数相关

| 事实 | 位置 |
|---|---|
| favorites 缓存类型是 `List<MangaSummary>?` | `favorites_store.dart:11` |
| 分类映射是独立 Map，key = `'${sourceId}_$mangaId'` | `favorites_store.dart:17,24-25` |
| `_save()` 序列化的字段 | `favorites_store.dart:140-156` |
| `fromJson` 读的字段 | `favorites_store.dart:36-53` |
| `chapterCount` 字段存在但 favorites 丢弃 | `manga.dart:20`（定义）；`favorites_store.dart:144-153,44-52,126-135`（三处丢弃） |
| 唯一填充 `chapterCount` 的源 | `pica_comic.dart:444`（用 `epsCount`） |
| `manga_card.dart` 已在展示 `'${chapterCount}章'` | `manga_card.dart:55-56,138,144-145` |
| 已读章节集合（chapterId 列表） | `reading_history_store.dart:112-120` 写 / `:93-109` 读 |
| 进度表 `{chapterId,page,timestamp}` | `reading_history_store.dart:79-90` |
| 时间线，上限 200 条 | `reading_history_store.dart:55,56`；`HistoryEntry` `:4-23` |
| `currentChapterIndex` 只在内存 | `reader_state.dart:72`；算于 `reader_bloc.dart:258-260` |
| markChapterRead 在章节加载完成时触发 | `reader_bloc.dart:242` |
| 现有 NEW 角标 | `home_screen.dart:326-345`；`hasUpdate()` 在 `home_state.dart:68` |
| `UpdateStore` 的 `NewChapter` 无章节数 | `update_store.dart:5-19,23-30`；key `'update_status'` `:52` |

### 章节分页

| 事实 | 位置 |
|---|---|
| 二选一分发器 | `detail_cubit.dart:57` |
| 路径 A（内嵌型直接用） | `detail_cubit.dart:57-65` |
| 路径 B 贪婪循环，maxPages=200 | `detail_cubit.dart:82-107`，`:83` |
| 空页不中断（MangaDex 语言过滤会塌成空页） | `detail_cubit.dart:96-99` |
| **catch 丢弃 allChapters（bug）** | `detail_cubit.dart:115-117` |
| 全量章节的唯一汇合点 | `detail_cubit.dart:109-114` |
| `getMangaInfo` 在 refresh 调，之后才 loadChapters | `detail_cubit.dart:42,45` |
| 仓库层零分页展开 | `manga_repository_impl.dart:69-91`（getMangaInfo）、`:94-107`（getChapterList） |
| 仓库层展开的是图片页 | `chapter_image_pipeline.dart:288` `_expandPicaPages`，调用点 `:108/:209` |
| 内嵌型源只 4 个 | `haokan_manhua.dart:194,203,206-208`、`manga18_club.dart`、`mmero.dart`、`vymanga.dart` |
| MangaDex 不传 chapters | `mangadex.dart:250-284`；`:288` `_feedPageSize=100`；`:386` canLoadMore |
| weeb_central 显式空 + 决定性注释 | `weeb_central.dart:342`、**`:346-348`**、`:352` |
| LibraryUpdateService 只比对 latestChapter | `library_update_service.dart:63-65`；`:81-82` 静默吞失败；`:92` 并发 3 |

### 书架

| 事实 | 位置 |
|---|---|
| HomeState 无 sort/filter 字段 | `home_state.dart:12-24` |
| GridView 零 sort 调用 | `home_screen.dart:201` |
| AppSettings 18 字段无 librarySort | `settings_store.dart:17-36` |
| filteredFavorites | `home_state.dart:72` |
| 分类 Tab | `home_screen.dart:233`；管理对话框 `:425`；批量设分类 `:552` |
| `MangaSummary` 无 status（只有 MangaDetail 有） | `manga.dart` |

### 死设置

| 事实 | 位置 |
|---|---|
| `cropBorders` 定义 | `settings_store.dart:29` |
| `splitWidePages` 定义 | `settings_store.dart:31` |
| UI 开关 | `reader_enhancements_section.dart:81,87` |
| 传递链 | `settings_cubit:91` → `reader_bloc:112` → `reader_state:88/124/156/187/247` |
| 渲染层零引用 | `horizontal_reader.dart` / `vertical_reader.dart` / `manga_image.dart` |

### 备份

| 事实 | 位置 |
|---|---|
| `_storageKeys` 只有 4 个 | `backup_service.dart:13-18` |
| web 抛 UnsupportedError | `backup_service.dart:3,44-46` |
| stale categoryIds 已被注释承认 | `category_store.dart:103` |

### CI / 测试

| 事实 | 位置 |
|---|---|
| analyze 实测 244 issues（237 info + 2 error） | 4.6s |
| 2 个 error：函数体内 import | `test/verify_ehentai_chapter.dart:48:5` |
| lib/ 唯一 2 个 info | `webview_native.dart:150:15,153:15` |
| http 未声明依赖 | `test/verify_jcomic.dart:2`；`pubspec.lock:547-548` transitive |
| analysis_options 是默认 flutter_lints | `avoid_print: false` 被注释 = 启用 |
| flutter-action 未 pin 版本 | `release.yml:39/41, 121/123, 166/168` |
| widget_test DI 已修 | `widget_test.dart:11-16,18-20,24-26` |
| 全仓零 tag 注解，无 dart_test.yaml | — |
| dev_dependencies | `pubspec.yaml:78-83`（flutter_test / flutter_lints ^5.0.0 / bloc_test ^10.0.0 / mocktail ^1.0.3） |

### Web

| 事实 | 位置 |
|---|---|
| 7 处条件导入 | `local_storage.dart:6`、`secure_store.dart:1-2`、`webview_fetcher.dart:1-2`、`manga_image.dart:10-11`、`manga_image.dart:12-13`、`manga_cover_image.dart:17-18`、`webview_screen.dart:4` |
| 无任何 `dart.library.js_interop` | 0 命中 |
| `kIsWeb` 41 处 / 18 文件 | — |
| chapter_cache_service 整体 web no-op（先例） | `:25,51,73,100,120,191,202,218` |
| translation_cache_store 同样 | `:4,26,47,61,73` |
| image_proxy 被 native 调用 | `chapter_cache_service.dart:150`、`manga_cover_image.dart:249,252` |
| CorsProxyInterceptor 只在 web 注册 | `injection.dart:120-122` |
| WebProxySection 与 ProxySection 同文件 | `proxy_section.dart:79-86`；分流在 `settings_screen.dart:45` |
| translation_service 是 web 专用 | `tools/translation_service/README.md:3` |
| download_models.sh 两边共用 | `:2,:7-8` |
