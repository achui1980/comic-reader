import 'package:comic_reader/data/remote/cloudflare_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockResponseInterceptorHandler extends Mock
    implements ResponseInterceptorHandler {}

class MockErrorInterceptorHandler extends Mock
    implements ErrorInterceptorHandler {}

Response<dynamic> _htmlResponse({
  required String body,
  String path = 'https://example.com/page',
  Map<String, dynamic>? extra,
  int statusCode = 200,
  String contentType = 'text/html; charset=utf-8',
}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path, extra: extra ?? {}),
    statusCode: statusCode,
    data: body,
    headers: Headers.fromMap({
      'content-type': [contentType],
    }),
  );
}

DioException _err403({
  required String path,
  required dynamic data,
  Map<String, dynamic>? extra,
  String contentType = 'text/html; charset=utf-8',
  int statusCode = 403,
}) {
  final requestOptions = RequestOptions(path: path, extra: extra ?? {});
  final response = Response<dynamic>(
    requestOptions: requestOptions,
    statusCode: statusCode,
    data: data,
    headers: Headers.fromMap({
      'content-type': [contentType],
    }),
  );
  return DioException(
    requestOptions: requestOptions,
    response: response,
    type: DioExceptionType.badResponse,
  );
}

void main() {
  late CloudflareDetectorInterceptor interceptor;

  setUpAll(() {
    registerFallbackValue(
      DioException(requestOptions: RequestOptions(path: '')),
    );
    registerFallbackValue(
      Response<dynamic>(requestOptions: RequestOptions(path: '')),
    );
  });

  setUp(() {
    interceptor = CloudflareDetectorInterceptor();
  });

  group('CloudflareDetectorInterceptor.onResponse', () {
    test('rejects when title is "Just a moment..."', () {
      final handler = MockResponseInterceptorHandler();
      final response = _htmlResponse(
        body: '<html><head><title>Just a moment...</title></head></html>',
        extra: {'sourceId': 'manga18'},
      );

      interceptor.onResponse(response, handler);

      final captured =
          verify(() => handler.reject(captureAny())).captured.single
              as DioException;
      expect(captured.error, isA<CloudflareException>());
      final cfEx = captured.error as CloudflareException;
      expect(cfEx.sourceId, 'manga18');
      expect(cfEx.url, response.requestOptions.uri.toString());
      verifyNever(() => handler.next(any()));
    });

    test('rejects when title is "Attention Required! | Cloudflare"', () {
      final handler = MockResponseInterceptorHandler();
      final response = _htmlResponse(
        body:
            '<html><head><title>Attention Required! | Cloudflare</title></head></html>',
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.reject(any())).called(1);
      verifyNever(() => handler.next(any()));
    });

    test('rejects when title is "403 Forbidden"', () {
      final handler = MockResponseInterceptorHandler();
      final response = _htmlResponse(
        body: '<html><head><title>403 Forbidden</title></head></html>',
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.reject(any())).called(1);
    });

    test('rejects when body contains challenges.cloudflare.com marker', () {
      final handler = MockResponseInterceptorHandler();
      final response = _htmlResponse(
        body:
            '<html><body><script src="https://challenges.cloudflare.com/turnstile/v0/api.js"></script></body></html>',
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.reject(any())).called(1);
    });

    test('rejects when body contains cf-browser-verification marker', () {
      final handler = MockResponseInterceptorHandler();
      final response = _htmlResponse(
        body: '<html><body><div id="cf-browser-verification"></div></body></html>',
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.reject(any())).called(1);
    });

    test('rejects when body contains cf_chl_opt marker', () {
      final handler = MockResponseInterceptorHandler();
      final response = _htmlResponse(
        body: '<html><body><script>var cf_chl_opt = {};</script></body></html>',
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.reject(any())).called(1);
    });

    test('passes through non-HTML content-type unchanged', () {
      final handler = MockResponseInterceptorHandler();
      final response = _htmlResponse(
        body: '{"ok": true}',
        contentType: 'application/json',
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.next(response)).called(1);
      verifyNever(() => handler.reject(any()));
    });

    test('passes through HTML without CF markers unchanged', () {
      final handler = MockResponseInterceptorHandler();
      final response = _htmlResponse(
        body: '<html><head><title>Manga Detail</title></head><body>hi</body></html>',
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.next(response)).called(1);
      verifyNever(() => handler.reject(any()));
    });

    test('passes through when content-type header is missing', () {
      final handler = MockResponseInterceptorHandler();
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: 'https://example.com'),
        statusCode: 200,
        data: '<html><title>Just a moment...</title></html>',
        headers: Headers(),
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.next(response)).called(1);
    });
  });

  group('CloudflareDetectorInterceptor.onError', () {
    test('rejects 403 with CF HTML body', () {
      final handler = MockErrorInterceptorHandler();
      final err = _err403(
        path: 'https://example.com/manga/1',
        data: '<html><title>Just a moment...</title></html>',
        extra: {'sourceId': 'manga51'},
      );

      interceptor.onError(err, handler);

      final captured =
          verify(() => handler.reject(captureAny())).captured.single
              as DioException;
      final cfEx = captured.error as CloudflareException;
      expect(cfEx.sourceId, 'manga51');
      expect(cfEx.url, err.requestOptions.uri.toString());
      verifyNever(() => handler.next(any()));
    });

    test(
        'rejects 403 with non-CF HTML body when source declares needsCloudflare',
        () {
      final handler = MockErrorInterceptorHandler();
      final err = _err403(
        path: 'https://example.com/manga/1',
        data: '<html><title>Some Other Page</title></html>',
        extra: {'sourceId': 'manga18', 'needsCloudflare': true},
      );

      interceptor.onError(err, handler);

      verify(() => handler.reject(any())).called(1);
      verifyNever(() => handler.next(any()));
    });

    test(
        'passes through 403 with non-CF HTML body when needsCloudflare is not set',
        () {
      final handler = MockErrorInterceptorHandler();
      final err = _err403(
        path: 'https://example.com/manga/1',
        data: '<html><title>Some Other Page</title></html>',
        extra: {'sourceId': 'manga18'},
      );

      interceptor.onError(err, handler);

      verify(() => handler.next(err)).called(1);
      verifyNever(() => handler.reject(any()));
    });

    test('rejects 403 with non-HTML body when source declares needsCloudflare', () {
      final handler = MockErrorInterceptorHandler();
      final err = _err403(
        path: 'https://example.com/api/1',
        data: '{"error": "forbidden"}',
        contentType: 'application/json',
        extra: {'sourceId': 'manga18', 'needsCloudflare': true},
      );

      interceptor.onError(err, handler);

      verify(() => handler.reject(any())).called(1);
    });

    test(
        'passes through 403 with non-HTML body when needsCloudflare is false',
        () {
      final handler = MockErrorInterceptorHandler();
      final err = _err403(
        path: 'https://example.com/api/1',
        data: '{"error": "forbidden"}',
        contentType: 'application/json',
        extra: {'sourceId': 'manga18', 'needsCloudflare': false},
      );

      interceptor.onError(err, handler);

      verify(() => handler.next(err)).called(1);
      verifyNever(() => handler.reject(any()));
    });

    test('passes through non-403 errors unchanged', () {
      final handler = MockErrorInterceptorHandler();
      final err = _err403(
        path: 'https://example.com/manga/1',
        data: '<html><title>Just a moment...</title></html>',
        statusCode: 500,
        extra: {'sourceId': 'manga18', 'needsCloudflare': true},
      );

      interceptor.onError(err, handler);

      verify(() => handler.next(err)).called(1);
      verifyNever(() => handler.reject(any()));
    });

    test('passes through when err.response is null', () {
      final handler = MockErrorInterceptorHandler();
      final requestOptions = RequestOptions(path: 'https://example.com');
      final err = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionError,
      );

      interceptor.onError(err, handler);

      verify(() => handler.next(err)).called(1);
      verifyNever(() => handler.reject(any()));
    });
  });
}
