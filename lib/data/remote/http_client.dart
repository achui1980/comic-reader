import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/webview_fetcher.dart';

/// HTTP client wrapper around Dio for making network requests.
class HttpClient {
  final Dio _dio;

  /// Optional WebView-based fetcher for Cloudflare-protected sources that
  /// require the browser's TLS/JA3 fingerprint. When a request's
  /// `extra['useWebViewFetch']` is true and the fetcher is supported on this
  /// platform, the request is issued through the WebView instead of Dio.
  final WebViewFetcher? _webViewFetcher;

  HttpClient({Dio? dio, WebViewFetcher? webViewFetcher})
      : _dio = dio ?? Dio(),
        _webViewFetcher = webViewFetcher {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 15);
  }

  /// Execute a request based on FetchConfig
  Future<Response> execute(FetchConfig config) async {
    // Route through the WebView engine when the source requires it (e.g.
    // Cloudflare JA3-bound protection) and the platform supports it.
    if (_shouldUseWebView(config)) {
      return _executeViaWebView(config);
    }

    final options = Options(
      method: config.method == HttpMethod.get ? 'GET' : 'POST',
      headers: config.headers,
      receiveTimeout: config.timeout,
      sendTimeout: config.timeout,
      extra: config.extra,
      responseType: config.responseType,
    );

    return _dio.request(
      config.url,
      data: config.body,
      queryParameters: config.queryParameters,
      options: options,
    );
  }

  bool _shouldUseWebView(FetchConfig config) {
    final fetcher = _webViewFetcher;
    if (fetcher == null || !fetcher.isSupported) return false;
    final extra = config.extra;
    if (extra == null) return false;
    return extra['useWebViewFetch'] == true &&
        (extra['cloudflareUrl'] is String);
  }

  Future<Response> _executeViaWebView(FetchConfig config) async {
    final fetcher = _webViewFetcher!;
    final extra = config.extra!;
    final sourceId = (extra['sourceId'] as String?) ?? '';
    final cloudflareUrl = extra['cloudflareUrl'] as String;

    // Build the fully-resolved URL including query parameters so the WebView
    // fetch hits the same endpoint Dio would have.
    final resolvedUrl = _resolveUrl(config);

    final headers = <String, String>{};
    config.headers?.forEach((k, v) {
      // The WebView sets its own User-Agent/Referer/Cookie via the page
      // context; forbidden fetch headers are dropped by the browser anyway.
      headers[k] = v.toString();
    });

    final userAgent = headers['User-Agent'] ?? headers['user-agent'];

    final wantsBytes = config.responseType == ResponseType.bytes;

    final result = await fetcher.fetch(
      sourceId: sourceId,
      cloudflareUrl: cloudflareUrl,
      url: resolvedUrl,
      method: config.method == HttpMethod.get ? 'GET' : 'POST',
      headers: headers,
      body: config.body?.toString(),
      userAgent: userAgent,
      binary: wantsBytes,
      timeout: config.timeout ?? const Duration(seconds: 30),
    );

    final requestOptions = RequestOptions(
      path: resolvedUrl,
      method: config.method == HttpMethod.get ? 'GET' : 'POST',
      extra: extra,
      responseType: config.responseType,
    );

    dynamic data;
    if (wantsBytes) {
      data = Uint8List.fromList(result.bytes ?? const <int>[]);
    } else if (config.responseType == ResponseType.json) {
      // Leave as string; callers in this project parse strings themselves.
      data = result.body;
    } else {
      data = result.body;
    }

    final response = Response(
      requestOptions: requestOptions,
      statusCode: result.statusCode,
      data: data,
      headers: Headers.fromMap({
        if (result.contentType != null)
          Headers.contentTypeHeader: [result.contentType!],
      }),
    );

    // Preserve Dio's error semantics so interceptors (e.g. Cloudflare
    // detection) and callers see non-2xx as failures.
    if (result.statusCode < 200 || result.statusCode >= 400) {
      throw DioException(
        requestOptions: requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'WebView fetch returned status ${result.statusCode}',
      );
    }

    return response;
  }

  String _resolveUrl(FetchConfig config) {
    final qp = config.queryParameters;
    if (qp == null || qp.isEmpty) return config.url;
    final uri = Uri.parse(config.url);
    final merged = <String, dynamic>{...uri.queryParameters, ...qp};
    return uri
        .replace(
          queryParameters: merged.map((k, v) => MapEntry(k, v.toString())),
        )
        .toString();
  }

  /// Add an interceptor
  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// Get the underlying Dio instance (for testing)
  Dio get dio => _dio;
}
