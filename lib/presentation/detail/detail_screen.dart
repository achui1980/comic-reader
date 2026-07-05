import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/presentation/common/manga_cover_image.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/presentation/common/cloudflare_dialog.dart';
import 'bloc/detail_cubit.dart';
import 'bloc/detail_state.dart';
import 'bloc/download_cubit.dart';
import 'bloc/download_state.dart';

class DetailScreen extends StatelessWidget {
  final String sourceId;
  final String mangaId;

  const DetailScreen({super.key, required this.sourceId, required this.mangaId});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => DetailCubit(
            repository: GetIt.instance<MangaRepository>(),
            favoritesStore: GetIt.instance<FavoritesStore>(),
            historyStore: GetIt.instance<ReadingHistoryStore>(),
            sourceId: sourceId,
            mangaId: mangaId,
          )..loadDetail(),
        ),
        BlocProvider(
          create: (_) => DownloadCubit(
            cacheService: GetIt.instance<ChapterCacheService>(),
            repository: GetIt.instance<MangaRepository>(),
            sourceId: sourceId,
            mangaId: mangaId,
          ),
        ),
      ],
      child: const _DetailView(),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<DetailCubit, DetailState>(
      listenWhen: (prev, curr) => prev.chapters.isEmpty && curr.chapters.isNotEmpty,
      listener: (context, state) {
        // Check which chapters are already cached
        context.read<DownloadCubit>().checkCachedChapters(state.chapters);
      },
      child: BlocBuilder<DetailCubit, DetailState>(
        builder: (context, state) {
          if (state.status == DetailStatus.loading) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (state.status == DetailStatus.error) {
            final isCfError = state.errorMessage?.contains('CloudflareException') == true ||
                state.errorMessage?.contains('Cloudflare') == true;
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCfError ? Icons.shield_outlined : Icons.error_outline,
                      size: 48,
                      color: isCfError ? Colors.orange : Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isCfError ? '需要完成 Cloudflare 验证' : (state.errorMessage ?? '加载失败'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (isCfError)
                      FilledButton.icon(
                        onPressed: () async {
                          await showCloudflareDialog(context, sourceId: context.read<DetailCubit>().sourceId);
                        },
                        icon: const Icon(Icons.verified_user_outlined, size: 18),
                        label: const Text('去验证'),
                      ),
                    if (isCfError) const SizedBox(height: 8),
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
            body: RefreshIndicator(
              onRefresh: () => context.read<DetailCubit>().refresh(),
              child: CustomScrollView(
                slivers: [
                  _buildHeader(context, manga, state.isFavorite),
                  _buildInfo(context, manga),
                  _buildChapterHeader(context, state),
                  _buildChapterGrid(context, state),
                ],
              ),
            ),
          );
        },
      ),
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
            MangaCoverImage(
              imageUrl: manga.coverUrl,
              headers: manga.headers,
              sourceId: manga.sourceId,
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
            _ReadButton(manga: manga),
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
            // Download all button
            BlocBuilder<DownloadCubit, DownloadState>(
              builder: (context, downloadState) {
                final isDownloading = downloadState.activeChapterId != null;
                return IconButton(
                  icon: Icon(
                    isDownloading ? Icons.downloading : Icons.download_outlined,
                    size: 18,
                  ),
                  onPressed: isDownloading
                      ? () => context.read<DownloadCubit>().cancelDownload()
                      : () => _showDownloadAllDialog(context, state.chapters),
                  tooltip: isDownloading ? '取消下载' : '下载全部',
                );
              },
            ),
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

  void _showDownloadAllDialog(BuildContext context, List<ChapterItem> chapters) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('下载全部章节'),
        content: Text('确定下载全部 ${chapters.length} 个章节？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<DownloadCubit>().downloadMultiple(chapters);
            },
            child: const Text('下载'),
          ),
        ],
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
    if (chapters.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 48,
                color: Theme.of(context).disabledColor,
              ),
              const SizedBox(height: 12),
              Text(
                '暂无章节',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
            ],
          ),
        ),
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
            return BlocBuilder<DownloadCubit, DownloadState>(
              buildWhen: (prev, curr) =>
                  prev.chapters[chapter.id] != curr.chapters[chapter.id] ||
                  (curr.activeChapterId == chapter.id &&
                      prev.activeProgress != curr.activeProgress),
              builder: (context, downloadState) {
                final status = downloadState.chapters[chapter.id] ??
                    ChapterDownloadStatus.none;
                return _ChapterTile(
                  chapter: chapter,
                  downloadStatus: status,
                  isRead: cubit.state.readChapterIds.contains(chapter.id),
                  progress: downloadState.activeChapterId == chapter.id
                      ? downloadState.activeProgress
                      : null,
                  total: downloadState.activeChapterId == chapter.id
                      ? downloadState.activeTotal
                      : null,
                  onTap: () => context.push(
                    AppRoutes.readerPath(cubit.sourceId, cubit.mangaId, chapter.id),
                    extra: <String, dynamic>{
                      'chapterList': cubit.state.chapters,
                      'initialPage': 0,
                    },
                  ),
                  onLongPress: () => _showChapterActions(context, chapter, status),
                );
              },
            );
          },
          childCount: chapters.length,
        ),
      ),
    );
  }

  void _showChapterActions(
    BuildContext context,
    ChapterItem chapter,
    ChapterDownloadStatus status,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载此章节'),
              enabled: status != ChapterDownloadStatus.cached &&
                  status != ChapterDownloadStatus.downloading,
              onTap: () {
                Navigator.pop(sheetContext);
                context.read<DownloadCubit>().downloadChapter(chapter);
              },
            ),
            if (status == ChapterDownloadStatus.cached)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除缓存', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final cubit = context.read<DetailCubit>();
                  GetIt.instance<ChapterCacheService>().deleteChapter(
                    cubit.sourceId,
                    cubit.mangaId,
                    chapter.id,
                  );
                  // Re-check cache status
                  context
                      .read<DownloadCubit>()
                      .checkCachedChapters(cubit.state.chapters);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final ChapterItem chapter;
  final ChapterDownloadStatus downloadStatus;
  final int? progress;
  final int? total;
  final bool isRead;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ChapterTile({
    required this.chapter,
    required this.downloadStatus,
    this.progress,
    this.total,
    this.isRead = false,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isRead
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isRead
                        ? colorScheme.onSurface.withValues(alpha: 0.5)
                        : null,
                  ),
                ),
              ),
            ),
            // Download status indicator
            Positioned(
              top: 4,
              right: 4,
              child: _buildStatusIcon(),
            ),
            // Read indicator
            if (isRead)
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (downloadStatus) {
      case ChapterDownloadStatus.none:
      case ChapterDownloadStatus.failed:
        return const SizedBox.shrink();
      case ChapterDownloadStatus.queued:
        return const Icon(Icons.hourglass_empty, size: 12, color: Colors.orange);
      case ChapterDownloadStatus.downloading:
        if (progress != null && total != null && total! > 0) {
          return SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: progress! / total!,
              strokeWidth: 2,
              color: Colors.blue,
            ),
          );
        }
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
        );
      case ChapterDownloadStatus.cached:
        return const Icon(Icons.check_circle, size: 14, color: Colors.green);
    }
  }
}

class _ReadButton extends StatefulWidget {
  final MangaDetail manga;
  const _ReadButton({required this.manga});

  @override
  State<_ReadButton> createState() => _ReadButtonState();
}

class _ReadButtonState extends State<_ReadButton> {
  Map<String, dynamic>? _progress;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final cubit = context.read<DetailCubit>();
    final progress = await GetIt.instance<ReadingHistoryStore>()
        .getProgress(cubit.sourceId, cubit.mangaId);
    if (mounted) {
      setState(() {
        _progress = progress;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DetailCubit>();
    final hasProgress = _loaded && _progress != null;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          String chapterId;
          int initialPage;
          if (hasProgress) {
            chapterId = _progress!['chapterId'] as String;
            initialPage = (_progress!['page'] as num?)?.toInt() ?? 0;
          } else if (cubit.state.chapters.isNotEmpty) {
            chapterId = cubit.state.chapters.first.id;
            initialPage = 0;
          } else {
            // Fallback for single-chapter manga with no explicit chapter list
            chapterId = cubit.mangaId;
            initialPage = 0;
          }
          context.push(
            AppRoutes.readerPath(cubit.sourceId, cubit.mangaId, chapterId),
            extra: <String, dynamic>{
              'chapterList': cubit.state.chapters.isNotEmpty
                  ? cubit.state.chapters
                  : [ChapterItem(id: chapterId, mangaId: cubit.mangaId, title: '开始阅读', href: '')],
              'initialPage': initialPage,
            },
          );
        },
        icon: Icon(hasProgress ? Icons.play_circle_outline : Icons.play_arrow),
        label: Text(hasProgress ? '继续阅读' : '开始阅读'),
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
