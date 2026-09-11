import 'dart:convert' show base64Encode;
import 'dart:typed_data';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/reader/widgets/manga_image_loader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _MockHttpClient extends Mock implements HttpClient {}

void main() {
  late _MockHttpClient httpClient;

  setUpAll(() {
    registerFallbackValue(const FetchConfig(url: ''));
  });

  setUp(() {
    httpClient = _MockHttpClient();
    if (GetIt.instance.isRegistered<HttpClient>()) {
      GetIt.instance.unregister<HttpClient>();
    }
    GetIt.instance.registerSingleton<HttpClient>(httpClient);
  });

  tearDown(() {
    if (GetIt.instance.isRegistered<HttpClient>()) {
      GetIt.instance.unregister<HttpClient>();
    }
  });

  group('loadAndCacheImageBytes with a data: URI', () {
    test('decodes locally and never calls HttpClient.execute', () async {
      final originalBytes = Uint8List.fromList([1, 2, 3, 4, 5, 250, 251, 252]);
      final dataUri = 'data:image/png;base64,${base64Encode(originalBytes)}';
      final image = ChapterImage(url: dataUri, scrambleType: ScrambleType.none);

      final result = await loadAndCacheImageBytes(image: image);

      expect(result, equals(originalBytes));
      verifyNever(() => httpClient.execute(any()));
    });

    test('rejects a malformed data: URI with no comma separator', () async {
      final image = ChapterImage(
        url: 'data:image/png;base64',
        scrambleType: ScrambleType.none,
      );

      await expectLater(
        loadAndCacheImageBytes(image: image),
        throwsA(isA<FormatException>()),
      );
      verifyNever(() => httpClient.execute(any()));
    });
  });

  group('loadAndCacheImageBytes with a network URL (regression check)', () {
    test('still goes through HttpClient.execute as before', () async {
      final bytes = Uint8List.fromList([9, 9, 9]);
      when(() => httpClient.execute(any())).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: 'https://example.com/a.jpg'),
          data: bytes,
          statusCode: 200,
        ),
      );
      final image = ChapterImage(
        url: 'https://example.com/a.jpg',
        scrambleType: ScrambleType.none,
      );

      final result = await loadAndCacheImageBytes(image: image);

      expect(result, equals(bytes));
      verify(() => httpClient.execute(any())).called(1);
    });
  });
}
