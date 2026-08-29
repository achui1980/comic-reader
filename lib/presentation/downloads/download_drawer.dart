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
                _buildHeader(context, manager),
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

  Widget _buildHeader(BuildContext context, DownloadManager manager) {
    final total = manager.tasks.length;
    final active = manager.activeCount;
    final hasPaused = manager.tasks.any(
      (t) => t.status == DownloadTaskStatus.paused,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('下载队列 ($total)', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (active > 0)
            Text(
              '进行中: $active',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.pause),
            tooltip: '全部暂停',
            onPressed: active == 0 && manager.pendingCount == 0
                ? null
                : () => manager.pauseAll(),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: '全部恢复',
            onPressed: hasPaused ? () => manager.resumeAll() : null,
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTile(
    BuildContext context,
    DownloadTask task,
    DownloadManager manager,
  ) {
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
      case DownloadTaskStatus.paused:
        return const Icon(Icons.pause_circle_outline, color: Colors.orange);
      case DownloadTaskStatus.partiallyFailed:
        return const Icon(Icons.error_outline, color: Colors.orange);
    }
  }

  Widget? _buildTrailing(
    BuildContext context,
    DownloadTask task,
    DownloadManager manager,
  ) {
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
      case DownloadTaskStatus.paused:
        return IconButton(
          icon: const Icon(Icons.play_circle_outline, size: 20),
          tooltip: '恢复',
          onPressed: () => manager.resumeTask(task.key),
        );
      case DownloadTaskStatus.partiallyFailed:
        return TextButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: Text('${task.failedImageIndexes.length}张失败，点击重试'),
          onPressed: () => manager.retryTask(task.key),
        );
      default:
        return null;
    }
  }

  void _confirmRemove(
    BuildContext context,
    DownloadTask task,
    DownloadManager manager,
  ) {
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
