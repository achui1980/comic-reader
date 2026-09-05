import 'package:comic_reader/data/remote/webview_fetcher.dart';
import 'package:comic_reader/data/remote/webview_fetcher_stub.dart' as stub;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('webview_fetcher_stub.createWebViewFetcher()', () {
    // NOTE: We deliberately import webview_fetcher_stub.dart directly rather
    // than going through the conditional-import entry point in
    // webview_fetcher.dart. Under a standard `flutter test` (Dart VM)
    // environment, the `dart.library.io` condition is satisfied, so the
    // conditional import resolves to webview_fetcher_native.dart (which
    // depends on flutter_inappwebview and is out of scope for unit tests).
    // Importing the stub file directly guarantees we're exercising the
    // actual no-op stub implementation.

    test('isSupported is false', () {
      final fetcher = stub.createWebViewFetcher();
      expect(fetcher.isSupported, isFalse);
    });

    test('warmUp completes without throwing (no-op)', () async {
      final fetcher = stub.createWebViewFetcher();
      await expectLater(
        fetcher.warmUp(sourceId: 'manga51', cloudflareUrl: 'https://example.com'),
        completes,
      );
    });

    test('fetch throws UnsupportedError', () {
      final fetcher = stub.createWebViewFetcher();
      // fetch() throws synchronously (its body is not `async`), so the call
      // must be wrapped in a closure rather than awaited directly -
      // otherwise the exception escapes before expectLater/throwsA can see it.
      expect(
        () => fetcher.fetch(
          sourceId: 'manga51',
          cloudflareUrl: 'https://example.com',
          url: 'https://example.com/api',
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('dispose completes without throwing (no-op)', () async {
      final fetcher = stub.createWebViewFetcher();
      await expectLater(fetcher.dispose(), completes);
    });

    test('createWebViewFetcher returns a WebViewFetcher', () {
      final fetcher = stub.createWebViewFetcher();
      expect(fetcher, isA<WebViewFetcher>());
    });
  });
}
