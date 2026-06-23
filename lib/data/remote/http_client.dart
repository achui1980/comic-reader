import 'package:dio/dio.dart';
import 'package:comic_reader/core/models/fetch_config.dart';

/// HTTP client wrapper around Dio for making network requests.
class HttpClient {
  final Dio _dio;

  HttpClient({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 15);
  }

  /// Execute a request based on FetchConfig
  Future<Response> execute(FetchConfig config) async {
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

  /// Add an interceptor
  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// Get the underlying Dio instance (for testing)
  Dio get dio => _dio;
}
