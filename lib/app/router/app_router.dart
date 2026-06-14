import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:comic_reader/presentation/reader/reader_screen.dart';
import 'routes.dart';

/// Placeholder screen used during development
class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(title)),
    );
  }
}

/// App router configuration using GoRouter.
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _PlaceholderScreen(title: 'Home'),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        builder: (context, state) => const _PlaceholderScreen(title: 'Discovery'),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const _PlaceholderScreen(title: 'Search'),
      ),
      GoRoute(
        path: AppRoutes.detail,
        builder: (context, state) {
          return const _PlaceholderScreen(title: 'Detail');
        },
      ),
      GoRoute(
        path: AppRoutes.reader,
        builder: (context, state) {
          final sourceId = state.pathParameters['sourceId'] ?? '';
          final mangaId = state.pathParameters['mangaId'] ?? '';
          final chapterId = state.pathParameters['chapterId'] ?? '';
          return ReaderScreen(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterId: chapterId,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const _PlaceholderScreen(title: 'Settings'),
      ),
    ],
  );
}
