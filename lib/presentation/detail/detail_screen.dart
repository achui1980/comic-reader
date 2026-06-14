import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'bloc/detail_cubit.dart';
import 'bloc/detail_state.dart';

class DetailScreen extends StatelessWidget {
  final String sourceId;
  final String mangaId;

  const DetailScreen({super.key, required this.sourceId, required this.mangaId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DetailCubit(
        repository: GetIt.instance<MangaRepository>(),
        favoritesStore: GetIt.instance<FavoritesStore>(),
        sourceId: sourceId,
        mangaId: mangaId,
      )..loadDetail(),
      child: const _DetailView(),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetailCubit, DetailState>(
      builder: (context, state) {
        if (state.status == DetailStatus.loading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (state.status == DetailStatus.error) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.errorMessage ?? '加载失败'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<DetailCubit>().loadDetail(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        final manga = state.manga;
        if (manga == null) return const Scaffold(body: SizedBox.shrink());
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              _buildHeader(context, manga, state.isFavorite),
              _buildInfo(context, manga),
              _buildChapterHeader(context, state),
              _buildChapterGrid(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, MangaDetail manga, bool isFavorite) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      actions: [
        IconButton(
          icon: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? Colors.red : null,
          ),
          onPressed: () => context.read<DetailCubit>().toggleFavorite(),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: Text(manga.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        background: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: manga.coverUrl,
              httpHeaders: manga.headers,
              fit: BoxFit.cover,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context, MangaDetail manga) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (manga.author.isNotEmpty) ...[
                  const Icon(Icons.person, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(manga.author, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 16),
                ],
                _StatusBadge(status: manga.status),
              ],
            ),
            const SizedBox(height: 8),
            if (manga.tags.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: manga.tags
                    .map((tag) => Chip(
                          label: Text(tag, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            if (manga.description != null) ...[
              const SizedBox(height: 12),
              Text(
                manga.description!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final cubit = context.read<DetailCubit>();
                  if (cubit.state.chapters.isNotEmpty) {
                    final first = cubit.state.chapters.first;
                    context.push(AppRoutes.readerPath(cubit.sourceId, cubit.mangaId, first.id));
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始阅读'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterHeader(BuildContext context, DetailState state) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text('章节列表 (${state.chapters.length})',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            IconButton(
              icon: Icon(
                state.chaptersReversed ? Icons.arrow_upward : Icons.arrow_downward,
                size: 18,
              ),
              onPressed: () => context.read<DetailCubit>().toggleSortOrder(),
              tooltip: '排序',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterGrid(BuildContext context, DetailState state) {
    final chapters = state.displayChapters;
    if (state.chaptersLoading && chapters.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final chapter = chapters[index];
            final cubit = context.read<DetailCubit>();
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.push(
                    AppRoutes.readerPath(cubit.sourceId, cubit.mangaId, chapter.id)),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            );
          },
          childCount: chapters.length,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final MangaStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      MangaStatus.ongoing => ('连载中', Colors.green),
      MangaStatus.completed => ('已完结', Colors.blue),
      MangaStatus.unknown => ('未知', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
