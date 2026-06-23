/// Manual verification script for Wu55Comic source.
/// Run with: dart run test/verify_wu55comic.dart
///
/// This script tests the wu55comic source against the live website
/// to verify HTML parsing and image decryption work correctly.
/// It does NOT run as part of `flutter test`.

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() async {
  final source = Wu55Comic();
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  print('=== Wu55Comic Verification ===');
  print('Base URL: ${source.baseUrl}');
  print('');

  // 1. Test domain discovery
  print('--- Step 1: Domain Discovery ---');
  try {
    final config = source.prepareDomainDiscoveryFetch();
    final response = await dio.get<String>(config.url);
    if (response.statusCode == 200) {
      final changed = source.parseDomainDiscovery(response.data!);
      print('✓ Domain discovery successful. Changed: $changed');
      print('  Current base URL: ${source.baseUrl}');
    } else {
      print('✗ Domain discovery failed: HTTP ${response.statusCode}');
    }
  } catch (e) {
    print('✗ Domain discovery error: $e');
  }
  print('');

  // 2. Test discovery (book list)
  print('--- Step 2: Discovery (Book List) ---');
  try {
    final config = source.prepareDiscoveryFetch(1, {});
    final response = await dio.get<String>(
      config.url,
      queryParameters: config.queryParameters,
      options: Options(headers: source.defaultHeaders),
    );
    if (response.statusCode == 200) {
      final results = source.parseDiscovery(response.data!);
      print('✓ Discovery returned ${results.length} items');
      if (results.isNotEmpty) {
        final first = results.first;
        print('  First: [${first.id}] ${first.title}');
        if (first.coverUrl.length > 80) {
          print('  Cover: ${first.coverUrl.substring(0, 80)}...');
        } else {
          print('  Cover: ${first.coverUrl}');
        }
      }
    } else {
      print('✗ Discovery failed: HTTP ${response.statusCode}');
    }
  } catch (e) {
    print('✗ Discovery error: $e');
  }
  print('');

  // 3. Test search
  print('--- Step 3: Search ---');
  try {
    final config = source.prepareSearchFetch('秘密', 1, {});
    final response = await dio.get<String>(
      config.url,
      queryParameters: config.queryParameters,
      options: Options(headers: source.defaultHeaders),
    );
    if (response.statusCode == 200) {
      final results = source.parseSearch(response.data!);
      print('✓ Search returned ${results.length} results');
      if (results.isNotEmpty) {
        print('  First: [${results.first.id}] ${results.first.title}');
      }
    } else {
      print('✗ Search failed: HTTP ${response.statusCode}');
    }
  } catch (e) {
    print('✗ Search error: $e');
  }
  print('');

  // 4. Test manga info
  print('--- Step 4: Manga Info ---');
  String? testChapterId;
  try {
    final config = source.prepareMangaInfoFetch('3751');
    final response = await dio.get<String>(
      config.url,
      options: Options(headers: source.defaultHeaders),
    );
    if (response.statusCode == 200) {
      final detail = source.parseMangaInfo(response.data!, '3751');
      print('✓ Manga info: ${detail.title}');
      print('  Author: ${detail.author}');
      print('  Status: ${detail.status}');
      print('  Tags: ${detail.tags.take(5).join(", ")}');
      print('  Chapters: ${detail.chapters.length}');
      if (detail.chapters.isNotEmpty) {
        testChapterId = detail.chapters.first.id;
        print(
            '  First chapter: [$testChapterId] ${detail.chapters.first.title}');
      }
    } else {
      print('✗ Manga info failed: HTTP ${response.statusCode}');
    }
  } catch (e) {
    print('✗ Manga info error: $e');
  }
  print('');

  // 5. Test chapter parsing
  if (testChapterId == null) {
    print('--- Step 5: Skipped (no chapter ID) ---');
    print('');
    print('=== Verification Complete ===');
    exit(1);
  }
  print('--- Step 5: Chapter Content ---');
  List<ChapterImage> chapterImages = [];
  try {
    final config = source.prepareChapterFetch('3751', testChapterId, 1);
    final response = await dio.get<String>(
      config.url,
      options: Options(headers: config.headers?.cast<String, String>()),
    );
    if (response.statusCode == 200) {
      final result =
          source.parseChapter(response.data!, '3751', testChapterId, 1);
      chapterImages = result.chapter.images;
      print('✓ Chapter has ${chapterImages.length} images');
      if (chapterImages.isNotEmpty) {
        final first = chapterImages.first;
        if (first.url.length > 80) {
          print('  First image URL: ${first.url.substring(0, 80)}...');
        } else {
          print('  First image URL: ${first.url}');
        }
        print('  ScrambleType: ${first.scrambleType}');
        print('  wu55BookId: ${first.wu55BookId}');
        print('  wu55PageNumber: ${first.wu55PageNumber}');
      }
    } else {
      print('✗ Chapter failed: HTTP ${response.statusCode}');
    }
  } catch (e) {
    print('✗ Chapter error: $e');
  }
  print('');

  // 6. Test image decryption (first image only)
  if (chapterImages.isEmpty) {
    print('--- Step 6: Skipped (no images) ---');
    print('');
    print('=== Verification Complete ===');
    exit(1);
  }
  print('--- Step 6: Image Decryption (first image) ---');
  try {
    final firstImg = chapterImages.first;
    final shardUrls = Wu55ComicDecoder.buildShardUrls(firstImg.url);
    print('  Shard 0: ${shardUrls[0]}');
    print('  Shard 1: ${shardUrls[1]}');

    // Download both shards as raw bytes
    final shard0 = await dio.get<List<int>>(
      shardUrls[0],
      options: Options(
        responseType: ResponseType.bytes,
        headers: source.defaultHeaders,
      ),
    );
    final shard1 = await dio.get<List<int>>(
      shardUrls[1],
      options: Options(
        responseType: ResponseType.bytes,
        headers: source.defaultHeaders,
      ),
    );
    print(
        '  Shard 0: ${shard0.statusCode} (${shard0.data!.length} bytes)');
    print(
        '  Shard 1: ${shard1.statusCode} (${shard1.data!.length} bytes)');

    if (shard0.statusCode == 200 && shard1.statusCode == 200) {
      // Combine and decrypt
      final combined =
          Uint8List.fromList([...shard0.data!, ...shard1.data!]);
      final decoded = Wu55ComicDecoder.decode(combined);

      print('✓ Decryption successful!');
      print('  MIME type: ${decoded.mimeType}');
      print('  Needs unscramble: ${decoded.needsUnscramble}');
      print('  Book ID (from header): ${decoded.bookId}');
      print('  Page number (from header): ${decoded.pageNumber}');
      print('  Image size: ${decoded.imageBytes.length} bytes');

      // Verify it starts with correct magic bytes
      final bytes = decoded.imageBytes;
      if (decoded.mimeType == 'image/jpeg') {
        final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
        print('  Valid JPEG header: $isJpeg');
      } else if (decoded.mimeType == 'image/gif') {
        final isGif =
            bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
        print('  Valid GIF header: $isGif');
      } else if (decoded.mimeType == 'image/avif') {
        print('  AVIF format detected');
      }

      // Calculate slice count
      if (decoded.needsUnscramble) {
        final slices =
            Wu55ComicDecoder.getSliceCount(decoded.bookId, decoded.pageNumber);
        print('  Slice count for unscramble: $slices');
      }

      // Save decoded image for manual inspection
      final outFile = File('/tmp/wu55_decoded_test.jpg');
      await outFile.writeAsBytes(decoded.imageBytes);
      print('  Saved decoded image to: ${outFile.path}');
    } else {
      print('✗ Shard download failed');
    }
  } catch (e, st) {
    print('✗ Image decryption error: $e');
    print('  Stack: $st');
  }
  print('');

  print('=== Verification Complete ===');
  exit(0);
}
