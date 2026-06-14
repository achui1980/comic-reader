import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Interceptor that routes requests through a CORS proxy when running on web.
///
/// On native platforms (iOS/Android/macOS), this interceptor does nothing.
/// On web, it prepends a proxy URL to bypass CORS restrictions.
class CorsProxyInterceptor extends Interceptor {
  /// The CORS proxy base URL.
  /// Default uses a local proxy at localhost:9090.
  /// You can also use public proxies like 'https://corsproxy.io/?'
  final String proxyBaseUrl;

  CorsProxyInterceptor({
    this.proxyBaseUrl = 'http://localhost:9090/',
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kIsWeb) {
      // Prepend the CORS proxy URL
      final originalUrl = options.uri.toString();
      options.path = '$proxyBaseUrl$originalUrl';
      // Remove host-specific headers that cause issues with proxy
      options.headers.remove('host');
    }
    handler.next(options);
  }
}
