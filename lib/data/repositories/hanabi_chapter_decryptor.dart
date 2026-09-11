import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show ResponseType;
import 'package:flutter/foundation.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/repositories/fetch_pipeline.dart';
import 'package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// A decoded RGBA bitmap: `rgba` is tightly packed `width * height * 4` bytes.
typedef _Rgba = ({Uint8List bytes, int width, int height});

/// Downloads a scrambled hanabimanga.com CDN image, unscrambles it via the
/// official `/reader.wasm` module (see [HanabiWasmUnscrambler]), and returns
/// an image ready for direct rendering.
///
/// Image decode/encode goes through `dart:ui` (Skia/libwebp, native code, and
/// decoding happens off the UI thread) rather than `package:image`'s pure-Dart
/// codecs, because the pure-Dart WebP decode + PNG deflate of a multi-megapixel
/// page blocked the UI thread long enough to drop frames on every page turn.
///
/// When a [ChapterCacheService] and a full cache identity
/// (`mangaId`/`chapterId`/`imageIndex`) are available, the decrypted PNG is
/// written to the on-disk chapter cache and the returned [ChapterImage.url] is
/// a `file://` URI. That makes re-entering a chapter free (no download, no
/// wasm round trip) and keeps multi-megabyte payloads out of the Dart heap.
/// Without a cache (notably on web, where [ChapterCacheService] is a no-op)
/// it falls back to an inline `data:` URI.
class HanabiChapterDecryptor {
  final HttpClient _httpClient;
  final FetchPipeline _pipeline;
  final HanabiWasmUnscrambler _unscrambler;
  final ChapterCacheService? _cache;

  HanabiChapterDecryptor(
    this._httpClient,
    this._pipeline, [
    HanabiWasmUnscrambler? unscrambler,
    ChapterCacheService? cache,
  ]) : _unscrambler = unscrambler ?? HanabiWasmUnscrambler(),
       _cache = cache;

  /// Decrypts [chapterImage] if it is scrambled (`ScrambleType.hanabi`).
  /// Returns the input unchanged for any other scramble type, or on
  /// failure (network error, decode error, or wasm error) — in the failure
  /// case the caller will attempt to render the original (still-scrambled)
  /// CDN URL, which will look garbled but at least won't crash the reader.
  ///
  /// [mangaId], [chapterId] and [imageIndex] are only used as the on-disk
  /// cache key; when any of them is omitted the result is returned inline
  /// instead of being cached.
  Future<ChapterImage> decrypt(
    ChapterImage chapterImage,
    HanabiManga source, {
    String? mangaId,
    String? chapterId,
    int? imageIndex,
  }) async {
    if (chapterImage.scrambleType != ScrambleType.hanabi) return chapterImage;

    final ticketB64 = chapterImage.hanabiTicket;
    final nonceB64 = chapterImage.hanabiNonce;
    final cols = chapterImage.hanabiCols;
    final rows = chapterImage.hanabiRows;
    if (ticketB64 == null || nonceB64 == null || cols == null || rows == null) {
      return chapterImage;
    }

    final cache = _cache;
    final cacheable =
        !kIsWeb &&
        cache != null &&
        mangaId != null &&
        chapterId != null &&
        imageIndex != null;

    if (cacheable) {
      // Already decrypted on a previous visit: skip the download *and* the
      // wasm round trip entirely.
      final cached = await cache.getImageFile(
        source.id,
        mangaId,
        chapterId,
        imageIndex,
      );
      if (cached != null) {
        return ChapterImage(
          url: Uri.file(cached).toString(),
          scrambleType: ScrambleType.none,
        );
      }
    }

    try {
      var config = _pipeline.mergeHeaders(
        FetchConfig(url: chapterImage.url, responseType: ResponseType.bytes),
        source,
      );
      // `mergeHeaders` unconditionally attaches `source.extraHeaders`
      // (which includes the `web.hanabimanga.com` session Cookie) to every
      // request. This image download goes to a *different* host
      // (`cdn.hanabimanga.top`), which doesn't need -- and shouldn't
      // receive -- that session cookie. Strip it here without touching
      // how any other Hanabi request (login/search/discovery/chapter
      // manifest) builds its headers.
      final headers = {...config.headers ?? {}}..remove('Cookie');
      config = config.copyWith(headers: headers);
      final response = await _httpClient.execute(config);
      final scrambledBytes = response.data as Uint8List;

      final decoded = await _decodeToRgba(scrambledBytes);
      if (decoded == null) return chapterImage;

      final ticket = base64Decode(ticketB64);
      final nonce = base64Decode(nonceB64);

      final decryptedRgba = await _unscrambler.unscramble(
        decoded.bytes,
        decoded.width,
        decoded.height,
        ticket,
        nonce,
        cols,
        rows,
      );

      final pngBytes = await _encodePng(
        decryptedRgba,
        decoded.width,
        decoded.height,
      );
      if (pngBytes == null) return chapterImage;

      if (cacheable) {
        await cache.saveImage(
          source.id,
          mangaId,
          chapterId,
          imageIndex,
          pngBytes,
          contentType: 'image/png',
          scrambleType: ScrambleType.none,
        );
        final path = await cache.getImageFile(
          source.id,
          mangaId,
          chapterId,
          imageIndex,
        );
        if (path != null) {
          return ChapterImage(
            url: Uri.file(path).toString(),
            scrambleType: ScrambleType.none,
          );
        }
        // Write succeeded but the file vanished (or web no-op): fall through
        // to the inline representation rather than returning a dead path.
      }

      final dataUri = 'data:image/png;base64,${base64Encode(pngBytes)}';
      return ChapterImage(url: dataUri, scrambleType: ScrambleType.none);
    } catch (e) {
      debugPrint('HanabiChapterDecryptor failed: $e');
      return chapterImage;
    }
  }

  /// Decodes any engine-supported format (the CDN serves WebP) to packed RGBA.
  static Future<_Rgba?> _decodeToRgba(Uint8List encoded) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    final codec = await ui.instantiateImageCodecFromBuffer(buffer);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) return null;
        return (
          bytes: data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          ),
          width: image.width,
          height: image.height,
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// Encodes packed RGBA pixels to PNG using the engine's encoder.
  static Future<Uint8List?> _encodePng(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return null;
        return data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
      descriptor.dispose();
    }
  }
}
