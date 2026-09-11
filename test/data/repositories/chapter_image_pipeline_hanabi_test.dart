import 'dart:convert';
import 'dart:io';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/repositories/chapter_image_pipeline.dart';
import 'package:comic_reader/data/repositories/fetch_pipeline.dart';
import 'package:comic_reader/data/repositories/hanabi_chapter_decryptor.dart';
import 'package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart';
import 'package:comic_reader/data/repositories/wu55_chapter_decryptor.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements HttpClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(const FetchConfig(url: ''));
  });

  test(
    'ChapterImagePipeline.getChapter runs a HanabiManga chapter fetch '
    'through the real decryptor+unscrambler end-to-end',
    () async {
      const readerApiUrl =
          'https://web.hanabimanga.com/api/reader/comic/3361/chapter-1';
      const cdnUrl = 'https://cdn.hanabimanga.top/a/001.webp';

      final wasmBytes = await File('test/fixtures/hanabi/reader.wasm').readAsBytes();
      final scrambledBytes =
          await File('test/fixtures/hanabi/scrambled_page001.webp').readAsBytes();

      final readerApiJson = jsonEncode({
        'chapter': {
          'comicId': 3361,
          'chapterSlug': 'chapter-1',
          'chapterId': 164145,
          'title': '第01话',
          'idx': 1,
          'totalPages': 1,
        },
        'pages': [
          {'index': 0, 'page': '001', 'url': cdnUrl},
        ],
        'metadata': {
          'expiresIn': 7200,
          'scrambleInfo': {
            'ticket': 'Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=',
            'nonce': 'ZkfsVQTteF2Ab4Ha',
            'cols': 4,
            'rows': 4,
          },
        },
      });

      final mockHttpClient = MockHttpClient();
      // Route by URL: the reader-API manifest request gets the hand-written
      // JSON above; anything else (the CDN scrambled-image download) gets
      // the real fixture webp bytes -- mocking only the network, letting
      // the real HanabiChapterDecryptor + HanabiWasmUnscrambler run against
      // real fixture data for the rest of the pipeline.
      when(() => mockHttpClient.execute(any())).thenAnswer((invocation) async {
        final config = invocation.positionalArguments.first as FetchConfig;
        if (config.url == readerApiUrl) {
          return Response(
            data: readerApiJson,
            requestOptions: RequestOptions(path: config.url),
            statusCode: 200,
          );
        }
        return Response(
          data: scrambledBytes,
          requestOptions: RequestOptions(path: config.url),
          statusCode: 200,
        );
      });

      final pipeline = FetchPipeline(mockHttpClient);
      final unscrambler = HanabiWasmUnscrambler();
      await unscrambler.ensureLoaded(wasmBytesOverride: wasmBytes);
      final hanabiDecryptor = HanabiChapterDecryptor(mockHttpClient, pipeline, unscrambler);
      final wu55Decryptor = Wu55ChapterDecryptor(mockHttpClient, pipeline);

      final chapterPipeline = ChapterImagePipeline(
        mockHttpClient,
        pipeline,
        wu55Decryptor,
        hanabiDecryptor,
      );

      final source = HanabiManga();

      final result = await chapterPipeline.getChapter('3361', 'chapter-1', 1, source);

      expect(result.chapter.title, '第01话');
      expect(result.chapter.images.length, 1);
      for (final image in result.chapter.images) {
        expect(image.scrambleType, ScrambleType.none);
        expect(image.url.startsWith('data:image/png;base64,'), isTrue);
      }
    },
  );
}
