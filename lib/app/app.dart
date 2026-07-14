import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/router/app_router.dart';
import 'package:comic_reader/app/theme/app_theme.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/settings/bloc/settings_cubit.dart';
import 'package:comic_reader/presentation/settings/bloc/settings_state.dart';

class ComicReaderApp extends StatelessWidget {
  const ComicReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SettingsCubit(
        settingsStore: GetIt.instance<SettingsStore>(),
        localStorage: GetIt.instance<LocalStorage>(),
        sourceRegistry: GetIt.instance<SourceRegistry>(),
        favoritesStore: GetIt.instance<FavoritesStore>(),
      )..init(),
      child: BlocBuilder<SettingsCubit, SettingsState>(
        buildWhen: (prev, curr) => prev.themeMode != curr.themeMode,
        builder: (context, state) {
          ThemeMode themeMode;
          ThemeData? darkTheme;

          switch (state.themeMode) {
            case AppThemeMode.light:
              themeMode = ThemeMode.light;
              darkTheme = AppTheme.dark();
              break;
            case AppThemeMode.dark:
              themeMode = ThemeMode.dark;
              darkTheme = AppTheme.dark();
              break;
            case AppThemeMode.amoled:
              themeMode = ThemeMode.dark;
              darkTheme = AppTheme.amoled();
              break;
            case AppThemeMode.system:
              themeMode = ThemeMode.system;
              darkTheme = AppTheme.dark();
              break;
          }

          return MaterialApp.router(
            title: 'Comic Reader',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: darkTheme,
            themeMode: themeMode,
            routerConfig: AppRouter.router,
          );
        },
      ),
    );
  }
}
