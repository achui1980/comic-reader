import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/app.dart';
import 'package:comic_reader/app/di/injection.dart';
import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/local/library_update_service.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';
import 'package:comic_reader/app/router/app_router.dart';
import 'package:comic_reader/core/update/app_update_service.dart';
import 'package:comic_reader/presentation/common/app_update_dialog.dart';

/// Bypass SSL certificate verification for sites with problematic certs
/// (e.g., manhuagui.com behind Cloudflare)
/// Also configures HTTP proxy when enabled in settings.
class MyHttpOverrides extends HttpOverrides {
  bool proxyEnabled;
  String proxyAddress;

  MyHttpOverrides({this.proxyEnabled = false, this.proxyAddress = '127.0.0.1:2222'});

  /// Hosts that must never be routed through the configured HTTP proxy, even
  /// when the proxy is enabled.
  ///
  /// Some sites refuse traffic from datacentre / VPN exit IPs. 51manga's origin
  /// (openresty) IP-bans such exits and then answers every CDN cache MISS with a
  /// 159-byte `403 Forbidden` page while cached URLs still return 200 — so the
  /// failure looks intermittent rather than like a block. These sites are
  /// reachable on a normal residential connection, so they go out direct.
  ///
  /// Matched by host suffix, so `51manga.com` also covers `www.` and `m.`.
  static const Set<String> proxyBypassHosts = {
    '51manga.com',
    'baipiaoguai.org', // 51manga's image CDN — keep on the same exit IP as the pages
  };

  /// Whether [host] is covered by [proxyBypassHosts].
  ///
  /// Suffix match is anchored on a dot so `not51manga.com` does not match
  /// `51manga.com`.
  static bool shouldBypassProxy(String host) {
    final normalized = host.toLowerCase();
    return proxyBypassHosts.any(
      (domain) => normalized == domain || normalized.endsWith('.$domain'),
    );
  }

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
      // Sites that reject proxy/VPN exit IPs must use the device's own route.
      if (shouldBypassProxy(uri.host)) {
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
  // On macOS, a stored custom download directory was originally granted
  // via FilePicker's NSOpenPanel, which under App Sandbox only remains
  // writable for the process lifetime. Resolve the persisted
  // security-scoped bookmark (see DownloadDirectoryBookmark.swift) to
  // restore write access after a full app relaunch, preferring it over the
  // raw stored path. Only attempted when a custom directory is actually
  // set — if the user has reset to the platform default (downloadDirectory
  // == null), a stale bookmark from a previously-chosen directory must
  // never resurrect that old path.
  if (Platform.isMacOS && appSettings.downloadDirectory != null) {
    final resolvedBookmarkPath = await resolveDownloadDirectoryBookmark();
    ChapterCacheService.customDownloadDirectory =
        resolvedBookmarkPath ?? appSettings.downloadDirectory;
  } else {
    ChapterCacheService.customDownloadDirectory = appSettings.downloadDirectory;
  }

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

  // Fire-and-forget: silently check for a newer app release on GitHub.
  // Only shows a dialog if an update is actually found; all errors are
  // swallowed so this never affects app startup.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final info = await GetIt.instance<AppUpdateService>().checkForUpdate();
      final ctx = AppRouter.navigatorKey.currentContext;
      if (info != null && ctx != null && ctx.mounted) {
        showAppUpdateDialog(ctx, info, GetIt.instance<AppUpdateService>());
      }
    } catch (_) {}
  });
}
