import 'package:comic_reader/data/remote/cors_proxy_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRequestInterceptorHandler extends Mock
    implements RequestInterceptorHandler {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
  });

  late MockRequestInterceptorHandler handler;

  setUp(() {
    handler = MockRequestInterceptorHandler();
  });

  group('CorsProxyInterceptor (isWeb: false, default production behavior)', () {
    test('does not modify the request and calls handler.next', () {
      final interceptor = CorsProxyInterceptor(isWeb: false);
      final options = RequestOptions(
        path: 'https://example.com/api',
        queryParameters: {'q': 'manga'},
        headers: {'User-Agent': 'Dalvik/2.1', 'Accept': 'application/json'},
      );

      interceptor.onRequest(options, handler);

      expect(options.path, 'https://example.com/api');
      expect(options.queryParameters, {'q': 'manga'});
      expect(options.headers['User-Agent'], 'Dalvik/2.1');
      expect(options.headers['Accept'], 'application/json');
      verify(() => handler.next(options)).called(1);
    });
  });

  group('CorsProxyInterceptor (isWeb: true)', () {
    test('rewrites path to proxyBaseUrl + full original url with query', () {
      final interceptor = CorsProxyInterceptor(isWeb: true);
      final options = RequestOptions(
        baseUrl: 'https://example.com',
        path: '/api/manga',
        queryParameters: {'page': '1'},
      );

      interceptor.onRequest(options, handler);

      expect(
        options.path,
        'http://localhost:9090/https://example.com/api/manga?page=1',
      );
      verify(() => handler.next(options)).called(1);
    });

    test('clears queryParameters and baseUrl since they are encoded in path', () {
      final interceptor = CorsProxyInterceptor(isWeb: true);
      final options = RequestOptions(
        baseUrl: 'https://example.com',
        path: '/api/manga',
        queryParameters: {'page': '1'},
      );

      interceptor.onRequest(options, handler);

      expect(options.queryParameters, isEmpty);
      expect(options.baseUrl, '');
    });

    test('uses a custom proxyBaseUrl when provided', () {
      final interceptor = CorsProxyInterceptor(
        isWeb: true,
        proxyBaseUrl: 'https://my-proxy.example.org/',
      );
      final options = RequestOptions(path: 'https://example.com/x');

      interceptor.onRequest(options, handler);

      expect(
        options.path,
        'https://my-proxy.example.org/https://example.com/x',
      );
    });

    test(
      'moves user-agent, referer, and cookie to X-Proxy-* headers and removes originals',
      () {
        final interceptor = CorsProxyInterceptor(isWeb: true);
        final options = RequestOptions(
          path: 'https://example.com/x',
          headers: {
            'User-Agent': 'MyBrowser/1.0',
            'Referer': 'https://example.com/',
            'Cookie': 'session=abc123',
          },
        );

        interceptor.onRequest(options, handler);

        expect(options.headers.containsKey('User-Agent'), isFalse);
        expect(options.headers.containsKey('Referer'), isFalse);
        expect(options.headers.containsKey('Cookie'), isFalse);
        expect(options.headers['X-Proxy-User-Agent'], 'MyBrowser/1.0');
        expect(options.headers['X-Proxy-Referer'], 'https://example.com/');
        expect(options.headers['X-Proxy-Cookie'], 'session=abc123');
      },
    );

    test(
      'removes host/origin/connection/content-length/accept-encoding without adding X-Proxy-* replacements',
      () {
        final interceptor = CorsProxyInterceptor(isWeb: true);
        final options = RequestOptions(
          path: 'https://example.com/x',
          headers: {
            'Host': 'example.com',
            'Origin': 'https://example.com',
            'Connection': 'keep-alive',
            'Content-Length': '42',
            'Accept-Encoding': 'gzip',
          },
        );

        interceptor.onRequest(options, handler);

        expect(options.headers.containsKey('Host'), isFalse);
        expect(options.headers.containsKey('Origin'), isFalse);
        expect(options.headers.containsKey('Connection'), isFalse);
        expect(options.headers.containsKey('Content-Length'), isFalse);
        expect(options.headers.containsKey('Accept-Encoding'), isFalse);
        expect(
          options.headers.keys.where((k) => k.startsWith('X-Proxy-')),
          isEmpty,
        );
      },
    );

    test('leaves non-forbidden headers untouched', () {
      final interceptor = CorsProxyInterceptor(isWeb: true);
      final options = RequestOptions(
        path: 'https://example.com/x',
        headers: {'Accept': 'application/json', 'X-Custom': 'value'},
      );

      interceptor.onRequest(options, handler);

      expect(options.headers['Accept'], 'application/json');
      expect(options.headers['X-Custom'], 'value');
    });

    test('forbidden header matching is case-insensitive', () {
      final interceptor = CorsProxyInterceptor(isWeb: true);
      final options = RequestOptions(
        path: 'https://example.com/x',
        headers: {'user-agent': 'lowercase-ua'},
      );

      interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('user-agent'), isFalse);
      expect(options.headers['X-Proxy-User-Agent'], 'lowercase-ua');
    });
  });
}
