import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'fetch_pipeline.dart';

/// Decrypts wu55comic scrambled chapter images: downloads AES-CBC shards in
/// parallel, decrypts, and returns a data URI ChapterImage.
class Wu55ChapterDecryptor {
  Wu55ChapterDecryptor(this._httpClient, this._pipeline);

  final HttpClient _httpClient;
  final FetchPipeline _pipeline;

  /// Decrypt a single wu55comic image: download shards in parallel, AES decrypt, return data URI.
  Future<ChapterImage> decrypt(ChapterImage img, int index, Wu55Comic source) async {
    if (img.scrambleType != ScrambleType.wu55) return img;

    try {
      final shardUrls = Wu55ComicDecoder.buildShardUrls(img.url);

      // Download both shards in parallel
      final responses = await Future.wait([
        _httpClient.execute(_pipeline.mergeHeaders(FetchConfig(
          url: shardUrls[0],
          responseType: ResponseType.bytes,
          headers: img.headers,
        ), source)),
        _httpClient.execute(_pipeline.mergeHeaders(FetchConfig(
          url: shardUrls[1],
          responseType: ResponseType.bytes,
          headers: img.headers,
        ), source)),
      ]);

      final shard0Bytes = Uint8List.fromList(responses[0].data as List<int>);
      final shard1Bytes = Uint8List.fromList(responses[1].data as List<int>);

      // Each shard is an independent AES-CBC stream
      final decoded = Wu55ComicDecoder.decodeShards([shard0Bytes, shard1Bytes]);
      final base64Data = base64Encode(decoded.imageBytes);
      final dataUri = 'data:${decoded.mimeType};base64,$base64Data';

      return ChapterImage(
        url: dataUri,
        scrambleType: decoded.needsUnscramble ? ScrambleType.wu55 : ScrambleType.none,
        wu55BookId: decoded.bookId,
        wu55PageNumber: decoded.pageNumber,
      );
    } catch (e) {
      debugPrint('[Wu55] Failed to decrypt image ${index + 1}: $e');
      return img; // fallback to original
    }
  }
}
