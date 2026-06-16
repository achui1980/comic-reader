import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/remote/source_interceptor.dart';
import 'package:comic_reader/data/remote/cors_proxy_interceptor.dart';
import 'package:comic_reader/data/remote/cloudflare_interceptor.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/copy_manga.dart';
import 'package:comic_reader/data/sources/manhuagui_mobile.dart';
import 'package:comic_reader/data/sources/jm_comic.dart';
import 'package:comic_reader/data/sources/nhentai.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';
import 'package:comic_reader/data/sources/wnacg.dart';
import 'package:comic_reader/data/sources/ehentai.dart';
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
  final httpClient = HttpClient();
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
