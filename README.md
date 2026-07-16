# Comic Reader

<p align="center">
  <img src="macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png" width="128" alt="Comic Reader Icon">
</p>

<p align="center">
  <b>多源聚合漫画阅读器</b><br>
  支持 macOS / iOS / Android / Web 多平台
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11+-blue?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Platform-macOS%20|%20iOS%20|%20Android%20|%20Web-green" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="License">
</p>

---

## 功能特性

### 多源聚合

| 源 | 说明 | 特殊要求 | 点击 |
|----|------|---------|------|
| 包子漫画 | 国漫/日漫/韩漫 | - | [打开](https://www.baozimh.com) |
| 拷贝漫画 | 综合漫画 | 科学上网 | [打开](https://www.mangacopy.com) |
| E-Hentai | 综合漫画 | 科学上网 | [打开](https://e-hentai.org) |
| 禁漫天堂 | 综合漫画 | 无需 CF 验证, 科学上网 | [打开](https://18comic.vip) |
| 漫画柜 | 综合漫画 | 科学上网 | [打开](https://m.manhuagui.com) |
| NHentai | 综合漫画 | 科学上网 | [打开](https://nhentai.to) |
| 哔咔漫画 | 需账号登录 | Email/Password内置 | [打开](https://manhuabika.com) |
| 绅士漫画 | 综合漫画 | 需 Cloudflare 验证 | [打开](https://www.wnacg.com) |
| 漫画人 | 综合漫画 | 科学上网 | [打开](https://www.manhuaren.com) |
| Hitomi.la | 综合漫画 | 科学上网 | [打开](https://hitomi.la) |
| Komiic | 综合漫画 | 科学上网 | [打开](https://komiic.com) |
| 漫画GUI | 综合漫画（移动端 API）| 科学上网 | [打开](https://m.manhuagui.com) |
| 在漫画 | 国漫 | - | [打开](https://www.zaimanhua.com) |
| HotManga | 综合漫画 | 科学上网 | [打开](https://www.manga2026.com) |
| IkanManhua | 综合漫画 | 科学上网 | [打开](https://ikanmanhua.org) |
| JComic | 综合漫画 | 科学上网 | [打开](https://jcomic.net) |
| HComic | 综合漫画 | 科学上网 | [打开](https://h-comic.com) |
| 吾五漫画 | 综合漫画 | 科学上网 | [打开](https://www.wu55comic.store) |
| 哥打漫画 | 综合漫画 | - | [打开](https://godamh.com) |
| Jestful | 综合漫画 | 科学上网 | [打开](https://jestful.net) |
| Mangabz | 综合漫画 | 科学上网 | [打开](https://mangabz.com) |
| Dongmanmanhua | 综合漫画 | - | [打开](https://www.dongmanmanhua.cn) |
| Manga18.Club | 综合漫画 | 需 Cloudflare 验证 | [打开](https://manga18.club) |

### 阅读体验

- 全屏沉浸式阅读器
- 横向翻页模式（支持 LTR/RTL）
- 纵向滚动模式（Webtoon 风格）
- 自动翻页（2-15 秒间隔可调）
- 阅读进度自动记录与恢复

### 收藏与管理

- 收藏书架 + 新章节更新提示
- 章节下载（离线阅读）
- 跨源搜索
- 数据备份/恢复（JSON 导出）

### 设置与个性化

- 主题：浅色 / 深色 / AMOLED / 跟随系统
- 网络代理配置
- 插件启用/禁用管理

---

## 截图

| 书架 | 书架2 | 发现 |
|:----:|:-----:|:----:|
| ![书架](docs/snapshoots/home.png) | ![书架2](docs/snapshoots/home2.png) | ![发现](docs/snapshoots/discovery.png) |

| 详情 | 详情2 | 设置 |
|:----:|:-----:|:----:|
| ![详情](docs/snapshoots/detail1.png) | ![详情2](docs/snapshoots/detail2.png) | ![设置](docs/snapshoots/setting.png) |

---

## 安装

### 方式一：下载 Release（推荐）

前往 [Releases](../../releases) 页面下载对应平台安装包：

| 平台 | 文件 | 要求 |
|------|------|------|
| macOS | `ComicReader-x.x.x-macOS.dmg` | macOS 11.0 (Big Sur)+ |
| Windows | `ComicReader-x.x.x-Windows.zip` | Windows 10+ |

#### macOS 安装说明

1. 双击 `.dmg` 文件
2. 将 app 拖到 Applications 文件夹
3. **首次打开**（重要）：右键点击 app → 打开 → 弹出警告点"打开"
4. 或终端执行：
   ```bash
   xattr -cr /Applications/comic_reader.app
   ```

#### Windows 安装说明

1. 解压 `.zip` 到任意目录
2. 双击 `comic_reader.exe` 运行

### 方式二：从源码编译

#### 环境要求

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.11+
- Xcode 15+（macOS/iOS）
- Android Studio（Android）

#### 编译运行

```bash
# 克隆项目
git clone https://github.com/achui1980/comic-reader.git
cd comic-reader

# 安装依赖
flutter pub get

# 运行（macOS）
flutter run -d macos

# 运行（iOS 真机）
flutter run -d <device-id>

# 运行（Android）
flutter run -d <device-id>

# 运行（Web - 需要 CORS 代理）
./tools/run_web.sh
```

#### 打包 macOS DMG

```bash
# 安装 create-dmg
brew install create-dmg

# 一键打包
./tools/build_dmg.sh
```

产物：`build/dmg/ComicReader-x.x.x.dmg`

---

## 项目结构

```
lib/
├── app/
│   ├── di/                 # 依赖注入（GetIt，手动注册）
│   └── router/             # 路由（GoRouter）
├── data/
│   ├── local/              # 本地存储（收藏、历史、设置）
│   ├── remote/             # 网络层（Dio、拦截器、代理）
│   ├── repositories/       # 数据仓库实现
│   └── sources/            # 漫画源插件
│       ├── manga_source.dart       # 抽象基类
│       ├── baozi_manga.dart        # 包子漫画
│       ├── copy_manga.dart         # 拷贝漫画
│       ├── ehentai.dart            # E-Hentai
│       ├── jm_comic.dart           # 禁漫天堂
│       ├── nhentai.dart            # NHentai
│       ├── pica_comic.dart         # 哔咔漫画
│       ├── wnacg.dart              # 绅士漫画
│       ├── manhuaren.dart          # 漫画人
│       ├── hitomi.dart             # Hitomi.la
│       ├── komiic.dart             # Komiic
│       ├── manhuagui_mobile.dart   # 漫画GUI
│       ├── zaimanhua.dart          # 在漫画
│       ├── hot_manga.dart          # HotManga
│       ├── ikan_manhua.dart        # IkanManhua
│       ├── jcomic.dart             # JComic
│       ├── h_comic.dart            # HComic
│       ├── goda_manga.dart         # 哥打漫画
│       ├── jestful.dart            # Jestful
│       ├── mangabz.dart            # Mangabz
│       ├── dongmanmanhua.dart      # Dongmanmanhua
│       ├── manga18_club.dart       # Manga18.Club
│       └── wu55comic.dart          # 吾五漫画
├── domain/
│   ├── entities/           # 领域实体
│   └── repositories/       # 仓库接口
└── presentation/
    ├── home/               # 书架首页
    ├── discovery/          # 发现页
    ├── search/             # 搜索页
    ├── detail/             # 漫画详情
    ├── reader/             # 阅读器
    ├── settings/           # 设置
    └── downloads/          # 下载管理
```

---

## 网络与代理

本应用部分漫画源需要代理才能访问。在设置中配置代理地址（格式：`host:port`）。

### Cloudflare 验证

部分源（如绅士漫画）有 Cloudflare 保护：
1. App 会自动检测并弹出验证提示
2. 点击"去验证"进入 WebView 完成人机验证
3. 验证通过后 Cookie 自动保存，后续请求自动携带

部分源（如 Manga18.Club）除人机验证外还有 Cloudflare TLS/JA3 指纹校验，普通 HTTP 请求即使带正确 Cookie 也会被 403 拦截。本应用按平台自动绕过，无需额外配置：
- **原生平台**：请求经常驻的无头 `flutter_inappwebview` 页内 `fetch()` 发出，复用真实浏览器 TLS 指纹。
- **Web 平台**：CORS 代理对指定站点改用 curl-impersonate（真实 Chrome 指纹）转发。需先 `brew install lexiforest/tap/curl-impersonate`，`./tools/run_web.sh` 默认已对 `manga18.club` 启用（通过 `CURL_IMPERSONATE_HOSTS` 控制）。

### Web 平台

Web 端由于浏览器跨域限制，需要本地 CORS 代理：

```bash
# 启动代理 + Web 服务
./tools/run_web.sh
```

---

## CI/CD

项目使用 GitHub Actions 自动构建发布：

- **触发条件**：推送 `v*` tag 或手动触发
- **产物**：macOS DMG + Windows zip
- **发布**：自动上传到 GitHub Releases

```bash
# 发布新版本
git tag v1.0.4
git push --tags
```

---

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.11+ / Dart |
| 状态管理 | flutter_bloc / Cubit |
| 导航 | GoRouter |
| 网络 | Dio |
| 依赖注入 | GetIt + Injectable |
| HTML 解析 | html (dart) |
| 加密 | PointyCastle / Encrypt |
| 图片 | CachedNetworkImage / ExtendedImage |
| WebView | flutter_inappwebview |

---

## 许可证

MIT License

---

## ⚠️ 免责声明

> **请在使用本项目前仔细阅读以下声明。下载、安装或使用本项目，即视为您已阅读并同意本声明的全部内容。**

1. **性质与用途**：本项目为**开源技术学习项目**，仅用于个人学习、技术研究与交流，**请勿用于任何商业用途**。

2. **内容与版权**：本项目仅作为客户端**聚合、展示**第三方公开网络数据源的内容，**不制作、不存储、不上传、不分发**任何漫画资源。所有内容的版权归原作者及各源网站所有。请支持正版，并在使用后及时删除相关内容。

3. **成人内容警示**：本应用聚合的部分数据源包含**成人向（R18）内容**。**未满 18 周岁（或所在地区法定成年年龄）的用户请勿下载、安装或使用相关功能。** 使用者需自行承担因访问相关内容而产生的一切责任。

4. **法律合规**：使用者应确保自身行为符合所在国家/地区的法律法规。若当地法律禁止访问相关内容，或禁止使用代理、VPN 等网络技术手段，请立即停止使用本应用的相关功能。因使用者违反当地法律法规而导致的任何后果，由使用者自行承担。

5. **第三方关联**：本项目与文中提及的任何漫画网站、平台**均无官方合作或从属关系**，相关商标、名称归各自所有者所有。本项目不对第三方源的内容、可用性、安全性及合法性负责。

6. **内置凭据**：应用内置的任何第三方账号（如哔咔漫画）仅供技术演示与测试，作者不保证其长期可用，也不对任何滥用行为负责。

7. **无担保**：本软件按"现状"提供，不提供任何明示或暗示的担保。因使用或无法使用本软件造成的任何直接或间接损失，作者不承担任何责任。

8. **侵权处理**：若任何版权方认为本项目侵犯了其合法权益，请通过 [Issues](../../issues) 联系我们，我们将在核实后及时移除对相关源的支持。