import 'dart:typed_data';

import 'package:dio/dio.dart' show Headers, Response, ResponseType;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get_it/get_it.dart' hide Disposable;

import '../../../data/local/chapter_cache_service.dart';
import '../../../data/remote/http_client.dart';
import '../../../core/models/fetch_config.dart';
import '../../../core/utils/image_response_decoder.dart';
import '../../../domain/entities/chapter.dart';

const int kMangaImageMaxLoadAttempts = 3;

/// Downloads [image]'s bytes through the shared [HttpClient], retrying on
/// failure (with exponential backoff) and verifying that the number of
/// bytes received matches the server-declared Content-Length. This guards
/// against proxies/upstreams that close the connection early while still
/// returning a 2xx status, which would otherwise be silently decoded as a
/// (corrupt) truncated image. On success, if [sourceId]/[mangaId]/
/// [chapterId]/[imageIndex] are all provided (native-only), the decoded
/// bytes are also persisted via [ChapterCacheService.saveImage] so that
/// future reads (including precache/prefetch call sites) hit the disk
/// cache instead of re-downloading.
Future<Uint8List> loadAndCacheImageBytes({
  required ChapterImage image,
  String? sourceId,
  String? mangaId,
  String? chapterId,
  int? imageIndex,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= kMangaImageMaxLoadAttempts; attempt++) {
    try {
      final response = await GetIt.instance<HttpClient>().execute(
        FetchConfig(
          url: image.url,
          headers: image.headers,
          responseType: ResponseType.bytes,
        ),
      );
      final responseData = response.data;
      if (responseData is! List<int>) {
        throw const FormatException('Image response did not contain bytes');
      }
      final rawBytes = Uint8List.fromList(responseData);
      _verifyResponseIntegrity(response, rawBytes);
      final bytes = decodeImageResponseBytes(rawBytes, image.responseEncoding);
      if (bytes.isEmpty) {
        throw const FormatException('Decoded image is empty');
      }
      final canCache = sourceId != null &&
          mangaId != null &&
          chapterId != null &&
          imageIndex != null;
      if (canCache) {
        await GetIt.instance<ChapterCacheService>().saveImage(
          sourceId,
          mangaId,
          chapterId,
          imageIndex,
          bytes,
        );
      }
      return bytes;
    } catch (e) {
      lastError = e;
      debugPrint(
        '[MangaImageLoader] load attempt $attempt/$kMangaImageMaxLoadAttempts '
        'failed: ${image.url} - $e',
      );
      if (attempt == kMangaImageMaxLoadAttempts) break;
      await Future.delayed(Duration(milliseconds: 300 * (1 << (attempt - 1))));
    }
  }
  throw lastError ?? const FormatException('Failed to load image');
}

/// Throws if the downloaded [bytes] don't match the response's declared
/// Content-Length (when present), catching truncated-but-200 responses.
void _verifyResponseIntegrity(Response response, Uint8List bytes) {
  final declared = response.headers.value(Headers.contentLengthHeader);
  final declaredLength = declared != null ? int.tryParse(declared) : null;
  if (declaredLength != null && declaredLength != bytes.length) {
    throw FormatException(
      'Image response truncated: expected $declaredLength bytes, got '
      '${bytes.length}',
    );
  }
}
