import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:comic_reader/app/router/routes.dart';

/// Home screen showing user's favorite manga bookshelf.
/// Currently shows empty state - favorites persistence will be added with Isar.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画阅读器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore),
            tooltip: '发现',
            onPressed: () => context.push(AppRoutes.discovery),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Center(
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
              onPressed: () => context.push(AppRoutes.discovery),
              icon: const Icon(Icons.explore),
              label: const Text('去发现'),
            ),
          ],
        ),
      ),
    );
  }
}
