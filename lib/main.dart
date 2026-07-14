import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/app.dart';
import 'package:comic_reader/app/di/injection.dart';
import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/local/library_update_service.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';

/// Bypass SSL certificate verification for sites with problematic certs
/// (e.g., manhuagui.com behind Cloudflare)
/// Also configures HTTP proxy when enabled in settings.
class MyHttpOverrides extends HttpOverrides {
  bool proxyEnabled;
  String proxyAddress;

  MyHttpOverrides({this.proxyEnabled = false, this.proxyAddress = '127.0.0.1:2222'});

  /// Update proxy config at runtime (called from settings).
  void updateProxy({required bool enabled, required String address}) {
    proxyEnabled = enabled;
    proxyAddress = address;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    client.findProxy = (uri) {
      if (!proxyEnabled || proxyAddress.isEmpty) {
        return 'DIRECT';
      }
      // Android emulator uses 10.0.2.2 to reach host machine's localhost.
      var addr = proxyAddress;
      if (Platform.isAndroid && (addr.startsWith('127.0.0.1') || addr.startsWith('localhost'))) {
        addr = addr.replaceFirst(RegExp(r'127\.0\.0\.1|localhost'), '10.0.2.2');
      }
      return 'PROXY $addr';
    };
    return client;
  }
}

void main() async {
  // Install HttpOverrides early (proxy config will be updated after settings load)
  final httpOverrides = MyHttpOverrides();
  HttpOverrides.global = httpOverrides;
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

  // Register the HttpOverrides instance so settings can update it later
  GetIt.instance.registerSingleton<MyHttpOverrides>(httpOverrides);

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

  // Load settings and apply
  final settingsStore = GetIt.instance<SettingsStore>();
  final appSettings = await settingsStore.load();
  registry.setDisabledSources(appSettings.disabledSources);
  registry.setAdultUnlocked(appSettings.adultUnlocked);

  // Apply proxy settings from persisted config
  if (!kIsWeb) {
    httpOverrides.updateProxy(
      enabled: appSettings.proxyEnabled,
      address: appSettings.proxyAddress,
    );
  }

  // Fire-and-forget: check the whole library for new chapters on startup.
  // Runs in the background without blocking app launch.
  GetIt.instance<LibraryUpdateService>().runUpdate();

  runApp(const ComicReaderApp());
}
