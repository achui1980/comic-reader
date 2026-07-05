import 'webview_fetcher_stub.dart'
    if (dart.library.io) 'webview_fetcher_native.dart' as impl;

/// Result of a WebView-mediated fetch.
class WebViewFetchResult {
  final int statusCode;

  /// Decoded text body (for HTML/JSON responses).
  final String? body;

  /// Raw bytes (for binary responses such as images).
  final List<int>? bytes;

  /// Content-Type reported by the response, if any.
  final String? contentType;

  const WebViewFetchResult({
    required this.statusCode,
    this.body,
    this.bytes,
    this.contentType,
  });
}

/// Abstraction for issuing HTTP requests through an on-device WebView engine
/// so that the request reuses the browser's real TLS/JA3 fingerprint and the
/// already-passed Cloudflare session.
///
/// Native platforms use a headless InAppWebView; web and unsupported platforms
/// use a no-op stub (see [createWebViewFetcher]).
abstract class WebViewFetcher {
  /// Whether this fetcher is functional on the current platform.
  bool get isSupported;

  /// Ensure the WebView is running and has navigated to [cloudflareUrl] so the
  /// Cloudflare session is active. Safe to call repeatedly.
  Future<void> warmUp({
    required String sourceId,
    required String cloudflareUrl,
    String? userAgent,
  });

  /// Perform a fetch inside the WebView.
  ///
  /// [binary] true means the response should be returned as raw bytes
  /// (used for images); otherwise the decoded text body is returned.
  Future<WebViewFetchResult> fetch({
    required String sourceId,
    required String cloudflareUrl,
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    String? userAgent,
    bool binary = false,
    Duration timeout = const Duration(seconds: 30),
  });

  /// Release resources held by the fetcher.
  Future<void> dispose();
}

/// Create the platform-appropriate [WebViewFetcher].
WebViewFetcher createWebViewFetcher() => impl.createWebViewFetcher();
