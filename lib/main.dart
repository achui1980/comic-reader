import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/app.dart';
import 'package:comic_reader/app/di/injection.dart';
import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow all orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Configure dependency injection
  configureDependencies();

  // Initialize download manager
  await GetIt.instance<DownloadManager>().init();

  // Initialize auth store and restore cookies to sources
  final authStore = GetIt.instance<AuthStore>();
  await authStore.init();
  final registry = GetIt.instance<SourceRegistry>();
  for (final source in registry.all) {
    final extra = authStore.getExtra(source.id);
    if (extra != null && extra.isNotEmpty) {
      source.syncExtraData(extra);
    }
  }

  // Auto-login PicaComic if no token stored
  final picaSource = registry.get(PicaComic.sourceId);
  if (picaSource != null && !picaSource.isAuthenticated) {
    // Fire and forget - don't block app startup
    picaAutoLogin();
  }

  // Load settings and apply disabled sources to registry
  final settingsStore = GetIt.instance<SettingsStore>();
  final appSettings = await settingsStore.load();
  registry.setDisabledSources(appSettings.disabledSources);

  runApp(const ComicReaderApp());
}
