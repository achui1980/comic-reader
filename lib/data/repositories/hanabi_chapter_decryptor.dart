import 'dart:convert';

import 'package:dio/dio.dart' show ResponseType;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/repositories/fetch_pipeline.dart';
import 'package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Downloads a scrambled hanabimanga.com CDN image, unscrambles it via the
/// official `/reader.wasm` module (see [HanabiWasmUnscrambler]), and returns
/// a `data:` URI image ready for direct rendering.
class HanabiChapterDecryptor {
  final HttpClient _httpClient;
  final FetchPipeline _pipeline;
  final HanabiWasmUnscrambler _unscrambler;

  HanabiChapterDecryptor(
    this._httpClient,
    this._pipeline, [
    HanabiWasmUnscrambler? unscrambler,
  ]) : _unscrambler = unscrambler ?? HanabiWasmUnscrambler();

  /// Decrypts [chapterImage] if it is scrambled (`ScrambleType.hanabi`).
  /// Returns the input unchanged for any other scramble type, or on
  /// failure (network error, decode error, or wasm error) — in the failure
  /// case the caller will attempt to render the original (still-scrambled)
  /// CDN URL, which will look garbled but at least won't crash the reader.
  Future<ChapterImage> decrypt(ChapterImage chapterImage, HanabiManga source) async {
    if (chapterImage.scrambleType != ScrambleType.hanabi) return chapterImage;

    final ticketB64 = chapterImage.hanabiTicket;
    final nonceB64 = chapterImage.hanabiNonce;
    final cols = chapterImage.hanabiCols;
    final rows = chapterImage.hanabiRows;
    if (ticketB64 == null || nonceB64 == null || cols == null || rows == null) {
      return chapterImage;
    }

    try {
      final config = _pipeline.mergeHeaders(
        FetchConfig(url: chapterImage.url, responseType: ResponseType.bytes),
        source,
      );
      final response = await _httpClient.execute(config);
      final scrambledBytes = response.data as Uint8List;

      final decoded = img.decodeImage(scrambledBytes);
      if (decoded == null) return chapterImage;
      final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);

      final ticket = base64Decode(ticketB64);
      final nonce = base64Decode(nonceB64);

      final decryptedRgba = await _unscrambler.unscramble(
        rgba,
        decoded.width,
        decoded.height,
        ticket,
        nonce,
        cols,
        rows,
      );

      final decryptedImage = img.Image.fromBytes(
        width: decoded.width,
        height: decoded.height,
        bytes: decryptedRgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      final pngBytes = img.encodePng(decryptedImage);
      final dataUri = 'data:image/png;base64,${base64Encode(pngBytes)}';

      return ChapterImage(url: dataUri, scrambleType: ScrambleType.none);
    } catch (e) {
      debugPrint('HanabiChapterDecryptor failed: $e');
      return chapterImage;
    }
  }
}
