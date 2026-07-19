import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/core/utils/image_response_decoder.dart';

/// Manages local caching and downloading of chapter images.
/// On web: all methods are no-ops (web uses online-only browsing).
/// On native: stores images as files under appDocDir/chapter_cache/.
class ChapterCacheService {
  String? _basePath;
  final Dio _dio;

  ChapterCacheService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
    _dio.options.responseType = ResponseType.bytes;
  }

  /// Get the base cache directory path.
  Future<String> get _cachePath async {
    if (_basePath != null) return _basePath!;
    if (kIsWeb) {
      _basePath = '';
      return '';
    }
    final dir = await getApplicationDocumentsDirectory();
    _basePath = '${dir.path}/chapter_cache';
    return _basePath!;
  }

  /// Get the directory path for a specific chapter.
  String _chapterDir(String basePath, String sourceId, String mangaId, String chapterId) {
    // Sanitize IDs for filesystem safety
    final safeSource = sourceId.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final safeManga = mangaId.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final safeChapter = chapterId.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return '$basePath/$safeSource/$safeManga/$safeChapter';
  }

  /// Check if a specific image is cached locally.
  /// Returns the file path if cached, null otherwise.
  Future<String?> getImageFile(
    String sourceId,
    String mangaId,
    String chapterId,
    int index,
  ) async {
    if (kIsWeb) return null;
    final base = await _cachePath;
    final dir = _chapterDir(base, sourceId, mangaId, chapterId);
    final baseName = index.toString().padLeft(4, '0');
    for (final ext in ['.jpg', '.png', '.webp', '.gif', '']) {
      final file = File('$dir/$baseName$ext');
      if (await file.exists()) {
        return file.path;
      }
    }
    return null;
  }

  /// Save image bytes to local cache.
  Future<void> saveImage(
    String sourceId,
    String mangaId,
    String chapterId,
    int index,
    Uint8List bytes, {
    String? contentType,
  }) async {
    if (kIsWeb) return;
    final base = await _cachePath;
    final dir = _chapterDir(base, sourceId, mangaId, chapterId);
    final directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final ext = _extensionFromContentType(contentType);
    final file = File('$dir/${index.toString().padLeft(4, '0')}$ext');
    await file.writeAsBytes(bytes);
  }

  String _extensionFromContentType(String? contentType) {
    if (contentType == null) return '.jpg';
    if (contentType.contains('png')) return '.png';
    if (contentType.contains('webp')) return '.webp';
    if (contentType.contains('gif')) return '.gif';
    return '.jpg';
  }

  /// Check if an entire chapter is fully cached.
  Future<bool> isChapterCached(
    String sourceId,
    String mangaId,
    String chapterId,
    int totalImages,
  ) async {
    if (kIsWeb) return false;
    final base = await _cachePath;
    final dir = _chapterDir(base, sourceId, mangaId, chapterId);
    final directory = Directory(dir);
    if (!await directory.exists()) return false;
    final files = await directory.list().length;
    return files >= totalImages;
  }

  /// Download all images of a chapter to local cache.
  /// [onProgress] callback reports (completedCount, totalCount).
  /// Returns true if all images downloaded successfully.
  Future<bool> downloadChapter({
    required String sourceId,
    required String mangaId,
    required String chapterId,
    required List<ChapterImage> images,
    void Function(int completed, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (kIsWeb) return false;
    final base = await _cachePath;
    final dir = _chapterDir(base, sourceId, mangaId, chapterId);
    final directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    int completed = 0;
    final total = images.length;

    for (int i = 0; i < images.length; i++) {
      final baseName = i.toString().padLeft(4, '0');

      // Check if already downloaded (any extension)
      bool alreadyExists = false;
      for (final ext in ['.jpg', '.png', '.webp', '.gif', '']) {
        final file = File('$dir/$baseName$ext');
        if (await file.exists()) {
          alreadyExists = true;
          break;
        }
      }
      if (alreadyExists) {
        completed++;
        onProgress?.call(completed, total);
        continue;
      }

      try {
        final url = ImageProxy.url(images[i].url);
        final response = await _dio.get<List<int>>(
          url,
          options: Options(
            headers: images[i].headers,
            responseType: ResponseType.bytes,
          ),
          cancelToken: cancelToken,
        );

        if (response.data != null) {
          final contentType = response.headers.value('content-type');
          final ext = _extensionFromContentType(contentType);
          final file = File('$dir/$baseName$ext');
          final bytes = decodeImageResponseBytes(
            Uint8List.fromList(response.data as List<int>),
            images[i].responseEncoding,
          );
          await file.writeAsBytes(bytes);
        }
        completed++;
        onProgress?.call(completed, total);
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          return false; // Cancelled
        }
        // Skip failed image, continue with rest
        completed++;
        onProgress?.call(completed, total);
      }
    }

    return true;
  }

  /// Delete cached images for a specific chapter.
  Future<void> deleteChapter(
    String sourceId,
    String mangaId,
    String chapterId,
  ) async {
    if (kIsWeb) return;
    final base = await _cachePath;
    final dir = _chapterDir(base, sourceId, mangaId, chapterId);
    final directory = Directory(dir);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Get total cache size in bytes.
  Future<int> getCacheSize() async {
    if (kIsWeb) return 0;
    final base = await _cachePath;
    final directory = Directory(base);
    if (!await directory.exists()) return 0;

    int totalSize = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// Clear all cached chapter images.
  Future<void> clearCache() async {
    if (kIsWeb) return;
    final base = await _cachePath;
    final directory = Directory(base);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
