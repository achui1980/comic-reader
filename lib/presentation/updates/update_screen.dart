import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';

import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/core/utils/responsive.dart';
import 'package:comic_reader/data/local/library_update_service.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/presentation/common/manga_cover_image.dart';
import 'bloc/updates_cubit.dart';
import 'bloc/updates_state.dart';

/// Library updates tab: a time-ordered list of newly-found chapters across
/// all favorited manga.
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => UpdatesCubit(
        updateStore: GetIt.instance<UpdateStore>(),
        libraryUpdateService: GetIt.instance<LibraryUpdateService>(),
      )..load(),
      child: const _UpdatesView(),
    );
  }
}

class _UpdatesView extends StatelessWidget {
  const _UpdatesView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新'),
        actions: [
          BlocBuilder<UpdatesCubit, UpdatesState>(
            builder: (context, state) {
              if (state.chapters.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: '全部标记已读',
                icon: const Icon(Icons.done_all),
                onPressed: () => _confirmClearAll(context),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<UpdatesCubit, UpdatesState>(
        builder: (context, state) {
          return Column(
            children: [
              if (state.isUpdating) _buildProgress(context, state),
              Expanded(child: _buildBody(context, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgress(BuildContext context, UpdatesState state) {
    final total = state.total;
    final value = total > 0 ? state.progress / total : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: LinearProgressIndicator(value: value)),
          const SizedBox(width: 12),
          Text(total > 0 ? '${state.progress}/$total' : '检查中…'),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, UpdatesState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.chapters.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<UpdatesCubit>().refresh(),
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.new_releases_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无更新', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 4),
                  Text('下拉刷新以检查新章节',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<UpdatesCubit>().refresh(),
      child: Responsive.constrainedContent(
        context: context,
        child: ListView.separated(
          itemCount: state.chapters.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) =>
              _buildItem(context, state.chapters[index]),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, NewChapter chapter) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 44,
          height: 60,
          child: chapter.coverUrl.isEmpty
              ? Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.image_not_supported, size: 20),
                )
              : MangaCoverImage(
                  imageUrl: chapter.coverUrl,
                  sourceId: chapter.sourceId,
                  fit: BoxFit.cover,
                ),
        ),
      ),
      title: Text(
        chapter.mangaTitle.isEmpty ? '(未知漫画)' : chapter.mangaTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        chapter.chapterTitle.isEmpty ? '有新章节' : chapter.chapterTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatTime(chapter.foundAt),
        style: const TextStyle(color: Colors.grey, fontSize: 11),
      ),
      onTap: () {
        context.push(
          AppRoutes.detailPath(chapter.sourceId, chapter.mangaId),
        );
      },
      onLongPress: () => context
          .read<UpdatesCubit>()
          .clearForManga(chapter.sourceId, chapter.mangaId),
    );
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  void _confirmClearAll(BuildContext context) {
    final cubit = context.read<UpdatesCubit>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('全部标记已读'),
        content: const Text('确定清空所有更新记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              cubit.clearAll();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
