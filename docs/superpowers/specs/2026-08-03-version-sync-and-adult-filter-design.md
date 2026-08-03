# 设计文档:版本号同步 GitHub tag + 插件管理页隐藏成人数据源

日期: 2026-08-03
来源: `todo.md` 中两条待办事项

## 1. 同步软件版本号与 GitHub tag

### 问题

1. **App 侧**:`lib/presentation/settings/sections/about_section.dart` 第18行硬编码
   `subtitle: Text('版本 1.0.0')`,与 `pubspec.yaml` 的 `version: 1.2.1+6` 及任何
   GitHub tag 都无关联。
2. **CI 侧**:`.github/workflows/release.yml` 的 `build-macos` / `build-windows` /
   `build-android` 三个 job 的「Get version」步骤只识别
   `workflow_dispatch` 手动输入的 `version`,**没有识别由 `push: tags: 'v*'` 触发的场景**,
   会 fallback 到 `pubspec.yaml` 里的旧版本号。同时三处 `flutter build ... --release`
   命令都没有传 `--build-name`,导致编译产物内嵌的版本号始终等于 `pubspec.yaml` 当前值,
   与打的 tag 无关。只有 `release` job 的「Get version」步骤正确识别了 tag
   (`VERSION=${GITHUB_REF_NAME#v}`),造成 Release 标题/tag 与实际构建产物文件名、
   App 内嵌版本号三者可能不一致。

### 方案

- **App 侧**:引入 `package_info_plus` 依赖,将 `about_section.dart` 改为运行时通过
  `PackageInfo.fromPlatform()` 读取真实的 `version`(可选附加 `buildNumber`)并显示,
  替换硬编码字符串。
- **CI 侧**:在 `build-macos` / `build-windows` / `build-android` 三个 job 的
  「Get version」步骤中,补充与 `release` job 一致的版本解析优先级:
  `workflow_dispatch 输入的 version` > `若 github.ref_type == 'tag' 则用
  ${GITHUB_REF_NAME#v}` > `pubspec.yaml 中的版本号(fallback)`。
  不需要 `release` job 里"tag 已存在则追加 `-build.<run_number>`"的去重逻辑
  (那是为避免创建重名 tag,build job 不创建 tag,不涉及冲突)。
  然后在三处 `flutter build ... --release` 命令后追加
  `--build-name=${{ steps.version.outputs.version }}`,使编译产物内嵌版本号与
  tag 版本号一致。

### 验证

- Dart 侧:`flutter analyze` 通过;手动确认「关于」页面显示的版本号随
  `pubspec.yaml` 变化(本地跑一次 debug build 看效果)。
- CI 侧:通过静态检查 workflow YAML 语法正确性(`actionlint` 或 GitHub 直接校验);
  不在本次会话中实际打 tag 触发线上 workflow 验证,由用户后续自行验证。

## 2. 成人内容开关未开启时隐藏成人内容数据源

### 问题

基础设施已经完整实现且工作正常:
- `PluginInfo.isAdult` / `MangaSource.isAdult` 标记各数据源是否为成人内容。
- `SourceRegistry.enabled` getter 已正确按 `_adultUnlocked` 状态过滤成人源。
- 「设置 → 成人内容」开关本身、持久化 (`settings_store.dart`)、激活码校验
  (`activation_service.dart`) 均已正常工作。
- 消费 `registry.enabled` 的 UI(搜索、发现页)均已正确隐藏成人源。

唯一遗漏:`lib/presentation/settings/sections/plugin_section.dart` 第26行遍历的是
`state.plugins`(来自 `SettingsCubit.init()` 里未过滤的 `_sourceRegistry.all`),
而不是按开关过滤的列表。因此无论「成人内容」开关是否打开,「插件管理」列表始终会
列出全部成人数据源(仅带 18+ 图标提示,不隐藏)。

### 方案

- 在 `SettingsState` 新增派生 getter:
  ```dart
  List<PluginInfo> get visiblePlugins =>
      adultUnlocked ? plugins : plugins.where((p) => !p.isAdult).toList();
  ```
- 将 `plugin_section.dart` 中 `state.plugins.map(...)` 改为
  `state.visiblePlugins.map(...)`。
- 不改动 `settings_cubit.dart` 的 `init()` / `setAdultUnlocked()` /
  `unlockWithCode()` / `lockAdult()`,因为 `visiblePlugins` 是从 `state` 派生的
  只读 getter,会在每次 state 变化(包括开关切换)时自动重新计算。
- 保留现有行为:开关打开后,插件管理列表中的成人源仍显示 18+ 图标提示。

### 验证

- `flutter analyze` 通过。
- 手动/逐行核查:开关关闭时 `visiblePlugins` 不含 `isAdult == true` 的项;
  开关打开时包含全部项且行为与之前一致。
