import 'package:flutter/material.dart';
import 'package:comic_reader/app/router/app_router.dart';
import 'package:comic_reader/app/theme/app_theme.dart';

class ComicReaderApp extends StatelessWidget {
  const ComicReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Comic Reader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
    );
  }
}
