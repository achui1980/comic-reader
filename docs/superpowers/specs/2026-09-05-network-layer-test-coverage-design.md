# 设计文档：网络层测试覆盖

日期: 2026-09-05
来源: 项目健康度头脑风暴（AGENTS.md 明确标注 `lib/data/remote/` 是"单一网络出口"，一旦改动出错影响全部 34 个源；探索确认该目录 7 个文件目前零测试）

## 背景

`lib/data/remote/` 下共 7 个文件，984 行，目前无任何单测覆盖：

| 文件 | 行数 |
| --- | --- |
| `http_client.dart` | 165 |
| `webview_fetcher_native.dart` | 486 |
| `cloudflare_interceptor.dart` | 113 |
| `cors_proxy_interceptor.dart` | 68 |
| `webview_fetcher.dart` | 72 |
| `source_interceptor.dart` | 40 |
| `webview_fetcher_stub.dart` | 40 |

`http_client.dart` 是 AGENTS.md 明确标注的"single network exit"——所有 34 个数据源的请求都经过它，是全仓库风险最集中、ROI 最高的未测区域。

## 范围

| 文件 | 处理方式 |
| --- | --- |
| `http_client.dart` | 完整测试 |
| `cloudflare_interceptor.dart` | 完整测试 |
| `cors_proxy_interceptor.dart` | 小改造后测试 |
| `source_interceptor.dart` | 轻量 smoke test |
| `webview_fetcher_stub.dart` | 轻量 smoke test |
| `webview_fetcher.dart` | 不测（纯类型定义+条件导入胶水，无独立逻辑） |
| `webview_fetcher_native.dart` | **排除**，见下方说明 |

### 为什么排除 `webview_fetcher_native.dart`

核心逻辑（`_SourceWebView.ensureReady` 轮询 DOM ready、`fetch()` 通过 `callAsyncJavaScript` 注入 JS 执行浏览器内 `fetch`、`fetchRendered()` 做真实导航后读 `outerHTML`）全部依赖 `flutter_inappwebview` 的 `HeadlessInAppWebView`/`InAppWebViewController` 等具体平台类运行。这些类不是抽象接口，`mocktail` 无法对其打洞，标准 `flutter test`（Dart VM）也无法启动真实 WebView 引擎。要测它需要 `plugin_platform_interface` 级别的 mock 或真机/模拟器集成测试，是完全不同量级的工作。本次设计将其标注为"out of scope，需要未来单独的集成测试计划"，不纳入本轮。

## 测试文件组织

新建 `test/data/remote/` 目录（当前不存在），每个源文件对应一个测试文件：

```
test/data/remote/
├── http_client_test.dart
├── cloudflare_interceptor_test.dart
├── cors_proxy_interceptor_test.dart
├── source_interceptor_test.dart
└── webview_fetcher_stub_test.dart
```

## 测试技术方案

不引入任何新的 dev 依赖包——`mocktail: ^1.0.3` 和 `bloc_test: ^10.0.0` 已在 `pubspec.yaml` 中。

### `http_client.dart`

`Dio` 本身是 `abstract class Dio`（dio 5.9.2），可直接 mock：

```dart
class MockDio extends Mock implements Dio {}
class MockWebViewFetcher extends Mock implements WebViewFetcher {}
```

stub `dio.request<T>(...)` 返回预制 `Response` 或抛出 `DioException`，测试 `HttpClient.execute()` 自身的逻辑（不涉及真实网络或 interceptor 链——interceptor 逻辑单独测，职责分离更清晰）。覆盖点：

- 无 `useWebViewFetch`/`cloudflareUrl` 时走 Dio 路径（`dio.request` 被调用，`fetcher.fetch` 未被调用）
- `useWebViewFetch`+`cloudflareUrl` 都满足但 `fetcher == null` 或 `fetcher.isSupported == false` 时仍回退 Dio 路径
- 两个条件都满足且 `isSupported == true` 时走 WebView 路径（`fetcher.fetch` 被调用，`dio.request` 未被调用）
- WebView 路径下 `responseType: bytes` 返回 `List<int>`／`responseType: text`（含默认 json）返回字符串/解析后的 body，两种分支各测一次
- WebView 返回结果 `statusCode` ∈ [200, 400) 时返回正常 `Response`；否则抛出 `DioException(type: DioExceptionType.badResponse)`
- `_resolveUrl` 的查询参数合并逻辑：普通 key 合并、重复 key（如 `includes[]=x&includes[]=y`）不丢失

### `cloudflare_interceptor.dart`

直接构造真实的 `RequestOptions`/`Response`/`DioException`，配合 mocktail mock 的 handler：

```dart
class MockResponseInterceptorHandler extends Mock implements ResponseInterceptorHandler {}
class MockErrorInterceptorHandler extends Mock implements ErrorInterceptorHandler {}
```

调用 `interceptor.onResponse(response, handler)` / `interceptor.onError(err, handler)`，用 `verify(() => handler.reject(any())).called(1)` 或 `verify(() => handler.next(any())).called(1)` 断言行为（不依赖 handler 内部的 `Completer`/`.future`，避免触碰 `@protected` 成员产生 lint 噪音）。覆盖点：

- `onResponse`：命中 CF 挑战标题（`Just a moment...`、`Attention Required! | Cloudflare`）→ reject 为 `CloudflareException`
- `onResponse`：命中 CF 特征字符串（`challenges.cloudflare.com`、`cf-browser-verification`、`cf_chl_opt`）→ reject
- `onResponse`：正常 HTML/JSON 响应 → next（放行）
- `onError`：403 + HTML 内容命中 CF 特征 → reject 为 `CloudflareException`
- `onError`：403 + source 声明 `needsCloudflare == true` → reject 为 `CloudflareException`（即使响应体本身不含 CF 特征字符串）
- `onError`：非 403 或不满足以上条件的错误 → next（原样透传）

### `cors_proxy_interceptor.dart`

`kIsWeb` 是编译期常量，标准 `flutter test`（VM）下恒为 `false`，无法测到 `if (kIsWeb) {...}` 内部的核心改写逻辑。做一个最小可测试性改造：

```dart
class CorsProxyInterceptor extends Interceptor {
  CorsProxyInterceptor({bool isWeb = kIsWeb}) : _isWeb = isWeb;
  final bool _isWeb;
  // onRequest 里原来判断 kIsWeb 的地方改判断 _isWeb
}
```

默认值仍是 `kIsWeb`，生产环境行为完全不变；测试时传 `isWeb: true` 强制走 web 分支。覆盖点：

- `isWeb: false` 时 `onRequest` 不改写请求（URL/headers 原样传递）
- `isWeb: true` 时正确拼接 proxy URL，且禁止 header（user-agent/host/origin/referer/cookie/connection/content-length/accept-encoding）被转移到对应 `X-Proxy-*` header，原 header 被移除

### `source_interceptor.dart` / `webview_fetcher_stub.dart`

轻量 smoke test，各 1-2 个：

- `source_interceptor.dart`：验证 `onRequest`/`onResponse`/`onError` 均只是记录日志后调用 `handler.next(...)`，不修改传入的 options/response/error（pass-through 行为不变）
- `webview_fetcher_stub.dart`：验证 `isSupported == false`；`fetch(...)` 抛出 `UnsupportedError`

## 不做的事

- 不改动任何生产行为逻辑（唯一的生产代码改动是 `cors_proxy_interceptor.dart` 构造函数新增可选参数，默认值保证零行为变化）
- 不引入新的 dev 依赖包
- 不测 `webview_fetcher_native.dart`（见上）和 `webview_fetcher.dart`（无独立逻辑）

## 验证

- `flutter analyze` 对 5 个改动/新增文件通过
- 5 个新测试文件全部通过 `flutter test test/data/remote/`
- 确认 `cors_proxy_interceptor.dart` 的构造函数改动不影响现有调用方（`lib/app/di/injection.dart` 中 `CorsProxyInterceptor()` 无参调用，因默认值兜底，无需改动调用点）

## 影响范围小结

| 文件 | 改动类型 |
| --- | --- |
| `lib/data/remote/cors_proxy_interceptor.dart` | 构造函数新增可选 `isWeb` 参数（默认 `kIsWeb`，行为不变） |
| `test/data/remote/http_client_test.dart` | 新建 |
| `test/data/remote/cloudflare_interceptor_test.dart` | 新建 |
| `test/data/remote/cors_proxy_interceptor_test.dart` | 新建 |
| `test/data/remote/source_interceptor_test.dart` | 新建 |
| `test/data/remote/webview_fetcher_stub_test.dart` | 新建 |

纯增量工作（新增测试为主，唯一的生产代码改动是一个零行为变化的可测试性改造），无依赖其他优化方向。
