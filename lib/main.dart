import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/app.dart';
import 'package:comic_reader/app/di/injection.dart';
import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';

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

  runApp(const ComicReaderApp());
}
