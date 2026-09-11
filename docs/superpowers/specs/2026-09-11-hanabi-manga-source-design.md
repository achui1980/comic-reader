# HanabiManga 数据源集成设计

**日期**: 2026-09-11
**状态**: 草案
**目标**: 在 comic-reader 中集成花火漫画 (hanabimanga.com) 作为新的漫画源插件，并将现有仅供 PicaComic 使用的账号登录 UI 泛化为通用组件

---

## 1. 概述

### 1.1 目标网站

- **名称**: 花火漫画 (HanabiManga)
- **域名**: `web.hanabimanga.com`（固定域名，无需动态发现）
- **后端**: Next.js SSR 前端 + 自建 API（`server: Photon-Edge`）+ Supabase（project ref `uhkvqrxmcapgtpspglrp`，鉴权/会员/进度等辅助数据）
- **图片 CDN**: `cdn.hanabimanga.top`（带时效签名 `?t=<unix>&sign=<sig>`）
- **内容范围**: 本次只做**免费/普通章节**阅读；遇到 VIP 专属章节时直接提示"该章节需要 VIP，暂不支持"，不做购买/解锁流程

### 1.2 核心技术挑战

| 层次 | 说明 |
|------|------|
| 登录 | 标准 Supabase Auth REST（无需 WebView），但站点 API 只认自定义格式的 Cookie，不认 `Authorization` header |
| 会话 | 需手工构造 Supabase SSR 风格 Cookie（含超长值切片规则），通过现有 `extraHeaders`/`AuthStore` 机制注入 |
| 章节列表 | 完整章节数据以**反斜杠转义的 JSON 字符串**内嵈在详情页 HTML 的 Next.js RSC flight payload 中，需专用提取算法 |
| 图片反扰码 | 官方用 WASM 模块 (`/reader.wasm`, wasm-bindgen 产物) 做 unscramble，且官方阅读器有反提取 DRM（成功渲染后立即废掉 canvas 的 `toDataURL`/`toBlob`/`getImageData`） |

---

## 2. 架构设计

### 2.1 新增/修改文件

```
lib/data/sources/hanabi_manga.dart                    # 新源主体（MangaSource子类）
lib/data/repositories/hanabi_wasm_unscrambler.dart     # WASM 反扰码封装
lib/presentation/reader/widgets/hanabi_memory_image.dart  # 反扰码后图片显示 widget
lib/presentation/common/login_dialog.dart              # 通用邮箱密码登录框（重构自 pica_login_dialog.dart）
lib/app/di/injection.dart                               # 注册新源
lib/data/sources/pica_comic.dart                        # 改用泛化后的通用登录逻辑
lib/presentation/discovery/discovery_screen.dart         # 改用通用登录判断（替换 `if (source is PicaComic)`）
lib/presentation/settings/sections/plugin_section.dart    # 同上
```

### 2.2 架构层级

```
HanabiManga (MangaSource)
  ├── requiresLogin => true / isAuthenticated => 依据本地 expires_at
  ├── buildSignInRequest / parseSignIn         → Supabase Auth 直连登录
  ├── refreshSession()                          → Supabase refresh_token 刷新
  ├── prepareDiscoveryFetch / parseDiscovery    → SSR HTML 解析（/browse 页）
  ├── prepareSearchFetch / parseSearch          → Supabase RPC JSON（search_comics_pgroonga）
  ├── prepareMangaInfoFetch / parseMangaInfo    → SSR HTML 解析详情页元数据
  ├── prepareChapterListFetch                   → 返回 null（章节已内嵌详情页 HTML）
  ├── parseChapterList                          → 从详情页 HTML 的 RSC flight payload 提取
  ├── prepareChapterFetch / parseChapter        → GET /api/reader/comic/{id}/{slug}（JSON）
  └── HanabiWasmUnscrambler（图片反扰码，UI侧调用）
        ├── ensureWasmLoaded()   → 下载/缓存 /reader.wasm 并实例化
        ├── unscramble(imageBytes, ticket, nonce, cols, rows) → RGBA字节
        └── 封装 wasm-bindgen 调用约定（内存分配/写入/读取/释放）
```

### 2.3 与现有架构的集成点

- **DI 注册**: `lib/app/di/injection.dart` 中 `registry.register(HanabiManga())`
- **ScrambleType 扩展**: 新增 `ScrambleType.hanabi`
- **ChapterImage 扩展**: 新增 `hanabiTicket`/`hanabiNonce`/`hanabiCols`/`hanabiRows` 字段（仿 Wu55Comic 的 `wu55BookId`/`wu55PageNumber` 模式）
- **登录存储**: 复用现有 `AuthStore`（`lib/data/local/auth_store.dart`），无需新存储机制
- **登录 UI 泛化**: 把 `pica_login_dialog.dart` 重构为 `lib/presentation/common/login_dialog.dart`，接收 `MangaSource source` 参数，`showLoginDialog(context, source)` 通用签名；`discovery_screen.dart`/`plugin_section.dart` 中原先 `if (source is PicaComic)` 替换为 `if (source.requiresLogin && !source.isAuthenticated)`

---

## 3. 登录与会话管理

### 3.1 登录 API（Supabase Auth 直连，纯 HTTP，无需 WebView）

```
POST https://uhkvqrxmcapgtpspglrp.supabase.co/auth/v1/token?grant_type=password
Headers: apikey: <anon key>, Content-Type: application/json
Body: {"email": "...", "password": "..."}
```

公开 anon key（可安全硬编码）:
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoa3ZxcnhtY2FwZ3Rwc3BnbHJwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5NjgzMjksImV4cCI6MjA3OTU0NDMyOX0.uuHr888lp14ObW5eWowJrHPJGgQf3sF2l7NPmFN84g4
```

成功响应:
```json
{
  "access_token": "...", "token_type": "bearer", "expires_in": 3600,
  "expires_at": 1234567890, "refresh_token": "...",
  "user": {"id": "...", "email": "...",
    "app_metadata": {"provider": "...", "vip_expiration_date": null, "vip_is_lifetime": false},
    "user_metadata": {"avatar_url": "...", "username": "..."}}
}
```

刷新走同一端点，`grant_type=refresh_token`，body 为 `{"refresh_token": "..."}`。

`buildSignInRequest(email, password)` 返回上述 POST 的 `FetchConfig`；`parseSignIn(response)` 解析出 access_token/refresh_token/expires_at/user，调用 `_persistSession(...)` 完成登录状态更新并返回 `true`/`false`。

### 3.2 会话验证 = 只认 Cookie，不认 Authorization Header（关键陷阱）

实测确认：带 `Authorization: Bearer <access_token>` 但不带 cookie 访问 `web.hanabimanga.com/api/*`，服务端仍返回 429 `ANON_QUOTA_EXCEEDED`（`authMode: "anon"`）——该 Next.js 应用的 API 路由只从**请求 Cookie** 里解析 session（通过 `@supabase/ssr` 服务端 helper），完全忽略 Authorization header。

真实 cookie 名: `sb-uhkvqrxmcapgtpspglrp-auth-token`
真实 cookie 值: `base64-` + base64(`JSON.stringify({access_token, token_type:"bearer", expires_in, expires_at, refresh_token, user:{...}})`)

若该字符串长度超过约 3180 字符（supabase-ssr 默认 chunk 阈值），拆分成多个同名后缀 cookie：`sb-uhkvqrxmcapgtpspglrp-auth-token.0`、`.1`、`.2`...，服务端按后缀数字顺序拼接还原。

**实现**: 登录/刷新成功后，在 `HanabiManga` 内部按上述规则构造完整 Cookie 字符串（含超长切片），通过 `syncExtraData({'Cookie': cookieHeaderValue})` 写入 `extraHeaders`（走现有 `mergeHeaders` 机制自动附加到所有后续请求，无需在每个 `prepare*Fetch` 里手动加 header）。同时把 `access_token`/`refresh_token`/`expires_at`/`user` 存入内部字段，并调用 `AuthStore.saveExtra(id, {...})` 持久化（下次启动时通过现有的"恢复每源 auth"启动流程自动恢复，见 `AGENTS.md` 中 `lib/main.dart` 启动顺序）。

### 3.3 Token 过期与刷新（懒式检测，无 401 自动重试）

`manga_source.dart` 的五个 `prepare*Fetch` 方法均为同步签名，无法做 async 刷新拦截。采用与 Pica 一致的懒式模式：

- `isAuthenticated` getter：依据本地持久化的 `expires_at` 是否已过期判断
- 新增 `Future<bool> refreshSession()` 方法：调用 `grant_type=refresh_token` 端点，成功则重新构造 Cookie 并持久化，返回 `true`
- UI 侧（`discovery_screen.dart`/`plugin_section.dart`）在用户进入源/点击源时：若 `isAuthenticated` 但 `expires_at` 在 5 分钟内到期，先调用一次 `refreshSession()`；若 `!isAuthenticated`（未登录或刷新失败），弹出通用 `showLoginDialog(context, source)`
- 若 `refreshSession()` 失败（refresh_token 也失效），调用 `clearExtraData()` + `AuthStore.clearSource(id)`，视为未登录，走登录 dialog

### 3.4 登录 UI 泛化

将 `pica_login_dialog.dart` 重构为 `lib/presentation/common/login_dialog.dart`：

```dart
Future<bool?> showLoginDialog(BuildContext context, MangaSource source);
class _LoginDialog extends StatefulWidget {
  final MangaSource source;
  // AlertDialog + 邮箱/密码 TextField，调用 source.buildSignInRequest/parseSignIn
}
```

`PicaComic` 保留其专属的 `picaAutoLogin()`（内置账号静默登录），但登录弹窗改为共享组件。调用点统一改为 `if (source.requiresLogin && !source.isAuthenticated) showLoginDialog(context, source)`，去掉硬编码的 `if (source is PicaComic)` 判断。

---

## 4. Discovery / Search / 详情页技术实现

### 4.1 Discovery（`/browse` 页，纯 SSR，无 JSON 接口）

实测确认 `/browse` 页面没有任何 XHR/fetch 请求返回列表数据——**完全 SSR 服务器渲染**，与 wu55/ikan 模式一致，需直接用 `html` 包 CSS 选择器解析整页 HTML。

- URL: `https://web.hanabimanga.com/zh-CN/browse?category={cat}&sort={sort}&region={region}&status={status}&page={page}`
- 分页: 标准 query param `page`（从 1 开始）
- 筛选参数（均为 URL query，非 path）:
  - `category`: 分类 slug（27 个可选值，见 4.4；`全部`不传该参数）
  - `sort`: 排序方式（按钮为 推荐/评分/最近更新/最新上架；已验证 `rating` 对应"评分"，其余按钮对应值需实现时用相同方式点击验证或按经验填入 `recommend`/`updated`/`new`，实现时以实测优先）
  - `region`: 分区（按钮为 全部/日漫/韩漫/美漫/其他；已验证 `jp` 对应"日漫"，其余同上需实测确认）
  - `status`: 状态（按钮为 全部/连载中/已完结；已验证 `serializing` 对应"连载中"，"已完结"值需实测确认，推测为 `completed`）
- 列表项 CSS 结构: 卡片含封面 `<img>`、连载/完结标签、可选 `★ 评分`、标题 `<h3>`、可选作者字符串；链接 `href` 格式 `/zh-CN/comic/{id}`（数字 id）
- 封面 CDN: `img2.xfmanga.top` 或 `img2.cycimg.me`，格式 `https://img2.xfmanga.top/r/400/pic/cover/l/{2hex}/{2hex}/{slug}_{5位随机}.jpg`

> 实现时对 `sort`/`region`/`status` 未完全验证的枚举值，应在编码阶段用浏览器实测每个筛选按钮对应的真实 query 值一一补全，不应凭猜测硬编码上线。

### 4.2 Search（Supabase RPC，干净 JSON 接口）

```
POST https://uhkvqrxmcapgtpspglrp.moedot.net/rest/v1/rpc/search_comics_pgroonga
Headers: apikey: <anon key>, authorization: Bearer <access_token 或 anon key>,
         content-type: application/json, content-profile: public,
         x-client-info: supabase-ssr/0.9.0 createBrowserClient
Body: {"search_term": "...", "page_number": 1, "items_per_page": 24}
```

响应为 JSON 数组，每条记录示例:
```json
{
  "id": 3361, "title": "尼古喵喵", "pinyin_name": "nigumiaomiao",
  "aliases": ["雅尼猫"], "slug": "445083",
  "summary": "...", "cover_url": "https://img2.cycimg.me/...",
  "category_id": 15, "lock_status": "free",
  "rating_average": 7.7, "rating_count": 15,
  "popularity_daily": 5, "popularity_weekly": 653, "popularity_monthly": 2028,
  "is_finished": false, "view_count": 26967,
  "categories": {"id": 15, "name": "搜笑", "slug": "comedy"},
  "chapters_count": 73, "total_count": 1
}
```

`lock_status` 字段区分免费/VIP（已确认存在 `"free"` 值，VIP 漫画的具体取值需实现时留意兼容，遇到非 `"free"` 值时在 UI 上做提示/跳过，与 1.1 节的范围限制一致）。域名可用 `uhkvqrxmcapgtpspglrp.supabase.co` 标准域或站点实际使用的 `uhkvqrxmcapgtpspglrp.moedot.net` 自定义代理域（二者等价，实现时优先用标准 `.supabase.co` 域以减少对第三方代理域名的依赖，除非测试发现该域名在部分网络环境下不可达）。

### 4.3 漫画详情页元数据（SSR HTML 解析）

`GET /zh-CN/comic/{id}` 返回完整 SSR HTML，需用 CSS 选择器解析（实测得到的 DOM 结构，选择器细节实现时以实际抓取的 HTML 结构为准编码验证）:

| 数据项 | 说明 |
|--------|------|
| 封面 | `<img>` src，如 `https://img2.cycimg.me/r/400/pic/cover/l/90/31/445083_BXuSi.jpg` |
| 标题 | `h1` 文本 |
| 作者 | 链接文本，`href` 指向 `/zh-CN/author/{urlEncoded作者名}` |
| 又名 | 纯文本 "又名：xxx" |
| 状态 | 纯文本 "连载中" / "已完结" |
| 话数 | 纯文本 "N 话" |
| 评分 | 纯文本，如 "7.7"，评分人数括号 "(15)" |
| 阅读量 | 纯文本，如 "2.7万 阅读" |
| 更新时间 | 纯文本 "更新于 N天前" |
| 简介 | 紧随以上字段之后的纯文本段落 |

已登录用户还会额外显示"上次读到：第N话" + 阅读进度 + "继续阅读"链接，此为可选功能，非本次实现范围（阅读进度对应 Supabase `reading_history` 表，是独立数据源，暂不接入）。

### 4.4 分类 slug 完整列表（用于 discoveryFilters 与 `/genre/{slug}`）

`mystery`(推理) `harem`(后宫) `scifi`(科幻) `yuri`(百合) `horror`(恐怖) `romance`(恋爱) `music`(音乐) `school`(校园) `isekai`(穿越) `battle`(战斗) `sports`(运动) `wuxia`(武侠) `fantasy`(奇幻) `thriller`(惊悚) `comedy`(搞笑) `slice-of-life`(日常) `suspense`(悬疑) `adventure`(冒险) `history`(历史) `otome`(乙女) `gourmet`(美食) `workplace`(职场) `xuanhuan`(玄幻) `mecha`(机战) `magic`(魔幻) `femboy`(伪娘)

---

## 5. 章节列表提取（详情页 HTML 内嵌 RSC 数据）

### 5.1 问题背景

`prepareChapterListFetch` 可返回 `null`——完整章节列表已内嵌在 `prepareMangaInfoFetch` 同一次请求拉取的详情页 HTML 中，无需额外请求。但该数据**不是**普通可直接 grep 到的字面 JSON，而是以**反斜杠转义**的 JSON 字符串形式内嵌在 Next.js 的 RSC flight payload（`self.__next_f.push([1,"..."])` 脚本标签）中。

实测确认：原始 HTML 字节中，形如 `\"chapters\":[...]` 的片段（每个引号前都有真实的反斜杠字符），完整对象结构为：

```
\"comicId\":3361,\"chapters\":[{\"id\":164145,\"title\":\"第01话\",\"idx\":1,\"category\":\"normal\",\"image_count\":15,\"updated_at\":\"2026-06-04T03:45:17.148783+00:00\"},...]}
```

该对象**只有 `comicId` 和 `chapters` 两个键**，不含漫画元数据（元数据仍走 4.3 节的 DOM 解析）。

### 5.2 提取算法

1. 在获取到的详情页 HTML 字符串中，查找字面字符串 `\"chapters\":[`（注意每个引号前有真实反斜杠）
2. 定位到该匹配后的第一个 `[`，按方括号层级深度计数匹配到对应的闭合 `]`（方括号本身未被转义，可安全按方括号计数找边界，不受内部转义引号干扰）
3. 提取 `[...]` 之间的完整子字符串，将其中所有 `\"` 字面字符序列替换为 `"`（去掉一层反斜杠转义）
4. 对结果调用 `jsonDecode` 得到章节对象数组

Dart 实现（伪代码）:
```dart
List<Chapter>? parseChapterList(String html, String comicId) {
  final needle = '\\"chapters\\":[';
  final start = html.indexOf(needle);
  if (start == -1) return null;
  final arrayStart = start + needle.length - 1; // 指向 '['
  int depth = 0, i = arrayStart, end = -1;
  for (; i < html.length; i++) {
    if (html[i] == '[') depth++;
    else if (html[i] == ']') { depth--; if (depth == 0) { end = i; break; } }
  }
  if (end == -1) return null;
  final raw = html.substring(arrayStart, end + 1).replaceAll('\\"', '"');
  final list = jsonDecode(raw) as List;
  return list.map((e) => Chapter.fromJson(e)).toList();
}
```

### 5.3 字段说明与验证数据

| 字段 | 说明 |
|------|------|
| `id` | 内部数字 ID（全平台全局自增主键，跨漫画不保证连续） |
| `title` | 展示文本，如 `"第01话"` 或 `"动画化"`（非正式插入内容） |
| `idx` | 本漫画内部序号，**必须用于构造 URL**: `/comic/{comicId}/chapter-{idx}`。不能用 `title` 中的显示话数，因为存在"动画化"等非正式插入导致的错位 |
| `category` | `normal`/`volume`/`special`，对应 UI 上的 连载/单行本/特典番外 三个分类 tab。实现时可全部并入 `ChapterItem` 列表，不需要分 tab 过滤 |
| `image_count` | 可选，预告页数 |
| `updated_at` | ISO 时间戳 |

验证样例（漫画 3361"尼古喵喵"，共 73 章）: `idx=1` → `{"id":164145,"title":"第01话",...}`；`idx=30` → `{"id":164174,"title":"第29话",...}`（对应 URL `chapter-30`，与 DOM 观察到的"第29话"链接一致）；`idx=36` → `{"id":164180,"title":"动画化",...}`（`category` 仍为 `normal`）；`idx=73`（最后一章）→ `{"id":201340,"title":"第69话",...}`。

此"查找 `\"key\":[` 前缀 + 按方括号计数 + 去转义 + jsonDecode"技巧具有通用性，若未来发现其他内嵌字段可复用同一 helper 函数。

---

## 6. 阅读器 API 与图片反扰码

### 6.1 章节内容清单

```
GET https://web.hanabimanga.com/api/reader/comic/{comicId}/chapter-{idx}[?quality=hd]
```

成功响应（200）:
```json
{
  "chapter": {"comicId": 3960, "chapterSlug": "chapter-1", "chapterId": 199900,
              "title": "第01话", "idx": 1, "totalPages": 3},
  "pages": [{"index": 0, "page": "001",
             "url": "https://cdn.hanabimanga.top/web-res/.../001.webp?t=...&sign=..."}, ...],
  "metadata": {"expiresIn": 7200,
               "scrambleInfo": {"ticket": "<base64>", "nonce": "<base64>", "cols": 4, "rows": 4}}
}
```

失败（429）:
```json
{"error": "...", "code": "ANON_QUOTA_EXCEEDED", "requestId": "...",
 "authMode": "anon", "details": {"dailyLimit": 10}}
```

- 错误码全集: `ANON_QUOTA_EXCEEDED`（匿名每日额度用尽）、`FREE_QUOTA_EXCEEDED`（免费用户 HD 画质额度用尽）、401/403（session 失效）、普通 429（无 code，纯速率限制）
- 实测：登录后普通账号连续读取 2 部漫画共 103 个不重复章节全部返回 200，未触发任何限额，说明登录后对非 VIP 标记章节基本无限制
- 成功响应体不含 quota 字段（前端源码显示可能含 `quota:{usedToday,dailyLimit}` 但实测未见，实现时应做空值兼容处理，不强依赖该字段）

### 6.2 图片反扰码（WASM，方案 A：绕开官方 DRM）

**背景**：官方阅读器用 `/reader.wasm`（wasm-bindgen/Rust 编译产物）的 `unscramble` 导出函数对每页图片做反扰码，调用约定为标准 wasm-bindgen 多返回值模式：分配内存写入 `ticket`/`nonce`/图片 RGBA 字节 → 调用 `unscramble(retPtr, ticketPtr, ticketLen, noncePtr, nonceLen, imageDataPtr, imageDataLen, width, height, cols, rows)` → 从 `retPtr` 读 4 个 int32（`resultPtr, resultLen, errFlag, hasError`）→ 取出结果字节 → 释放内存。官方 React 阅读器组件在成功渲染后会立即覆盖 `canvas.toDataURL`/`toBlob`/`ctx.getImageData` 为空实现，专门阻断脚本化截图（不影响我们的方案，因为我们不使用其组件代码路径）。

**方案 A（已选定）**：不触发官方 React 阅读器组件、不触发 DRM，直接在 Dart 侧用 `wasm_run_flutter` 包（基于 `flutter_rust_bridge`）加载同一份官方公开发布的 `/reader.wasm` 二进制，自己按 wasm-bindgen 约定实现等价的胶水内存读写逻辑调用 `unscramble`。已验证 `wasm_run_flutter` 支持的运行时覆盖本项目全部已支持平台：macOS/Windows→Wasmtime 14.0，iOS→Wasmi 0.31，Android arm64→Wasmtime 14.0（其余 ABI→Wasmi 0.31），Web→浏览器原生/Wasmi 0.31。不需要逆向 `unscramble` 内部算法本身，只需按标准调用约定传参。

`HanabiWasmUnscrambler` 职责：
1. `ensureWasmLoaded()`：首次调用时下载 `/reader.wasm` 到本地缓存文件（native）或直接在 Web 端用浏览器原生 `WebAssembly.instantiateStreaming`；后续复用已加载实例
2. `unscramble(Uint8List imageRgba, int width, int height, Uint8List ticket, Uint8List nonce, int cols, int rows)`：按 wasm-bindgen 约定分配/写入/调用/读取/释放，返回解密后的 RGBA `Uint8List`；`hasError` 非 0 时抛出异常
3. WASM 导入对象仅需两个占位函数（`__wbg_Error_...`/`__wbg___wbindgen_throw_...`），构造/抛出 JS 风格 Error 供 WASM 侧调用

`ChapterImage` 新增字段 `hanabiTicket`/`hanabiNonce`/`hanabiCols`/`hanabiRows`（base64 解码后的 `ticket`/`nonce` 字节可在 `parseChapter` 阶段直接存为 `Uint8List` 或原始 base64 字符串，实现时二选一，倾向存 base64 字符串以保持 `ChapterImage` 可序列化）。

`hanabi_memory_image.dart`（UI 层）流程：普通 HTTP GET 拿到原始（扰码）图片字节 → 解码得到 RGBA（先用 `dart:ui`/`image` 包 decode 拿到 `width/height` 及像素数据，等价于 JS 端 `drawImage`+`getImageData`）→ 调用 `HanabiWasmUnscrambler.unscramble(...)` → 得到解密后 RGBA 字节 → 构造内存位图（`ui.decodeImageFromPixels` 或等价 API）供 Flutter `Image` 渲染，不落盘中间态。

---

## 7. 错误处理

| 场景 | 处理方式 |
|------|---------|
| `ANON_QUOTA_EXCEEDED` / `FREE_QUOTA_EXCEEDED`（429） | 明确提示对应额度用尽信息，不自动重试 |
| 401 / 403 | 判定 session 失效：`clearExtraData()` + `AuthStore.clearSource(id)`，UI 层触发通用登录 dialog |
| 其他 429（无 code） | 按标准网络限流错误处理（可提示稍后重试） |
| WASM 解扰码失败（`hasError`非0 / wasm 初始化异常 / `/reader.wasm` 下载失败） | 该页显示"解密失败"占位图 + 重试按钮，不影响其他页 |
| 章节 `lock_status`/VIP 标记非免费 | 直接提示"该章节需要 VIP，暂不支持"，不做购买/解锁流程 |
| `/reader.wasm` 签名/接口未来变化 | v1 先假设签名稳定，不做版本探测；若未来官方更新导致调用约定变化需人工重新逆向 |

---

## 8. 测试策略

分层策略：

1. **纯逻辑单元测试**（无网络）:
   - Cookie 构造/超长切片逻辑（含边界值：正好 3180 字符、略超、远超）
   - `parseChapterList` 的方括号深度匹配 + 去转义 + JSON 解析（用真实抓取的详情页 HTML 片段做 fixture）
   - `parseMangaInfo`/`parseSignIn`/`parseChapter` 的 JSON/HTML 解析（用真实抓到的响应体样例做 fixture）
2. **WASM 调用集成测试**:
   - 用真实下载保存的 `reader.wasm` + 一组已知 `ticket`/`nonce`/扰码图片字节 fixture，验证 `HanabiWasmUnscrambler` 能正确解出预期图片（存入 `test/fixtures/`）
3. **手动验证**（不纳入 CI）:
   - 真机/模拟器用真实账号登录、翻阅章节，肉眼确认图片正常解扫码显示
   - 登出/token 过期后能正确弹出登录框
   - discovery 筛选参数（`sort`/`region`/`status` 未完全验证的枚举值）人工核对实际生效情况

---

## 9. 依赖

### 9.1 已有依赖（无需新增）

- `dio` — HTTP 请求
- `html` — HTML 解析
- `dart:convert` — JSON 编解码
- `dart:typed_data` — 字节操作

### 9.2 新增依赖

- `wasm_run_flutter` — 加载并调用官方 `/reader.wasm` 的 `unscramble` 导出函数（MIT 许可）

---

## 10. 元数据

```dart
@override String get id => 'hanabi_manga';
@override String get name => '花火漫画';
@override String get shortName => '花火';
@override String? get description => '花火漫画（hanabimanga.com），需登录账号阅读';
@override bool get requiresLogin => true;
@override String? get href => 'https://web.hanabimanga.com';
@override bool get needsProxy => false; // 无 Cloudflare 挑战，纯 Dio 即可
@override int get firstPage => 1;
```
