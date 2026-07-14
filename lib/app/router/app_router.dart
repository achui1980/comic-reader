import 'package:go_router/go_router.dart';
import 'package:comic_reader/presentation/home/home_screen.dart';
import 'package:comic_reader/presentation/discovery/discovery_screen.dart';
import 'package:comic_reader/presentation/updates/update_screen.dart';
import 'package:comic_reader/presentation/history/history_screen.dart';
import 'package:comic_reader/presentation/search/search_screen.dart';
import 'package:comic_reader/presentation/detail/detail_screen.dart';
import 'package:comic_reader/presentation/reader/reader_screen.dart';
import 'package:comic_reader/presentation/settings/settings_screen.dart';
import 'package:comic_reader/presentation/webview/webview_screen.dart';
import 'package:comic_reader/presentation/shell/app_shell.dart';
import 'routes.dart';

/// App router configuration using GoRouter with responsive shell layout.
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      // Shell route for main navigation tabs
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.discovery,
                builder: (context, state) => const DiscoveryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.updates,
                builder: (context, state) => const UpdatesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Non-shell routes (full-screen)
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.history,
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.detail,
        builder: (context, state) {
          return DetailScreen(
            sourceId: state.pathParameters['sourceId'] ?? '',
            mangaId: state.pathParameters['mangaId'] ?? '',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.reader,
        builder: (context, state) {
          final sourceId = state.pathParameters['sourceId'] ?? '';
          final mangaId = state.pathParameters['mangaId'] ?? '';
          final chapterId = state.pathParameters['chapterId'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          return ReaderScreen(
            sourceId: sourceId,
            mangaId: mangaId,
            chapterId: chapterId,
            chapterList: extra?['chapterList'] as List<dynamic>? ?? const [],
            initialPage: extra?['initialPage'] as int? ?? 0,
            mangaTitle: extra?['mangaTitle'] as String? ?? '',
            coverUrl: extra?['coverUrl'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.webview,
        builder: (context, state) {
          final sourceId = state.pathParameters['sourceId'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          return WebViewScreen(
            sourceId: sourceId,
            initialUrl: extra?['url'] as String?,
          );
        },
      ),
    ],
  );
}
