import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/data/local/download_manager.dart';

/// Bottom sheet showing the download queue.
class DownloadDrawer extends StatelessWidget {
  const DownloadDrawer({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DownloadDrawer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = GetIt.instance<DownloadManager>();
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final tasks = manager.tasks;
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                _buildHandle(),
                _buildHeader(context, tasks.length, manager.activeCount),
                const Divider(height: 1),
                Expanded(
                  child: tasks.isEmpty
                      ? _buildEmpty(context)
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: tasks.length,
                          itemBuilder: (context, index) =>
                              _buildTaskTile(context, tasks[index], manager),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade400,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int total, int active) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '下载队列 ($total)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          if (active > 0)
            Text(
              '进行中: $active',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_done, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            '暂无下载任务',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTile(
      BuildContext context, DownloadTask task, DownloadManager manager) {
    return GestureDetector(
      onLongPress: () => _confirmRemove(context, task, manager),
      child: ListTile(
        leading: _statusIcon(task.status),
        title: Text(
          task.chapterTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          task.mangaTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _buildTrailing(context, task, manager),
      ),
    );
  }

  Widget _statusIcon(DownloadTaskStatus status) {
    switch (status) {
      case DownloadTaskStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey);
      case DownloadTaskStatus.downloading:
        return const Icon(Icons.downloading, color: Colors.blue);
      case DownloadTaskStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadTaskStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  Widget? _buildTrailing(
      BuildContext context, DownloadTask task, DownloadManager manager) {
    switch (task.status) {
      case DownloadTaskStatus.downloading:
        return SizedBox(
          width: 40,
          child: Text(
            '${task.progress}%',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        );
      case DownloadTaskStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: '重试',
          onPressed: () => manager.retryTask(task.key),
        );
      default:
        return null;
    }
  }

  void _confirmRemove(
      BuildContext context, DownloadTask task, DownloadManager manager) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除任务'),
        content: Text('确定移除 "${task.chapterTitle}" 的下载任务？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              manager.removeTask(task.key);
              Navigator.of(ctx).pop();
            },
            child: const Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
