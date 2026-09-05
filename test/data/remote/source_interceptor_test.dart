import 'package:comic_reader/data/remote/source_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRequestInterceptorHandler extends Mock
    implements RequestInterceptorHandler {}

class MockResponseInterceptorHandler extends Mock
    implements ResponseInterceptorHandler {}

class MockErrorInterceptorHandler extends Mock
    implements ErrorInterceptorHandler {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Response<dynamic>(requestOptions: RequestOptions(path: '')));
    registerFallbackValue(DioException(requestOptions: RequestOptions(path: '')));
  });

  late SourceInterceptor interceptor;

  setUp(() {
    interceptor = SourceInterceptor();
  });

  group('SourceInterceptor (pure pass-through logging)', () {
    test('onRequest forwards the same options unmodified via handler.next', () {
      final handler = MockRequestInterceptorHandler();
      final options = RequestOptions(
        path: 'https://example.com/x',
        extra: {'sourceId': 'manga51'},
        headers: {'Cookie': 'session=abc', 'User-Agent': 'TestAgent/1.0'},
      );

      interceptor.onRequest(options, handler);

      verify(() => handler.next(options)).called(1);
      // Object identity must be preserved: the interceptor must not clone
      // or mutate the request on its way through.
      expect(options.headers['Cookie'], 'session=abc');
      expect(options.headers['User-Agent'], 'TestAgent/1.0');
      expect(options.extra['sourceId'], 'manga51');
    });

    test('onRequest does not throw when cookie/UA/sourceId are absent', () {
      final handler = MockRequestInterceptorHandler();
      final options = RequestOptions(path: 'https://example.com/x');

      expect(() => interceptor.onRequest(options, handler), returnsNormally);
      verify(() => handler.next(options)).called(1);
    });

    test('onResponse forwards the same response unmodified via handler.next', () {
      final handler = MockResponseInterceptorHandler();
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: 'https://example.com/x'),
        statusCode: 200,
        data: 'body',
      );

      interceptor.onResponse(response, handler);

      verify(() => handler.next(response)).called(1);
      expect(response.data, 'body');
    });

    test('onError forwards the same error unmodified via handler.next', () {
      final handler = MockErrorInterceptorHandler();
      final err = DioException(
        requestOptions: RequestOptions(path: 'https://example.com/x'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: 'https://example.com/x'),
          statusCode: 403,
        ),
      );

      interceptor.onError(err, handler);

      verify(() => handler.next(err)).called(1);
    });

    test('onError does not throw when err.response is null', () {
      final handler = MockErrorInterceptorHandler();
      final err = DioException(
        requestOptions: RequestOptions(path: 'https://example.com/x'),
        type: DioExceptionType.connectionError,
      );

      expect(() => interceptor.onError(err, handler), returnsNormally);
      verify(() => handler.next(err)).called(1);
    });
  });
}
