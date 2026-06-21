import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Logging interceptor for HTTP requests.
class SourceInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final sourceId = options.extra['sourceId'] ?? '';
    final cookie = options.headers['Cookie'] ?? options.headers['cookie'] ?? '';
    final ua = options.headers['User-Agent'] ?? options.headers['user-agent'] ?? '';
    debugPrint('[HTTP] → ${options.method} ${options.uri} (source=$sourceId)');
    if (cookie.toString().isNotEmpty) {
      final cookiePreview = cookie.toString().length > 60
          ? '${cookie.toString().substring(0, 60)}...'
          : cookie.toString();
      debugPrint('[HTTP]   Cookie: $cookiePreview');
    } else {
      debugPrint('[HTTP]   Cookie: (none)');
    }
    if (ua.toString().isNotEmpty) {
      debugPrint('[HTTP]   UA: ${ua.toString().substring(0, ua.toString().length > 50 ? 50 : ua.toString().length)}...');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('[HTTP] ← ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('[HTTP] ✗ ${err.type}: ${err.message} ${err.requestOptions.uri}');
    if (err.response != null) {
      debugPrint('[HTTP]   status=${err.response?.statusCode}');
    }
    handler.next(err);
  }
}
