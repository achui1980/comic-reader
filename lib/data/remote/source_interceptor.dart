import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

/// Logging interceptor for HTTP requests.
class SourceInterceptor extends Interceptor {
  final _log = Logger('HttpClient');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _log.fine('\u2192 ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log.fine('\u2190 ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log.warning('\u2717 ${err.type}: ${err.message} ${err.requestOptions.uri}');
    handler.next(err);
  }
}
