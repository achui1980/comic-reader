# 设计文档:同步 GitHub Release 到 Gitee

日期: 2026-08-05
来源: 用户提问「github 上面的 release 有办法同步过去吗?」

## 背景

`.github/workflows/sync-gitee.yml`(已存在)通过 `git push --mirror` 把 GitHub 上的
所有分支/tag 同步到 Gitee(`https://gitee.com/achui/comic-reader.git`),但这只同步
git 对象,不涉及 GitHub Release —— Release 的标题、说明(release notes)、以及上传的
二进制附件(`.dmg`/`.zip`/`.apk`,由 `.github/workflows/release.yml` 的
`softprops/action-gh-release@v2` 步骤创建)是 GitHub 特有的 API 对象,`--mirror` 不会
碰它们。Gitee 有自己独立的「发行版」功能和对应的 API v5,需要单独调用同步。

**范围**:不仅覆盖未来新发布的 release,还要一次性把历史上已发布过的 release 补齐到
Gitee。

## 方案

新增独立 workflow 文件 `.github/workflows/sync-gitee-release.yml`,不改动现有的
`release.yml`(构建+发布)和 `sync-gitee.yml`(分支/tag 镜像)。

### 触发方式

- `release: types: [published]` — GitHub 发布新 Release 后自动触发,只同步这一个 tag
  (覆盖"未来")。
- `workflow_dispatch` — 手动触发,遍历 GitHub 上**所有**已发布的 release,逐一执行同一
  套同步逻辑(用于"一次性补齐历史",以及日常需要重跑/修复时的兜底手段)。

两种触发方式共享同一段同步逻辑,只是"要同步哪些 tag"的来源不同:单个 tag(来自事件
payload)vs 全部 tag(来自 `gh api repos/achui1980/comic-reader/releases --paginate`)。

### 认证

- **GitHub 侧(读)**:使用 Actions 内置的 `GITHUB_TOKEN`,配合 runner 自带、已自动认证
  的 `gh` CLI 读取 release 信息,无需新增 secret。
- **Gitee 侧(写)**:复用已有的 `GITEE_TOKEN` secret,作为 Gitee API v5 的
  `access_token` 参数,无需新增 secret。

### 核心同步逻辑(每个 tag,幂等)

对每一个待同步的 tag 依次执行:

1. **读取 GitHub release 信息**:
   `gh api repos/achui1980/comic-reader/releases/tags/$tag`,取出 `name`、`body`、
   `prerelease`、`draft`、`assets[].name` + `assets[].browser_download_url`。
2. **跳过 draft**:若 `draft == true` 直接跳过该 tag(现有 `release.yml` 产出的
   release 始终是 `draft:false`,此判断作为安全兜底)。
3. **检查 Gitee 上是否已存在该 tag 的 release**:
   `GET https://gitee.com/api/v5/repos/achui/comic-reader/releases/tags/$tag?access_token=$GITEE_TOKEN`。
   - 404 → 执行第 4 步创建。
   - 已存在 → 跳到第 5 步,直接用已有 release 的 `id`。
4. **创建 Gitee release**(仅当不存在时):
   `POST https://gitee.com/api/v5/repos/achui/comic-reader/releases`,body 包含
   `access_token`、`tag_name`(= `$tag`)、`name`、`body`、`prerelease`。不传
   `target_commitish`(tag 已由 `sync-gitee.yml` 镜像到 Gitee,Gitee 会自动关联)。
5. **同步附件(增量、幂等)**:
   - `GET .../releases/{id}/attach_files` 拿 Gitee 上已有的附件文件名列表。
   - 与 GitHub 的 `assets[].name` 比较,找出 Gitee 缺失的文件名。
   - 对每个缺失文件:`curl -L` 从 `browser_download_url` 下载到本地(公开 release 的
     asset 下载不需要认证 header),再 `POST .../releases/{id}/attach_files`
     (multipart,字段名 `file`,带 `access_token`)上传到 Gitee。
   - Gitee 上已存在同名文件的直接跳过,不重复上传、不报错。

`workflow_dispatch` 模式下对每个 release 循环执行上述 1-5 步;`release: published`
模式下只对触发事件里的那一个 tag 执行一次。

### 错误处理

单个 tag 处理失败(网络抖动、Gitee 侧临时错误等)不应中断整批同步:在
`workflow_dispatch` 的循环里捕获单个 tag 的失败、记录失败的 tag 列表,循环跑完后如果
有失败项则整个 job 标记失败(方便在 Actions 页面看到需要人工重跑),但已成功同步的
tag 不受影响,不会重复处理。

### 已知的次要风险(不做额外处理)

`release: published` 事件理论上可能在 `sync-gitee.yml` 把该 tag 镜像到 Gitee **之前**
触发(竞态),导致创建 Gitee release 时 tag 在 Gitee 上还不存在而失败。由于 tag push
几乎是瞬时的,而 `release.yml` 构建产物耗时更久,实际发生概率很低;一旦发生,只需手动
重新触发一次 `workflow_dispatch`(逻辑幂等,安全重跑)即可修复,不额外增加重试/等待
逻辑。

### 验证

- 用 YAML 解析工具(如 `ruby -ryaml`)验证新 workflow 文件语法正确。
- 先手动触发一次 `workflow_dispatch` 做历史补齐验证,检查 Gitee 上的 release 列表和
  附件是否与 GitHub 一致,且可以安全重跑(不产生重复项)。
- 确认无误后,后续新 release 会自动通过 `release: published` 触发同步,无需人工干预。
- 不在本次会话中实际触发线上 workflow 验证,由用户后续自行验证。
