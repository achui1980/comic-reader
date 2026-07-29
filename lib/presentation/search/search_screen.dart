import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/core/ai/ai_service.dart';
import 'package:comic_reader/data/local/work_group_store.dart';
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
        aiService: GetIt.instance<AiService>(),
        workGroupStore: GetIt.instance<WorkGroupStore>(),
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

  void _submit(BuildContext context, String value) {
    final cubit = context.read<SearchCubit>();
    cubit.submitQuery(value);
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
          onSubmitted: (value) => _submit(context, value),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _submit(context, _controller.text),
          ),
        ],
      ),
      body: Column(
        children: [
          // Aggregate / single-source toggle
          BlocBuilder<SearchCubit, SearchState>(
            buildWhen: (prev, curr) =>
                prev.aggregateMode != curr.aggregateMode ||
                prev.sourceId != curr.sourceId ||
                prev.aiMode != curr.aiMode ||
                prev.aiInterpretation != curr.aiInterpretation,
            builder: (context, state) {
              final cubit = context.read<SearchCubit>();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _ModeToggle(
                          aggregateMode: state.aggregateMode,
                          onChanged: (aggregate) =>
                              cubit.setAggregateMode(aggregate),
                        ),
                        const Spacer(),
                        _AiToggle(
                          aiMode: state.aiMode,
                          onChanged: (v) => cubit.setAiMode(v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Single-source picker (only in single mode)
                    if (!state.aggregateMode)
                      GestureDetector(
                        onTap: () => _showSourcePicker(context, cubit),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.source_outlined,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                cubit.registry.get(state.sourceId)?.name ??
                                    '选择源',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.blue),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down,
                                size: 18, color: Colors.blue),
                          ],
                        ),
                      )
                    else
                      const Text(
                        '聚合所有已启用源',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    if (state.aiMode && state.aiInterpretation.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.auto_awesome,
                              size: 14, color: Colors.deepPurple),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              state.aiInterpretation,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.deepPurple),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: BlocBuilder<SearchCubit, SearchState>(
              builder: (context, state) {
                if (state.aggregateMode) {
                  return const _AggregateResults();
                }
                return const _SingleSourceResults();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool aggregateMode;
  final ValueChanged<bool> onChanged;
  const _ModeToggle({required this.aggregateMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: false, label: Text('单源', style: TextStyle(fontSize: 12))),
        ButtonSegment(value: true, label: Text('聚合', style: TextStyle(fontSize: 12))),
      ],
      selected: {aggregateMode},
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

/// Small toggle enabling AI natural-language search interpretation.
class _AiToggle extends StatelessWidget {
  final bool aiMode;
  final ValueChanged<bool> onChanged;
  const _AiToggle({required this.aiMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onChanged(!aiMode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 16,
              color: aiMode ? Colors.deepPurple : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              'AI 搜索',
              style: TextStyle(
                fontSize: 12,
                color: aiMode ? Colors.deepPurple : Colors.grey,
                fontWeight: aiMode ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single-source result list (original behavior).
class _SingleSourceResults extends StatelessWidget {
  const _SingleSourceResults();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchCubit, SearchState>(
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
    );
  }
}

/// Aggregate results grouped per source.
class _AggregateResults extends StatelessWidget {
  const _AggregateResults();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        if (state.status == SearchStatus.initial) {
          return const Center(
            child: Text('输入关键词聚合搜索', style: TextStyle(color: Colors.grey)),
          );
        }
        if (state.status == SearchStatus.error && state.slices.isEmpty) {
          return Center(child: Text(state.errorMessage ?? '搜索失败'));
        }
        final slices = state.slices.values.toList();
        if (slices.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final cubit = context.read<SearchCubit>();
        return RefreshIndicator(
          onRefresh: () => cubit.refresh(),
          child: ListView.builder(
            itemCount: slices.length,
            itemBuilder: (context, index) {
              return _SourceGroup(slice: slices[index]);
            },
          ),
        );
      },
    );
  }
}

/// A collapsible group showing one source's results/loading/error state.
class _SourceGroup extends StatelessWidget {
  final SourceSearchSlice slice;
  const _SourceGroup({required this.slice});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchCubit>();
    final source = cubit.registry.get(slice.sourceId);
    final sourceName = source?.name ?? slice.sourceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Source header
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.source_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                sourceName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              if (slice.status == SearchStatus.loading ||
                  slice.status == SearchStatus.loadingMore)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (slice.status == SearchStatus.loaded)
                Text(
                  '${slice.results.length} 条',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              const Spacer(),
              if (slice.status == SearchStatus.error)
                TextButton.icon(
                  onPressed: () => cubit.retrySource(slice.sourceId),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('重试', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ),
        // Source body
        if (slice.status == SearchStatus.error)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              slice.errorMessage ?? '加载失败',
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          )
        else if (slice.status == SearchStatus.loaded && slice.results.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('没有结果', style: TextStyle(fontSize: 12, color: Colors.grey)),
          )
        else
          ...slice.results.map((m) => _SearchResultItem(manga: m)),
        // Load more for this source
        if (slice.status == SearchStatus.loaded && slice.hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: TextButton(
                onPressed: () => cubit.loadMoreSource(slice.sourceId),
                child: const Text('加载更多', style: TextStyle(fontSize: 12)),
              ),
            ),
          )
        else if (slice.status == SearchStatus.loadingMore)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
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
