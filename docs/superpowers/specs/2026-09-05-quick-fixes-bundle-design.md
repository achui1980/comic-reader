# 设计文档:四项快速修复合集

日期: 2026-09-05
来源: 项目健康度头脑风暴（探索 ROADMAP.md / todo.md / mihon-gap-improvement-plan.md 交叉核实后确认的四个具体问题）

## 1. 隐藏 cropBorders / splitWidePages 死设置

### 问题

- `lib/data/local/settings_store.dart` 定义并持久化 `cropBorders`/`splitWidePages` 两个字段（默认 `false`）。
- `lib/presentation/settings/bloc/settings_cubit.dart`（84/96 行）暴露对应 setter。
- `lib/presentation/settings/sections/reader_enhancements_section.dart`（81/87 行）在设置页渲染开关 UI。
- `lib/presentation/reader/bloc/reader_state.dart`/`reader_bloc.dart`（110/112 行）把字段一路传递进阅读器 state。
- 但 `rtk grep -rln "cropBorders|splitWidePages" lib/` 显示 `lib/presentation/reader/widgets/` 下**零引用**——没有任何渲染部件消费这两个字段来做真实的裁边/拆页处理。用户打开开关，实际什么都没发生（信任损耗型体验债）。

### 方案

- 仅移除 `reader_enhancements_section.dart` 中这两个开关对应的 UI 控件（81/87 行）。
- 保留 `settings_store.dart` 底层字段、`settings_cubit.dart` setter、`reader_state.dart`/`reader_bloc.dart` 中的字段不变——不做数据迁移/清理，为未来若要真正实现该功能保留接口，已持久化的用户设置值不受影响（只是不再有 UI 入口修改它）。
- 不实现任何真实的图像裁剪/拆页算法（超出本次快速修复范围）。

### 验证

- `flutter analyze` 通过。
- 若 `reader_enhancements_section.dart` 存在对应 widget 测试，更新断言确认这两个开关不再渲染；否则跳过（该文件此前无测试覆盖）。
- 手动确认设置页不再显示这两项，其余阅读增强选项不受影响。

## 2. 备份系统补充缺失字段

### 问题

`lib/data/local/backup_service.dart` 的 `_storageKeys`（13-18 行）当前只有 4 项：
`'favorites', 'reading_history', 'settings', 'update_status'`。

`exportData()`/`importData()` 均遍历这个列表做导出/恢复，导致用户导出备份、换设备恢复后，以下数据会全部丢失：
- 书架分类（`category_store.dart:48` → key `'categories'`）
- AI 元数据（`ai_metadata_store.dart:15` → key `'ai_metadata'`）
- 跨源同作品分组（`work_group_store.dart:10` → key `'work_groups'`）

### 方案

- 在 `_storageKeys` 中新增 `'categories'`, `'ai_metadata'`, `'work_groups'` 三项。
- **故意不加**：
  - `'auth'`（`auth_store.dart:6`，存放各源登录/session 凭据）——安全考虑，避免导出文件包含明文登录凭据。
  - `'download_tasks'`（`download_manager.dart:97`）——下载队列是瞬时、设备本地状态，跨设备恢复没有意义（下载文件本身不会随备份迁移）。
- 在 `_storageKeys` 定义处加注释，明确写出以上两项排除理由，避免日后被误当作"遗漏"再修一次。

### 验证

- `flutter analyze` 通过。
- 补充/更新 `backup_service` 单测（该文件目前零测试）：验证 `exportData()` 产出的 JSON 包含全部 7 个 key（4 个旧 + 3 个新），且不包含 `auth`/`download_tasks`；验证 `importData()` 能正确恢复新增的三类数据。

## 3. 本地 JSON 原子写入

### 问题

`lib/data/local/local_storage_io.dart` 的 `writeString`（22-26 行）直接对目标文件调用 `File('$dir/$name.json').writeAsString(content)`，没有任何原子性保护。写入过程中进程被杀/崩溃会导致该 `.json` 文件变成空文件或截断内容，下次启动 `readString` 读到坏数据（相当于用户该类数据全部丢失/应用启动异常）。

`local_storage_web.dart`（web 版）不受影响：`window.localStorage.setItem` 本身在 JS 运行时中是单次调用完成，不需要修复。

### 方案

- 修改 `writeString`：
  1. 先把内容写入同目录下的临时文件 `$dir/$name.json.tmp`，写入时使用 `flush: true` 确保数据落盘。
  2. 写入成功后，用 `rename` 把临时文件覆盖到目标文件名 `$dir/$name.json`（同目录内 rename 在主流文件系统上是原子操作，不会出现"写了一半"的中间状态）。
  3. 若中途写入 tmp 失败，目标文件保持原有内容不变（原逻辑下则会被截断/损坏）。

### 验证

- `flutter analyze` 通过。
- 新增 `local_storage_io` 单测（该文件目前零测试）：验证正常写入后能读回同样内容；模拟写入中断场景（可用较大内容 + mock 文件系统或验证 tmp 文件清理逻辑）确认目标文件在异常路径下不会被截断/损坏，仍保留写入前的旧内容。

## 4. 章节分页失败 → 错误提示 + 手动重试

### 问题

`lib/presentation/detail/bloc/detail_cubit.dart` 的 `loadChapters()`（53-118 行）分页循环中，每页成功都会 `emit` 最新的累积章节列表，所以已成功页不会丢失。但 catch 块（115-117 行）：

```dart
catch (e) { emit(state.copyWith(chaptersLoading: false)); }
```

只把 `chaptersLoading` 置 `false`，**不设置任何错误信息，也不改变 `status`**，用户看到的只是"加载停止了"，没有任何错误提示或重试入口。

更关键的是：`loadMoreChapters()`（120-135 行）目前是**死代码**——`lib/presentation/detail/*.dart` 全目录 grep 只命中它自身定义，没有任何 UI 触发它。即使失败后 `canLoadMoreChapters` 仍为 `true`，用户也完全无法手动重试，分页永久卡在当前页。

`detail_screen.dart`（80-96 行）只处理顶层 `DetailStatus.error`（区分 Cloudflare 错误与普通错误文案），对章节分页层面的失败完全无感。

### 方案

- 在 `DetailState` 新增字段 `chaptersError`（`String?`，默认 `null`）。
- `detail_cubit.dart`：
  - `loadChapters()` 的 catch 块改为 `emit(state.copyWith(chaptersLoading: false, chaptersError: '章节加载失败，请重试'))`（具体文案可根据异常类型细化，参考现有 Cloudflare 错误文案风格）。
  - 每次成功进入循环/成功加载一页时清除 `chaptersError`（置回 `null`），避免重试成功后错误提示残留。
- 激活现有 `loadMoreChapters()`：在 `detail_screen.dart` 章节列表末尾，若 `chaptersError != null`，渲染错误文案 + 「重试」按钮，`onPressed` 调用 `context.read<DetailCubit>().loadMoreChapters()`。

### 验证

- `flutter analyze` 通过。
- 补充/更新 `detail_cubit` 单测：模拟分页中途失败，断言 `chaptersError` 被设置且已加载的前几页章节保留在 state 中；断言调用 `loadMoreChapters()` 重试成功后 `chaptersError` 恢复为 `null` 且新章节被追加。
- 手动确认：`detail_screen.dart` 在分页失败场景下展示重试按钮，点击后能继续加载剩余章节。

## 影响范围小结

| 文件 | 改动类型 |
| --- | --- |
| `lib/presentation/settings/sections/reader_enhancements_section.dart` | 移除 UI 控件 |
| `lib/data/local/backup_service.dart` | 新增 3 个 storage key + 注释 |
| `lib/data/local/local_storage_io.dart` | `writeString` 改为 tmp+flush+rename |
| `lib/presentation/detail/bloc/detail_state.dart` | 新增 `chaptersError` 字段 |
| `lib/presentation/detail/bloc/detail_cubit.dart` | catch 块设置/清除 `chaptersError` |
| `lib/presentation/detail/detail_screen.dart` | 新增分页错误提示 + 重试按钮 UI |

四项均为独立、无相互依赖的小修复，可在同一实施计划中并行安排，也可拆成独立 commit。均不涉及新增依赖包。
