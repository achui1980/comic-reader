# 依赖升级扫描 (ROADMAP #26) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `flutter_lints` 4.0.0→5.x、`flutter_bloc` 8.1.6→9.x（连带 `bloc_test`）、`go_router` 14.8.1→15.x 三个包依次升级并验证零回归。按用户决策：go_router 和 flutter_lints 升到 ROADMAP 字面提到的过渡版本（15.x / 5.x），不直接跳到实测最新的 17.3.0 / 6.0.0（那是更激进的后续任务，本次不做）。

**Architecture:** 三个包按"风险从低到高、影响面从广到窄"顺序隔离升级：先 `flutter_lints`（可能引入大量新lint但不影响运行时行为），再 `flutter_bloc`（21个文件用到，1个Bloc+8个Cubit，但API公开面稳定），最后 `go_router`（11个文件用到，风险最集中在 `StatefulShellRoute.indexedStack`）。每个包升级后必须跑全量 `flutter analyze`+`flutter test`+手动走查，确认零回归才能进入下一个包。

**Tech Stack:** Flutter/Dart, pub.dev。

**已知项目现状（供参考，来自实测 `flutter pub outdated`）：**
- `flutter_bloc`：21个文件使用，1个 `Bloc`（`ReaderBloc`）+8个 `Cubit`（Settings/Home/Discovery/Updates/Search/Download/Detail/History），未使用 `BlocConsumer`/`context.watch`/`context.select`/`BlocObserver`
- `go_router`：11个文件使用，`lib/app/router/app_router.dart` 重度依赖 `StatefulShellRoute.indexedStack`（4个Tab），全部导航走 `context.push`/`context.pop`（15+1处），未用 `context.go`/命名路由/`redirect`
- `analysis_options.yaml` 零自定义规则覆盖（纯用 `flutter_lints` 默认集），升级后新规则会全量生效
- 项目目前**没有任何 Bloc/Cubit 单测覆盖**，go_router/reader 相关升级缺少自动化回归网，高度依赖手动走查

---

## Part A: flutter_lints 4.0.0 → 5.x

### Task 1: 升级 flutter_lints 并处理新增 lint

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 记录基线**

Run: `flutter analyze 2>&1 | tail -5`
Expected: 记下当前 issue 总数（预期是 `No issues found!`，作为"升级前0个issue"的基线）

- [ ] **Step 2: 修改版本约束**

`pubspec.yaml` 的 `dev_dependencies:` 部分：
```yaml
  flutter_lints: ^5.0.0
```

- [ ] **Step 3: 更新依赖**

Run: `flutter pub get`
Expected: 成功，`pubspec.lock` 中 `flutter_lints` 更新到 5.x

- [ ] **Step 4: 全量分析，收集新增issue**

Run: `flutter analyze > /tmp/lints_after_upgrade.txt 2>&1; cat /tmp/lints_after_upgrade.txt`
Expected: 输出新增的 lint 警告列表（若为 `No issues found!` 则无需 Step 5）

- [ ] **Step 5: 逐条处理新增 lint**

对每一条新增警告，按规则名分类，优先修代码而不是关闭规则。若某条规则短期内不适合大范围修复（例如涉及数十个文件的风格调整），在 `analysis_options.yaml` 里显式关闭并注明原因和后续计划：
```yaml
linter:
  rules:
    # TODO(#26-followup): re-enable after batch-fixing existing call sites
    some_new_rule_name: false
```
（具体规则名需要根据 Step 4 实际输出确定，不可预先假设；这里的占位规则名 `some_new_rule_name` 仅为格式示例，实际执行时必须替换为 `flutter analyze` 真实报出的规则名。）

- [ ] **Step 6: 验证收敛**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: 全量测试**

Run: `flutter test`
Expected: 全部 PASS（lint升级不改变运行时行为，测试结果应与升级前一致）

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml
git commit -m "chore: upgrade flutter_lints 4.x -> 5.x"
```

（若 Step 5 修改了业务代码文件以消除新lint，这些文件改动应在同一个commit或紧随其后的独立commit里，视改动量决定是否拆分：改动量大就拆成"chore: upgrade flutter_lints"+"style: fix new lint warnings"两个commit。）

---

## Part B: flutter_bloc 8.1.6 → 9.x + bloc_test 同步升级

### Task 2: 升级 flutter_bloc/bloc_test 并回归 ReaderBloc

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 记录基线**

Run: `flutter test 2>&1 | tail -20`
Expected: 记下当前测试通过数量（作为升级后对比基线）

- [ ] **Step 2: 修改版本约束**

`pubspec.yaml`：
```yaml
dependencies:
  flutter_bloc: ^9.0.0
```
```yaml
dev_dependencies:
  bloc_test: ^10.0.0
```

- [ ] **Step 3: 更新依赖**

Run: `flutter pub get`
Expected: 成功，`bloc`（`flutter_bloc` 传递依赖）连带升到 9.x

- [ ] **Step 4: 全量分析**

Run: `flutter analyze`
Expected: 若有报错，多半集中在 `Bloc`/`Cubit`/`emit` 相关的类型收紧（8→9的典型breaking change）。逐一打开报错文件修复，21个使用 `flutter_bloc` 的文件列表见上方"已知项目现状"，优先检查 `lib/presentation/reader/bloc/reader_bloc.dart`（唯一真正的 `Bloc`，`emit` 调用最密集）。

- [ ] **Step 5: 全量测试**

Run: `flutter test`
Expected: 全部 PASS，数量与 Step 1 基线一致。若 `bloc_test` 的 `blocTest()` API 因大版本切换有类型收紧导致编译失败，逐一修复测试文件（重点是 `2026-07-29-predictive-prefetch.md` Task 3 新增的 `reader_bloc_test.dart`，若该计划已先执行）。

- [ ] **Step 6: 手动走查 8 个 Cubit 页面**

依次打开并操作以下页面，确认状态流转与 UI 渲染正常（因无自动化测试覆盖 Cubit 层，这是唯一的回归手段）：
1. 首页（`HomeCubit`）：下拉刷新、列表加载
2. 发现页（`DiscoveryCubit`）：切换分类、翻页加载
3. 更新页（`UpdatesCubit`）：刷新更新列表
4. 搜索页（`SearchCubit`）：输入关键词搜索、清空
5. 详情页（`DetailCubit`+`DownloadCubit`，`MultiBlocProvider`）：查看漫画详情、触发下载
6. 历史页（`HistoryCubit`）：查看/清除历史
7. 设置页（`SettingsCubit`）：切换各项设置开关
8. 阅读器（`ReaderBloc`）：横向/纵向翻页、自动翻页、追加下一章、（若已实现#21）预取下一章

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: upgrade flutter_bloc 8.x -> 9.x, bloc_test 9.x -> 10.x"
```

（若 Step 4/5 修复业务代码产生改动，视改动量决定是否拆分成独立 commit，命名如 `fix: adapt to flutter_bloc 9.x emit API changes`。）

---

## Part C: go_router 14.8.1 → 15.x

### Task 3: 升级 go_router 并重点验证 StatefulShellRoute

**Files:**
- Modify: `pubspec.yaml`
- 重点验证: `lib/app/router/app_router.dart`, `lib/presentation/shell/app_shell.dart`

- [ ] **Step 1: 修改版本约束**

`pubspec.yaml`：
```yaml
dependencies:
  go_router: ^15.0.0
```

- [ ] **Step 2: 更新依赖**

Run: `flutter pub get`
Expected: 成功

- [ ] **Step 3: 全量分析**

Run: `flutter analyze`
Expected: 若有报错，重点检查 `lib/app/router/app_router.dart` 里 `StatefulShellRoute.indexedStack(...)`/`StatefulShellBranch(...)`/`GoRoute(...)` 的构造签名是否有变化（14→15的breaking change范围）。

- [ ] **Step 4: 手动走查全部路由**

因为 go_router 升级没有自动化测试覆盖，必须逐条手动走查：
1. 启动App，确认落在首页（`initialLocation: AppRoutes.home`）
2. 依次点击底部4个Tab（首页/发现/更新/设置），确认 `StatefulShellRoute.indexedStack` 切换Tab时**各Tab内部导航状态被保留**（这是 `indexedStack` 的核心特性，也是升级中风险最高的点）
3. 在任意Tab内触发一次 `context.push` 导航（例如首页点进详情页），确认页面正常跳转，系统返回键/手势返回正常回退到上一页
4. 验证详情页路由：`context.push` 到详情页时携带的 `state.pathParameters['mangaId']` 等路径参数正确解析（核实 `app_router.dart` 里 detail 路由的 path 定义）
5. 验证阅读器路由：从详情页进入阅读器，确认 `state.extra as Map<String, dynamic>?` 携带的 `chapterList`/`initialPage`/`mangaTitle`/`coverUrl` 全部正确传递并在阅读器里生效
6. 验证 webview 路由（用于登录/验证码等场景）：确认 `state.extra` 里的 `url` 正确传递
7. 依次触发全部 15 处 `context.push` 调用点（`reader_controls.dart`、`settings_screen.dart`/或拆分后的对应 section 文件、`home_screen.dart`、`discovery_screen.dart`、`update_screen.dart`、`search_screen.dart`、`cloudflare_dialog.dart`、`detail_screen.dart`、`history_screen.dart`），确认均正常跳转
8. 触发 `reader_controls.dart` 里的 1 处 `context.pop()`，确认阅读器返回按钮正常工作

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: upgrade go_router 14.x -> 15.x"
```

（若 Step 3/4 发现需要修改 `app_router.dart`/`app_shell.dart` 才能适配新版本 API，作为独立 commit：`fix: adapt to go_router 15.x StatefulShellRoute API changes`。）

---

### Task 4: 全量最终回归 + 更新 ROADMAP

**Files:**
- Modify: `ROADMAP.md`

- [ ] **Step 1: 全量分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 3: 完整手动走查主流程**

依次走一遍：首页 → 发现 → 搜索 → 详情 → 阅读器（含翻页/自动翻页/追加下一章）→ 设置（含各section）→ webview登录场景，确认三个包升级叠加后没有交互问题（例如 go_router 页面切换时 flutter_bloc 的 BlocProvider 生命周期是否正常）。

- [ ] **Step 4: 更新 ROADMAP.md**

Run: `grep -n "#26" ROADMAP.md`
把对应复选框从 `- [ ]` 改为 `- [x]`，并在条目后追加实际升级到的版本号记录：
```markdown
  - 已完成（2026-07-29）：flutter_lints 5.x / flutter_bloc 9.x / go_router 15.x
```

- [ ] **Step 5: Commit**

```bash
git add ROADMAP.md
git commit -m "docs: mark ROADMAP #26 as complete"
```
