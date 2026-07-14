import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/core/utils/responsive.dart';
import 'package:comic_reader/presentation/common/manga_cover_image.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/data/local/category_store.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/downloads/download_drawer.dart';
import 'bloc/home_cubit.dart';
import 'bloc/home_state.dart';

/// Home screen showing user's favorite manga bookshelf.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(
        favoritesStore: GetIt.instance<FavoritesStore>(),
        updateStore: GetIt.instance<UpdateStore>(),
        categoryStore: GetIt.instance<CategoryStore>(),
        repository: GetIt.instance<MangaRepository>(),
      )..loadFavorites(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  late final FavoritesStore _favoritesStore;

  @override
  void initState() {
    super.initState();
    _favoritesStore = GetIt.instance<FavoritesStore>();
    _favoritesStore.notifier.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    _favoritesStore.notifier.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    context.read<HomeCubit>().loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        return Scaffold(
          appBar: state.isSelecting
              ? _buildSelectionAppBar(context, state)
              : AppBar(
                  title: const Text('漫画阅读器'),
                  actions: [
                    _buildUpdateAction(context, state),
                    ListenableBuilder(
                      listenable: GetIt.instance<DownloadManager>(),
                      builder: (context, _) {
                        final manager = GetIt.instance<DownloadManager>();
                        return IconButton(
                          icon: Badge(
                            isLabelVisible: manager.activeCount > 0,
                            label: Text('${manager.activeCount}'),
                            child: const Icon(Icons.download),
                          ),
                          tooltip: '下载',
                          onPressed: () => DownloadDrawer.show(context),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: '搜索',
                      onPressed: () => context.push(AppRoutes.search),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history),
                      tooltip: '最近阅读',
                      onPressed: () => context.push(AppRoutes.history),
                    ),
                    IconButton(
                      icon: const Icon(Icons.label_outline),
                      tooltip: '分类管理',
                      onPressed: () => _showCategoryManager(context, state),
                    ),
                  ],
                ),
          body: _buildBody(context, state),
        );
      },
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(BuildContext context, HomeState state) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => context.read<HomeCubit>().exitSelectionMode(),
      ),
      title: Text('已选 ${state.selectedKeys.length} 项'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: '全选',
          onPressed: () => context.read<HomeCubit>().selectAll(),
        ),
        IconButton(
          icon: const Icon(Icons.label),
          tooltip: '设置分类',
          onPressed: state.selectedKeys.isEmpty
              ? null
              : () => _showSetCategories(context, state),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          tooltip: '删除',
          onPressed: () => _confirmDelete(context, state),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, HomeState state) async {
    final count = state.selectedKeys.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要从书架移除 $count 部漫画吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<HomeCubit>().deleteSelected();
    }
  }

  Widget _buildUpdateAction(BuildContext context, HomeState state) {
    if (state.status == HomeStatus.updating) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text(
              '${state.updateProgress + 1}/${state.updateTotal}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: '检查更新',
      onPressed: () => context.read<HomeCubit>().batchUpdate(),
    );
  }

  Widget _buildBody(BuildContext context, HomeState state) {
    if (state.status == HomeStatus.loading || state.status == HomeStatus.initial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.favorites.isEmpty) {
      return _buildEmptyState(context);
    }
    final filtered = state.filteredFavorites;
    return Column(
      children: [
        _buildCategoryTabs(context, state),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyCategory(context)
              : Responsive.constrainedContent(
                  context: context,
                  child: RefreshIndicator(
                    onRefresh: () => context.read<HomeCubit>().loadFavorites(),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: Responsive.gridColumns(context),
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final manga = filtered[index];
                        return _buildMangaCard(context, manga, state);
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Horizontal category tab bar: All | Uncategorized | <custom categories...>
  Widget _buildCategoryTabs(BuildContext context, HomeState state) {
    final tabs = <_CategoryTab>[
      const _CategoryTab(id: kAllCategoryId, name: '全部'),
      const _CategoryTab(id: kUncategorizedId, name: '未分类'),
      ...state.categories.map((c) => _CategoryTab(id: c.id, name: c.name)),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final selected = state.selectedCategoryId == tab.id ||
              (state.selectedCategoryId == null && tab.id == kAllCategoryId);
          return ChoiceChip(
            label: Text(tab.name),
            selected: selected,
            onSelected: (_) =>
                context.read<HomeCubit>().selectCategory(tab.id),
          );
        },
      ),
    );
  }

  Widget _buildEmptyCategory(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_none, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            '该分类暂无漫画',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildMangaCard(BuildContext context, MangaSummary manga, HomeState state) {
    final hasNewUpdate = state.hasUpdate(manga.sourceId, manga.id);
    final key = '${manga.sourceId}_${manga.id}';
    final isSelected = state.selectedKeys.contains(key);

    return GestureDetector(
      onTap: () async {
        final cubit = context.read<HomeCubit>();
        if (state.isSelecting) {
          cubit.toggleSelection(manga.sourceId, manga.id);
          return;
        }
        if (hasNewUpdate) {
          cubit.clearUpdate(manga.sourceId, manga.id);
        }
        await context.push(
          AppRoutes.detail
              .replaceFirst(':sourceId', manga.sourceId)
              .replaceFirst(':mangaId', manga.id),
        );
        if (mounted) {
          cubit.loadFavorites();
        }
      },
      onLongPress: () {
        final cubit = context.read<HomeCubit>();
        if (!state.isSelecting) {
          cubit.enterSelectionMode(manga.sourceId, manga.id);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: MangaCoverImage(
                    imageUrl: manga.coverUrl,
                    headers: manga.headers,
                    sourceId: manga.sourceId,
                    fit: BoxFit.cover,
                  ),
                ),
                if (hasNewUpdate)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (state.isSelecting)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black45,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.collections_bookmark_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无收藏',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            '去发现页面浏览漫画吧',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              // Navigate to discovery tab
              final shell = StatefulNavigationShell.maybeOf(context);
              if (shell != null) {
                shell.goBranch(1);
              } else {
                context.push(AppRoutes.discovery);
              }
            },
            icon: const Icon(Icons.explore),
            label: const Text('去发现'),
          ),
        ],
      ),
    );
  }

  /// Category management dialog: add / rename / delete categories.
  Future<void> _showCategoryManager(BuildContext context, HomeState state) async {
    final cubit = context.read<HomeCubit>();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('分类管理'),
          content: SizedBox(
            width: double.maxFinite,
            child: BlocBuilder<HomeCubit, HomeState>(
              bloc: cubit,
              builder: (context, s) {
                if (s.categories.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('暂无分类，点击下方按钮添加'),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: s.categories.length,
                  itemBuilder: (context, index) {
                    final category = s.categories[index];
                    return ListTile(
                      dense: true,
                      title: Text(category.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            tooltip: '重命名',
                            onPressed: () =>
                                _promptRenameCategory(ctx, cubit, category),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20),
                            tooltip: '删除',
                            onPressed: () => cubit.removeCategory(category.id),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _promptAddCategory(ctx, cubit),
              icon: const Icon(Icons.add),
              label: const Text('添加分类'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _promptAddCategory(BuildContext context, HomeCubit cubit) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '分类名称'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      cubit.addCategory(name);
    }
  }

  Future<void> _promptRenameCategory(
    BuildContext context,
    HomeCubit cubit,
    Category category,
  ) async {
    final controller = TextEditingController(text: category.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '分类名称'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != category.name) {
      cubit.renameCategory(category.id, name);
    }
  }

  /// Multi-select dialog to assign the selected manga to categories.
  Future<void> _showSetCategories(BuildContext context, HomeState state) async {
    final cubit = context.read<HomeCubit>();
    if (state.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在“分类管理”中添加分类')),
      );
      return;
    }
    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('设置分类（${state.selectedKeys.length} 项）'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: state.categories.map((category) {
                    return CheckboxListTile(
                      dense: true,
                      title: Text(category.name),
                      value: selected.contains(category.id),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            selected.add(category.id);
                          } else {
                            selected.remove(category.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed == true) {
      cubit.setCategoriesForSelected(selected.toList());
    }
  }
}

/// Lightweight descriptor for a category tab (real or virtual).
class _CategoryTab {
  final String id;
  final String name;

  const _CategoryTab({required this.id, required this.name});
}
