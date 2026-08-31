# 51漫画（51manga.com）漫画源设计

## 背景

为 comic-reader 新增漫画源「51漫画」，站点 `https://www.51manga.com/`。底层同样是 **MCCMS 漫画系统**（页面引用 `/packs/mccms/empty.png`，模板路径 `/template/pc/51manga/`、`/template/wap/51manga/`），与已有的 `haokan_manhua` 同族但模板与加密方案不同。

关键差异：**章节图片列表不在 HTML 中**。章节页 `<div id="pic-list">` 为空容器，真实图片数组藏在内联脚本的 `params` 变量里，经 AES 加密。解密逻辑由混淆脚本 `/template/pc/51manga/js/pic-v3.js`（jsjiami.com.v7 + CryptoJS）在浏览器端执行。

## 目标与范围

- 实现标准 `MangaSource` 子类，覆盖发现、搜索、详情、章节列表、章节图片五组契约。
- 在 `lib/core/utils/crypto_utils.dart` 增加一个通用 AES-CBC helper（base64 载荷 + 二进制前缀 IV），供本源解密 `params`。
- 遵循「源是纯函数」惯例：解密是纯计算，放在 `parseChapter` 内，不产生额外网络请求，不改动框架。

非目标：不引入新依赖（`encrypt` / `html` 已在 `pubspec.yaml`）；不做 WebView/JS 执行（算法已静态还原）；不做分类 tag 动态抓取（硬编码 `/category` 上的 30 个）。

## 侦察结论（已实测验证）

### 主机选择：全部走移动站 `m.51manga.com`

| 现象 | 结论 |
|---|---|
| PC `/search?key=...` 与 PC `/search/<kw>` 恒返回 0 结果（模板坏） | 搜索必须走 `m.` |
| `m.` 与 `www.` 的 manga id / chapter id / 路径完全一致 | 可以整源统一用 `m.` |
| PC 页面内含 `www.` → `m.` 的 UA 嗅探跳转脚本 | 配移动端 UA 更自然 |
| `m.` 列表/详情 DOM 更干净，且详情页一次给出全部章节 | 解析更省力 |

`51manga.com` 裸域 301 到 `www.`。图片防盗链的 Referer 用 `https://www.51manga.com/`（已实测放行）。

### URL 方案

| 功能 | URL |
|---|---|
| 发现 | `/category[/list/N][/tags/N][/finish/N][/order/X][/page/N]` |
| 搜索（首页） | `/search/<urlencoded keyword>` |
| 搜索（第 N 页） | `/search/<urlencoded keyword>/<N>` |
| 详情 | `/mh/<mangaId>` |
| 章节 | `/show/<chapterId>.html` |

- `mangaId` / `chapterId` 均为 `[A-Za-z0-9]+`（如 `4aNek4246W`、`Vd3Q3uKzVB`），**不含斜杠**，对 `routes.dart` 的 `Uri.encodeComponent` 路由安全。
- `chapterId` 独立于 `mangaId`，拼章节 URL 只需 `chapterId`。
- `/category` 路径段**顺序固定** list→tags→finish→order→page，缺省段省略。不带筛选时共 50 页，每页约 28–30 条。
- 搜索翻页是**裸数字段**：`/search/妹妹/2`（实测返回 `2/10`）。写成 `/search/妹妹/page/2` 会静默返回第 1 页——这是本源最容易踩的坑。每页 30 条。
- 漫画不存在时返回约 259 字节的页面，正文 `很遗憾，该漫画不存在或章节已被删除。` 并 JS 跳转 `/category`。

### 移动站 DOM 选择器

列表卡片（`/category` 与 `/search` 共用，容器 `#comic-list`）：

```html
<div class="comic-item"><a href="/mh/4aNek4246W">
  <div class="pic"><img src="https://img1.baipiaoguai.org/...cover_1.jpg?v=...">
    <div class="mask">已完结</div></div>
  <div class="field-info"><h3 class="title">溯古之黄鹤楼</h3>
    <div class="txt">最终章 释然</div></div>
</a></div>
```

分页指示：`div.layui-flow-more > cite` 文本形如 `2/10`（当前/总页）。

详情页 `/mh/<ID>`：

| 字段 | 选择器 |
|---|---|
| 标题 | `h1.name`（兜底 `header .title h2`） |
| 封面 | `div.comic_cover` 的 `style="background-image: url('...')"` |
| 作者 | `div.comic_hot` 的文本（去掉内部 `<i>`） |
| 标签 | `span.tags_last.diy_tags` 内的 `a[href^="/category/tags/"]` |
| 最新章节 | `div.zuixin p` 文本，去掉 `最新话：` 前缀 |
| 更新时间 | `div.zuixin time` |
| 简介 | `div.metas-desc` 内**最后一个** `<p>` |
| 章节 | `ul.chapter-list > li > a[href^="/show/"]`，标题取 `a` 文本 |

简介坑：`div.metas-desc` 里嵌了一个 `div.download-app > p` 诱饵（文本 `下载APP，免费看更多精彩漫画`）。取第一个 `<p>` 会拿到广告，因此取最后一个 `<p>`，或先移除 `.download-app` 子树。

章节列表坑：移动详情页**一次性给出全部章节，无分页**（实测《魔皇大管家》`r368n70WNX` 916 章、《我！天命大反派》`4aNeq37zNW` 305 章均在单次响应中）。因此 `prepareChapterListFetch` 返回 `null`。章节为**升序**（首条是最早/预告）。

状态坑：移动详情页没有独立的「状态」字段。由标签文本推断（含 `已完结`/`完结` → completed，含 `连载` → ongoing，否则 unknown）；列表卡片则直接用 `div.mask` 文本。

章节页 `/show/<CID>.html`（移动，约 9.5KB）：

| 字段 | 来源 |
|---|---|
| 章节标题 | `header .title h2` |
| 所属漫画 id | `div.back > a[href^="/mh/"]` |
| 下一话 | `div.diy_btn a`，文本含 `下一话` |
| 图片数据 | 内联脚本 `var tpl_path = '/template/wap/51manga/', params = '<BASE64>';` |

### 图片解密算法（已还原）

在 Node 中给 `pic-v3.js` 的 `CryptoJS.AES.decrypt` 打桩，取出实参后确认：

- **AES-128-CBC / PKCS7**
- **Key = 字符串 `9S8$vJnU2ANeSRoF` 的 UTF-8 字节**（hex `39533824764a6e5532414e6553526f46`）
- `raw = base64Decode(params)`；**IV = raw[0..16)**，**密文 = raw[16..]**
- 明文为 JSON：

```json
{"host":"www.51manga.com","source_id":"12","comic_id":"618431",
 "comic_down":0,"chapter_id":"223165","images":["https://img1.baipiaoguai.org/..."],
 "lazy":false}
```

已用 Python 在 12+ 个不同漫画的章节上独立复现，全部成功。观测样本中 `source_id` 恒为 `"12"`、`lazy` 恒为 `false`、`images` 为绝对 URL（`.webp` / `.jpg`）。

`pic-v3.js` 的相对路径规则需一并复刻作为兜底：若图片路径不以 `http` 开头，则在前面拼 `https://img1.baipiaoguai.org`。

### 图片防盗链（硬坑）

CDN `img1.baipiaoguai.org` **无 Referer 直接 403**，带 `Referer: https://www.51manga.com/` 返回 200（实测 `.../68c41d6e6d7d34ef36d0fdc951e0a904_zb.webp` → 74214 字节 `image/webp`）。站方自己的 JS 给 `<img>` 设了 `referrerPolicy="no-referrer"`，但直连抓取时 Referer 是必需的。

因此封面与章节图**都要**带头：`MangaSummary.headers`、`MangaDetail.headers`、`ChapterImage.headers` 三处都注入 `{'Referer': 'https://www.51manga.com/', 'User-Agent': <移动UA>}`。

无封面时站点占位图为 `https://www.51manga.com/packs/mccms/empty.png`。

### 筛选器取值（从 `/category` 采集）

- `list`（类型/地区）：1 国产漫画、2 日本漫画、3 韩国漫画、4 欧美漫画
- `finish`：1 连载中、2 已完结（PC 模板把两者都标成「连载」，移动站标注正确，列表 `.mask` 也印证）
- `order`：`hits` 热门、`addtime` 最新
- `tags`（30 个，id→标签）：867 科幻、868 后宫、869 机甲、870 都市、871 恋爱生活、872 恋爱、873 恋爱、874 其他、875 推理悬疑、876 魔法、877 奇幻、878 异世界、879 滑稽搞笑、880 重生、881 励志、882 浪漫、883 逆袭、884 脑洞、885 日常、886 热血机战、887 魔法/奇幻、888 武侠经典、889 韩漫、890 小说改编、891 穿越、892 非现代、893 大女主、894 腹黑、895 校园、896 剧情

872 与 873 标签文本重复（站方数据问题），实现时**丢弃 873**，避免下拉框出现两个「恋爱」。详情页还会引用 `/category` tag 栏之外的 id（如 1025 已完结、2843 国漫、2593 古风、2585 玄幻），说明 tag 栏是策展子集——只用于筛选下拉，不做反查。

搜索无筛选器，`searchFilters` 留空。

## 关键决策

| # | 决策点 | 取值 | 理由 |
|---|--------|------|------|
| 1 | 请求主机 | 全站 `m.51manga.com` + 移动 UA | PC 搜索模板坏；移动 DOM 更干净；id 完全一致 |
| 2 | 章节列表 | `prepareChapterListFetch` 返回 `null` | 详情页一次给全（916 章实测） |
| 3 | 图片解密位置 | `parseChapter` 内纯计算 | 无额外网络，符合 prepare/parse 纯函数约定 |
| 4 | 解密 helper | 新增 `aesDecryptBase64PrefixedIv` 到 `crypto_utils.dart` | 现有 `aesDecrypt` 是「hex 密文 + UTF-8 字符 IV」（CopyManga 方案），与本源「base64 + 二进制前缀 IV」不兼容 |
| 5 | 防盗链 | Summary/Detail/ChapterImage 三处注入 Referer + UA | CDN 无 Referer 403 |
| 6 | 18+ | `isAdult => true` | 站点内容以成人向为主 |
| 7 | 代理 / Cloudflare | 都不需要 | 实测普通 Dio 请求 + UA 即可，无 CF 挑战 |
| 8 | 搜索翻页 | 裸数字段 `/search/<kw>/<N>` | `/page/N` 形式静默回退第 1 页 |

## 架构

### 文件与注册

- 新建 `lib/data/sources/manga51.dart`，类 `Manga51`，id `manga51`。
- `lib/core/utils/crypto_utils.dart` 追加 `aesDecryptBase64PrefixedIv`。
- `lib/app/di/injection.dart`：import + register 块追加 `registry.register(Manga51())`。
- 新建单测 `test/data/sources/manga51_test.dart`（零网络）。

### 元数据 getter

```
id='manga51'  name='51漫画'  shortName='51漫'  score=4.0
description='MCCMS 漫画站，章节图片 AES 加密'
href='https://www.51manga.com'
isAdult=true  needsProxy=false  firstPage=1
```

### 常量与请求头

```dart
static const String _baseUrl = 'https://m.51manga.com';   // 所有请求
static const String _pcBaseUrl = 'https://www.51manga.com'; // Referer / 浏览器打开
static const String _imageCdn = 'https://img1.baipiaoguai.org'; // 相对路径兜底
static const String _picKey = r'9S8$vJnU2ANeSRoF';
static const String _mobileUa = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
```

- `userAgent` → `_mobileUa`
- `defaultHeaders` → `{'Referer': '$_pcBaseUrl/'}`
- `_imageHeaders` → `{'Referer': '$_pcBaseUrl/', 'User-Agent': _mobileUa}`

`_picKey` 用 raw string 字面量，因为含 `$`。

## 五组 prepare/parse 映射

### ① Discovery

- `prepareDiscoveryFetch(page, filters)` → GET `$_baseUrl/category[/list/N][/tags/N][/finish/N][/order/X]/page/$page`，段顺序固定，空值跳过。
- `discoveryFilters`：4 个 `FilterOption` = `list` / `tags` / `finish` / `order`（取值见上，`order` 默认 `hits`，其余默认 `''`）。
- `parseDiscovery(html)` → `_parseCards(html)`。

### ② Search

- `prepareSearchFetch(keyword, page, _)` → GET `$_baseUrl/search/${Uri.encodeComponent(keyword)}` 当 `page <= 1`，否则再追加 `/$page`。
- `parseSearch(html)` → `_parseCards(html)`。

### ③ MangaInfo

- `prepareMangaInfoFetch(mangaId)` → GET `$_baseUrl/mh/$mangaId`
- `parseMangaInfo(html, mangaId)` → `MangaDetail`：按上表选择器取字段；章节由 `ul.chapter-list` 解析为 `ChapterItem(id: cid, mangaId: mangaId, title: text, href: '$_pcBaseUrl/show/$cid.html')`；`headers: _imageHeaders`。
- 若页面命中「不存在」文案且标题为空 → 抛 `Exception('该漫画不存在或已被删除')`。

### ④ ChapterList

- `prepareChapterListFetch(_, _)` → **return null**
- `parseChapterList(_, _)` → `const ChapterListResult(chapters: [])`

### ⑤ Chapter

- `prepareChapterFetch(mangaId, chapterId, page, {extra})` → GET `$_baseUrl/show/$chapterId.html`
- `parseChapter(html, mangaId, chapterId, page)` → `ChapterResult`：
  1. 正则 `params\s*=\s*'([^']+)'` 取 base64；缺失则抛 `Exception('未找到章节图片数据')`。
  2. `aesDecryptBase64PrefixedIv(payload, _picKey)` → `json.decode` → `images` 数组。
  3. 每条走 `_absoluteImageUrl`：以 `http` 开头原样用；以 `/` 开头拼 `$_imageCdn$path`；否则 `$_imageCdn/$path`。
  4. `ChapterImage(url: ..., headers: _imageHeaders)`，`canLoadMore: false`。
  5. 标题取 `header .title h2`，兜底 `chapterId`。
- 覆写 `getChapterWebUrl(mangaId, chapterId)` → `$_pcBaseUrl/show/$chapterId.html`（浏览器里 PC 版更好读）。

## 私有辅助

- `_parseCards(String html)` → `List<MangaSummary>`：遍历 `div.comic-item`，`a[href^="/mh/"]` 取 id，`div.pic img` 取 `src`（兜底 `data-src`），`h3.title` 取标题（兜底 `img[alt]`），`div.field-info .txt` 取最新章节，`headers: _imageHeaders`。`div.mask` 的状态文本**不使用**——`MangaSummary` 没有 status 字段，状态只在详情页体现。
- `_extractId(String href, String prefix)` → 从 `/mh/xxx` 或 `/show/xxx.html` 抽 id 的正则封装。
- `_absoluteImageUrl(String raw)` → 相对路径补全。
- `_parseStatusFromTags(List<String> tags)` → `MangaStatus`。
- `_cleanText(String?)` → trim + 压缩空白 + 去 `&nbsp;`。

### crypto_utils 新增

```dart
/// AES-128-CBC decryption where [payload] is base64 and the first 16 BYTES of
/// the decoded payload are the IV, the remainder the ciphertext.
/// Used by 51manga's pic-v3.js scheme.
String aesDecryptBase64PrefixedIv(String payload, String key) { ... }
```

用 `package:encrypt` 的 `AES(Key.fromUtf8(key), mode: AESMode.cbc, padding: 'PKCS7')` + `IV(ivBytes)`。

## 边界处理（防御性，不静默产出脏数据）

- 卡片缺字段 → 该字段给默认值（author=''、cover=''），不跳过整条；仅当 id 为空时跳过。
- 详情页拿不到标题 → 抛异常（页面结构变了或漫画已删，不要返回空壳）。
- 简介 `div.metas-desc` 无 `<p>` → description = null。
- 章节页无 `params` → 抛异常（明确报错优于返回 0 图静默失败）。
- 解密成功但 `images` 为空 → 返回空 images 的 `ChapterResult`（章节确实没图）。
- 解密抛异常（key 失效/算法改版）→ 让异常冒泡，附上 `chapterId` 便于定位。

## 测试用例清单

文件 `test/data/sources/manga51_test.dart`，零网络零 mock。

group 1 `Manga51 metadata and request builders`：
- id/name/shortName/score/isAdult/firstPage 断言。
- `discoveryFilters` 含 list/tags/finish/order 四项；tags 不含重复标签（无两个「恋爱」）。
- `prepareDiscoveryFetch(1, {})` → `/category/page/1`。
- `prepareDiscoveryFetch(3, {list:'1',tags:'889',finish:'2',order:'hits'})` → `/category/list/1/tags/889/finish/2/order/hits/page/3`（顺序必须一致）。
- `prepareSearchFetch('妹妹', 1, {})` → `/search/%E5%A6%B9%E5%A6%B9`（**不带**尾随数字）。
- `prepareSearchFetch('妹妹', 2, {})` → `/search/%E5%A6%B9%E5%A6%B9/2`（**不是** `/page/2`）。
- `prepareMangaInfoFetch('4aNek4246W')` → `/mh/4aNek4246W`。
- `prepareChapterListFetch(...)` → `isNull`。
- `prepareChapterFetch('4aNek4246W','Vd3Q3uKzVB',1)` → `m.` 域 `/show/Vd3Q3uKzVB.html`。
- `getChapterWebUrl(...)` → `www.` 域 `/show/Vd3Q3uKzVB.html`。

group 2 `Manga51 response parsing`：
- `parseDiscovery` 喂手写 `div.comic-item` HTML → id/title/cover/latestChapter，且 `headers` 含 Referer。
- `parseSearch` 同上。
- `parseMangaInfo` 喂完整详情 HTML → title/cover/author/tags/latestChapter/updateTime/description/章节数与首末章 id；断言 description **不是**「下载APP，免费看更多精彩漫画」（诱饵回归测试）。
- `parseMangaInfo` 喂 tags 含 `已完结` → `status == MangaStatus.completed`；含 `连载` → ongoing。
- `parseMangaInfo` 喂「该漫画不存在」页 → 抛异常。
- `parseChapterList` → 空列表。
- `parseChapter` 喂含**预先用真实 key 加密**的 `params` 的 HTML → 得到期望的图片 URL 列表、每张 `headers` 含 Referer、`canLoadMore == false`、标题正确。（fixture 由 Python 用 key `9S8$vJnU2ANeSRoF` + 固定 IV 离线生成后作为字面量嵌入，因此改错 key 或 IV 处理会导致测试失败。）
- `parseChapter` 的相对路径样本 → 补全为 `https://img1.baipiaoguai.org/...`。
- `parseChapter` 喂无 `params` 的 HTML → 抛异常。

group 3 `aesDecryptBase64PrefixedIv`：
- 离线生成的已知 payload → 已知明文字符串。
- 载荷长度不足 16 字节 → 抛异常。

验证命令：

```
flutter analyze lib/data/sources/manga51.dart lib/core/utils/crypto_utils.dart lib/app/di/injection.dart
flutter test test/data/sources/manga51_test.dart
```

不跑全仓库 `flutter test`（仓库内有联网脚本与已知失败的 `widget_test.dart`）。

实现完成后另做一次**手工联网端到端验证**（临时脚本，不入库）：发现首页 → 搜索 → 详情 → 章节解密 → 取第一张图确认 HTTP 200 且 `content-type: image/*`。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 站方轮换 AES key（`pic-v3.js` 已混淆，说明有防护意识） | key 抽成单个 `static const`，改一处即可；解密失败直接抛异常暴露问题，不静默返回 0 图 |
| 移动站模板改版 | 每个选择器都有兜底路径；关键字段（标题、params）缺失时抛异常而非返回空壳 |
| 搜索翻页格式易写错 | 单测显式断言 `/search/<enc>/2` 且断言不含 `/page/` |
| CDN 域名从 `img1.baipiaoguai.org` 漂移 | 实际使用的是明文 JSON 里的绝对 URL；`_imageCdn` 仅作相对路径兜底，漂移影响有限 |
| tag id 无语义、且 872/873 重复 | 硬编码策展子集并丢弃 873；站方增删分类会漂移（可接受） |
| 简介诱饵 `<p>` | 取最后一个 `<p>`，并加回归断言 |
