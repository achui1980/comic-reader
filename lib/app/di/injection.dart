import 'package:get_it/get_it.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/remote/source_interceptor.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/copy_manga.dart';
import 'package:comic_reader/data/repositories/manga_repository_impl.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';

final getIt = GetIt.instance;

/// Configure all dependency injection bindings.
void configureDependencies() {
  // HTTP Client
  final httpClient = HttpClient();
  httpClient.addInterceptor(SourceInterceptor());
  getIt.registerSingleton<HttpClient>(httpClient);

  // Source Registry
  final registry = SourceRegistry();
  registry.register(CopyManga());
  getIt.registerSingleton<SourceRegistry>(registry);

  // Repository
  getIt.registerSingleton<MangaRepository>(
    MangaRepositoryImpl(
      httpClient: getIt<HttpClient>(),
      sourceRegistry: getIt<SourceRegistry>(),
    ),
  );
}
