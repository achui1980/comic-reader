import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/common/manga_cover_image.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'bloc/search_cubit.dart';
import 'bloc/search_state.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchCubit(
        repository: GetIt.instance<MangaRepository>(),
        registry: GetIt.instance<SourceRegistry>(),
      )..init(),
      child: const _SearchView(),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showSourcePicker(BuildContext context, SearchCubit cubit) {
    final sources = cubit.registry.enabled;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        shrinkWrap: true,
        itemCount: sources.length,
        itemBuilder: (ctx, i) => ListTile(
          title: Text(sources[i].name),
          subtitle: Text(sources[i].description ?? ''),
          onTap: () {
            Navigator.pop(ctx);
            cubit.changeSource(sources[i].id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索漫画...',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (value) => context.read<SearchCubit>().search(value),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.read<SearchCubit>().search(_controller.text),
          ),
        ],
      ),
      body: Column(
        children: [
          // Source selector bar
          BlocBuilder<SearchCubit, SearchState>(
            buildWhen: (prev, curr) => prev.sourceId != curr.sourceId,
            builder: (context, state) {
              final cubit = context.read<SearchCubit>();
              final source = cubit.registry.get(state.sourceId);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: GestureDetector(
                  onTap: () => _showSourcePicker(context, cubit),
                  child: Row(
                    children: [
                      const Icon(Icons.source_outlined, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        source?.name ?? '选择源',
                        style: const TextStyle(fontSize: 13, color: Colors.blue),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blue),
                    ],
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: BlocBuilder<SearchCubit, SearchState>(
              builder: (context, state) {
                if (state.status == SearchStatus.initial) {
                  return const Center(
                    child: Text('输入关键词搜索', style: TextStyle(color: Colors.grey)),
                  );
                }
                if (state.status == SearchStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.status == SearchStatus.error) {
                  return Center(child: Text(state.errorMessage ?? '搜索失败'));
                }
                if (state.results.isEmpty) {
                  return const Center(
                    child: Text('没有找到结果', style: TextStyle(color: Colors.grey)),
                  );
                }
                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollEndNotification &&
                        notification.metrics.extentAfter < 200) {
                      context.read<SearchCubit>().loadMore();
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: () => context.read<SearchCubit>().refresh(),
                    child: ListView.builder(
                      itemCount: state.results.length + (state.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= state.results.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        return _SearchResultItem(manga: state.results[index]);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  final MangaSummary manga;
  const _SearchResultItem({required this.manga});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 64,
          child: MangaCoverImage(
            imageUrl: manga.coverUrl,
            headers: manga.headers,
            sourceId: manga.sourceId,
            fit: BoxFit.cover,
          ),
        ),
      ),
      title: Text(manga.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(manga.author, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: manga.latestChapter != null
          ? Text(manga.latestChapter!, style: const TextStyle(fontSize: 11, color: Colors.grey))
          : null,
      onTap: () => context.push(AppRoutes.detailPath(manga.sourceId, manga.id)),
    );
  }
}
