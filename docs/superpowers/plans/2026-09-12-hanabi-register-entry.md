# 花火漫画注册入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在通用登录弹窗里给花火漫画加一个「去注册」入口,点击用系统浏览器打开花火官网注册页;打不开则把链接复制到剪贴板并内联提示。

**Architecture:** 在 `MangaSource` 基类新增 `String? get registerUrl => null`,把"有没有公开注册页"变成源的一项声明式能力;花火 override 它。登录弹窗读这个字段决定是否渲染入口按钮。这样其他源零改动、行为完全不变,未来任何源想加注册入口只需填一个 getter。

**Tech Stack:** Flutter / Dart,`url_launcher: ^6.3.0`(已在 `pubspec.yaml:73`,无需新增依赖),`flutter_test` + `mocktail` widget test。

## Global Constraints

- 所有面向用户的新文案用简体中文,硬编码在 Dart 源码里(本项目**无 i18n 方案**,`intl` 只用于日期格式化)。
- git commit message 用简体中文,`feat:`/`test:`/`docs:` 等前缀保留英文。
- 注册页 URL 用 `'$_baseUrl/auth/register'`,**不带 `/zh-CN` locale 前缀**——已实测裸路径 308 重定向到 `/zh-CN/auth/register`,让站点按 `Accept-Language` 自己选简/繁。
- `launchUrl` 用 `mode: LaunchMode.externalApplication`,与既有唯一用例 `lib/presentation/common/app_update_dialog.dart:38-41` 一致。
- 用弹窗已有的 `_error` 内联红字做失败提示,**不用 SnackBar**(AlertDialog 在 Navigator overlay 层,`ScaffoldMessenger` 的 SnackBar 会被遮罩压暗)。
- 不改 `plugin_section.dart`、不改 `discovery_screen.dart`、不改 DI、不改路由、不改 `AuthStore`。
- 本计划涉及的测试都不需要 native asset,**不必** stage `wasm_run_dart.framework`。
- **不要跑全量 `flutter test`**:`test/verify_*.dart` / `test/check_jmc_chapters.dart` 是手动联网脚本,`test/widget_test.dart` 本身就是坏的。只跑本计划点名的测试文件。

---

### Task 0: 落盘设计文档

**Files:**
- Create: `docs/superpowers/specs/2026-09-12-hanabi-register-entry-design.md`

**Interfaces:**
- Consumes: 无(本任务是起点)
- Produces: 无代码产物,仅文档

- [ ] **Step 1: 写设计文档**

内容需包含以下小节(正文中文):

1. **背景** — 花火漫画 `requiresLogin => true`,用户没账号时登录弹窗是死路,没有任何获取账号的指引。
2. **站点探测结论** — 注册页 `https://web.hanabimanga.com/zh-CN/auth/register`(裸 `/auth/register` 会 308 到它);站点是 Next.js + next-intl,支持 `zh-CN`(x-default)/`zh-TW`;注册表单字段为邮箱、用户名(3-20 字符,带实时唯一性校验)、昵称(可空)、邀请码(可空,给 3 天 VIP)、密码、确认密码;页面无任何 captcha/turnstile;**提交后站点显示「验证邮箱 / 我们已向 xxx 发送了验证邮件,请查收并点击链接完成注册」**。
3. **方案取舍** — 记录三个决策及理由:
   - 跳系统浏览器,而非内置 WebView 或 app 内自建注册表单。**决定性依据是上面那条邮箱验证**:注册必须过邮件链接,app 内做表单也无法闭环,用户终究要离开 app 收邮件,自建表单只是徒增用户名唯一性校验、确认密码、邀请码等一堆需要跟随上游变化的逻辑。
   - 入口只加在登录弹窗。设置页「验证」按钮(`plugin_section.dart:74-89`)和发现页源选择器(`discovery_screen.dart:139-146`)这两条现有路径最终都会调 `showLoginDialog`,一处改动全覆盖。
   - 打不开浏览器时复制链接到剪贴板 + 内联提示。
4. **设计** — `MangaSource.registerUrl` getter 契约;花火 override;登录弹窗条件渲染 `TextButton.icon`;`_openRegisterPage()` 的 launch → 失败 → 剪贴板兜底流程。
5. **已知局限** — web 平台 `url_launcher_web` 底层是 `window.open`,被浏览器拦弹窗时**可能仍返回 true**,剪贴板兜底覆盖不到。这是 `url_launcher` 的已知行为,不为此额外造机制。
6. **不做的事** — 弹窗里不预先解释邮箱验证(注册页自己会提示,属重复告知);不做 magic link / OTP 登录(站点支持,但超出本次范围);不加「忘记密码」入口。

- [ ] **Step 2: 提交**

```bash
git add docs/superpowers/specs/2026-09-12-hanabi-register-entry-design.md
git commit -m "docs: 添加花火漫画注册入口设计文档"
```

---

### Task 1: `MangaSource.registerUrl` 契约 + 花火实现

**Files:**
- Modify: `lib/data/sources/manga_source.dart:159-161`(在 `loginDescription` getter 之后插入)
- Modify: `lib/data/sources/hanabi_manga.dart:158-159`(在 `loginDescription` override 之后插入)
- Test: `test/data/sources/hanabi_manga_test.dart`(在 `HanabiManga login/session` group 内追加,该 group 起于 `:313`)

**Interfaces:**
- Consumes: 无(本任务是代码起点)
- Produces: `MangaSource` 上的实例 getter `String? get registerUrl`(默认返回 `null`)。Task 2 的 UI 和 Task 3 的 widget test 都依赖这个名字和类型。

- [ ] **Step 1: 写失败的测试**

在 `test/data/sources/hanabi_manga_test.dart` 里,`group('HanabiManga login/session', () { ... })` 的最后一个 `test(...)` 之后追加:

```dart
    test('registerUrl points at the Hanabi sign-up page', () {
      final source = HanabiManga();
      expect(source.registerUrl, 'https://web.hanabimanga.com/auth/register');
    });
```

- [ ] **Step 2: 跑测试确认失败**

```bash
flutter test test/data/sources/hanabi_manga_test.dart --plain-name "registerUrl points at the Hanabi sign-up page"
```

预期:编译失败,报 `The getter 'registerUrl' isn't defined for the class 'HanabiManga'`。

- [ ] **Step 3: 在基类加 getter**

`lib/data/sources/manga_source.dart`,在

```dart
  /// Optional description shown above the email/password fields in the
  /// generic login dialog (see lib/presentation/common/login_dialog.dart).
  String? get loginDescription => null;
```

之后、`buildSignInRequest` 的文档注释之前,插入:

```dart

  /// Public sign-up page for this source. When non-null, the generic login
  /// dialog shows a "go register" entry that opens this URL in the user's
  /// external browser. Null means the source has no self-service
  /// registration to advertise.
  String? get registerUrl => null;
```

- [ ] **Step 4: 在花火 override**

`lib/data/sources/hanabi_manga.dart`,在

```dart
  @override
  String? get loginDescription => '使用花火漫画账号登录后即可阅读免费章节';
```

之后、`isAuthenticated` getter 之前,插入:

```dart

  /// The bare path 308-redirects to the locale-prefixed URL (e.g.
  /// /zh-CN/auth/register), so let the site pick the locale from
  /// Accept-Language instead of hardcoding one here.
  @override
  String? get registerUrl => '$_baseUrl/auth/register';
```

- [ ] **Step 5: 跑测试确认通过**

```bash
flutter test test/data/sources/hanabi_manga_test.dart
```

预期:全部 PASS(含新增那条)。

- [ ] **Step 6: 静态检查**

```bash
flutter analyze lib/data/sources/manga_source.dart lib/data/sources/hanabi_manga.dart
```

预期:`No issues found!`

- [ ] **Step 7: 提交**

```bash
git add lib/data/sources/manga_source.dart lib/data/sources/hanabi_manga.dart test/data/sources/hanabi_manga_test.dart
git commit -m "feat: MangaSource 新增 registerUrl 契约并为花火漫画填入注册页"
```

---

### Task 2: 登录弹窗渲染注册入口并打开浏览器

**Files:**
- Modify: `lib/presentation/common/login_dialog.dart`(加 2 个 import;`_LoginDialogState` 加 `_openRegisterPage()`;`build()` 的 content 里 `:211` 之后、`:212` 的 `if (_error != null)` 之前插入按钮行)

**Interfaces:**
- Consumes: Task 1 的 `MangaSource.registerUrl`(`String?`)。
- Produces: 用户可见文案常量 `'还没有账号？去注册'`(注意是**全角问号**)和失败文案 `'无法打开浏览器，注册链接已复制到剪贴板'`(全角逗号)。Task 3 的 widget test 按这两个字符串做 `find.text`,必须逐字符一致。

**现有文件事实(已核实):**
- `_LoginDialogState` 起于 `:82`,字段有 `_loading`(`:89`)、`_error`(`:90`)、`_obscurePassword`(`:91`);`_login()` 是 `:100-158`。
- `build()` 起于 `:161`,**`:162` 已有 `final source = widget.source;`**,直接复用,不要新建局部变量。
- content 是 `SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, children: [...]))`;children 依次为说明文字(`:176-179`)、`SizedBox(height:16)`、邮箱 `TextField`(`:181-191`)、`SizedBox(height:12)`、密码 `TextField`(`:193-211`)、`if (_error != null) ...[...]`(`:212-218`)。
- `actions` 是「取消 / 登录」两项,**保持不动**。

- [ ] **Step 1: 加 import**

`lib/presentation/common/login_dialog.dart` 顶部,现有 `import 'package:flutter/foundation.dart';` / `import 'package:flutter/material.dart';` 旁边补两行(跟随 `lib/presentation/webview/webview_web.dart:1-2` 显式 import `services.dart` 的既有惯例):

```dart
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
```

按文件现有 import 排序惯例放置(`flutter/` 组内 `services` 排在 `material` 之后;`url_launcher` 属第三方包组)。

- [ ] **Step 2: 加 `_openRegisterPage()`**

在 `_LoginDialogState` 里,`_login()`(`:100-158`)之后、`build()`(`:160` 的 `@override`)之前插入:

```dart
  Future<void> _openRegisterPage() async {
    final url = widget.source.registerUrl;
    if (url == null) return;

    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (opened) return;

    // No browser available (or the platform refused). Hand the user the URL
    // instead of dead-ending. Uses the dialog's own inline error text rather
    // than a SnackBar: this AlertDialog sits in the Navigator overlay, above
    // the Scaffold that ScaffoldMessenger would render the SnackBar into.
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _error = '无法打开浏览器，注册链接已复制到剪贴板');
  }
```

- [ ] **Step 3: 在 content 里插入按钮行**

`build()` 里,密码 `TextField` 的闭合 `),`(`:211`)之后、`if (_error != null) ...[`(`:212`)之前插入:

```dart
            if (source.registerUrl != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loading ? null : _openRegisterPage,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('还没有账号？去注册'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
```

- [ ] **Step 4: 静态检查**

```bash
flutter analyze lib/presentation/common/login_dialog.dart
```

预期:`No issues found!`

- [ ] **Step 5: 跑既有登录测试确认没回归**

```bash
flutter test test/presentation/common/login_dialog_test.dart
```

预期:既有 2 条 `tryAutoLogin` 测试仍 PASS(它们的 fake 源 `registerUrl` 为基类默认 `null`,按钮不渲染)。

- [ ] **Step 6: 提交**

```bash
git add lib/presentation/common/login_dialog.dart
git commit -m "feat: 登录弹窗为有注册页的源展示去注册入口"
```

---

### Task 3: 注册入口的 widget test

**Files:**
- Modify: `test/presentation/common/login_dialog_test.dart`(**文件已存在,158 行,是追加不是新建**)

**Interfaces:**
- Consumes: Task 1 的 `MangaSource.registerUrl`;Task 2 的文案 `'还没有账号？去注册'` 与图标 `Icons.open_in_new`。
- Produces: 无(终点任务)。

**现有文件事实(已核实):**
- imports 有 `core/models/fetch_config.dart`、`data/local/auth_store.dart`、`data/remote/http_client.dart`、`data/sources/manga_source.dart`、`data/sources/source_registry.dart`、`domain/entities/entities.dart`、`presentation/common/login_dialog.dart`、`dio`、`flutter_test`、`get_it`、`mocktail`。**当前没有 `flutter/material.dart`。**
- `class _FakeAutoLoginSource extends MangaSource` 在 `:17-95`,有可变字段 `bool authenticated = false;`,override 了 `isAuthenticated => authenticated`、`requiresLogin => true`、`supportsAutoLogin => true`、`autoLoginEmail => 'user@example.com'`、`autoLoginPassword => 'password'` 等。
- `main()` 起于 `:97`,`setUp` 里创建共享变量 `source`(`_FakeAutoLoginSource`)并 `registry.register(source)`,同时把 `HttpClient`/`AuthStore`/`SourceRegistry` 注册进 GetIt。
- 既有 2 条测试结束于 `:157`。新内容追加在其后、`main()` 闭合花括号之前。

**不测实际跳转。** `url_launcher` 在测试环境没有 platform channel,测跳转要 mock `UrlLauncherPlatform`,收益低于成本。这里只锁"按 `registerUrl` 有无正确显示/隐藏入口"这一条行为——而 `registerUrl` 为 null 的用例同时也覆盖了基类默认值。

- [ ] **Step 1: 补 material import**

在 import 区补:

```dart
import 'package:flutter/material.dart';
```

- [ ] **Step 2: 给 fake 源加可控的 registerUrl**

`class _FakeAutoLoginSource extends MangaSource`(`:17-95`)里,在已有的 `bool authenticated = false;` 字段旁加:

```dart
  String? registerUrlValue;
```

并在 `isAuthenticated` override 附近加:

```dart
  @override
  String? get registerUrl => registerUrlValue;
```

默认 `null`,所以既有两条 `tryAutoLogin` 测试不受影响。

- [ ] **Step 3: 写失败的测试**

在 `main()` 内,最后一个既有 `test(...)`(结束于 `:157`)之后、`main()` 闭合花括号之前,追加:

```dart
  group('register entry', () {
    Future<void> pumpAndOpenDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showLoginDialog(context, source),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('is hidden when the source has no registerUrl', (tester) async {
      source.registerUrlValue = null;

      await pumpAndOpenDialog(tester);

      expect(find.text('还没有账号？去注册'), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    });

    testWidgets('is shown when the source exposes a registerUrl', (
      tester,
    ) async {
      source.registerUrlValue = 'https://example.com/auth/register';

      await pumpAndOpenDialog(tester);

      expect(find.text('还没有账号？去注册'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });
  });
```

`source` 是 `setUp` 里已创建并注册进 `SourceRegistry` 的那个 `_FakeAutoLoginSource` 共享变量,直接用。

- [ ] **Step 4: 跑测试**

```bash
flutter test test/presentation/common/login_dialog_test.dart
```

预期:4 条全 PASS(既有 2 条 + 新增 2 条)。若 `is shown` 那条报 `findsNothing`,说明 Task 2 Step 3 的条件渲染没生效或文案标点不一致(检查全角问号)。

- [ ] **Step 5: 静态检查**

```bash
flutter analyze test/presentation/common/login_dialog_test.dart
```

预期:`No issues found!`

- [ ] **Step 6: 提交**

```bash
git add test/presentation/common/login_dialog_test.dart
git commit -m "test: 覆盖登录弹窗注册入口的显示与隐藏"
```

---

### Task 4: 收尾验证与知识图谱刷新

**Files:**
- Modify: `graphify-out/`(由 `graphify update .` 自动生成)

**Interfaces:**
- Consumes: Task 1-3 的全部改动
- Produces: 无

- [ ] **Step 1: 全量静态检查**

```bash
flutter analyze
```

预期:本计划触及的 3 个 lib 文件 + 2 个 test 文件零新增 error/warning。仓库存在既有的无关问题(如 `test/verify_ehentai_chapter.dart` 的 2 个 pre-existing errors),确认与本次改动无关即可。

- [ ] **Step 2: 跑相关测试(不跑全量)**

```bash
flutter test test/data/sources/hanabi_manga_test.dart test/presentation/common/login_dialog_test.dart
```

- [ ] **Step 3: 手工验收(需真机/模拟器,由人类执行)**

```bash
bash tools/prefetch_wasm_run.sh
flutter run -d macos
```

路径:设置 → 插件管理 → 花火漫画「验证」→ 弹窗里应看到「还没有账号？去注册」→ 点击应在系统浏览器打开 `web.hanabimanga.com`,并落到中文注册页。另确认 PicaComic 等源的登录弹窗**没有**这个按钮。

- [ ] **Step 4: 刷新知识图谱**

```bash
graphify update .
```

- [ ] **Step 5: 提交图谱变更(若有)**

```bash
git add graphify-out
git commit -m "chore: 刷新 graphify 知识图谱"
```

---

## Self-Review

- **规格覆盖:** 三个已确认决策各有对应任务(Task 1 = 能力契约 + 花火 URL;Task 2 = 弹窗入口 + 跳浏览器 + 剪贴板兜底;Task 3 = 测试)。设计里提到的所有改动文件都在计划中。
- **一处修正:** 原设计说 `test/presentation/common/login_dialog_test.dart` 是"新增文件",实为已存在的 158 行文件,Task 3 已改为追加,并明确要补 `material.dart` import。
- **一处范围收窄:** 原设计提到"断言基类默认为 null(用一个最小 fake source)"。已收窄为只测 UI 行为:Task 3 的 `is hidden when the source has no registerUrl` 用例覆盖"`registerUrl` 为 null 时不渲染入口",不再单造一次性 fake 去断言基类默认值本身。**注意该用例并不覆盖 `MangaSource.registerUrl => null` 这一行**——测试 fake 自己 override 了该 getter(`=> registerUrlValue`),基类实现永不执行。基类默认值靠"`lib/` 内无任何其他源覆写它"这一静态事实保障,无常驻测试;这是已知且已接受的空洞,记在 ledger 的 Minor deferred 里。
- **命名一致性:** 全程只用 `registerUrl`(基类/花火 getter)与 `registerUrlValue`(测试 fake 的可写字段)、`_openRegisterPage`(弹窗方法),三者在各任务间引用一致。
