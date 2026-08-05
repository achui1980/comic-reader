# 设计文档:发现页新增列表布局(Grid ⇄ List 切换)

日期: 2026-08-05
来源: 用户需求 —— 发现页目前只有网格(Grid)布局,希望新增一种列表(List)布局并支持切换

## 背景

`lib/presentation/discovery/discovery_screen.dart` 当前固定使用 `GridView.builder` +
`SliverGridDelegateWithFixedCrossAxisCount` 展示 `MangaSummary`,列数由
`Responsive.gridColumns()` 按屏宽动态计算(手机3列/平板4~5列/桌面6列)。卡片组件
`_MangaCard` 是页面内部私有类,展示封面(`MangaCoverImage`)+标题(2行)+
章节数/热度合并的一行小字。

`DiscoveryState`/`DiscoveryCubit` 中目前没有任何 `viewMode`/布局相关字段;全局
`AppSettings`(`lib/data/local/settings_store.dart`)已有 `LayoutMode` 命名先例
(阅读器横向翻页/纵向滚动开关,语义不同但持久化模式可复用)。

## 需求确认(与用户逐项确认结果)

1. 列表项展示:封面+标题+章节数/热度(与网格一致) + 新增作者名 + 新增简介 +
   新增更新时间/最新章节(字段已存在于 `MangaSummary`,大部分源未填充)。
2. 简介(`description`)分阶段实现:先在 `MangaSummary` 加字段,只对少数源
   (comick/pica_comic 等)解析填充,其余源保持 `null`,UI 无简介时不显示该行。
3. 切换入口:AppBar 图标按钮;选择结果持久化到全局 `AppSettings`,走现有
   `local_storage_io.dart`/`local_storage_web.dart` 机制,跨会话记住。
4. 应用范围:仅发现页。`home_screen.dart`(收藏页)保持现状不改动,但卡片组件
   抽取为公共 widget 以便未来复用(本次不改 `home_screen.dart` 的调用代码)。
5. 列表布局始终单列(不做类似 `Responsive.gridColumns()` 的列表列数策略),
   桌面端仍用 `Responsive.constrainedContent` 居中限宽。
6. 列表项排版:三种候选(A紧凑/B标准/C详情)通过浏览器可视化原型对比后,
   用户选定 **方案 C · 详情列表**。

## 方案 C 排版规格

- 封面 96×136(圆角8,与网格卡片一致),`MangaCoverImage` 复用。
- 右侧纵向排列:
  1. 标题,最多2行,字号略大(`titleMedium`)
  2. 作者,1行(`bodySmall`)
  3. 信息 chip 行:章节数/热度/更新时间,按存在与否动态生成,`Wrap` 展示;
     三者都缺失时该行为空(不留空白)
  4. 简介,最多3行,浅灰色(`colorScheme.outline`),`description == null` 时
     整行隐藏
- 行高按内容自适应(约160px+,不固定死)
- 列表项之间用 `ListView.separated` + 1px `Divider`
  (`colorScheme.outlineVariant`),`indent` 对齐到文字区起始位置(封面宽96 +
  左右 padding),不使用 Card/阴影,保持项目现有扁平化风格
  (`CardThemeData(elevation: 0)`)。

## 数据模型改动

`lib/domain/entities/manga.dart` 的 `MangaSummary` 新增可空字段:

```dart
class MangaSummary extends Equatable {
  final String id;
  final String sourceId;
  final String title;
  final String coverUrl;
  final String author;
  final List<String> altTitles;
  final String? latestChapter;
  final String? updateTime;
  final Map<String, String>? headers;
  final int? chapterCount;
  final String? popularityText;
  final String? description;   // 新增:简介,仅部分源解析填充
  // props 加入 description;copyWith 加入 description 参数
}
```

仅对已支持解析简介的数据源(如 `comick`、`pica_comic`)在其 `parseDiscovery`
中补充解析 `description`,其余源保持 `null`,不要求本次全部适配
(后续可作为独立任务逐步补齐)。

## 状态管理与持久化

**1. `AppSettings` 新增字段**(`lib/data/local/settings_store.dart`):

```dart
enum DiscoveryViewMode { grid, list }

class AppSettings {
  // ...现有字段
  final DiscoveryViewMode discoveryViewMode; // 新增,默认 grid
  // copyWith 增加对应参数
  // toJson/fromJson: discoveryViewMode:
  //   DiscoveryViewMode.values[json['discoveryViewMode'] as int? ?? 0]
}
```

沿用现有 `LayoutMode`/`ReadingDirection` 等"枚举+索引"持久化模式,走
`local_storage_io.dart`/`local_storage_web.dart` 现有读写机制,不新增存储通道。

**2. `DiscoveryState` 新增字段**(`discovery_state.dart`):

```dart
class DiscoveryState extends Equatable {
  // ...现有字段
  final DiscoveryViewMode viewMode; // 新增,从 AppSettings 初始化
}
```

**3. `DiscoveryCubit` 新增逻辑**(`discovery_cubit.dart`):

- `init()` 时从 `SettingsStore`(或注入的 settings 仓库)读取
  `discoveryViewMode` 初始化 state。
- 新增 `toggleViewMode()`:切换 `grid ⇄ list`,更新 state,同时调用
  `SettingsStore` 保存新值(fire-and-forget,不阻塞UI)。

## 组件架构

**1. 抽取公共卡片组件到 `lib/presentation/common/manga_card.dart`**:

- `MangaGridCard`:原 `_MangaCard` 逻辑原样迁移(封面 `Expanded` + 标题2行 +
  章节数/热度小字)。
- `MangaListItem`(方案C排版):
  ```dart
  class MangaListItem extends StatelessWidget {
    final MangaSummary manga;
    const MangaListItem({super.key, required this.manga});

    @override
    Widget build(BuildContext context) {
      return InkWell(
        onTap: () => context.push(AppRoutes.detailPath(manga.sourceId, manga.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 96, height: 136,
                  child: MangaCoverImage(
                    imageUrl: manga.coverUrl, headers: manga.headers,
                    sourceId: manga.sourceId, fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(manga.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(manga.author, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: _buildChips(context)),
                    if (manga.description != null) ...[
                      const SizedBox(height: 6),
                      Text(manga.description!, maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    /// 按 chapterCount / popularityText / updateTime 是否存在动态生成 chip,
    /// 三者都缺失时返回空列表(Wrap 不占空间)。
    List<Widget> _buildChips(BuildContext context) { /* ... */ }
  }
  ```
- `discovery_screen.dart` 中原私有 `_MangaCard` 删除,改为引用
  `MangaGridCard`。
- `home_screen.dart` 不改动,仍用其自身 `_buildMangaCard()`(保留重复代码,
  作为后续任务)。
- chip 用 Material 3 `Chip`/`Container` 轻量实现,不引入新依赖。

**2. AppBar 切换按钮**(`discovery_screen.dart` 的 `_DiscoveryView`):

```dart
appBar: AppBar(
  title: const Text('发现'),
  actions: [
    IconButton(
      icon: Icon(state.viewMode == DiscoveryViewMode.grid
          ? Icons.view_list : Icons.grid_view),
      tooltip: state.viewMode == DiscoveryViewMode.grid ? '切换到列表' : '切换到网格',
      onPressed: () => context.read<DiscoveryCubit>().toggleViewMode(),
    ),
    IconButton(icon: const Icon(Icons.search),
        onPressed: () => context.push(AppRoutes.search)),
  ],
),
```

需要一个 `BlocBuilder`(或包裹整个 AppBar)读取 `viewMode` 决定图标,其余
AppBar 逻辑不变。

**3. `_buildGrid` 改为统一入口 `_buildContent`**,按 `state.viewMode` 分支:

```dart
Widget _buildContent(BuildContext context) {
  return BlocBuilder<DiscoveryCubit, DiscoveryState>(
    builder: (context, state) {
      // loading/error 分支保持不变(含 Cloudflare 特殊处理)
      final isGrid = state.viewMode == DiscoveryViewMode.grid;
      return RefreshIndicator(
        onRefresh: () => context.read<DiscoveryCubit>().refresh(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification && n.metrics.extentAfter < 200) {
              context.read<DiscoveryCubit>().loadMore();
            }
            return false;
          },
          child: isGrid
              ? GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Responsive.gridColumns(context),
                    childAspectRatio: 0.55,
                    crossAxisSpacing: 8, mainAxisSpacing: 8,
                  ),
                  itemCount: state.manga.length + (state.hasMore ? 1 : 0),
                  itemBuilder: (context, index) => index >= state.manga.length
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : MangaGridCard(manga: state.manga[index]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: state.manga.length + (state.hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => Divider(
                    height: 1, indent: 96 + 12 + 12,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    if (index >= state.manga.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    return MangaListItem(manga: state.manga[index]);
                  },
                ),
        ),
      );
    },
  );
}
```

## 边界情况

- `chapterCount`/`popularityText`/`updateTime`/`description` 均可能为
  `null`,每个字段独立条件渲染,不留空白占位。
- 章节数/热度/更新时间三者都缺失时,chip `Wrap` 为空 widget(不显示空行)。
- 列表模式的加载更多/下拉刷新/错误态/Cloudflare 验证态逻辑与网格模式完全
  共用(`_buildContent` 统一处理,不区分)。
- 切换 `viewMode` 不重新拉取数据,只切换 UI 展示层,`state.manga` 数据不变。

## 测试计划

1. Widget 测试:`MangaListItem` 独立测试 —— 有/无 `description`、有/无 chip
   数据时的渲染分支。
2. Cubit 测试:`toggleViewMode()` 状态切换 + 校验调用了 `SettingsStore`
   持久化方法。
3. 回归:确认网格模式(`MangaGridCard`)渲染效果与改造前 `_MangaCard`
   一致(人工核对,非像素级测试)。
4. 手动验证:重启 App 后 `viewMode` 是否记住上次选择。

## 范围声明(本次不做)

- 不改 `home_screen.dart` 的调用代码(仅抽取公共组件供其未来可选复用)。
- 不为所有数据源补充 `description` 解析,仅示范 comick/pica_comic 等少数源。
- 不新增列表布局下的多列/响应式列数策略(始终单列)。
