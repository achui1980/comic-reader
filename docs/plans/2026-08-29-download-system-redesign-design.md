# 下载系统重构设计

## 日期
2026-08-29

## 背景

`todo.md` 中长期存在"修复下载问题，包括收藏也无法下载的问题"。经调研（详见下方"现状调研结论"）确认这不是简单 bug，而是架构问题：代码里存在两套完全独立、互不知道对方存在的下载系统，导致收藏页/书架页完全没有下载入口，且现有下载路径全链路串行、没有暂停/续传、存储位置不可控。

本设计文档给出重构方案，目标：
1. 修复"收藏无法下载"——收藏页获得真正的下载入口
2. 章节级 + 图片级双层并发，显著提速
3. 支持暂停/恢复、App 重启自动接续、单图自动重试、失败可见化
4. macOS/Windows 支持自定义下载目录；Android/iOS 换更合理的默认位置

## 现状调研结论

代码里存在两套完全独立、互不知道对方存在的下载系统：

| | `DownloadManager`（全局单例队列） | `DownloadCubit`（详情页局部队列） |
|---|---|---|
| 文件 | `lib/data/local/download_manager.dart` | `lib/presentation/detail/bloc/download_cubit.dart` |
| 生命周期 | App 级单例 | 每次进入详情页新建，退出即销毁 |
| 谁能添加任务 | `addTask()` —— **全代码库 0 处调用** | `downloadChapter()`/`downloadMultiple()` —— 详情页按钮在用 |
| UI 入口 | 首页 `DownloadDrawer`（只读展示，永远是空队列） | 详情页"下载全部"按钮 + 章节长按菜单 |
| 并发 | 声明 `_maxConcurrent=3`，因无人调用 `addTask` 是死代码 | 严格串行 `while` 循环，一次一个章节 |

**"收藏无法下载"根因**：`home_screen.dart` 首页/书架页代码里完全没有任何下载入口（单本、批量均无），只接了 `DownloadManager` 的只读展示。真正能下载的入口只存在于 `detail_screen.dart` 详情页，调用 `DownloadCubit`。

**"下载慢"根因**：`chapter_cache_service.dart` 的 `downloadChapter()` 用 for 循环逐张 `await` 图片，零并发；`DownloadCubit._processQueue()` 同样严格串行处理章节队列；唯一写了并发上限的 `DownloadManager._maxConcurrent=3` 从未生效。

**存储位置**：硬编码 `getApplicationDocumentsDirectory()/chapter_cache/{sourceId}/{mangaId}/{chapterId}/0000.jpg...`，四端统一走 `path_provider` 同一套代码，无平台分支。macOS/iOS 因 App Sandbox 开启（`macos/Runner/Release.entitlements:5` 确认 `app-sandbox=true`），实际路径在用户不可见的沙盒容器内。无任何用户可配置存储路径的设置项。

**失败处理**：`chapter_cache_service.dart` 和 `download_cubit.dart` 的 catch 块均静默处理，无日志系统接入。

**依赖现状**：`pubspec.yaml` 已有 `path_provider: ^2.1.2` 和 `file_picker: ^8.1.7`，后者可直接用于 macOS/Windows 目录选择器，无需新增依赖。

## 架构：统一为一套

保留并重构 `DownloadManager`（`lib/data/local/download_manager.dart`）作为唯一的下载队列/状态机。`DownloadCubit` 改造为对它的**薄 BLoC 封装**（详情页仍用 Cubit 订阅状态展示 UI，但底层调用全部转发给 `DownloadManager`），不再自己维护队列。`ChapterCacheService` 角色不变，仍是纯文件 I/O 层，被 `DownloadManager` 调用。

### `DownloadTask` 字段扩展

在现有 `sourceId/mangaId/chapterId/mangaTitle/chapterTitle/status/progress/error` 基础上新增：

```dart
class DownloadTask {
  // ...existing fields
  int totalImages;
  int completedImages;
  List<int> failedImageIndexes;   // 记录哪几张失败，用于"失败可见化"+手动重试
  int retryCount;                  // 该任务被整体重试的次数
  DateTime? pausedAt;
  int priority;                    // 入队顺序（FIFO），不做用户可调优先级
}
```

持久化 key 仍是 `download_tasks`；旧格式字段缺失时用默认值兜底，不做强制迁移。

状态枚举扩展：新增 `paused`、`partiallyFailed`（区别于整体 `failed`，表示大部分图片成功但少数图片失败）。

## 并发调度（两级并发池）

- **章节级**：`_maxConcurrentChapters = 2`（保守值，多章节同时拉低速源容易被封或互相抢带宽；不做成用户可调设置，避免选项爆炸）
- **图片级**：每个正在下载的章节内部，用 `Future.wait` 分批 + 信号量方式并发拉取，`_maxConcurrentImagesPerChapter = 4`
- 两级相乘的总并发上限 = 8，作为写死常量集中在 `DownloadManager` 顶部，方便以后按源站反馈调整
- 单图下载失败：自动重试 2 次（固定延时，不引入指数退避库），仍失败则记入 `failedImageIndexes`，**不阻塞其他图片继续下**
- 章节内所有图片处理完后：若 `failedImageIndexes` 非空 → 状态设为 `partiallyFailed`，下载抽屉里单独展示"N 张失败，点击重试"，重试时只重新拉取失败的那几张

## 暂停/恢复 + 重启接续

- `DownloadManager` 新增 `pauseAll()` / `resumeAll()` / 单任务 `pauseTask(key)`：暂停时用 `CancelToken` 取消该任务当前进行中的网络请求，但**任务状态设为 `paused` 而不是从队列移除**，已下载的图片文件保留在磁盘上
- 恢复时先检查磁盘上哪些序号的图片文件已存在（`File.exists()` + 文件大小 > 0 校验），跳过已存在的，只补齐缺的——这不是字节级断点续传，是**图片级去重续传**，实现成本低且覆盖核心诉求
- App 重启：`init()` 里不再把 `downloading` 状态粗暴 reset 成 `pending, progress=0`，改成 reset 成 `pending` 但**保留 `completedImages`/磁盘上已有的图片**，重新入队时走"跳过已存在图片"逻辑

## 收藏页/书架入口

- 单本漫画卡片：长按（或已有的更多菜单）新增"下载未读章节"——若 favorites 还没有章节列表，走一次轻量的 `getChapterList`（仅取列表不取图片），过滤出未读的加入 `DownloadManager` 队列
- 多选模式：底部操作栏新增"下载所选"按钮，对多本漫画分别展开未读章节，一次性批量入队（复用同一套章节级并发池，不会因为选了 10 本就开 10 倍并发）
- 不做"一键下载全部收藏"（范围收紧到显式选择的本子）

## 存储位置

- **Android**：默认目录从 `getApplicationDocumentsDirectory()` 换成 `getExternalStorageDirectory()` 下的 App 专属目录（`/Android/data/<pkg>/files/chapter_cache`），Android 10+ 不需要运行时权限请求，不做自定义目录选择（Scoped Storage 下"任选目录后用普通文件 API 写入"不可靠，需要 SAF 平台通道代码，工作量与 macOS/Windows 不是同一量级，本次不做）
- **iOS**：路径不变（仍沙盒），`Info.plist` 加 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`，让用户能在"文件"App 里看到/导出
- **macOS/Windows**：设置页新增"下载存储位置"，用已有依赖 `file_picker` 的 `getDirectoryPath()` 弹目录选择器
  - **macOS 沙盒陷阱需专门处理**：选定目录后必须保存 security-scoped bookmark（`NSURL.bookmarkData`，需通过原生 Swift 桥接少量代码写入 `macos/Runner`），App 下次启动时用 bookmark 恢复访问权限并调用 `startAccessingSecurityScopedResource()`，否则重启后写入会静默失败或抛权限异常。这是本次唯一需要碰原生 Swift 代码的地方，其余全是 Dart 层改动
  - Windows 没有沙盒限制，选完目录直接用即可，不需要额外处理

## 明确不做（本次范围外）

- Android 完整 SAF 任意目录选择
- 真正的 HTTP Range 字节级断点续传（图片级去重续传已覆盖核心场景，字节级收益边际小、实现和测试成本高）
- 下载并发数做成用户可调设置（先用保守常量，后续有真实反馈再考虑开放）
- "一键下载全部收藏"

## 测试计划

- `DownloadManager` 单元测试：章节级+图片级并发上限不被突破、暂停后任务状态正确、恢复后跳过已存在图片、单图重试计数、`partiallyFailed` 状态转换
- 持久化兼容性测试：旧格式 `download_tasks` JSON（缺新字段）能被正确解析并使用默认值兜底
- `DownloadCubit` 薄封装测试：确认调用全部转发到 `DownloadManager`，不再自己维护队列状态
- 收藏页入口的 widget 测试：单本"下载未读"、多选"下载所选"正确调用 `DownloadManager.addTask`
- macOS security-scoped bookmark 的手动验证（自动化测试难以覆盖原生沙盒行为，需人工验证选目录→重启 App→写入仍成功）
