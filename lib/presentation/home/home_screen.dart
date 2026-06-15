import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/core/utils/responsive.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Home screen showing user's favorite manga bookshelf.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MangaSummary> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await GetIt.instance<FavoritesStore>().getAll();
    if (mounted) {
      setState(() {
        _favorites = favorites;
        _loading = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload favorites every time this screen becomes active
    // (e.g., tab switch in indexedStack)
    _loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画阅读器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => context.push(AppRoutes.search),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? _buildEmptyState(context)
              : Responsive.constrainedContent(
                  context: context,
                  child: RefreshIndicator(
                    onRefresh: _loadFavorites,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: Responsive.gridColumns(context),
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _favorites.length,
                      itemBuilder: (context, index) {
                        final manga = _favorites[index];
                        return _buildMangaCard(context, manga);
                      },
                    ),
                  ),
                ),
    );
  }

  Widget _buildMangaCard(BuildContext context, MangaSummary manga) {
    return GestureDetector(
      onTap: () async {
        await context.push(
          AppRoutes.detail
              .replaceFirst(':sourceId', manga.sourceId)
              .replaceFirst(':mangaId', manga.id),
        );
        _loadFavorites();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: ImageProxy.url(manga.coverUrl),
                httpHeaders: manga.headers,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
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
}
