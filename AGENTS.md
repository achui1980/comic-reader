# AGENTS.md

## Start Here
- `README.md` is still the stock Flutter template. Treat `pubspec.yaml`, `lib/main.dart`, and `lib/app/di/injection.dart` as the real source of truth.
- OpenCode has `graphify` wired in via `.opencode/opencode.json`, and `graphify-out/graph.json` already exists. Prefer `graphify query "..."` for architecture questions before broad manual searching.

## Commands
- Install/update Dart deps: `flutter pub get`
- Full static check: `flutter analyze`
- Focused static check: `flutter analyze lib/path/to/file.dart`
- Safe focused unit test: `flutter test test/data/sources/copy_manga_test.dart`
- Web dev helper: `./tools/run_web.sh` starts the local CORS proxy and then runs `flutter run -d chrome`.
- Proxy-only web debugging: `node tools/cors_proxy.js` from the repo root, or `node cors_proxy.js` inside `tools/`.

## Test And Verification Quirks
- Do not treat `flutter test` over the whole repo as a cheap smoke check. `test/verify_jmc_api.dart`, `test/verify_pica_images.dart`, `test/verify_ehentai_chapter.dart`, and `test/check_jmc_chapters.dart` are manual live-network scripts meant to be run explicitly with `dart run ...`.
- `test/widget_test.dart` currently fails as written because `ComicReaderApp` expects `GetIt` registrations from `configureDependencies()` before the widget is pumped.
- `test/verify_pica_images.dart` expects an upstream proxy, and its file header documents the intended form: `HTTPS_PROXY="http://127.0.0.1:2222" dart run test/verify_pica_images.dart`.

## Architecture
- App startup is in `lib/main.dart`: it installs permissive `HttpOverrides`, calls `configureDependencies()`, initializes `DownloadManager` and `AuthStore`, restores per-source auth into every registered source, applies persisted disabled sources and proxy settings, then calls `runApp(const ComicReaderApp())`.
- Dependency injection is manual in `lib/app/di/injection.dart`. `injectable`, `build_runner`, and `injectable_generator` are present in `pubspec.yaml`, but there are no generated DI files in the repo; when adding services or sources, register them manually there.
- The source-plugin boundary is `lib/data/sources/manga_source.dart`. Concrete sources live in `lib/data/sources/*.dart`, and the active set is assembled in `SourceRegistry` during `configureDependencies()`.
- `lib/data/repositories/manga_repository_impl.dart` is the core fetch pipeline: it merges stored auth headers into requests, routes all network access through `HttpClient`, handles JMComic domain fallback, expands paginated chapter fetches, and resolves E-Hentai image-page indirection.
- Routing lives in `lib/app/router/app_router.dart` and `lib/app/router/routes.dart`. The shell tabs are home, discovery, and settings; search/detail/reader/webview are full-screen routes outside the shell.

## Platform And Storage Quirks
- Native builds trust all SSL certs in `MyHttpOverrides`; when proxying on Android emulators, `127.0.0.1`/`localhost` is rewritten to `10.0.2.2`.
- Web requests are expected to flow through the local CORS proxy at `http://localhost:9090/`. `CorsProxyInterceptor`, `ImageProxy`, the web settings UI, and the Pica token registration flow all depend on that server being up.
- `tools/cors_proxy.js` also supports dynamic upstream proxy changes through `GET/POST /__proxy_config`, and `tools/run_web.sh` starts it with `HTTPS_PROXY="http://127.0.0.1:2222"` by default.
- Cloudflare handling is platform-specific: native uses `flutter_inappwebview` to capture cookies automatically, while web falls back to the manual cookie-paste flow in `lib/presentation/webview/webview_web.dart`.
- Persistent app state is JSON in the app documents directory on native (`lib/data/local/local_storage_io.dart`) and `window.localStorage` keys prefixed with `comic_reader_` on web (`lib/data/local/local_storage_web.dart`).
- Chapter downloads and local image cache are native-only. `ChapterCacheService` is effectively a no-op on web.
