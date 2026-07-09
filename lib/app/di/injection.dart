import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/remote/source_interceptor.dart';
import 'package:comic_reader/data/remote/cors_proxy_interceptor.dart';
import 'package:comic_reader/data/remote/cloudflare_interceptor.dart';
import 'package:comic_reader/data/remote/webview_fetcher.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/copy_manga.dart';
import 'package:comic_reader/data/sources/manhuagui_mobile.dart';
import 'package:comic_reader/data/sources/jm_comic.dart';
import 'package:comic_reader/data/sources/nhentai.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';
import 'package:comic_reader/data/sources/wnacg.dart';
import 'package:comic_reader/data/sources/ehentai.dart';
import 'package:comic_reader/data/sources/baozi_manga.dart';
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/data/sources/goda_manga.dart';
import 'package:comic_reader/data/sources/ikan_manhua.dart';
import 'package:comic_reader/data/sources/komiic.dart';
import 'package:comic_reader/data/sources/hitomi.dart';
import 'package:comic_reader/data/sources/zaimanhua.dart';
import 'package:comic_reader/data/sources/hot_manga.dart';
import 'package:comic_reader/data/sources/jcomic.dart';
import 'package:comic_reader/data/sources/h_comic.dart';
import 'package:comic_reader/data/sources/manhuaren.dart';
import 'package:comic_reader/data/sources/jestful.dart';
import 'package:comic_reader/data/sources/mangabz.dart';
import 'package:comic_reader/data/sources/dongmanmanhua.dart';
import 'package:comic_reader/data/sources/webtoons.dart';
import 'package:comic_reader/data/sources/manga18_club.dart';
import 'package:comic_reader/data/sources/mangadex.dart';
import 'package:comic_reader/data/sources/comick.dart';
import 'package:comic_reader/data/repositories/manga_repository_impl.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/data/local/backup_service.dart';
import 'package:comic_reader/data/local/download_manager.dart';

final getIt = GetIt.instance;

/// Configure all dependency injection bindings.
void configureDependencies() {
  // Local Storage
  getIt.registerLazySingleton<LocalStorage>(() => LocalStorage());
  getIt.registerLazySingleton<FavoritesStore>(
    () => FavoritesStore(storage: getIt<LocalStorage>()),
  );
  getIt.registerLazySingleton<ReadingHistoryStore>(
    () => ReadingHistoryStore(storage: getIt<LocalStorage>()),
  );
  getIt.registerLazySingleton<SettingsStore>(
    () => SettingsStore(storage: getIt<LocalStorage>()),
  );
  getIt.registerLazySingleton<ChapterCacheService>(
    () => ChapterCacheService(),
  );
  getIt.registerLazySingleton<AuthStore>(
    () => AuthStore(storage: getIt<LocalStorage>()),
  );
  getIt.registerLazySingleton<UpdateStore>(
    () => UpdateStore(storage: getIt<LocalStorage>()),
  );
  getIt.registerLazySingleton<BackupService>(
    () => BackupService(storage: getIt<LocalStorage>()),
  );

  // HTTP Client
  // WebView-based fetcher for Cloudflare JA3-bound sources (native only;
  // no-op stub on web). Registered so it can be warmed up / disposed elsewhere.
  final webViewFetcher = createWebViewFetcher();
  getIt.registerSingleton<WebViewFetcher>(webViewFetcher);

  final httpClient = HttpClient(webViewFetcher: webViewFetcher);
  httpClient.addInterceptor(SourceInterceptor());
  httpClient.addInterceptor(CloudflareDetectorInterceptor());
  if (kIsWeb) {
    httpClient.addInterceptor(CorsProxyInterceptor());
  }
  getIt.registerSingleton<HttpClient>(httpClient);

  // Source Registry
  final registry = SourceRegistry();
  registry.register(ManhuaGuiMobile());
  registry.register(CopyManga());
  registry.register(JmComic());
  registry.register(NHentai());
  registry.register(PicaComic());
  registry.register(Wnacg());
  registry.register(EHentai());
  registry.register(BaoziManga());
  registry.register(Wu55Comic());
  registry.register(GodaManga());
  registry.register(IkanManhua());
  registry.register(Komiic());
  registry.register(Hitomi());
  registry.register(Zaimanhua());
  registry.register(HotManga());
  registry.register(JComic());
  registry.register(HComic());
  registry.register(ManhuarenSource());
  registry.register(Jestful());
  registry.register(Mangabz());
  registry.register(Dongmanmanhua());
  registry.register(WebtoonsSource());
  registry.register(Manga18Club());
  registry.register(MangaDexSource());
  registry.register(ComicKSource());
  getIt.registerSingleton<SourceRegistry>(registry);

  // Repository
  getIt.registerSingleton<MangaRepository>(
    MangaRepositoryImpl(
      httpClient: getIt<HttpClient>(),
      sourceRegistry: getIt<SourceRegistry>(),
    ),
  );

  // Download Manager
  getIt.registerLazySingleton<DownloadManager>(
    () => DownloadManager(
      repository: getIt<MangaRepository>(),
      cacheService: getIt<ChapterCacheService>(),
      storage: getIt<LocalStorage>(),
    ),
  );
}
