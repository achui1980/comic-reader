# 花火漫画注册入口设计

**日期**: 2026-09-12
**状态**: 草案
**目标**: 在通用登录弹窗中为花火漫画补一个「去注册」入口，点击后跳系统浏览器打开站点注册页

---

## 1. 背景

花火漫画（`lib/data/sources/hanabi_manga.dart`，`HanabiManga`）是目前少数 `requiresLogin => true` 的源，它的 `loginDescription` 是「使用花火漫画账号登录后即可阅读免费章节」。也就是说，没有账号的用户什么都读不了。

问题出在通用登录弹窗（`lib/presentation/common/login_dialog.dart`，公开入口 `showLoginDialog(BuildContext, MangaSource)`）：弹窗里只有邮箱、密码两个 `TextField` 和一个登录按钮，没有任何「怎么拿到账号」的指引。用户如果还没注册，弹窗就是一条死路 —— 只能自己猜域名、自己去浏览器找注册页，或者干脆放弃这个源。

本次要做的就是把这条路补上：在登录弹窗里加一个通往站点注册页的入口。

## 2. 站点探测结论

对 `web.hanabimanga.com` 的注册流程做了一轮实际探测，结论如下：

- **注册页地址**：`https://web.hanabimanga.com/zh-CN/auth/register`。不带 locale 前缀的裸路径 `/auth/register` 会 308 重定向到带前缀的地址。
- **站点技术栈**：Next.js + next-intl。语言分 `zh-CN`（同时是 `x-default`）与 `zh-TW` 两套，locale 体现在 URL 路径前缀上。
- **注册表单字段**：邮箱、用户名（3–20 字符，输入时带实时唯一性校验）、昵称（可空）、邀请码（可空，填了送 3 天 VIP）、密码、确认密码。
- **无人机验证**：整页没有任何 captcha / Turnstile 之类的挑战。
- **提交之后**：站点跳到一个「验证邮箱」页面，提示「我们已向 xxx 发送了验证邮件，请查收并点击链接完成注册」。**注册必须过邮箱验证链接才算完成。**

最后这条是整个方案的关键前提，见下一节。

## 3. 方案取舍

### 3.1 跳系统浏览器，而不是内置 WebView 或 app 内自建注册表单

**决定性依据就是上面那条邮箱验证。** 注册流程的最后一步在用户的邮箱里，不在我们的页面里 —— 无论 app 内做得多完整，用户终究要离开 app 去收邮件、点链接。既然闭环本来就做不到，app 内自建表单的收益只剩「少跳一次浏览器」，代价却是要自己实现用户名实时唯一性校验、确认密码一致性、邀请码这一堆逻辑，而且这些规则完全由上游决定，上游一改我们就得跟着改。

内置 WebView 同理：它能显示页面，但依然接不上邮件那一步，还额外背上 WebView 的 cookie / 返回键 / 加载失败等一堆边界情况。

所以直接 `launchUrl(..., LaunchMode.externalApplication)` 交给系统浏览器。项目已依赖 `url_launcher: ^6.3.0`（`pubspec.yaml:73`），现有唯一用例 `lib/presentation/common/app_update_dialog.dart:38-41` 用的也正是 `externalApplication`，行为与依赖都无需新增。

### 3.2 入口只加在登录弹窗

现有能触发登录的路径有两条：设置页的「验证」按钮（`plugin_section.dart:74-89`）和发现页的源选择器（`discovery_screen.dart:139-146`）。这两条最终都调用同一个 `showLoginDialog`。所以只改登录弹窗一处，两条路径全覆盖，不需要在页面层重复插入入口。

### 3.3 打不开浏览器时复制链接到剪贴板 + 内联提示

`launchUrl` 会因为没有可用浏览器、平台限制等原因失败。失败时不能静默 —— 那样用户点了按钮什么都没发生，比没有按钮更糟。兜底做法是把注册链接写进剪贴板，并告诉用户「已复制，请自行粘贴到浏览器打开」。

提示复用弹窗里已有的 `String? _error` 内联红字机制，**不用 SnackBar**。原因是层级：SnackBar 走 `ScaffoldMessenger`，挂在 Scaffold 那一层；而 `AlertDialog` 位于 Navigator 的 overlay 层，压在 Scaffold 之上并带一层遮罩。从弹窗里弹 SnackBar，结果是它出现在弹窗背后、被遮罩压暗，用户很可能根本注意不到。内联红字就长在弹窗内部，视线不会跑偏。

## 4. 设计

### 4.1 `MangaSource.registerUrl` 契约

在 `lib/data/sources/manga_source.dart` 现有那组登录相关 getter（`requiresLogin` / `isAuthenticated` / `supportsAutoLogin` / `autoLoginEmail` / `autoLoginPassword` / `loginDescription`）之后，紧跟 `loginDescription` 新增：

```dart
/// 该源的注册页地址；返回 null 表示没有可直接跳转的注册入口
String? get registerUrl => null;
```

语义约定：

- 默认 `null`，所有现有源无需改动，行为不变。
- 返回非 null 即表示「这个源有一个可以直接用浏览器打开的公开注册页」。
- 基类不校验 URL 合法性，也不区分平台 —— 值由各源自己负责，能不能打开由 `url_launcher` 在运行时决定。

### 4.2 花火 override

`HanabiManga` 中已有 `static const String _baseUrl = 'https://web.hanabimanga.com';`，直接复用：

```dart
@override
String? get registerUrl => '$_baseUrl/auth/register';
```

**故意不带 `/zh-CN` 前缀。** 裸路径会被站点按请求的 `Accept-Language` 自行 308 到 `zh-CN` 或 `zh-TW`，用户拿到的是符合自己系统语言的那一版。硬编码 `/zh-CN` 反而会把繁体用户也按到简体上，同时多出一处需要跟随上游 locale 方案变化的常量。少写一处硬编码。

### 4.3 登录弹窗条件渲染

`login_dialog.dart` 里按 `source.registerUrl != null` 条件渲染一个 `TextButton.icon`：

- 有值才渲染，`null` 时整个按钮不出现 —— 其它源的弹窗外观完全不变。
- 文案「去注册」，配一个表示「将离开 app」的外链图标，让用户对跳浏览器有预期。
- 位置在密码输入框之后、与登录按钮同区，属于「登录不了的备选出口」。

### 4.4 `_openRegisterPage()` 流程

```
取 source.registerUrl（为 null 时按钮本就不存在，无需再判）
  ↓
launchUrl(uri, mode: LaunchMode.externalApplication)
  ↓ 返回 true                    ↓ 返回 false 或抛异常
系统浏览器已接手，弹窗保持原样      Clipboard.setData(链接)
                                  ↓
                                setState 写 _error：告知已复制、请手动粘贴打开
```

要点：`launchUrl` 需要包 try/catch，因为它在部分平台上是抛异常而非返回 false。进入这个流程时应先清掉上一次遗留的 `_error`，避免登录失败的旧错误和兜底提示互相串味。这里复用的是 `_error` 这个红字通道，语义上它承载的是「一条需要用户注意的内联提示」，不严格等于「登录出错」。

## 5. 已知局限

web 平台上 `url_launcher_web` 底层就是 `window.open`。当浏览器的弹窗拦截器拦掉这次打开时，它**可能仍然返回 true** —— 于是我们判定成功、什么都不做，而用户那边其实什么也没发生，剪贴板兜底覆盖不到这种情况。

这是 `url_launcher` 的已知行为，不为它额外造检测机制（比如轮询 `document.visibilityState` 或强行无条件复制剪贴板），代价与收益不成比例。web 端的主要场景是开发调试，真实用户在移动端不受影响。

## 6. 不做的事

- **弹窗里不预先解释邮箱验证。** 注册页提交后自己会给出「请查收验证邮件」的提示，我们再说一遍是重复告知，只会让弹窗变啰嗦。
- **不做 magic link / OTP 登录。** 站点支持，但那是另一套登录方式，超出「补一个注册入口」的范围。
- **不加「忘记密码」入口。** 同样超出本次范围，需要时另开。
