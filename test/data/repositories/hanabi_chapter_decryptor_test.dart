import 'dart:convert';
import 'dart:io';

import 'package:comic_reader/core/models/fetch_config.dart';
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

    // NOTE: this hash is derived from package:image's pure-Dart WebP
    // decoder output, which is not bit-exact with libwebp (the reference
    // decoder used to derive fixtures in earlier tasks). Re-derive this
    // value if the WebP fixture or the `image` package version changes.
    expect(
      hash,
      '410f8598a95efb975e3ce55f441b6fee551a6b9d049fedf8464e3eebb3cd29d3',
    );
  });

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
