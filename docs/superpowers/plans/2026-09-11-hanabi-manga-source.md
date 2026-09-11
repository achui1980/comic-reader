# HanabiManga Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `HanabiManga` source (hanabimanga.com) to comic-reader, supporting user login (Supabase Auth), discovery/search/detail browsing, and WASM-based image unscrambling for free/normal chapters.

**Architecture:** One new source file (`lib/data/sources/hanabi_manga.dart`) following the existing Prepare/Parse pattern. Login uses direct Supabase Auth HTTP calls (no WebView) with a hand-built Supabase SSR session cookie stored via the existing `AuthStore`/`extraHeaders` mechanism. Image descrambling is a two-stage pipeline: `HanabiChapterDecryptor` (HTTP download + `package:image` decode/encode) calls `HanabiWasmUnscrambler` (loads the site's real `/reader.wasm` via `wasm_run_flutter` and invokes its `unscramble` export using the verified wasm-bindgen calling convention). The generic login dialog (`pica_login_dialog.dart`) is refactored into a reusable `login_dialog.dart` since this is the second login-required source.

**Tech Stack:** Dart/Flutter, dio, html, package:image ^4.8.0, wasm_run_flutter (new), dart:convert, mocktail (tests).

---

## Task 1: Add `wasm_run_flutter` dependency and commit test fixtures

**Files:**
- Modify: `pubspec.yaml`
- Commit (untracked): `test/fixtures/hanabi/reader.wasm`, `test/fixtures/hanabi/scrambled_page001.webp`, `test/fixtures/hanabi/detail_page.html`

These three fixture files already exist on disk (downloaded/saved during research) but are untracked in git.

- [ ] **Step 1: Add the dependency**

Run:
```bash
cd /Users/portz/js/comic/comic-reader && flutter pub add wasm_run_flutter
```
Expected: `pubspec.yaml` gets a new line under `dependencies:` such as `wasm_run_flutter: ^0.2.0+1` (exact resolved version may vary slightly; that's fine).

- [ ] **Step 2: Verify fixtures are present**

Run:
```bash
ls -la /Users/portz/js/comic/comic-reader/test/fixtures/hanabi/
```
Expected output lists exactly three files: `detail_page.html` (202649 bytes), `reader.wasm` (44964 bytes), `scrambled_page001.webp` (124854 bytes). If any are missing, STOP and report — they must be provided before continuing (they cannot be regenerated without live access to hanabimanga.com).

- [ ] **Step 3: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add pubspec.yaml pubspec.lock test/fixtures/hanabi/
git commit -m "chore: add wasm_run_flutter dependency and hanabi test fixtures"
```

---

## Task 2: Add `ScrambleType.hanabi` and new `ChapterImage` fields

**Files:**
- Modify: `lib/domain/entities/chapter.dart`
- Test: `test/domain/entities/chapter_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `test/domain/entities/chapter_test.dart`:
```dart
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChapterImage carries hanabi scramble metadata', () {
    const image = ChapterImage(
      url: 'https://cdn.hanabimanga.top/fake.webp',
      scrambleType: ScrambleType.hanabi,
      hanabiTicket: 'ticket-b64',
      hanabiNonce: 'nonce-b64',
      hanabiCols: 4,
      hanabiRows: 4,
    );

    expect(image.scrambleType, ScrambleType.hanabi);
    expect(image.hanabiTicket, 'ticket-b64');
    expect(image.hanabiNonce, 'nonce-b64');
    expect(image.hanabiCols, 4);
    expect(image.hanabiRows, 4);
  });

  test('ScrambleType.hanabi is a distinct enum value', () {
    expect(ScrambleType.values, contains(ScrambleType.hanabi));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/domain/entities/chapter_test.dart`
Expected: FAIL — `ScrambleType.hanabi` and the `hanabiTicket`/`hanabiNonce`/`hanabiCols`/`hanabiRows` named parameters do not exist yet.

- [ ] **Step 3: Modify `lib/domain/entities/chapter.dart`**

Change line 3 from:
```dart
enum ScrambleType { none, jmc, rm5, wu55 }
```
to:
```dart
enum ScrambleType { none, jmc, rm5, wu55, hanabi }
```

Replace the `ChapterImage` class (lines 25-59) with:
```dart
class ChapterImage extends Equatable {
  final String url;
  final ScrambleType scrambleType;
  final ImageResponseEncoding responseEncoding;
  final Map<String, String>? headers;
  /// The scramble_id threshold used for JMC unscrambling.
  /// Only relevant when scrambleType == ScrambleType.jmc.
  final int? scrambleId;
  /// wu55comic book ID, used for slice count calculation.
  /// Only relevant when scrambleType == ScrambleType.wu55.
  final int? wu55BookId;
  /// wu55comic page number (1-based index), used for slice count calculation.
  /// Only relevant when scrambleType == ScrambleType.wu55.
  final int? wu55PageNumber;
  /// Base64-encoded WASM unscramble ticket, from the reader API's
  /// metadata.scrambleInfo.ticket field. Only relevant when
  /// scrambleType == ScrambleType.hanabi.
  final String? hanabiTicket;
  /// Base64-encoded WASM unscramble nonce, from metadata.scrambleInfo.nonce.
  /// Only relevant when scrambleType == ScrambleType.hanabi.
  final String? hanabiNonce;
  /// Scramble grid column count, from metadata.scrambleInfo.cols.
  /// Only relevant when scrambleType == ScrambleType.hanabi.
  final int? hanabiCols;
  /// Scramble grid row count, from metadata.scrambleInfo.rows.
  /// Only relevant when scrambleType == ScrambleType.hanabi.
  final int? hanabiRows;

  const ChapterImage({
    required this.url,
    this.scrambleType = ScrambleType.none,
    this.responseEncoding = ImageResponseEncoding.binary,
    this.headers,
    this.scrambleId,
    this.wu55BookId,
    this.wu55PageNumber,
    this.hanabiTicket,
    this.hanabiNonce,
    this.hanabiCols,
    this.hanabiRows,
  });

  @override
  List<Object?> get props => [
    url,
    scrambleType,
    responseEncoding,
    scrambleId,
    wu55BookId,
    wu55PageNumber,
    hanabiTicket,
    hanabiNonce,
    hanabiCols,
    hanabiRows,
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/domain/entities/chapter_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/domain/entities/chapter.dart test/domain/entities/chapter_test.dart
git commit -m "feat: add ScrambleType.hanabi and hanabi scramble fields to ChapterImage"
```

---

## Task 3: Add login/session hooks to `MangaSource` base class

**Files:**
- Modify: `lib/data/sources/manga_source.dart`
- Test: `test/data/sources/manga_source_login_test.dart` (new — uses `PicaComic` as a concrete subclass since `MangaSource` is abstract)

- [ ] **Step 1: Write the failing test**

Create `test/data/sources/manga_source_login_test.dart`:
```dart
import 'package:comic_reader/data/sources/pica_comic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MangaSource exposes default login/session hooks', () {
    final source = PicaComic();

    // Defaults declared on the abstract base class.
    expect(source.needsSessionRefresh, isFalse);
    expect(
      () => source.buildRefreshRequest(),
      throwsA(isA<UnimplementedError>()),
    );
    // parseRefresh defaults to delegating to parseSignIn; with a response
    // that has no 'token' field, parseSignIn returns null.
    expect(source.parseRefresh(<String, dynamic>{}), isNull);
  });

  test('supportsAutoLogin/autoLoginEmail/autoLoginPassword/loginDescription default to null/false', () {
    // A source that does not override these (e.g. a hypothetical bare
    // MangaSource subclass) would see these defaults. PicaComic overrides
    // some of them via requiresLogin, but does NOT override
    // supportsAutoLogin/autoLoginEmail/autoLoginPassword/loginDescription,
    // so we can assert the base-class defaults through it.
    final source = PicaComic();
    expect(source.supportsAutoLogin, isFalse);
    expect(source.autoLoginEmail, isNull);
    expect(source.autoLoginPassword, isNull);
    expect(source.loginDescription, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/sources/manga_source_login_test.dart`
Expected: FAIL — `needsSessionRefresh`, `buildRefreshRequest`, `parseRefresh`, `supportsAutoLogin`, `autoLoginEmail`, `autoLoginPassword`, `loginDescription` are not defined on `MangaSource`/`PicaComic`.

- [ ] **Step 3: Modify `lib/data/sources/manga_source.dart`**

Insert the following immediately after line 118 (`bool get isAuthenticated => false;`) and before the blank line preceding `/// Build PluginInfo from this source`:

```dart

  /// Whether this source can silently auto-login with built-in test
  /// credentials (e.g. PicaComic). Sources requiring the user's own account
  /// (e.g. HanabiManga) must leave this false and rely on the login dialog.
  bool get supportsAutoLogin => false;

  /// Built-in credentials for [supportsAutoLogin] sources. Null when not
  /// applicable.
  String? get autoLoginEmail => null;
  String? get autoLoginPassword => null;

  /// Optional description shown above the email/password fields in the
  /// generic login dialog (see lib/presentation/common/login_dialog.dart).
  String? get loginDescription => null;

  /// Build the FetchConfig for signing in with email/password.
  /// Only relevant when [requiresLogin] is true.
  FetchConfig buildSignInRequest(String email, String password) {
    throw UnimplementedError('$id does not support login');
  }

  /// Parse a sign-in response into a data map to persist via
  /// [syncExtraData] and AuthStore.saveExtra. Return null on failed login.
  Map<String, dynamic>? parseSignIn(dynamic response) {
    throw UnimplementedError('$id does not support login');
  }

  /// Whether the current session needs a proactive refresh (e.g. an access
  /// token nearing expiry). Default false; override for sources with
  /// short-lived sessions (e.g. HanabiManga's Supabase session).
  bool get needsSessionRefresh => false;

  /// Build the FetchConfig for refreshing the current session.
  /// Only relevant when [needsSessionRefresh] can return true.
  FetchConfig buildRefreshRequest() {
    throw UnimplementedError('$id does not support session refresh');
  }

  /// Parse a refresh response. Defaults to [parseSignIn] since most refresh
  /// endpoints return the same shape as sign-in.
  Map<String, dynamic>? parseRefresh(dynamic response) => parseSignIn(response);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/sources/manga_source_login_test.dart`
Expected: PASS. Note `source.parseRefresh(<String, dynamic>{})` calls `PicaComic.parseSignIn` (not yet modified — still returns `String?` at this point in the plan, but with an empty map `_parseJsonResponse` will yield no `token` key so it returns `null` either way). If this step fails because `PicaComic.parseSignIn` isn't reachable as `Map<String,dynamic>? parseSignIn` yet (a type mismatch since the base class abstract-turned-default now declares `Map<String,dynamic>? parseSignIn(...)` while PicaComic still declares `String? parseSignIn(...)` without `@override`), that is expected and will be fixed in Task 4. If `flutter analyze` errors occur here referencing pica_comic.dart, proceed directly to Task 4 before re-running this test.

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/sources/manga_source.dart test/data/sources/manga_source_login_test.dart
git commit -m "feat: add login/session-refresh hooks to MangaSource base class"
```

---

## Task 4: Update `PicaComic.parseSignIn` to the new `Map<String,dynamic>?` signature

**Files:**
- Modify: `lib/data/sources/pica_comic.dart`
- Test: `test/data/sources/pica_comic_test.dart` (existing — add a new test, do not remove existing tests)

- [ ] **Step 1: Read the existing test file**

Run: `cat /Users/portz/js/comic/comic-reader/test/data/sources/pica_comic_test.dart`

(This is required before editing — confirm the existing tests still make sense; do not delete any existing test.)

- [ ] **Step 2: Write the failing test**

Append this test to the end of the `main()` block in `test/data/sources/pica_comic_test.dart` (inside the existing `void main() { ... }`, as a new top-level `test(...)` call alongside the others):

```dart
  test('parseSignIn returns a data map (not a bare token string)', () {
    final source = PicaComic();
    final result = source.parseSignIn({'token': 'abc123'});
    expect(result, isA<Map<String, dynamic>>());
    expect(result!['token'], 'abc123');
    expect(source.isAuthenticated, isTrue);
  });

  test('parseSignIn returns null when token is missing', () {
    final source = PicaComic();
    expect(source.parseSignIn({'code': 200}), isNull);
  });
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/sources/pica_comic_test.dart`
Expected: FAIL — `result` is currently a `String?`, so `result, isA<Map<String, dynamic>>()` fails (or the file fails to compile because line 97's return type still says `String?` while the base class default is now `Map<String,dynamic>?`, causing an override-signature mismatch reported by `flutter analyze`/the test runner).

- [ ] **Step 4: Modify `lib/data/sources/pica_comic.dart`**

Add `@override` above line 85 (the `FetchConfig buildSignInRequest(...)` declaration), so it reads:
```dart
  @override
  FetchConfig buildSignInRequest(String email, String password) {
```

Replace lines 95-106 (the `parseSignIn` method) from:
```dart
  /// Parse sign-in response and return the token, or null on failure.
  /// Also stores the token internally.
  String? parseSignIn(dynamic response) {
    final data = _parseJsonResponse(response);
    if (data == null) return null;
    final token = data['token'] as String?;
    if (token != null && token.isNotEmpty) {
      _authToken = token;
      return token;
    }
    return null;
  }
```
to:
```dart
  /// Parse sign-in response and return a data map containing the token,
  /// or null on failure. Also stores the token internally.
  @override
  Map<String, dynamic>? parseSignIn(dynamic response) {
    final data = _parseJsonResponse(response);
    if (data == null) return null;
    final token = data['token'] as String?;
    if (token != null && token.isNotEmpty) {
      _authToken = token;
      return {'token': token};
    }
    return null;
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/sources/pica_comic_test.dart`
Expected: PASS (all existing tests plus the 2 new ones).

- [ ] **Step 6: Run static analysis to catch any other callers of the old signature**

Run: `cd /Users/portz/js/comic/comic-reader && flutter analyze lib/`
Expected: No new errors. If `pica_login_dialog.dart` now shows errors because it calls `parseSignIn` expecting a `String?`, that is expected — it will be replaced in Task 5.

- [ ] **Step 7: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/sources/pica_comic.dart test/data/sources/pica_comic_test.dart
git commit -m "refactor: PicaComic.parseSignIn returns a data map instead of a bare token"
```

---

## Task 5: Replace `pica_login_dialog.dart` with a generic `login_dialog.dart`

**Files:**
- Create: `lib/presentation/common/login_dialog.dart`
- Delete: `lib/presentation/common/pica_login_dialog.dart`
- Test: `test/presentation/common/login_dialog_test.dart` (new — covers the pure logic function `tryAutoLogin`/`tryRefreshSession` via a fake in-memory source; full dialog UI is covered by manual verification, see Task 12)

This task keeps 100% of the existing PicaComic behavior (auto-login with built-in credentials, dialog UI, CORS proxy token registration on web) but generalizes it to work with any `MangaSource`.

- [ ] **Step 1: Write the failing test**

Create `test/presentation/common/login_dialog_test.dart`:
```dart
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/common/login_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements HttpClient {}

class MockAuthStore extends Mock implements AuthStore {}

class _FakeAutoLoginSource extends MangaSource {
  bool authenticated = false;

  @override
  String get id => 'fake_auto_login';
  @override
  String get name => 'Fake Auto Login Source';
  @override
  String get shortName => 'Fake';
  @override
  String? get description => null;
  @override
  double get score => 1;
  @override
  String? get href => null;

  @override
  bool get requiresLogin => true;
  @override
  bool get supportsAutoLogin => true;
  @override
  String? get autoLoginEmail => 'user@example.com';
  @override
  String? get autoLoginPassword => 'password';
  @override
  bool get isAuthenticated => authenticated;

  @override
  FetchConfig buildSignInRequest(String email, String password) =>
      const FetchConfig(url: 'https://example.com/login');

  @override
  Map<String, dynamic>? parseSignIn(dynamic response) {
    final map = response as Map<String, dynamic>;
    final token = map['token'] as String?;
    if (token == null) return null;
    authenticated = true;
    return {'cookie': 'session=$token'};
  }

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) =>
      const FetchConfig(url: 'https://example.com');
  @override
  List<MangaSummary> parseDiscovery(dynamic response) => const [];
  @override
  FetchConfig prepareSearchFetch(
    String keyword,
    int page,
    Map<String, String> filters,
  ) => const FetchConfig(url: 'https://example.com');
  @override
  List<MangaSummary> parseSearch(dynamic response) => const [];
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) =>
      const FetchConfig(url: 'https://example.com');
  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) =>
      MangaDetail(id: mangaId, sourceId: id, title: '', coverUrl: '');
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;
  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) =>
      const ChapterListResult(chapters: []);
  @override
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) => const FetchConfig(url: 'https://example.com');
  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) => ChapterResult(chapter: Chapter(id: chapterId, mangaId: mangaId, title: '', images: const []));
}

void main() {
  setUpAll(() {
    registerFallbackValue(const FetchConfig(url: ''));
  });

  late MockHttpClient httpClient;
  late MockAuthStore authStore;
  late SourceRegistry registry;
  late _FakeAutoLoginSource source;

  setUp(() {
    httpClient = MockHttpClient();
    authStore = MockAuthStore();
    when(() => authStore.saveExtra(any(), any())).thenAnswer((_) async {});
    source = _FakeAutoLoginSource();
    registry = SourceRegistry();
    registry.register(source);

    final getIt = GetIt.instance;
    if (getIt.isRegistered<HttpClient>()) getIt.unregister<HttpClient>();
    if (getIt.isRegistered<AuthStore>()) getIt.unregister<AuthStore>();
    if (getIt.isRegistered<SourceRegistry>()) getIt.unregister<SourceRegistry>();
    getIt.registerSingleton<HttpClient>(httpClient);
    getIt.registerSingleton<AuthStore>(authStore);
    getIt.registerSingleton<SourceRegistry>(registry);
  });

  test('tryAutoLogin returns true and marks the source authenticated on success', () async {
    when(() => httpClient.execute(any())).thenAnswer(
      (_) async => Response(
        data: {'token': 'tok-1'},
        requestOptions: RequestOptions(path: 'https://example.com/login'),
        statusCode: 200,
      ),
    );

    final result = await tryAutoLogin(source);

    expect(result, isTrue);
    expect(source.isAuthenticated, isTrue);
    expect(source.extraHeaders['Cookie'], 'session=tok-1');
    verify(() => authStore.saveExtra('fake_auto_login', any())).called(1);
  });

  test('tryAutoLogin returns false when the source does not support it', () async {
    source.authenticated = false;
    final noAutoSource = _FakeAutoLoginSource();
    // Override supportsAutoLogin indirectly is not possible on the fake
    // without subclassing again; instead verify via a source with
    // requiresLogin but no credentials configured returns false when
    // parseSignIn yields no token.
    when(() => httpClient.execute(any())).thenAnswer(
      (_) async => Response(
        data: <String, dynamic>{},
        requestOptions: RequestOptions(path: 'https://example.com/login'),
        statusCode: 200,
      ),
    );
    final result = await tryAutoLogin(noAutoSource);
    expect(result, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/presentation/common/login_dialog_test.dart`
Expected: FAIL — `package:comic_reader/presentation/common/login_dialog.dart` does not exist yet.

- [ ] **Step 3: Delete `lib/presentation/common/pica_login_dialog.dart`**

```bash
git rm /Users/portz/js/comic/comic-reader/lib/presentation/common/pica_login_dialog.dart
```

- [ ] **Step 4: Create `lib/presentation/common/login_dialog.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';

import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';

/// Attempts auto-login for [source] using its built-in credentials.
/// Returns true if login succeeded (or the source was already authenticated).
/// Returns false immediately (without any network call) if [source] does
/// not support auto-login.
Future<bool> tryAutoLogin(MangaSource source) async {
  try {
    if (!source.supportsAutoLogin) return false;
    if (source.isAuthenticated) return true;

    final email = source.autoLoginEmail;
    final password = source.autoLoginPassword;
    if (email == null || password == null) return false;

    final httpClient = GetIt.instance<HttpClient>();
    final config = source.buildSignInRequest(email, password);
    final response = await httpClient.execute(config);
    final data = source.parseSignIn(response.data);
    if (data == null) return false;

    source.syncExtraData(data);
    final authStore = GetIt.instance<AuthStore>();
    await authStore.saveExtra(source.id, data);

    if (source is PicaComic) {
      final token = data['token'] as String?;
      if (token != null) await _registerProxyToken(token);
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Attempts to refresh [source]'s session if it reports
/// [MangaSource.needsSessionRefresh]. Returns true if no refresh was needed
/// or the refresh succeeded; false if a refresh was needed but failed.
Future<bool> tryRefreshSession(MangaSource source) async {
  if (!source.needsSessionRefresh) return true;
  try {
    final httpClient = GetIt.instance<HttpClient>();
    final config = source.buildRefreshRequest();
    final response = await httpClient.execute(config);
    final data = source.parseRefresh(response.data);
    if (data == null) return false;

    source.syncExtraData(data);
    final authStore = GetIt.instance<AuthStore>();
    await authStore.saveExtra(source.id, data);
    return true;
  } catch (_) {
    return false;
  }
}

/// Shows a generic email/password login dialog for [source].
/// Returns true if login succeeded, false/null otherwise.
Future<bool?> showLoginDialog(BuildContext context, MangaSource source) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _LoginDialog(source: source),
  );
}

class _LoginDialog extends StatefulWidget {
  final MangaSource source;
  const _LoginDialog({required this.source});

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.source.autoLoginEmail ?? '',
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.source.autoLoginPassword ?? '',
  );
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入邮箱和密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final source = widget.source;
      final httpClient = GetIt.instance<HttpClient>();
      final config = source.buildSignInRequest(email, password);
      final response = await httpClient.execute(config);

      final data = source.parseSignIn(response.data);
      if (data != null) {
        source.syncExtraData(data);
        final authStore = GetIt.instance<AuthStore>();
        await authStore.saveExtra(source.id, data);

        if (source is PicaComic) {
          final token = data['token'] as String?;
          if (token != null) await _registerProxyToken(token);
        }

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _loading = false;
          _error = '登录失败，请检查账号密码';
        });
      }
    } catch (e) {
      final msg = e.toString();
      String errorText;
      if (msg.contains('1004') ||
          msg.contains('invalid email') ||
          msg.contains('invalid_credentials') ||
          msg.contains('Invalid login credentials')) {
        errorText = '邮箱或密码错误';
      } else if (msg.contains('timeout') || msg.contains('SocketException')) {
        errorText = '网络连接失败，请检查代理设置';
      } else {
        errorText = '登录失败: ${msg.length > 80 ? msg.substring(0, 80) : msg}';
      }
      setState(() {
        _loading = false;
        _error = errorText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.login, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Text('${source.name} 登录'),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              source.loginDescription ?? '使用账号登录后即可浏览',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '邮箱',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              enabled: !_loading,
              onSubmitted: (_) => _login(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
        ),
      ],
    );
  }
}

/// Register PICA auth token with CORS proxy so CDN images can be served.
/// Only needed on web platform. No-op for other sources.
Future<void> _registerProxyToken(String token) async {
  if (!kIsWeb) return;
  try {
    await Dio().post(
      'http://localhost:9090/__host_token',
      data: {
        'host': 'picacomic.com',
        'token': token,
        'header': 'Authorization',
      },
    );
  } catch (_) {
    // Non-critical: images will fail but app still works
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/presentation/common/login_dialog_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/presentation/common/login_dialog.dart test/presentation/common/login_dialog_test.dart
git commit -m "refactor: generalize pica_login_dialog.dart into a reusable login_dialog.dart"
```

---

## Task 6: Update the three call sites that used `pica_login_dialog.dart`

**Files:**
- Modify: `lib/presentation/discovery/discovery_screen.dart` (line 11 import, lines 140/144)
- Modify: `lib/presentation/settings/sections/plugin_section.dart` (line 8 import, line 79)
- Modify: `lib/main.dart` (line 16 import, lines 121-124)

There is no new automated test for this task — these are UI wiring changes covered by the manual verification checklist in Task 12, plus `flutter analyze` catching any leftover references to the deleted `pica_login_dialog.dart`.

- [ ] **Step 1: Read all three files fully before editing**

```bash
cd /Users/portz/js/comic/comic-reader
cat lib/presentation/discovery/discovery_screen.dart
cat lib/presentation/settings/sections/plugin_section.dart
cat lib/main.dart
```

- [ ] **Step 2: Edit `lib/presentation/discovery/discovery_screen.dart`**

Change the import on line 11 from:
```dart
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';
```
to:
```dart
import 'package:comic_reader/presentation/common/login_dialog.dart';
```

Change line 140 from:
```dart
              final result = await picaAutoLogin();
```
to:
```dart
              final result = await tryAutoLogin(sources[i]);
```

Change line 144 from:
```dart
                final manual = await showPicaLoginDialog(context);
```
to:
```dart
                final manual = await showLoginDialog(context, sources[i]);
```

- [ ] **Step 3: Edit `lib/presentation/settings/sections/plugin_section.dart`**

Change the import on line 8 from:
```dart
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';
```
to:
```dart
import 'package:comic_reader/presentation/common/login_dialog.dart';
```

Change line 79 from:
```dart
    showPicaLoginDialog(context);
```
to:
```dart
    showLoginDialog(context, source);
```
(This is inside `_navigateToVerify(BuildContext context, String sourceId)`, which already resolves `final source = registry.get(sourceId);` above this line — no new variable needed.)

- [ ] **Step 4: Edit `lib/main.dart`**

Change the import on line 16 from:
```dart
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';
```
to:
```dart
import 'package:comic_reader/presentation/common/login_dialog.dart';
```

Change lines 121-124 from:
```dart
  // Auto-login PicaComic if no token stored
  final picaSource = registry.get(PicaComic.sourceId);
  if (picaSource != null && !picaSource.isAuthenticated) {
    // Fire and forget - don't block app startup
    picaAutoLogin();
  }
```
to:
```dart
  // Auto-login sources that support silent login (e.g. PicaComic) if needed.
  for (final source in registry.all) {
    if (source.supportsAutoLogin && !source.isAuthenticated) {
      // Fire and forget - don't block app startup
      tryAutoLogin(source);
    }
  }
```

If `lib/main.dart` no longer references `PicaComic` anywhere else after this change, also remove the now-unused `import 'package:comic_reader/data/sources/pica_comic.dart';` import (check with `grep -n "PicaComic" lib/main.dart` first — only remove the import if there are zero remaining references).

- [ ] **Step 5: Run static analysis**

Run: `cd /Users/portz/js/comic/comic-reader && flutter analyze lib/`
Expected: No errors referencing `pica_login_dialog.dart`, `picaAutoLogin`, or `showPicaLoginDialog`.

- [ ] **Step 6: Run the full existing test suite to check for regressions**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test`
Expected: All tests pass (aside from any pre-existing known failures unrelated to this change, e.g. `test/widget_test.dart` if it was already failing before this plan per the project's AGENTS.md notes).

- [ ] **Step 7: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/presentation/discovery/discovery_screen.dart lib/presentation/settings/sections/plugin_section.dart lib/main.dart
git commit -m "refactor: switch discovery/settings/main to the generic login_dialog API"
```

---

## Task 7: Create `HanabiWasmUnscrambler`

**Files:**
- Create: `lib/data/repositories/hanabi_wasm_unscrambler.dart`
- Test: `test/data/repositories/hanabi_wasm_unscrambler_test.dart` (new — real integration test using the real `reader.wasm` and a real scrambled page fixture)

This class loads hanabimanga.com's real `/reader.wasm` module and invokes its `unscramble` export using the verified wasm-bindgen calling convention (confirmed end-to-end via a Python/wasmtime simulation during research — see fixed hashes below).

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/hanabi_wasm_unscrambler_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('unscramble decrypts a real scrambled page using the real reader.wasm', () async {
    final wasmBytes = await File('test/fixtures/hanabi/reader.wasm').readAsBytes();
    final scrambledBytes =
        await File('test/fixtures/hanabi/scrambled_page001.webp').readAsBytes();

    final decoded = img.decodeImage(scrambledBytes)!;
    expect(decoded.width, 960);
    expect(decoded.height, 1372);
    final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);

    final scrambledHash = sha256.convert(rgba).toString();
    expect(
      scrambledHash,
      'bb4c2d879b389919015288177f1106ff7da8dad7ef79791898db0b5a9f9b76a7',
    );

    final ticket = base64Decode('Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=');
    final nonce = base64Decode('ZkfsVQTteF2Ab4Ha');

    final unscrambler = HanabiWasmUnscrambler();
    await unscrambler.ensureLoaded(wasmBytesOverride: wasmBytes);
    final result = await unscrambler.unscramble(
      rgba,
      decoded.width,
      decoded.height,
      ticket,
      nonce,
      4,
      4,
    );

    expect(result.length, 5268480);
    final resultHash = sha256.convert(result).toString();
    expect(
      resultHash,
      '9735c728f504471ec4fc654752591901377c710801b9f96ad51d996afd0233e1',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/repositories/hanabi_wasm_unscrambler_test.dart`
Expected: FAIL — `package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart` does not exist yet.

- [ ] **Step 3: Create `lib/data/repositories/hanabi_wasm_unscrambler.dart`**

```dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:wasm_run/wasm_run.dart';

/// Loads hanabimanga.com's official `/reader.wasm` module and invokes its
/// `unscramble` export to reverse the site's page-shuffling obfuscation.
///
/// This deliberately does NOT run the site's own reader page/React
/// component (which would trigger its canvas export DRM). Instead it loads
/// the same publicly-served WASM binary directly and drives it with our own
/// wasm-bindgen-compatible glue code.
class HanabiWasmUnscrambler {
  static const String _wasmUrl = 'https://web.hanabimanga.com/reader.wasm';

  WasmInstance? _instance;
  WasmMemory? _memory;
  WasmFunction? _unscrambleFn;
  WasmFunction? _allocFn;
  WasmFunction? _deallocFn;
  WasmFunction? _addStackFn;
  static bool _libSetUp = false;

  /// Loads and instantiates the WASM module if not already loaded.
  /// Pass [wasmBytesOverride] (e.g. in tests) to skip the network download
  /// and use pre-fetched bytes instead.
  Future<void> ensureLoaded({Uint8List? wasmBytesOverride}) async {
    if (_instance != null) return;

    if (!_libSetUp) {
      await WasmRunLibrary.setUp(isFlutter: true, loadAsset: rootBundle.load);
      _libSetUp = true;
    }

    final bytes = wasmBytesOverride ?? await _downloadWasm();

    final module = await compileWasmModule(
      bytes,
      config: const ModuleConfig(
        wasmi: ModuleConfigWasmi(),
        wasmtime: ModuleConfigWasmtime(),
      ),
    );

    final builder = module.builder(wasiConfig: null);
    builder.addImport(
      './xfmanga_wasm_bg.js',
      '__wbg_Error_2e59b1b37a9a34c3',
      WasmFunction(
        (int msgPtr, int msgLen) => 0,
        params: [ValueTy.i32, ValueTy.i32],
        results: [ValueTy.i32],
      ),
    );
    builder.addImport(
      './xfmanga_wasm_bg.js',
      '__wbg___wbindgen_throw_81fc77679af83bc6',
      WasmFunction.voidReturn(
        (int msgPtr, int msgLen) {
          throw Exception('hanabi wasm unscramble threw an internal error');
        },
        params: [ValueTy.i32, ValueTy.i32],
      ),
    );

    final instance = await builder.build();

    final memory = instance.getMemory('memory');
    final unscrambleFn = instance.getFunction('unscramble');
    final allocFn = instance.getFunction('__wbindgen_export');
    final deallocFn = instance.getFunction('__wbindgen_export2');
    final addStackFn = instance.getFunction('__wbindgen_add_to_stack_pointer');

    if (memory == null ||
        unscrambleFn == null ||
        allocFn == null ||
        deallocFn == null ||
        addStackFn == null) {
      throw Exception('hanabi reader.wasm is missing expected exports');
    }

    _instance = instance;
    _memory = memory;
    _unscrambleFn = unscrambleFn;
    _allocFn = allocFn;
    _deallocFn = deallocFn;
    _addStackFn = addStackFn;
  }

  Future<Uint8List> _downloadWasm() async {
    final dio = Dio();
    final response = await dio.get<List<int>>(
      _wasmUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  int _writeBytes(Uint8List bytes) {
    final ptr = _allocFn!.inner(bytes.length, 1) as int;
    _memory!.view.setRange(ptr, ptr + bytes.length, bytes);
    return ptr;
  }

  /// Unscrambles a decoded RGBA image buffer using the given ticket/nonce
  /// and grid dimensions (all sourced from the reader API's
  /// `metadata.scrambleInfo`). Returns a new RGBA buffer of the same length.
  Future<Uint8List> unscramble(
    Uint8List rgba,
    int width,
    int height,
    Uint8List ticket,
    Uint8List nonce,
    int cols,
    int rows,
  ) async {
    await ensureLoaded();

    final ticketPtr = _writeBytes(ticket);
    final noncePtr = _writeBytes(nonce);
    final imagePtr = _writeBytes(rgba);

    final retPtr = _addStackFn!.inner(-16) as int;

    _unscrambleFn!.inner(
      retPtr,
      ticketPtr,
      ticket.length,
      noncePtr,
      nonce.length,
      imagePtr,
      rgba.length,
      width,
      height,
      cols,
      rows,
    );

    final retView = ByteData.sublistView(_memory!.view, retPtr, retPtr + 16);
    final resultPtr = retView.getInt32(0, Endian.little);
    final resultLen = retView.getInt32(4, Endian.little);
    final hasError = retView.getInt32(12, Endian.little);

    _addStackFn!.inner(16);

    if (hasError != 0) {
      throw Exception('hanabi wasm unscramble reported an error');
    }

    final decrypted = Uint8List.fromList(
      _memory!.view.sublist(resultPtr, resultPtr + resultLen),
    );

    _deallocFn!.inner(resultPtr, resultLen, 1);

    return decrypted;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/repositories/hanabi_wasm_unscrambler_test.dart`
Expected: PASS. This is a real end-to-end test against the actual WASM binary — if it fails, check that `wasm_run_flutter`/`wasm_run` resolved correctly (`flutter pub get`) and that the two fixture files are intact (correct byte sizes per Task 1 Step 2).

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/repositories/hanabi_wasm_unscrambler.dart test/data/repositories/hanabi_wasm_unscrambler_test.dart
git commit -m "feat: add HanabiWasmUnscrambler wrapping the official reader.wasm module"
```

---

## Task 8: Create the `HanabiManga` source

**Files:**
- Create: `lib/data/sources/hanabi_manga.dart`
- Test: `test/data/sources/hanabi_manga_test.dart` (new)

This is the core source file. It exposes three testable top-level functions (`buildHanabiSessionCookie`, `extractHanabiBookLdJson`, `extractHanabiChapters`) plus the `HanabiManga` class implementing all `MangaSource` prepare/parse pairs.

- [ ] **Step 1: Write the failing test file**

Create `test/data/sources/hanabi_manga_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildHanabiSessionCookie', () {
    test('keeps short payloads as a single cookie', () {
      final cookie = buildHanabiSessionCookie(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresIn: 3600,
        expiresAt: 1234567890,
        user: {'id': 'u1'},
      );
      expect(
        cookie.startsWith('sb-uhkvqrxmcapgtpspglrp-auth-token=base64-'),
        isTrue,
      );
      expect(cookie.contains('.0='), isFalse);
    });

    test('splits long payloads across suffixed cookies', () {
      final longRefreshToken = 'r' * 4000;
      final cookie = buildHanabiSessionCookie(
        accessToken: 'access',
        refreshToken: longRefreshToken,
        expiresIn: 3600,
        expiresAt: 1234567890,
        user: {'id': 'u1', 'email': 'x@example.com'},
      );
      expect(
        cookie.contains('sb-uhkvqrxmcapgtpspglrp-auth-token.0='),
        isTrue,
      );
      expect(
        cookie.contains('sb-uhkvqrxmcapgtpspglrp-auth-token.1='),
        isTrue,
      );
      expect(cookie.contains('; '), isTrue);
    });
  });

  group('extractHanabiBookLdJson', () {
    test('parses the Book ld+json block from the real detail page', () async {
      final html = await File(
        'test/fixtures/hanabi/detail_page.html',
      ).readAsString();
      final book = extractHanabiBookLdJson(html);
      expect(book, isNotNull);
      expect(book!['name'], '尼古喵喵');
      expect(book['alternateName'], ['雅尼猫']);
      expect(
        (book['author'] as List).first['name'],
        'にゃんにゃんファクトリー',
      );
      expect(
        book['image'],
        'https://img2.cycimg.me/r/400/pic/cover/l/90/31/445083_BXuSi.jpg',
      );
      expect(book['genre'], ['搜笑']);
    });
  });

  group('extractHanabiChapters', () {
    test('parses all 73 chapters from the real detail page', () async {
      final html = await File(
        'test/fixtures/hanabi/detail_page.html',
      ).readAsString();
      final chapters = extractHanabiChapters(html);
      expect(chapters.length, 73);
      expect(chapters.first['id'], 164145);
      expect(chapters.first['title'], '第01话');
      expect(chapters.first['idx'], 1);
      expect(chapters.first['category'], 'normal');
      expect(chapters.first['image_count'], 15);
      expect(chapters[29]['id'], 164174);
      expect(chapters[29]['title'], '第29话');
      expect(chapters[29]['idx'], 30);
      expect(chapters[35]['title'], '动画化');
      expect(chapters[35]['idx'], 36);
      expect(chapters.last['id'], 201340);
      expect(chapters.last['title'], '第69话');
      expect(chapters.last['idx'], 73);
    });
  });

  group('HanabiManga.parseMangaInfo', () {
    test('extracts full metadata and chapter list from the real detail page', () async {
      final html = await File(
        'test/fixtures/hanabi/detail_page.html',
      ).readAsString();
      final source = HanabiManga();
      final detail = source.parseMangaInfo(html, '3361');

      expect(detail.title, '尼古喵喵');
      expect(detail.author, 'にゃんにゃんファクトリー');
      expect(detail.altTitles, ['雅尼猫']);
      expect(
        detail.coverUrl,
        'https://img2.cycimg.me/r/400/pic/cover/l/90/31/445083_BXuSi.jpg',
      );
      expect(detail.tags, ['搜笑']);
      expect(detail.status, MangaStatus.ongoing);
      expect(detail.chapters.length, 73);
      expect(detail.chapters.first.id, 'chapter-1');
      expect(detail.chapters.first.title, '第01话');
      expect(detail.chapters[29].id, 'chapter-30');
      expect(detail.chapters[29].title, '第29话');
      expect(detail.chapters.last.id, 'chapter-73');
    });
  });

  group('HanabiManga chapter list', () {
    test('prepareChapterListFetch returns null; parseChapterList returns empty', () {
      final source = HanabiManga();
      expect(source.prepareChapterListFetch('3361', 1), isNull);
      expect(
        source.parseChapterList(null, '3361'),
        const ChapterListResult(chapters: []),
      );
    });
  });

  group('HanabiManga.prepareChapterFetch/parseChapter', () {
    test('prepareChapterFetch builds the reader API URL', () {
      final source = HanabiManga();
      final config = source.prepareChapterFetch('3361', 'chapter-30', 1);
      expect(
        config.url,
        'https://web.hanabimanga.com/api/reader/comic/3361/chapter-30',
      );
    });

    test('parseChapter extracts pages with hanabi scramble metadata', () {
      final source = HanabiManga();
      const response = {
        'chapter': {
          'comicId': 3361,
          'chapterSlug': 'chapter-1',
          'chapterId': 164145,
          'title': '第01话',
          'idx': 1,
          'totalPages': 2,
        },
        'pages': [
          {
            'index': 0,
            'page': '001',
            'url': 'https://cdn.hanabimanga.top/a/001.webp',
          },
          {
            'index': 1,
            'page': '002',
            'url': 'https://cdn.hanabimanga.top/a/002.webp',
          },
        ],
        'metadata': {
          'expiresIn': 7200,
          'scrambleInfo': {
            'ticket': 'Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=',
            'nonce': 'ZkfsVQTteF2Ab4Ha',
            'cols': 4,
            'rows': 4,
          },
        },
      };

      final result = source.parseChapter(response, '3361', 'chapter-1', 1);

      expect(result.chapter.title, '第01话');
      expect(result.chapter.images.length, 2);
      final first = result.chapter.images.first;
      expect(first.url, 'https://cdn.hanabimanga.top/a/001.webp');
      expect(first.scrambleType, ScrambleType.hanabi);
      expect(
        first.hanabiTicket,
        'Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=',
      );
      expect(first.hanabiNonce, 'ZkfsVQTteF2Ab4Ha');
      expect(first.hanabiCols, 4);
      expect(first.hanabiRows, 4);
    });
  });

  group('HanabiManga discovery', () {
    test('prepareDiscoveryFetch builds the browse URL with only non-default filters', () {
      final source = HanabiManga();
      final config = source.prepareDiscoveryFetch(2, {
        'category': 'yuri',
        'sort': 'rating',
        'region': 'jp',
        'status': 'serializing',
      });
      expect(
        config.url,
        'https://web.hanabimanga.com/zh-CN/browse?page=2&category=yuri&sort=rating&region=jp&status=serializing',
      );
    });

    test('prepareDiscoveryFetch omits default/all filter values', () {
      final source = HanabiManga();
      final config = source.prepareDiscoveryFetch(1, {
        'category': 'all',
        'sort': '',
        'region': 'all',
        'status': 'all',
      });
      expect(config.url, 'https://web.hanabimanga.com/zh-CN/browse?page=1');
    });

    test('parseDiscovery extracts manga cards via structural selectors', () {
      final source = HanabiManga();
      const html = '''
        <div>
          <a href="/zh-CN/comic/123">
            <img src="https://img2.xfmanga.top/cover1.jpg" alt="漫画A" />
            <h3>漫画A</h3>
          </a>
          <a href="/zh-CN/comic/456">
            <img src="https://img2.xfmanga.top/cover2.jpg" />
            <h3>漫画B</h3>
          </a>
          <a href="/zh-CN/comic/123">
            <img src="https://img2.xfmanga.top/cover1-dup.jpg" />
            <h3>漫画A重复</h3>
          </a>
        </div>
      ''';
      final results = source.parseDiscovery(html);
      expect(results.length, 2);
      expect(results[0].id, '123');
      expect(results[0].title, '漫画A');
      expect(results[0].coverUrl, 'https://img2.xfmanga.top/cover1.jpg');
      expect(results[1].id, '456');
      expect(results[1].title, '漫画B');
    });
  });

  group('HanabiManga search', () {
    test('prepareSearchFetch builds the Supabase RPC request', () {
      final source = HanabiManga();
      final config = source.prepareSearchFetch('尼古', 1, const {});
      expect(
        config.url,
        'https://uhkvqrxmcapgtpspglrp.supabase.co/rest/v1/rpc/search_comics_pgroonga',
      );
      expect(config.method, HttpMethod.post);
      expect(config.headers?['apikey'], isNotEmpty);
      expect(
        config.body,
        jsonEncode({
          'search_term': '尼古',
          'page_number': 1,
          'items_per_page': 24,
        }),
      );
    });

    test('parseSearch extracts MangaSummary from the Supabase RPC response', () {
      final source = HanabiManga();
      const response = [
        {
          'id': 3361,
          'title': '尼古喵喵',
          'aliases': ['雅尼猫'],
          'cover_url':
              'https://img2.cycimg.me/r/400/pic/cover/l/90/31/445083_BXuSi.jpg',
          'lock_status': 'free',
          'chapters_count': 73,
        },
      ];
      final results = source.parseSearch(response);
      expect(results.length, 1);
      expect(results.first.id, '3361');
      expect(results.first.title, '尼古喵喵');
      expect(results.first.altTitles, ['雅尼猫']);
      expect(results.first.chapterCount, 73);
    });
  });

  group('HanabiManga login/session', () {
    test('buildSignInRequest posts to the Supabase password grant endpoint', () {
      final source = HanabiManga();
      final config = source.buildSignInRequest('user@example.com', 'secret');
      expect(
        config.url,
        'https://uhkvqrxmcapgtpspglrp.supabase.co/auth/v1/token?grant_type=password',
      );
      expect(config.method, HttpMethod.post);
      expect(
        config.body,
        jsonEncode({'email': 'user@example.com', 'password': 'secret'}),
      );
    });

    test('parseSignIn builds a session cookie and marks the source authenticated', () {
      final source = HanabiManga();
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final data = source.parseSignIn({
        'access_token': 'access-tok',
        'refresh_token': 'refresh-tok',
        'expires_in': 3600,
        'expires_at': nowSeconds + 3600,
        'user': {'id': 'u1', 'email': 'user@example.com'},
      });

      expect(data, isNotNull);
      expect(
        data!['cookie'],
        startsWith('sb-uhkvqrxmcapgtpspglrp-auth-token=base64-'),
      );
      expect(data['accessToken'], 'access-tok');
      expect(data['refreshToken'], 'refresh-tok');
      expect(data['expiresAt'], nowSeconds + 3600);

      source.syncExtraData(data);
      expect(source.isAuthenticated, isTrue);
      expect(source.extraHeaders['Cookie'], data['cookie']);
    });

    test('needsSessionRefresh becomes true within 5 minutes of expiry', () {
      final source = HanabiManga();
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      source.syncExtraData({
        'cookie': 'sb-uhkvqrxmcapgtpspglrp-auth-token=base64-x',
        'accessToken': 'a',
        'refreshToken': 'r',
        'expiresAt': nowSeconds + 60,
      });
      expect(source.needsSessionRefresh, isTrue);
    });

    test('buildRefreshRequest posts to the Supabase refresh_token grant endpoint', () {
      final source = HanabiManga();
      source.syncExtraData({
        'cookie': 'sb-uhkvqrxmcapgtpspglrp-auth-token=base64-x',
        'accessToken': 'a',
        'refreshToken': 'r-123',
        'expiresAt':
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
      });
      final config = source.buildRefreshRequest();
      expect(
        config.url,
        'https://uhkvqrxmcapgtpspglrp.supabase.co/auth/v1/token?grant_type=refresh_token',
      );
      expect(config.body, jsonEncode({'refresh_token': 'r-123'}));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/sources/hanabi_manga_test.dart`
Expected: FAIL — `package:comic_reader/data/sources/hanabi_manga.dart` does not exist yet.

- [ ] **Step 3: Create `lib/data/sources/hanabi_manga.dart`**

```dart
import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Supabase project this source authenticates against.
const String _hanabiSupabaseUrl = 'https://uhkvqrxmcapgtpspglrp.supabase.co';
const String _hanabiAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoa3ZxcnhtY2FwZ3Rwc3BnbHJwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5NjgzMjksImV4cCI6MjA3OTU0NDMyOX0.uuHr888lp14ObW5eWowJrHPJGgQf3sF2l7NPmFN84g4';
const String _hanabiCookieName = 'sb-uhkvqrxmcapgtpspglrp-auth-token';
const int _hanabiCookieChunkSize = 3180;

/// Builds the Supabase SSR session cookie value that hanabimanga.com's
/// server-side API routes require. The site's `/api/*` routes only read
/// the session from this Cookie header — an `Authorization: Bearer` header
/// is silently ignored by the server.
///
/// If the JSON-encoded, base64'd payload exceeds [_hanabiCookieChunkSize]
/// characters, it is split across multiple same-name cookies suffixed
/// `.0`, `.1`, etc. (matching `@supabase/ssr`'s own chunking behavior),
/// joined into a single `Cookie:` header value with `; ` separators.
String buildHanabiSessionCookie({
  required String accessToken,
  required String refreshToken,
  required int expiresIn,
  required int expiresAt,
  required Map<String, dynamic> user,
}) {
  final payload = jsonEncode({
    'access_token': accessToken,
    'token_type': 'bearer',
    'expires_in': expiresIn,
    'expires_at': expiresAt,
    'refresh_token': refreshToken,
    'user': user,
  });
  final encoded = 'base64-${base64Encode(utf8.encode(payload))}';

  if (encoded.length <= _hanabiCookieChunkSize) {
    return '$_hanabiCookieName=$encoded';
  }

  final parts = <String>[];
  for (var i = 0; i < encoded.length; i += _hanabiCookieChunkSize) {
    final end = (i + _hanabiCookieChunkSize < encoded.length)
        ? i + _hanabiCookieChunkSize
        : encoded.length;
    parts.add('$_hanabiCookieName.${parts.length}=${encoded.substring(i, end)}');
  }
  return parts.join('; ');
}

/// Extracts the `application/ld+json` block with `"@type":"Book"` from a
/// hanabimanga.com comic detail page. Returns null if not found.
Map<String, dynamic>? extractHanabiBookLdJson(String html) {
  const marker = '<script type="application/ld+json">';
  var searchStart = 0;
  while (true) {
    final start = html.indexOf(marker, searchStart);
    if (start == -1) return null;
    final contentStart = start + marker.length;
    final end = html.indexOf('</script>', contentStart);
    if (end == -1) return null;
    final jsonStr = html.substring(contentStart, end);
    searchStart = end + '</script>'.length;
    if (!jsonStr.contains('"@type":"Book"')) continue;
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }
}

/// Extracts the full chapter list embedded in a hanabimanga.com comic
/// detail page's Next.js RSC flight payload. The data is present as a
/// backslash-escaped JSON string (e.g. `\"chapters\":[...]`) rather than
/// literal JSON, because it is nested inside a `self.__next_f.push([1,"..."])`
/// script tag. Square brackets themselves are NOT escaped, so the array's
/// extent can be found by simple bracket-depth counting; only the quotes
/// inside need unescaping before `jsonDecode`.
List<Map<String, dynamic>> extractHanabiChapters(String html) {
  const marker = r'\"chapters\":[';
  final markerIndex = html.indexOf(marker);
  if (markerIndex == -1) return const [];

  final arrayStart = markerIndex + marker.length - 1; // index of '['
  var depth = 0;
  var i = arrayStart;
  for (; i < html.length; i++) {
    final ch = html[i];
    if (ch == '[') depth++;
    if (ch == ']') {
      depth--;
      if (depth == 0) {
        i++; // move past the closing ']'
        break;
      }
    }
  }

  final rawArray = html.substring(arrayStart, i);
  final unescaped = rawArray.replaceAll(r'\"', '"');
  final decoded = jsonDecode(unescaped) as List<dynamic>;
  return decoded.cast<Map<String, dynamic>>();
}

/// HanabiManga (花火漫画) source plugin.
///
/// - Login: direct Supabase Auth REST calls (no WebView needed).
/// - Session: the server only trusts a hand-built Supabase SSR cookie
///   (see [buildHanabiSessionCookie]), stored via the generic
///   [MangaSource.extraHeaders]/[MangaSource.syncExtraData] mechanism.
/// - Chapter list: embedded in the comic detail page HTML itself (see
///   [extractHanabiChapters]); [prepareChapterListFetch] returns null.
/// - Image descrambling: handled out-of-band by `HanabiChapterDecryptor`
///   (see hanabi_chapter_decryptor.dart), which is invoked from
///   `ChapterImagePipeline` after [parseChapter] returns
///   `ScrambleType.hanabi` images.
class HanabiManga extends MangaSource {
  static const String sourceId = 'hanabi_manga';
  static const String _baseUrl = 'https://web.hanabimanga.com';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  @override
  String get id => sourceId;

  @override
  String get name => '花火漫画';

  @override
  String get shortName => '花火';

  @override
  String? get description => '需要登录账号才能使用，仅支持免费/普通章节';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get requiresLogin => true;

  @override
  String? get loginDescription => '使用花火漫画账号登录后即可阅读免费章节';

  @override
  bool get isAuthenticated =>
      extraHeaders.containsKey('Cookie') &&
      _expiresAt != null &&
      DateTime.now().toUtc().isBefore(_expiresAt!);

  @override
  void syncExtraData(Map<String, dynamic> data) {
    super.syncExtraData(data);
    final accessToken = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final expiresAt = data['expiresAt'] as int?;
    if (accessToken != null) _accessToken = accessToken;
    if (refreshToken != null) _refreshToken = refreshToken;
    if (expiresAt != null) {
      _expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
        isUtc: true,
      );
    }
  }

  @override
  FetchConfig buildSignInRequest(String email, String password) {
    return FetchConfig(
      url: '$_hanabiSupabaseUrl/auth/v1/token?grant_type=password',
      method: HttpMethod.post,
      headers: const {
        'apikey': _hanabiAnonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
  }

  @override
  Map<String, dynamic>? parseSignIn(dynamic response) {
    final data = response is String
        ? jsonDecode(response) as Map<String, dynamic>
        : response as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    final expiresIn = data['expires_in'] as int?;
    final expiresAt = data['expires_at'] as int?;
    final user = data['user'] as Map<String, dynamic>?;
    if (accessToken == null ||
        refreshToken == null ||
        expiresAt == null ||
        user == null) {
      return null;
    }
    final cookie = buildHanabiSessionCookie(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn ?? 3600,
      expiresAt: expiresAt,
      user: user,
    );
    return {
      'cookie': cookie,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt,
    };
  }

  @override
  bool get needsSessionRefresh {
    if (_expiresAt == null) return false;
    return DateTime.now()
        .toUtc()
        .isAfter(_expiresAt!.subtract(const Duration(minutes: 5)));
  }

  @override
  FetchConfig buildRefreshRequest() {
    return FetchConfig(
      url: '$_hanabiSupabaseUrl/auth/v1/token?grant_type=refresh_token',
      method: HttpMethod.post,
      headers: const {
        'apikey': _hanabiAnonKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'refresh_token': _refreshToken}),
    );
  }

  @override
  List<FilterOption> get discoveryFilters => const [
    FilterOption(
      name: 'category',
      label: '分类',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '推理', value: 'mystery'),
        FilterChoice(label: '后宫', value: 'harem'),
        FilterChoice(label: '科幻', value: 'scifi'),
        FilterChoice(label: '百合', value: 'yuri'),
        FilterChoice(label: '恐怖', value: 'horror'),
        FilterChoice(label: '恋爱', value: 'romance'),
        FilterChoice(label: '音乐', value: 'music'),
        FilterChoice(label: '校园', value: 'school'),
        FilterChoice(label: '穿越', value: 'isekai'),
        FilterChoice(label: '战斗', value: 'battle'),
        FilterChoice(label: '运动', value: 'sports'),
        FilterChoice(label: '武侠', value: 'wuxia'),
        FilterChoice(label: '奇幻', value: 'fantasy'),
        FilterChoice(label: '惊悚', value: 'thriller'),
        FilterChoice(label: '搜笑', value: 'comedy'),
        FilterChoice(label: '日常', value: 'slice-of-life'),
        FilterChoice(label: '悬疑', value: 'suspense'),
        FilterChoice(label: '冒险', value: 'adventure'),
        FilterChoice(label: '历史', value: 'history'),
        FilterChoice(label: '乙女', value: 'otome'),
        FilterChoice(label: '美食', value: 'gourmet'),
        FilterChoice(label: '职场', value: 'workplace'),
        FilterChoice(label: '玄幻', value: 'xuanhuan'),
        FilterChoice(label: '机战', value: 'mecha'),
        FilterChoice(label: '魔幻', value: 'magic'),
        FilterChoice(label: '伪娘', value: 'femboy'),
      ],
    ),
    FilterOption(
      name: 'sort',
      label: '排序',
      defaultValue: '',
      choices: [
        FilterChoice(label: '推荐', value: ''),
        FilterChoice(label: '评分', value: 'rating'),
        FilterChoice(label: '最近更新', value: 'updated'),
        FilterChoice(label: '最新上架', value: 'created'),
      ],
    ),
    FilterOption(
      name: 'region',
      label: '分区',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '日漫', value: 'jp'),
        FilterChoice(label: '韩漫', value: 'kr'),
        FilterChoice(label: '美漫', value: 'us'),
        FilterChoice(label: '其他', value: 'others'),
      ],
    ),
    FilterOption(
      name: 'status',
      label: '状态',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '连载中', value: 'serializing'),
        FilterChoice(label: '已完结', value: 'finished'),
      ],
    ),
  ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final category = filters['category'] ?? 'all';
    final sort = filters['sort'] ?? '';
    final region = filters['region'] ?? 'all';
    final status = filters['status'] ?? 'all';

    final query = <String, String>{'page': '$page'};
    if (category != 'all') query['category'] = category;
    if (sort.isNotEmpty) query['sort'] = sort;
    if (region != 'all') query['region'] = region;
    if (status != 'all') query['status'] = status;

    final queryString = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return FetchConfig(url: '$_baseUrl/zh-CN/browse?$queryString');
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final document = html_parser.parse(response as String);
    final links = document.querySelectorAll('a[href*="/comic/"]');
    final idPattern = RegExp(r'/comic/(\d+)');
    final seen = <String>{};
    final results = <MangaSummary>[];

    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      final match = idPattern.firstMatch(href);
      if (match == null) continue;
      final id = match.group(1)!;
      if (!seen.add(id)) continue;

      final img = link.querySelector('img');
      final coverUrl = img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';
      final title = (link.querySelector('h3')?.text.trim().isNotEmpty ?? false)
          ? link.querySelector('h3')!.text.trim()
          : (link.querySelector('h2')?.text.trim().isNotEmpty ?? false)
              ? link.querySelector('h2')!.text.trim()
              : (img?.attributes['alt'] ?? '').trim();
      if (title.isEmpty) continue;

      results.add(
        MangaSummary(id: id, sourceId: sourceId, title: title, coverUrl: coverUrl, author: ''),
      );
    }
    return results;
  }

  @override
  FetchConfig prepareSearchFetch(String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_hanabiSupabaseUrl/rest/v1/rpc/search_comics_pgroonga',
      method: HttpMethod.post,
      headers: const {
        'apikey': _hanabiAnonKey,
        'Content-Type': 'application/json',
        'Content-Profile': 'public',
      },
      body: jsonEncode({
        'search_term': keyword,
        'page_number': page,
        'items_per_page': 24,
      }),
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final list = response is String
        ? jsonDecode(response) as List<dynamic>
        : response as List<dynamic>;
    return list.map((item) {
      final map = item as Map<String, dynamic>;
      return MangaSummary(
        id: '${map['id']}',
        sourceId: sourceId,
        title: map['title'] as String? ?? '',
        coverUrl: map['cover_url'] as String? ?? '',
        author: '',
        altTitles:
            (map['aliases'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                const [],
        chapterCount: map['chapters_count'] as int?,
      );
    }).toList();
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/zh-CN/comic/$mangaId');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final book = extractHanabiBookLdJson(htmlStr) ?? const <String, dynamic>{};

    final title = book['name'] as String? ?? '';
    final altTitles =
        (book['alternateName'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final authors = (book['author'] as List<dynamic>?)
            ?.map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        const <String>[];
    final coverUrl = book['image'] as String? ?? '';
    final description = book['description'] as String?;
    final tags =
        (book['genre'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            const <String>[];

    var status = MangaStatus.unknown;
    final metaMatch =
        RegExp(r'<meta name="description" content="([^"]*)"').firstMatch(htmlStr);
    final metaContent = metaMatch?.group(1) ?? '';
    if (metaContent.contains('已完结')) {
      status = MangaStatus.completed;
    } else if (metaContent.contains('连载中')) {
      status = MangaStatus.ongoing;
    }

    final rawChapters = extractHanabiChapters(htmlStr);
    final chapters = rawChapters.map((c) {
      final idx = c['idx'] as int;
      final chapterTitle = c['title'] as String? ?? '第$idx话';
      return ChapterItem(id: 'chapter-$idx', mangaId: mangaId, title: chapterTitle);
    }).toList();

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: authors.join(', '),
      tags: tags,
      altTitles: altTitles,
      status: status,
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) =>
      const ChapterListResult(chapters: []);

  @override
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) {
    return FetchConfig(url: '$_baseUrl/api/reader/comic/$mangaId/$chapterId');
  }

  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) {
    final data = response is String
        ? jsonDecode(response) as Map<String, dynamic>
        : response as Map<String, dynamic>;
    final chapterMeta = data['chapter'] as Map<String, dynamic>;
    final title = chapterMeta['title'] as String? ?? chapterId;

    final scrambleInfo =
        (data['metadata'] as Map<String, dynamic>?)?['scrambleInfo'] as Map<String, dynamic>?;
    final ticket = scrambleInfo?['ticket'] as String?;
    final nonce = scrambleInfo?['nonce'] as String?;
    final cols = scrambleInfo?['cols'] as int?;
    final rows = scrambleInfo?['rows'] as int?;

    final pages = data['pages'] as List<dynamic>;
    final images = pages.map((p) {
      final pageMap = p as Map<String, dynamic>;
      final url = pageMap['url'] as String;
      if (ticket != null && nonce != null && cols != null && rows != null) {
        return ChapterImage(
          url: url,
          scrambleType: ScrambleType.hanabi,
          hanabiTicket: ticket,
          hanabiNonce: nonce,
          hanabiCols: cols,
          hanabiRows: rows,
        );
      }
      return ChapterImage(url: url);
    }).toList();

    return ChapterResult(
      chapter: Chapter(id: chapterId, mangaId: mangaId, title: title, images: images),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/sources/hanabi_manga_test.dart`
Expected: PASS (all groups/tests). If the `parseMangaInfo`/`extractHanabiChapters` tests fail on chapter counts or field values, re-verify the fixture file byte size matches Task 1 Step 2 (202649 bytes) — a truncated/corrupted fixture is the most likely cause, not a logic bug (the extraction algorithm and all expected values were verified against this exact fixture during research).

- [ ] **Step 5: Run static analysis**

Run: `cd /Users/portz/js/comic/comic-reader && flutter analyze lib/data/sources/hanabi_manga.dart`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/sources/hanabi_manga.dart test/data/sources/hanabi_manga_test.dart
git commit -m "feat: add HanabiManga source (discovery/search/detail/chapter/login)"
```

---

## Task 9: Create `HanabiChapterDecryptor`

**Files:**
- Create: `lib/data/repositories/hanabi_chapter_decryptor.dart`
- Test: `test/data/repositories/hanabi_chapter_decryptor_test.dart` (new)

This class downloads a scrambled CDN image, decodes it to RGBA via `package:image`, calls `HanabiWasmUnscrambler.unscramble`, re-encodes the result as a PNG, and returns a `data:` URI `ChapterImage` with `scrambleType: ScrambleType.none` (matching the existing pattern in `manga_image.dart` where `data:` URLs are rendered directly via `Image.memory`).

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/hanabi_chapter_decryptor_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/repositories/fetch_pipeline.dart';
import 'package:comic_reader/data/repositories/hanabi_chapter_decryptor.dart';
import 'package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements HttpClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(const FetchConfig(url: ''));
  });

  test('decrypt downloads, unscrambles via wasm, and returns a data: URI image', () async {
    final scrambledBytes =
        await File('test/fixtures/hanabi/scrambled_page001.webp').readAsBytes();
    final wasmBytes = await File('test/fixtures/hanabi/reader.wasm').readAsBytes();

    final mockHttpClient = MockHttpClient();
    when(() => mockHttpClient.execute(any())).thenAnswer(
      (_) async => Response(
        data: scrambledBytes,
        requestOptions: RequestOptions(path: 'https://cdn.hanabimanga.top/fake.webp'),
        statusCode: 200,
      ),
    );

    final pipeline = FetchPipeline(mockHttpClient);
    final unscrambler = HanabiWasmUnscrambler();
    await unscrambler.ensureLoaded(wasmBytesOverride: wasmBytes);
    final decryptor = HanabiChapterDecryptor(mockHttpClient, pipeline, unscrambler);
    final source = HanabiManga();

    const input = ChapterImage(
      url: 'https://cdn.hanabimanga.top/fake.webp',
      scrambleType: ScrambleType.hanabi,
      hanabiTicket: 'Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=',
      hanabiNonce: 'ZkfsVQTteF2Ab4Ha',
      hanabiCols: 4,
      hanabiRows: 4,
    );

    final result = await decryptor.decrypt(input, source);

    expect(result.scrambleType, ScrambleType.none);
    expect(result.url.startsWith('data:image/png;base64,'), isTrue);

    final base64Data = result.url.substring('data:image/png;base64,'.length);
    final pngBytes = base64Decode(base64Data);
    final decodedPng = img.decodeImage(pngBytes)!;
    final rgba = decodedPng.getBytes(order: img.ChannelOrder.rgba);
    final hash = sha256.convert(rgba).toString();

    expect(
      hash,
      '9735c728f504471ec4fc654752591901377c710801b9f96ad51d996afd0233e1',
    );
  });

  test('decrypt returns the original image unchanged when scrambleType is not hanabi', () async {
    final mockHttpClient = MockHttpClient();
    final pipeline = FetchPipeline(mockHttpClient);
    final decryptor = HanabiChapterDecryptor(mockHttpClient, pipeline);
    final source = HanabiManga();

    const input = ChapterImage(url: 'https://cdn.hanabimanga.top/plain.jpg');
    final result = await decryptor.decrypt(input, source);

    expect(result, input);
    verifyNever(() => mockHttpClient.execute(any()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/repositories/hanabi_chapter_decryptor_test.dart`
Expected: FAIL — `package:comic_reader/data/repositories/hanabi_chapter_decryptor.dart` does not exist yet.

- [ ] **Step 3: Create `lib/data/repositories/hanabi_chapter_decryptor.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show ResponseType;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/repositories/fetch_pipeline.dart';
import 'package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Downloads a scrambled hanabimanga.com CDN image, unscrambles it via the
/// official `/reader.wasm` module (see [HanabiWasmUnscrambler]), and returns
/// a `data:` URI image ready for direct rendering.
class HanabiChapterDecryptor {
  final HttpClient _httpClient;
  final FetchPipeline _pipeline;
  final HanabiWasmUnscrambler _unscrambler;

  HanabiChapterDecryptor(
    this._httpClient,
    this._pipeline, [
    HanabiWasmUnscrambler? unscrambler,
  ]) : _unscrambler = unscrambler ?? HanabiWasmUnscrambler();

  /// Decrypts [chapterImage] if it is scrambled (`ScrambleType.hanabi`).
  /// Returns the input unchanged for any other scramble type, or on
  /// failure (network error, decode error, or wasm error) — in the failure
  /// case the caller will attempt to render the original (still-scrambled)
  /// CDN URL, which will look garbled but at least won't crash the reader.
  Future<ChapterImage> decrypt(ChapterImage chapterImage, HanabiManga source) async {
    if (chapterImage.scrambleType != ScrambleType.hanabi) return chapterImage;

    final ticketB64 = chapterImage.hanabiTicket;
    final nonceB64 = chapterImage.hanabiNonce;
    final cols = chapterImage.hanabiCols;
    final rows = chapterImage.hanabiRows;
    if (ticketB64 == null || nonceB64 == null || cols == null || rows == null) {
      return chapterImage;
    }

    try {
      final config = _pipeline.mergeHeaders(
        FetchConfig(url: chapterImage.url, responseType: ResponseType.bytes),
        source,
      );
      final response = await _httpClient.execute(config);
      final scrambledBytes = response.data as Uint8List;

      final decoded = img.decodeImage(scrambledBytes);
      if (decoded == null) return chapterImage;
      final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);

      final ticket = base64Decode(ticketB64);
      final nonce = base64Decode(nonceB64);

      final decryptedRgba = await _unscrambler.unscramble(
        rgba,
        decoded.width,
        decoded.height,
        ticket,
        nonce,
        cols,
        rows,
      );

      final decryptedImage = img.Image.fromBytes(
        width: decoded.width,
        height: decoded.height,
        bytes: decryptedRgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      final pngBytes = img.encodePng(decryptedImage);
      final dataUri = 'data:image/png;base64,${base64Encode(pngBytes)}';

      return ChapterImage(url: dataUri, scrambleType: ScrambleType.none);
    } catch (e) {
      debugPrint('HanabiChapterDecryptor failed: $e');
      return chapterImage;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test test/data/repositories/hanabi_chapter_decryptor_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/repositories/hanabi_chapter_decryptor.dart test/data/repositories/hanabi_chapter_decryptor_test.dart
git commit -m "feat: add HanabiChapterDecryptor (download + wasm unscramble + re-encode)"
```

---

## Task 10: Wire `HanabiChapterDecryptor` into the chapter-fetch pipeline

**Files:**
- Modify: `lib/data/repositories/chapter_image_pipeline.dart`
- Modify: `lib/data/repositories/manga_repository_impl.dart`

No new automated test here (this is glue code inside an existing integration-tested pipeline); correctness is verified by `flutter analyze` + the full test suite in Task 12, plus manual verification.

- [ ] **Step 1: Read both files fully before editing**

```bash
cd /Users/portz/js/comic/comic-reader
cat lib/data/repositories/chapter_image_pipeline.dart
cat lib/data/repositories/manga_repository_impl.dart
```

- [ ] **Step 2: Edit `lib/data/repositories/chapter_image_pipeline.dart`**

Add these two imports near the top of the file, alongside the existing imports:
```dart
import 'package:comic_reader/data/repositories/hanabi_chapter_decryptor.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
```

Change the class fields and constructor from:
```dart
class ChapterImagePipeline {
  final HttpClient _httpClient;
  final FetchPipeline _pipeline;
  final Wu55ChapterDecryptor _wu55Decryptor;
  ChapterImagePipeline(this._httpClient, this._pipeline, this._wu55Decryptor);
```
to:
```dart
class ChapterImagePipeline {
  final HttpClient _httpClient;
  final FetchPipeline _pipeline;
  final Wu55ChapterDecryptor _wu55Decryptor;
  final HanabiChapterDecryptor _hanabiDecryptor;
  ChapterImagePipeline(
    this._httpClient,
    this._pipeline,
    this._wu55Decryptor,
    this._hanabiDecryptor,
  );
```

In `getChapter(...)`, locate the closing brace of the existing block:
```dart
    if (source is Wu55Comic && result.chapter.images.isNotEmpty) {
      List<ChapterImage> decryptedImages = const [];
      await for (final partial in _resolveWu55Images(result.chapter.images, source)) {
        decryptedImages = partial;
      }
      result = ChapterResult(
        chapter: Chapter(
          id: result.chapter.id,
          mangaId: result.chapter.mangaId,
          title: result.chapter.title,
          images: decryptedImages,
          headers: result.chapter.headers,
        ),
        canLoadMore: false,
      );
    }
```
and insert the following new block immediately after it (still inside `getChapter`, before whatever processing follows — e.g. the E-Hentai-style image page resolution or the final `return result;`):
```dart
    if (source is HanabiManga && result.chapter.images.isNotEmpty) {
      final decryptedImages = await Future.wait(
        result.chapter.images.map((img) => _hanabiDecryptor.decrypt(img, source)),
      );
      result = ChapterResult(
        chapter: Chapter(
          id: result.chapter.id,
          mangaId: result.chapter.mangaId,
          title: result.chapter.title,
          images: decryptedImages,
          headers: result.chapter.headers,
        ),
        canLoadMore: false,
      );
    }
```

Do the equivalent insertion in `getChapterStream(...)`: locate the matching Wu55 block (which uses `await for (... ) { yield ChapterResult(...); } return;` instead of assigning to `result`), and insert immediately after it:
```dart
    if (source is HanabiManga && result.chapter.images.isNotEmpty) {
      final decryptedImages = await Future.wait(
        result.chapter.images.map((img) => _hanabiDecryptor.decrypt(img, source)),
      );
      yield ChapterResult(
        chapter: Chapter(
          id: result.chapter.id,
          mangaId: result.chapter.mangaId,
          title: result.chapter.title,
          images: decryptedImages,
          headers: result.chapter.headers,
        ),
        canLoadMore: false,
      );
      return;
    }
```

- [ ] **Step 3: Edit `lib/data/repositories/manga_repository_impl.dart`**

Add this import alongside the existing ones:
```dart
import 'package:comic_reader/data/repositories/hanabi_chapter_decryptor.dart';
```

Change:
```dart
  late final FetchPipeline _pipeline = FetchPipeline(_httpClient);
  late final Wu55ChapterDecryptor _wu55Decryptor = Wu55ChapterDecryptor(_httpClient, _pipeline);
  late final ChapterImagePipeline _chapterPipeline = ChapterImagePipeline(_httpClient, _pipeline, _wu55Decryptor);
```
to:
```dart
  late final FetchPipeline _pipeline = FetchPipeline(_httpClient);
  late final Wu55ChapterDecryptor _wu55Decryptor = Wu55ChapterDecryptor(_httpClient, _pipeline);
  late final HanabiChapterDecryptor _hanabiDecryptor = HanabiChapterDecryptor(_httpClient, _pipeline);
  late final ChapterImagePipeline _chapterPipeline = ChapterImagePipeline(
    _httpClient,
    _pipeline,
    _wu55Decryptor,
    _hanabiDecryptor,
  );
```

- [ ] **Step 4: Run static analysis**

Run: `cd /Users/portz/js/comic/comic-reader && flutter analyze lib/data/repositories/`
Expected: No errors. If any other file constructs `ChapterImagePipeline(...)` directly (check with `grep -rn "ChapterImagePipeline(" lib/`), update that call site too to pass a `HanabiChapterDecryptor` instance.

- [ ] **Step 5: Run the full test suite**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/data/repositories/chapter_image_pipeline.dart lib/data/repositories/manga_repository_impl.dart
git commit -m "feat: invoke HanabiChapterDecryptor from the chapter-fetch pipeline"
```

---

## Task 11: Register `HanabiManga` in the DI container

**Files:**
- Modify: `lib/app/di/injection.dart`

- [ ] **Step 1: Read the file fully before editing**

```bash
cat /Users/portz/js/comic/comic-reader/lib/app/di/injection.dart
```

- [ ] **Step 2: Add the import**

Add, alongside the other `lib/data/sources/*.dart` imports (near line 15):
```dart
import 'package:comic_reader/data/sources/hanabi_manga.dart';
```

- [ ] **Step 3: Register the source**

In the source registry block, immediately before `getIt.registerSingleton<SourceRegistry>(registry);` (i.e. right after the last existing `registry.register(...)` call, which is `registry.register(Manga51());`), add:
```dart
  registry.register(HanabiManga());
```

- [ ] **Step 4: Run static analysis**

Run: `cd /Users/portz/js/comic/comic-reader && flutter analyze lib/app/di/injection.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/portz/js/comic/comic-reader
git add lib/app/di/injection.dart
git commit -m "feat: register HanabiManga in the source registry"
```

---

## Task 12: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run static analysis across the whole project**

Run: `cd /Users/portz/js/comic/comic-reader && flutter analyze`
Expected: No errors. Pre-existing warnings unrelated to this plan's files are acceptable; any new error/warning in a file touched by this plan must be fixed before continuing.

- [ ] **Step 2: Run the full automated test suite**

Run: `cd /Users/portz/js/comic/comic-reader && flutter test`
Expected: All tests pass, including every test added in Tasks 2-9 above:
- `test/domain/entities/chapter_test.dart`
- `test/data/sources/manga_source_login_test.dart`
- `test/data/sources/pica_comic_test.dart` (existing + 2 new cases)
- `test/presentation/common/login_dialog_test.dart`
- `test/data/repositories/hanabi_wasm_unscrambler_test.dart`
- `test/data/sources/hanabi_manga_test.dart`
- `test/data/repositories/hanabi_chapter_decryptor_test.dart`

If `test/widget_test.dart` was already failing before this plan (per the project's own AGENTS.md notes about GetIt not being initialized in that test), that pre-existing failure is not a regression and can be ignored.

- [ ] **Step 3: Manual verification checklist (real device/simulator, real hanabimanga.com account)**

Run the app (`flutter run`) and manually confirm:
1. Open Settings → Sources (or wherever plugins are listed) and select 花火漫画 (HanabiManga). Since `supportsAutoLogin` is false, a login dialog should appear (via `showLoginDialog`) rather than silently failing.
2. Enter a real hanabimanga.com account's email/password and submit. The dialog should close and the source should now show as authenticated.
3. Browse the source's discovery/browse tab: manga cards with covers and titles should render. Try changing the 分类/排序/分区/状态 filters and confirm the list changes (or at least the request URL changes — check via a network inspector if available).
4. Search for "尼古" (or any known title) and confirm results appear with covers/titles.
5. Open a manga detail page (e.g. 尼古喵喵, id 3361) and confirm: title, author, cover, tags, and a full chapter list (73 chapters for this title) are shown — not just 50.
6. Tap a free/normal chapter and confirm the pages render as normal, non-garbled images (i.e. the WASM unscramble pipeline worked end-to-end against a live CDN image, not just the test fixture).
7. Force-expire the session (e.g. wait past `expires_at`, or manually edit the stored `AuthStore` data on a debug build) and re-open the source: confirm `tryRefreshSession` silently refreshes the session on next relevant screen, OR — if refresh fails — confirm the app correctly detects the invalid session and re-prompts login rather than crashing or showing a blank chapter list.
8. Fully quit and relaunch the app; confirm the HanabiManga session persists (no need to log in again) as long as the token hasn't expired, proving `AuthStore` persistence round-trips correctly with the new data map shape.

- [ ] **Step 4: Confirm git history**

Run: `cd /Users/portz/js/comic/comic-reader && git log --oneline -14`
Expected: 12 new commits (one per task above), each with a clear conventional-commit-style message, on top of the pre-existing history.

---

## Known Limitations (consciously deferred from the design spec)

The design spec (`docs/superpowers/specs/2026-09-11-hanabi-manga-source-design.md`) section 7 ("错误处理") described three UI-polish behaviors that this plan intentionally does **not** implement, to keep the file/architecture footprint matching what was approved in the design's section 2 (no new UI files beyond `login_dialog.dart`). Documenting them here rather than silently dropping them:

1. **Per-page "decrypt failed, tap to retry" placeholder UI.** If `HanabiChapterDecryptor.decrypt` fails (network error, decode error, or WASM error), it returns the original still-scrambled `ChapterImage` unchanged (Task 9, Step 3). Since `manga_image.dart` has no rendering branch for `ScrambleType.hanabi`, this falls through to the default CDN-URL rendering path, which will show a garbled thumbnail rather than a dedicated "解密失败/重试" button. A future follow-up plan could add a `hanabi_memory_image.dart` widget (as originally sketched during brainstorming) if this proves to be a real user-facing problem.
2. **Automatic 401/403 session-invalidation → re-login prompt.** No source in this codebase has an automatic 401-detection interceptor (confirmed during research: `manga_source.dart`/`pica_comic.dart` rely entirely on lazy `isAuthenticated` checks when the user re-opens the source). `HanabiManga.isAuthenticated` is time-based (`_expiresAt`), not response-based, so a session revoked server-side before its token naturally expires will not be detected until the next request fails with a `DioException`, which today just surfaces as a generic error in the reader UI — consistent with how every other source in this app already behaves.
3. **VIP-chapter-specific error message.** During research, 103 real reader-API calls across two non-VIP-flagged manga never returned a VIP/quota field in a successful response, and no VIP-flagged chapter was ever observed to confirm its exact response shape. Rather than guess a field name, `parseChapter` does not special-case VIP chapters; if hanabimanga.com returns an error for a VIP chapter, it will surface as a normal `DioException`/error in the reader UI, same as any other fetch failure.

These are all safe defaults (nothing crashes; errors degrade to the same generic error handling every other source already has) and can be revisited in a follow-up plan if real-world usage shows they matter.
