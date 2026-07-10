import 'webview_fetcher.dart';

/// No-op [WebViewFetcher] used on web and unsupported platforms.
///
/// On web, Cloudflare-protected sources fall back to the Dio + CORS-proxy path
/// and the manual cookie-paste flow, so WebView-mediated fetch is unavailable.
class _StubWebViewFetcher implements WebViewFetcher {
  @override
  bool get isSupported => false;

  @override
  Future<void> warmUp({
    required String sourceId,
    required String cloudflareUrl,
    String? userAgent,
  }) async {}

  @override
  Future<WebViewFetchResult> fetch({
    required String sourceId,
    required String cloudflareUrl,
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    String? userAgent,
    bool binary = false,
    bool renderMode = false,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnsupportedError(
      'WebViewFetcher is not supported on this platform',
    );
  }

  @override
  Future<void> dispose() async {}
}

WebViewFetcher createWebViewFetcher() => _StubWebViewFetcher();
