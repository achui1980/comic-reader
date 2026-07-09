# AGENTS.md

## Start Here (read this first, then TRUST it)
- **This file is the authoritative architecture snapshot. On a fresh session, DO NOT spin up an explore/search agent to "rediscover" how the codebase is laid out — the map below (Architecture + Adding A New Data Source + the file index) is already the answer.** Only read specific source files when you are about to edit them or need an exact selector/signature. Reserve exploration for genuinely new/undocumented areas.
- `README.md` is still the stock Flutter template. Treat `pubspec.yaml`, `lib/main.dart`, and `lib/app/di/injection.dart` as the real source of truth.
- The list of "which data sources exist / which services are wired" is intentionally NOT duplicated here (it rots). It lives in exactly two always-current places: `lib/data/sources/*.dart` (one file per source) and the `registry.register(...)` block in `lib/app/di/injection.dart`. `rtk ls lib/data/sources` + a quick read of the register block tells you the full active set in seconds — no explore agent needed.
- A `graphify` knowledge graph exists at `graphify-out/`. `graph.html` is for a **human** to browse interactively; `GRAPH_REPORT.md` is a community index that is not useful for agent cold-start (prefer the architecture map in this file instead). After changing code, run `graphify update .` to refresh it (AST-only, no API cost).

## Commands
- Install/update Dart deps: `flutter pub get`
- Full static check: `flutter analyze`
- Focused static check: `flutter analyze lib/path/to/file.dart`
- Safe focused unit test: `flutter test test/data/sources/copy_manga_test.dart`
- Web dev helper: `./tools/run_web.sh` starts the local CORS proxy and then runs `flutter run -d chrome`.
- Proxy-only web debugging: `node tools/cors_proxy.js` from the repo root, or `node cors_proxy.js` inside `tools/`.
- CORS proxy tests: `node --test tools/cors_proxy.test.js`. Proxy deps live in `tools/package.json` (`npm install` inside `tools/`), separate from the Flutter project.

## Test And Verification Quirks
- Do not treat `flutter test` over the whole repo as a cheap smoke check. `test/verify_jmc_api.dart`, `test/verify_pica_images.dart`, `test/verify_ehentai_chapter.dart`, and `test/check_jmc_chapters.dart` are manual live-network scripts meant to be run explicitly with `dart run ...`.
- `test/widget_test.dart` currently fails as written because `ComicReaderApp` expects `GetIt` registrations from `configureDependencies()` before the widget is pumped.
- `test/verify_pica_images.dart` expects an upstream proxy, and its file header documents the intended form: `HTTPS_PROXY="http://127.0.0.1:2222" dart run test/verify_pica_images.dart`.

## Architecture
- App startup is in `lib/main.dart`: it installs permissive `HttpOverrides`, calls `configureDependencies()`, initializes `DownloadManager` and `AuthStore`, restores per-source auth into every registered source, applies persisted disabled sources and proxy settings, then calls `runApp(const ComicReaderApp())`.
- Dependency injection is manual in `lib/app/di/injection.dart`. `injectable`, `build_runner`, and `injectable_generator` are present in `pubspec.yaml`, but there are no generated DI files in the repo; when adding services or sources, register them manually there.
- The source-plugin boundary is `lib/data/sources/manga_source.dart`. Concrete sources live in `lib/data/sources/*.dart`, and the active set is assembled in `SourceRegistry` during `configureDependencies()`.
- `lib/data/repositories/manga_repository_impl.dart` is the core fetch pipeline: it merges stored auth headers into requests, routes all network access through `HttpClient`, handles JMComic domain fallback, expands paginated chapter fetches, and resolves E-Hentai image-page indirection.
- `HttpClient.execute()` (`lib/data/remote/http_client.dart`) is the single exit for every request. On native it can route a request through the WebView-fetch channel instead of Dio when `extra['useWebViewFetch'] == true` and `extra['cloudflareUrl']` is set (see Cloudflare section).
- Routing lives in `lib/app/router/app_router.dart` and `lib/app/router/routes.dart`. The shell tabs are home, discovery, and settings; search/detail/reader/webview are full-screen routes outside the shell. `routes.dart` helpers (`detailPath`/`readerPath`/`webviewPath`) `Uri.encodeComponent` each path param, so a `mangaId`/`chapterId` may contain a slash only if the source's own id already avoids literal slashes — do not build these routes by hand.

### Key File Index (what-is-where — use this instead of searching)
| Concern | File(s) |
| --- | --- |
| App bootstrap / startup order | `lib/main.dart` |
| Manual DI + source registration | `lib/app/di/injection.dart` |
| Source plugin base class (the contract) | `lib/data/sources/manga_source.dart` |
| Concrete sources (one per site) | `lib/data/sources/*.dart` |
| Source registry (active set) | `lib/data/sources/source_registry.dart` |
| Core fetch pipeline (prepare→HTTP→parse) | `lib/data/repositories/manga_repository_impl.dart` |
| Single network exit (Dio + WebView-fetch) | `lib/data/remote/http_client.dart` |
| Cloudflare WebView fetcher (native) | `lib/data/remote/webview_fetcher_native.dart` (+ `_stub`/conditional `webview_fetcher.dart`) |
| Request config model | `lib/core/models/fetch_config.dart` |
| Domain entities | `lib/domain/entities/` (`manga.dart`, `chapter.dart`, `plugin_info.dart`; re-exported via `entities.dart`) |
| Routing | `lib/app/router/app_router.dart`, `lib/app/router/routes.dart` |
| Local persistence | `lib/data/local/local_storage_io.dart` (native), `local_storage_web.dart` (web) |
| Web CORS proxy + TLS impersonation | `tools/cors_proxy.js`, `tools/run_web.sh` |
| State management | `flutter_bloc` Cubits under `lib/presentation/**/bloc/` |

Mental model in one line: **a source is a pure function** — `prepare*Fetch()` turns (page/keyword/id) into a `FetchConfig`, `parse*()` turns the raw response (HTML `String` by default) into domain entities. Everything else (network, cookie/auth merge, Cloudflare, pagination expansion) is the framework's job in `manga_repository_impl.dart` + `http_client.dart`; sources never touch the network.

## Adding A New Data Source

This is the most common task in this repo. Steps:

1. Create `lib/data/sources/your_source.dart` extending `MangaSource`.
2. Import and register it in `lib/app/di/injection.dart` via `registry.register(YourSource())`.
3. Run `flutter analyze lib/data/sources/your_source.dart` to verify.

**Design pattern — Prepare/Parse separation:**
- `prepare*Fetch()` builds a `FetchConfig` (URL, headers, params). It does NO network I/O.
- `parse*()` receives the raw response and returns domain entities.
- The framework calls HTTP between them — sources never touch `HttpClient` directly.

**Key method pairs to implement:**
- `prepareDiscoveryFetch` / `parseDiscovery` → `List<MangaSummary>`
- `prepareSearchFetch` / `parseSearch` → `List<MangaSummary>`
- `prepareMangaInfoFetch` / `parseMangaInfo` → `MangaDetail` (with `chapters` list)
- `prepareChapterListFetch` / `parseChapterList` → return `null` from prepare if chapters are embedded in the info page
- `prepareChapterFetch` / `parseChapter` → `ChapterResult` (images + pagination)

**Common pitfalls when scraping HTML sources:**
- Many Chinese manga sites use `onclick="send_app_msg(...)"` or similar JS callbacks instead of `<a href>` links. Always inspect the actual HTML with curl before assuming standard anchor tags.
- Image elements often use `data-src` (lazy loading) with `src` set to a placeholder GIF. Always check `data-src` first.
- Cover images may use a different CDN subdomain than chapter images.
- Chapter IDs should be stable identifiers derivable from the URL structure (e.g., `section_chapter` format).
- If a source returns paginated chapters, implement `canLoadMore`/`nextPage` in `ChapterResult`.

**Data model quick reference:**
- `MangaSummary`: id, sourceId, title, coverUrl, author, latestChapter?, updateTime?, headers?
- `MangaDetail`: adds description?, tags, status (ongoing/completed/unknown), chapters
- `ChapterItem`: id, mangaId, title, href?
- `ChapterImage`: url, scrambleType (default none), headers?
- `ChapterResult`: chapter (with images), canLoadMore, nextPage?, nextExtra?
- `FetchConfig`: url, method?, headers?, queryParameters?, body?, timeout?, extra?, responseType?
- `FilterOption` / `FilterChoice`: for discovery/search filter dropdowns

## Platform And Storage Quirks
- Native builds trust all SSL certs in `MyHttpOverrides`; when proxying on Android emulators, `127.0.0.1`/`localhost` is rewritten to `10.0.2.2`.
- Web requests are expected to flow through the local CORS proxy at `http://localhost:9090/`. `CorsProxyInterceptor`, `ImageProxy`, the web settings UI, and the Pica token registration flow all depend on that server being up.
- `tools/cors_proxy.js` also supports dynamic upstream proxy changes through `GET/POST /__proxy_config`, and `tools/run_web.sh` starts it with `HTTPS_PROXY="http://127.0.0.1:2222"` by default.
- Cloudflare handling is platform-specific: native uses `flutter_inappwebview` to capture cookies automatically, while web falls back to the manual cookie-paste flow in `lib/presentation/webview/webview_web.dart`.
- Persistent app state is JSON in the app documents directory on native (`lib/data/local/local_storage_io.dart`) and `window.localStorage` keys prefixed with `comic_reader_` on web (`lib/data/local/local_storage_web.dart`).
- Chapter downloads and local image cache are native-only. `ChapterCacheService` is effectively a no-op on web.

## Cloudflare / TLS Fingerprint Sources (manga18.club)
Some sources sit behind Cloudflare's TLS/JA3 fingerprint check, which rejects Dart/Dio (BoringSSL) and Node/OpenSSL requests with 403 even with valid cookies and a browser UA. `cf_clearance` is bound to TLS fingerprint + UA + exit IP together, so a cookie captured in a real browser is useless from a mismatched TLS stack. Both platforms solve this without changing source code:
- **Native**: a source sets `usesWebViewFetch => true` (see `manga_source.dart` getter, default false) and `cloudflareUrl`. `_mergeHeaders` in the repository injects `useWebViewFetch`/`cloudflareUrl` into `extra`; `HttpClient` then sends the HTTP request from a persistent headless `flutter_inappwebview` instance (`lib/data/remote/webview_fetcher_native.dart`) whose page-context `fetch()` reuses the real WebKit TLS fingerprint. `webview_fetcher_stub.dart` is the web/no-op fallback (conditional import in `webview_fetcher.dart`). The in-page fetch strips forbidden headers (User-Agent/Referer/Cookie/etc.) — the browser context supplies them, and `credentials:'include'` carries cookies.
- **Web**: `tools/cors_proxy.js` opt-in routes exact hosts in `CURL_IMPERSONATE_HOSTS` through curl-impersonate (real Chrome fingerprint) instead of Node's `https.request`. `run_web.sh` defaults this to `manga18.club`. Requires `brew install lexiforest/tap/curl-impersonate`; wrapper defaults to `curl_chrome136` (override via `CURL_IMPERSONATE_BIN`). Note: not all wrappers pass — `curl_chrome124`/`131` get 403 on manga18, `116`/`136`/`142`/`146` get 200.
- Only main sites need this; image CDNs (e.g. `cdn.manga18.club`) usually serve 200 directly. Keep such sub-domains off the impersonate list / WebView-fetch path so images take the fast direct route.
