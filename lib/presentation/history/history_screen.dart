import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/core/utils/responsive.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/presentation/common/manga_cover_image.dart';
import 'bloc/history_cubit.dart';
import 'bloc/history_state.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HistoryCubit(
        readingHistoryStore: GetIt.instance<ReadingHistoryStore>(),
      )..load(),
      child: const _HistoryView(),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('最近阅读'),
        actions: [
          BlocBuilder<HistoryCubit, HistoryState>(
            builder: (context, state) {
              if (state.entries.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: '清空',
                onPressed: () => _confirmClearAll(context),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<HistoryCubit, HistoryState>(
        builder: (context, state) {
          return _buildBody(context, state);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, HistoryState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无阅读记录', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return Responsive.constrainedContent(
      context: context,
      child: ListView.separated(
        itemCount: state.entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            _buildItem(context, state.entries[index]),
      ),
    );
  }

  Widget _buildItem(BuildContext context, HistoryEntry e) {
    final cubit = context.read<HistoryCubit>();
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 44,
          height: 60,
          child: e.coverUrl.isEmpty
              ? Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.image_not_supported, size: 20),
                )
              : MangaCoverImage(
                  imageUrl: e.coverUrl,
                  sourceId: e.sourceId,
                  fit: BoxFit.cover,
                ),
        ),
      ),
      title: Text(
        e.mangaTitle.isEmpty ? '(未知漫画)' : e.mangaTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        e.chapterTitle.isEmpty ? '已阅读' : e.chapterTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatTime(e.timestamp),
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      onTap: () => context.push(AppRoutes.detailPath(e.sourceId, e.mangaId)),
      onLongPress: () => cubit.removeItem(e.sourceId, e.mangaId),
    );
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final cubit = context.read<HistoryCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空阅读记录'),
        content: const Text('确定清空所有阅读记录吗？'),
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
      ),
    );
    if (confirmed == true) {
      await cubit.clearAll();
    }
  }
}
