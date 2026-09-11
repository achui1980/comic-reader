import 'dart:convert';
import 'dart:io';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/repositories/fetch_pipeline.dart';
import 'package:comic_reader/data/repositories/hanabi_chapter_decryptor.dart';
import 'package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements HttpClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(const FetchConfig(url: ''));
  });

  test('decrypt downloads, unscrambles via wasm, and returns a data: URI image', () async {
    final scrambledBytes =
        await File('test/fixtures/hanabi/scrambled_page001.webp').readAsBytes();
    final wasmBytes = await File('test/fixtures/hanabi/reader.wasm').readAsBytes();

    final mockHttpClient = MockHttpClient();
    when(() => mockHttpClient.execute(any())).thenAnswer(
      (_) async => Response(
        data: scrambledBytes,
        requestOptions: RequestOptions(path: 'https://cdn.hanabimanga.top/fake.webp'),
        statusCode: 200,
      ),
    );

    final pipeline = FetchPipeline(mockHttpClient);
    final unscrambler = HanabiWasmUnscrambler();
    await unscrambler.ensureLoaded(wasmBytesOverride: wasmBytes);
    final decryptor = HanabiChapterDecryptor(mockHttpClient, pipeline, unscrambler);
    final source = HanabiManga();

    const input = ChapterImage(
      url: 'https://cdn.hanabimanga.top/fake.webp',
      scrambleType: ScrambleType.hanabi,
      hanabiTicket: 'Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=',
      hanabiNonce: 'ZkfsVQTteF2Ab4Ha',
      hanabiCols: 4,
      hanabiRows: 4,
    );

    final result = await decryptor.decrypt(input, source);

    expect(result.scrambleType, ScrambleType.none);
    expect(result.url.startsWith('data:image/png;base64,'), isTrue);

    final base64Data = result.url.substring('data:image/png;base64,'.length);
    final pngBytes = base64Decode(base64Data);
    final decodedPng = img.decodeImage(pngBytes)!;
    final rgba = decodedPng.getBytes(order: img.ChannelOrder.rgba);
    final hash = sha256.convert(rgba).toString();

    // This is the ORIGINAL libwebp/Pillow-derived ground-truth hash from the
    // source-reversing diagnostic. The decryptor used to produce
    // `410f8598a9...` instead, because it decoded the WebP with
    // package:image's pure-Dart decoder, which is not bit-exact with libwebp
    // for lossy WebP (~1.5% of pixels off by small rounding amounts). Now
    // that decoding goes through `dart:ui` (Skia -> libwebp), the pipeline
    // reproduces the reference decode bit-exactly, so this assertion is real
    // external ground truth again rather than a self-consistency check.
    // The PNG round-trip above is lossless, so it does not affect the hash.
    expect(
      hash,
      '9735c728f504471ec4fc654752591901377c710801b9f96ad51d996afd0233e1',
    );
  });

  test(
    'decrypt persists the decrypted page to the chapter cache, returns a '
    'file:// URI, and serves a repeat request from disk without re-fetching '
    'or re-running the wasm unscrambler',
    () async {
      final scrambledBytes =
          await File('test/fixtures/hanabi/scrambled_page001.webp').readAsBytes();
      final wasmBytes = await File('test/fixtures/hanabi/reader.wasm').readAsBytes();

      final tempDir = await Directory.systemTemp.createTemp('hanabi_cache_test');
      ChapterCacheService.customDownloadDirectory = tempDir.path;
      addTearDown(() {
        ChapterCacheService.customDownloadDirectory = null;
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final mockHttpClient = MockHttpClient();
      when(() => mockHttpClient.execute(any())).thenAnswer(
        (_) async => Response(
          data: scrambledBytes,
          requestOptions: RequestOptions(path: 'https://cdn.hanabimanga.top/fake.webp'),
          statusCode: 200,
        ),
      );

      final pipeline = FetchPipeline(mockHttpClient);
      final unscrambler = HanabiWasmUnscrambler();
      await unscrambler.ensureLoaded(wasmBytesOverride: wasmBytes);
      final decryptor = HanabiChapterDecryptor(
        mockHttpClient,
        pipeline,
        unscrambler,
        ChapterCacheService(),
      );
      final source = HanabiManga();

      const input = ChapterImage(
        url: 'https://cdn.hanabimanga.top/fake.webp',
        scrambleType: ScrambleType.hanabi,
        hanabiTicket: 'Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=',
        hanabiNonce: 'ZkfsVQTteF2Ab4Ha',
        hanabiCols: 4,
        hanabiRows: 4,
      );

      final first = await decryptor.decrypt(
        input,
        source,
        mangaId: '3361',
        chapterId: 'chapter-1',
        imageIndex: 0,
      );

      expect(first.scrambleType, ScrambleType.none);
      expect(
        first.url.startsWith('file://'),
        isTrue,
        reason: 'expected a cached-file URI, got ${first.url.substring(0, 40)}',
      );
      final cachedFile = File(Uri.parse(first.url).toFilePath());
      expect(cachedFile.existsSync(), isTrue);

      // The bytes on disk must be the DECRYPTED page, not the scrambled
      // download. Verified against the same libwebp-derived ground truth as
      // the test above.
      final cachedRgba = img
          .decodeImage(await cachedFile.readAsBytes())!
          .getBytes(order: img.ChannelOrder.rgba);
      expect(
        sha256.convert(cachedRgba).toString(),
        '9735c728f504471ec4fc654752591901377c710801b9f96ad51d996afd0233e1',
      );

      verify(() => mockHttpClient.execute(any())).called(1);

      // Second request for the same page: must short-circuit on the cache
      // hit (no CDN round-trip, no decode/unscramble/encode work at all).
      final second = await decryptor.decrypt(
        input,
        source,
        mangaId: '3361',
        chapterId: 'chapter-1',
        imageIndex: 0,
      );

      expect(second.url, first.url);
      expect(second.scrambleType, ScrambleType.none);
      verifyNever(() => mockHttpClient.execute(any()));
    },
  );

  test('decrypt returns the original image unchanged when scrambleType is not hanabi', () async {
    final mockHttpClient = MockHttpClient();
    final pipeline = FetchPipeline(mockHttpClient);
    final decryptor = HanabiChapterDecryptor(mockHttpClient, pipeline);
    final source = HanabiManga();

    const input = ChapterImage(url: 'https://cdn.hanabimanga.top/plain.jpg');
    final result = await decryptor.decrypt(input, source);

    expect(result, input);
    verifyNever(() => mockHttpClient.execute(any()));
  });
}
