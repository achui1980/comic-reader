import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Interceptor that routes requests through a CORS proxy when running on web.
///
/// On native platforms (iOS/Android/macOS), this interceptor does nothing.
/// On web, it prepends a proxy URL to bypass CORS restrictions.
///
/// Forbidden headers (User-Agent, Host, etc.) are moved to X-Proxy-* headers
/// so the CORS proxy can restore them before forwarding the request.
class CorsProxyInterceptor extends Interceptor {
  /// The CORS proxy base URL.
  /// Default uses a local proxy at localhost:9090.
  final String proxyBaseUrl;

  CorsProxyInterceptor({
    this.proxyBaseUrl = 'http://localhost:9090/',
  });

  /// Headers that browsers refuse to set on XMLHttpRequest/fetch.
  /// We move these to X-Proxy-* so the proxy can restore them.
  static const _forbiddenHeaders = {
    'user-agent',
    'host',
    'origin',
    'referer',
    'cookie',
    'connection',
    'content-length',
    'accept-encoding',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kIsWeb) {
      // Prepend the CORS proxy URL
      final originalUrl = options.uri.toString();
      options.path = '$proxyBaseUrl$originalUrl';

      // Move forbidden headers to X-Proxy-* so the proxy can restore them.
      final toRemove = <String>[];
      final toAdd = <String, dynamic>{};
      for (final entry in options.headers.entries) {
        if (_forbiddenHeaders.contains(entry.key.toLowerCase())) {
          toRemove.add(entry.key);
          // Only preserve user-agent and referer - proxy needs these
          if (entry.key.toLowerCase() == 'user-agent') {
            toAdd['X-Proxy-User-Agent'] = entry.value;
          } else if (entry.key.toLowerCase() == 'referer') {
            toAdd['X-Proxy-Referer'] = entry.value;
          }
        }
      }
      for (final key in toRemove) {
        options.headers.remove(key);
      }
      options.headers.addAll(toAdd);
    }
    handler.next(options);
  }
}
