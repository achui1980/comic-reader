import 'dart:typed_data';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/remote/webview_fetcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

class MockWebViewFetcher extends Mock implements WebViewFetcher {}

Response<dynamic> _fakeResponse({int? statusCode = 200, dynamic data}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: 'https://example.com'),
    statusCode: statusCode,
    data: data,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    when(() => mockDio.options).thenReturn(BaseOptions());
    when(() => mockDio.interceptors).thenReturn(Interceptors());
  });

  void stubDioRequest({dynamic data, int? statusCode = 200}) {
    when(() => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        )).thenAnswer((_) async => _fakeResponse(data: data, statusCode: statusCode));
  }

  group('HttpClient.execute (Dio path)', () {
    test('sends a GET request by default and returns the Dio response', () async {
      final client = HttpClient(dio: mockDio);
      stubDioRequest(data: 'ok');

      final response =
          await client.execute(const FetchConfig(url: 'https://example.com/api'));

      expect(response.data, 'ok');
      final captured = verify(() => mockDio.request<dynamic>(
            captureAny(),
            data: captureAny(named: 'data'),
            queryParameters: captureAny(named: 'queryParameters'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], 'https://example.com/api');
      final options = captured[3] as Options;
      expect(options.method, 'GET');
    });

    test('sends a POST request with the configured body', () async {
      final client = HttpClient(dio: mockDio);
      stubDioRequest();

      await client.execute(FetchConfig(
        url: 'https://example.com/api',
        method: HttpMethod.post,
        body: {'a': 1},
      ));

      final captured = verify(() => mockDio.request<dynamic>(
            captureAny(),
            data: captureAny(named: 'data'),
            queryParameters: captureAny(named: 'queryParameters'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[1], {'a': 1});
      final options = captured[3] as Options;
      expect(options.method, 'POST');
    });

    test('passes headers, extra, query parameters, and responseType through Options',
        () async {
      final client = HttpClient(dio: mockDio);
      stubDioRequest();

      await client.execute(FetchConfig(
        url: 'https://example.com/api',
        headers: {'X-Test': '1'},
        extra: {'foo': 'bar'},
        queryParameters: {'q': 'manga'},
        responseType: ResponseType.json,
      ));

      final captured = verify(() => mockDio.request<dynamic>(
            captureAny(),
            data: captureAny(named: 'data'),
            queryParameters: captureAny(named: 'queryParameters'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[2], {'q': 'manga'});
      final options = captured[3] as Options;
      expect(options.headers, {'X-Test': '1'});
      expect(options.extra, {'foo': 'bar'});
      expect(options.responseType, ResponseType.json);
    });
  });

  group('HttpClient.execute (WebView routing decision)', () {
    test('falls back to Dio when there is no WebViewFetcher', () async {
      final client = HttpClient(dio: mockDio);
      stubDioRequest();

      await client.execute(FetchConfig(
        url: 'https://example.com/api',
        extra: {'useWebViewFetch': true, 'cloudflareUrl': 'https://example.com'},
      ));

      verify(() => mockDio.request<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).called(1);
    });

    test('falls back to Dio when fetcher.isSupported is false', () async {
      final fetcher = MockWebViewFetcher();
      when(() => fetcher.isSupported).thenReturn(false);
      final client = HttpClient(dio: mockDio, webViewFetcher: fetcher);
      stubDioRequest();

      await client.execute(FetchConfig(
        url: 'https://example.com/api',
        extra: {'useWebViewFetch': true, 'cloudflareUrl': 'https://example.com'},
      ));

      verify(() => mockDio.request<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).called(1);
    });

    test('falls back to Dio when extra is missing useWebViewFetch/cloudflareUrl',
        () async {
      final fetcher = MockWebViewFetcher();
      when(() => fetcher.isSupported).thenReturn(true);
      final client = HttpClient(dio: mockDio, webViewFetcher: fetcher);
      stubDioRequest();

      // No extra at all.
      await client.execute(const FetchConfig(url: 'https://example.com/api'));
      // extra present but missing cloudflareUrl.
      await client.execute(FetchConfig(
        url: 'https://example.com/api',
        extra: {'useWebViewFetch': true},
      ));

      verify(() => mockDio.request<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).called(2);
    });
  });

  group('HttpClient.execute (WebView path)', () {
    void stubFetch(WebViewFetchResult result, MockWebViewFetcher fetcher) {
      when(() => fetcher.fetch(
            sourceId: any(named: 'sourceId'),
            cloudflareUrl: any(named: 'cloudflareUrl'),
            url: any(named: 'url'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            userAgent: any(named: 'userAgent'),
            binary: any(named: 'binary'),
            renderMode: any(named: 'renderMode'),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => result);
    }

    test('routes through the WebViewFetcher and maps a text response', () async {
      final fetcher = MockWebViewFetcher();
      when(() => fetcher.isSupported).thenReturn(true);
      stubFetch(
        const WebViewFetchResult(
          statusCode: 200,
          body: '<html>ok</html>',
          contentType: 'text/html',
        ),
        fetcher,
      );

      final client = HttpClient(dio: mockDio, webViewFetcher: fetcher);
      final response = await client.execute(FetchConfig(
        url: 'https://example.com/api?a=1',
        headers: {'User-Agent': 'test-ua'},
        extra: {
          'sourceId': 'my-source',
          'useWebViewFetch': true,
          'cloudflareUrl': 'https://example.com/cf',
        },
      ));

      expect(response.statusCode, 200);
      expect(response.data, '<html>ok</html>');

      // NOTE: mocktail's `captured` list order for many simultaneous
      // captureAny() calls in one verify() follows Dart's internal
      // Invocation.namedArguments grouping (required params first, then
      // params with a default value, then nullable params without a
      // default -- each group in declaration order) rather than the order
      // captureAny() was written. For fetch()'s signature that resolves to:
      // [sourceId, cloudflareUrl, url, method, binary, renderMode, timeout,
      //  headers, body, userAgent]. All assertions must be made from a
      // single verify() call since mocktail marks matched invocations as
      // "verified" and a second verify() on the same call finds no match.
      final captured = verify(() => fetcher.fetch(
            sourceId: captureAny(named: 'sourceId'),
            cloudflareUrl: captureAny(named: 'cloudflareUrl'),
            url: captureAny(named: 'url'),
            method: captureAny(named: 'method'),
            headers: captureAny(named: 'headers'),
            body: captureAny(named: 'body'),
            userAgent: captureAny(named: 'userAgent'),
            binary: captureAny(named: 'binary'),
            renderMode: captureAny(named: 'renderMode'),
            timeout: captureAny(named: 'timeout'),
          )).captured;
      expect(captured[0], 'my-source');
      expect(captured[1], 'https://example.com/cf');
      expect(captured[2], 'https://example.com/api?a=1');
      expect(captured[4], false, reason: 'binary'); // binary
      expect(captured[9], 'test-ua', reason: 'userAgent'); // userAgent
    });

    test('requests bytes and decodes them into Uint8List when responseType is bytes',
        () async {
      final fetcher = MockWebViewFetcher();
      when(() => fetcher.isSupported).thenReturn(true);
      stubFetch(
        const WebViewFetchResult(
          statusCode: 200,
          bytes: [1, 2, 3],
          contentType: 'image/png',
        ),
        fetcher,
      );

      final client = HttpClient(dio: mockDio, webViewFetcher: fetcher);
      final response = await client.execute(FetchConfig(
        url: 'https://example.com/img.png',
        responseType: ResponseType.bytes,
        extra: {
          'useWebViewFetch': true,
          'cloudflareUrl': 'https://example.com/cf',
        },
      ));

      expect(response.data, isA<Uint8List>());
      expect(response.data, [1, 2, 3]);

      final captured = verify(() => fetcher.fetch(
            sourceId: captureAny(named: 'sourceId'),
            cloudflareUrl: captureAny(named: 'cloudflareUrl'),
            url: captureAny(named: 'url'),
            method: captureAny(named: 'method'),
            headers: captureAny(named: 'headers'),
            body: captureAny(named: 'body'),
            userAgent: captureAny(named: 'userAgent'),
            binary: captureAny(named: 'binary'),
            renderMode: captureAny(named: 'renderMode'),
            timeout: captureAny(named: 'timeout'),
          )).captured;
      // See ordering note in the previous test: for this signature,
      // index 2 is url and index 4 is binary.
      expect(captured[2], 'https://example.com/img.png');
      expect(captured[4], true, reason: 'binary');
    });

    test('throws a badResponse DioException when the WebView status is outside 200-399',
        () async {
      final fetcher = MockWebViewFetcher();
      when(() => fetcher.isSupported).thenReturn(true);
      stubFetch(
        const WebViewFetchResult(statusCode: 403, body: 'forbidden'),
        fetcher,
      );

      final client = HttpClient(dio: mockDio, webViewFetcher: fetcher);

      await expectLater(
        client.execute(FetchConfig(
          url: 'https://example.com/api',
          extra: {
            'useWebViewFetch': true,
            'cloudflareUrl': 'https://example.com/cf',
          },
        )),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.badResponse)),
      );
    });

    test('merges existing query parameters with new ones without dropping repeated keys',
        () async {
      final fetcher = MockWebViewFetcher();
      when(() => fetcher.isSupported).thenReturn(true);
      stubFetch(
        const WebViewFetchResult(statusCode: 200, body: 'ok'),
        fetcher,
      );

      final client = HttpClient(dio: mockDio, webViewFetcher: fetcher);
      await client.execute(FetchConfig(
        url: 'https://example.com/api?includes[]=a&includes[]=b&page=1',
        queryParameters: {'page': 2},
        extra: {
          'useWebViewFetch': true,
          'cloudflareUrl': 'https://example.com/cf',
        },
      ));

      final captured = verify(() => fetcher.fetch(
            sourceId: any(named: 'sourceId'),
            cloudflareUrl: any(named: 'cloudflareUrl'),
            url: captureAny(named: 'url'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
            userAgent: any(named: 'userAgent'),
            binary: any(named: 'binary'),
            renderMode: any(named: 'renderMode'),
            timeout: any(named: 'timeout'),
          )).captured;
      final resolvedUri = Uri.parse(captured[0] as String);
      expect(resolvedUri.queryParametersAll['includes[]'], ['a', 'b']);
      expect(resolvedUri.queryParametersAll['page'], ['2']);
    });
  });

  group('HttpClient misc', () {
    test('addInterceptor forwards to the underlying Dio interceptors list', () {
      final interceptors = Interceptors();
      when(() => mockDio.interceptors).thenReturn(interceptors);
      final client = HttpClient(dio: mockDio);
      final interceptor = InterceptorsWrapper();

      client.addInterceptor(interceptor);

      expect(interceptors, contains(interceptor));
    });

    test('dio getter exposes the underlying Dio instance', () {
      final client = HttpClient(dio: mockDio);
      expect(client.dio, same(mockDio));
    });
  });
}
