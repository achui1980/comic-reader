import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/core/utils/responsive.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'bloc/discovery_cubit.dart';
import 'bloc/discovery_state.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DiscoveryCubit(
        repository: GetIt.instance<MangaRepository>(),
        registry: GetIt.instance<SourceRegistry>(),
      )..init(),
      child: const _DiscoveryView(),
    );
  }
}

class _DiscoveryView extends StatelessWidget {
  const _DiscoveryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.search),
          ),
        ],
      ),
      body: Responsive.constrainedContent(
        context: context,
        child: Column(
          children: [
            _buildFilterBar(context),
            Expanded(child: _buildGrid(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return BlocBuilder<DiscoveryCubit, DiscoveryState>(
      buildWhen: (prev, curr) =>
          prev.filterOptions != curr.filterOptions ||
          prev.filters != curr.filters ||
          prev.sourceId != curr.sourceId,
      builder: (context, state) {
        final cubit = context.read<DiscoveryCubit>();
        final registry = GetIt.instance<SourceRegistry>();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ActionChip(
                avatar: const Icon(Icons.source, size: 16),
                label: Text(registry.get(state.sourceId)?.shortName ?? '源'),
                onPressed: () => _showSourcePicker(context, registry, cubit),
              ),
              const SizedBox(width: 8),
              ...state.filterOptions.map((option) {
                final selected = state.filters[option.name] ?? option.defaultValue;
                final selectedLabel = option.choices
                        .where((c) => c.value == selected)
                        .map((c) => c.label)
                        .firstOrNull ??
                    option.label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(selectedLabel, style: const TextStyle(fontSize: 12)),
                    selected: selected != option.defaultValue,
                    onSelected: (_) => _showFilterPicker(context, option, cubit),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showSourcePicker(BuildContext context, SourceRegistry registry, DiscoveryCubit cubit) {
    final sources = registry.enabled;
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

  void _showFilterPicker(BuildContext context, FilterOption option, DiscoveryCubit cubit) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        shrinkWrap: true,
        itemCount: option.choices.length,
        itemBuilder: (ctx, i) => ListTile(
          title: Text(option.choices[i].label),
          onTap: () {
            Navigator.pop(ctx);
            cubit.changeFilter(option.name, option.choices[i].value);
          },
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return BlocBuilder<DiscoveryCubit, DiscoveryState>(
      builder: (context, state) {
        if (state.status == DiscoveryStatus.loading && state.manga.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == DiscoveryStatus.error && state.manga.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.errorMessage ?? '加载失败'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.read<DiscoveryCubit>().loadDiscovery(),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        final columns = Responsive.gridColumns(context);
        // Keep aspect ratio similar to original maxCrossAxisExtent: 180, ratio: 0.55
        const childAspectRatio = 0.55;

        return RefreshIndicator(
          onRefresh: () => context.read<DiscoveryCubit>().refresh(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification &&
                  notification.metrics.extentAfter < 200) {
                context.read<DiscoveryCubit>().loadMore();
              }
              return false;
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: state.manga.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.manga.length) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                return _MangaCard(manga: state.manga[index]);
              },
            ),
          ),
        );
      },
    );
  }
}

class _MangaCard extends StatelessWidget {
  final MangaSummary manga;
  const _MangaCard({required this.manga});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.detailPath(manga.sourceId, manga.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: manga.coverUrl,
                httpHeaders: manga.headers,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey.shade200),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
