import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/core/utils/image_response_decoder.dart';

/// Result of a [ChapterCacheService.downloadChapter] call.
///
/// - [cancelled]: `true` if the download was aborted via [CancelToken]
///   cancellation before every image was attempted. When `true`,
///   [completedImages] and [failedImageIndexes] only reflect the images
///   that were processed before cancellation; the remaining images were
///   never attempted (and are not listed in [failedImageIndexes]).
/// - [completedImages]: the count of images that were **successfully**
///   downloaded (or already present on disk from a previous run). This
///   does NOT include images that ultimately failed after exhausting the
///   retry budget. In the non-cancelled case,
///   `completedImages == images.length - failedImageIndexes.length`.
/// - [failedImageIndexes]: sorted indexes of images that failed every
///   attempt (1 initial attempt + retries, up to [ChapterCacheService]'s
///   internal max retry count) and were given up on.
class ChapterDownloadResult {
  final bool cancelled;
  final int completedImages;
  final List<int> failedImageIndexes;

  const ChapterDownloadResult({
    required this.cancelled,
    required this.completedImages,
    required this.failedImageIndexes,
  });
}

/// Manages local caching and downloading of chapter images.
/// On web: all methods are no-ops (web uses online-only browsing).
/// On native: stores images as files under appDocDir/chapter_cache/.
class ChapterCacheService {
  static const int _maxConcurrentImagesPerChapter = 4;
  static const int _maxImageRetries = 2;

  final Dio _dio;
  final bool _forceAndroidPathForTest;

  /// Optional override for the base cache directory, settable at runtime
  /// (e.g. by a user-facing "change download location" setting). When set,
  /// it takes priority over both the Android external-storage path and the
  /// default application-documents path. Declared here for Task 9's
  /// `_cachePath` ordering; consumed by a later settings feature.
  static String? customDownloadDirectory;

  /// Memoized platform-resolved cache path (Android external-storage-or-
  /// fallback, or the default application-documents path). Safe to cache
  /// for the lifetime of this instance because the OS-level answer to
  /// "what is my documents/external directory" never changes once the app
  /// is running. Deliberately does NOT cache [customDownloadDirectory],
  /// which is re-checked fresh on every `_cachePath` call so a future
  /// runtime change to it takes effect immediately.
  String? _resolvedPlatformPath;

  ChapterCacheService({Dio? dio, bool forceAndroidPathForTest = false})
    : _dio = dio ?? Dio(),
      _forceAndroidPathForTest = forceAndroidPathForTest {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
    _dio.options.responseType = ResponseType.bytes;
  }

  /// Get the base cache directory path.
  ///
  /// [customDownloadDirectory] is checked fresh on every call (never
  /// cached) so a runtime change takes effect immediately. The platform-
  /// resolved path (everything below) IS memoized in [_resolvedPlatformPath]
  /// since re-resolving it costs a platform-channel round-trip on every
  /// call otherwise (e.g. once per page render via `getImageFile`), and the
  /// underlying OS answer cannot change during the instance's lifetime.
  Future<String> get _cachePath async {
    if (kIsWeb) return '';
    if (customDownloadDirectory != null) return customDownloadDirectory!;
    if (_resolvedPlatformPath != null) return _resolvedPlatformPath!;
    if (Platform.isAndroid || _forceAndroidPathForTest) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return _resolvedPlatformPath = '${externalDir.path}/chapter_cache';
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    return _resolvedPlatformPath = '${dir.path}/chapter_cache';
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

  /// Download all images of a chapter to local cache, [_maxConcurrentImagesPerChapter]
  /// images at a time, with per-image retry (up to [_maxImageRetries]).
  /// [onProgress] callback reports (completedCount, totalCount).
  /// Already-downloaded images (by index, any known extension) are skipped,
  /// which is the basis for resumable downloads.
  Future<ChapterDownloadResult> downloadChapter({
    required String sourceId,
    required String mangaId,
    required String chapterId,
    required List<ChapterImage> images,
    void Function(int completed, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (kIsWeb) {
      return ChapterDownloadResult(
        cancelled: false,
        completedImages: 0,
        failedImageIndexes: List.generate(images.length, (i) => i),
      );
    }

    final base = await _cachePath;
    final dir = _chapterDir(base, sourceId, mangaId, chapterId);
    await Directory(dir).create(recursive: true);

    int completed = 0;
    final failedIndexes = <int>{};

    Future<void> downloadOne(int i) async {
      final baseName = i.toString().padLeft(4, '0');

      // Preserve the existing "skip if already downloaded" logic (by index),
      // which is the basis for resumable downloads.
      for (final ext in ['.jpg', '.png', '.webp', '.gif', '']) {
        if (await File('$dir/$baseName$ext').exists()) {
          completed++;
          onProgress?.call(completed, images.length);
          return;
        }
      }

      var attempt = 0;
      while (true) {
        try {
          final response = await _dio.get<List<int>>(
            ImageProxy.url(images[i].url),
            options: Options(
              headers: images[i].headers,
              responseType: ResponseType.bytes,
            ),
            cancelToken: cancelToken,
          );
          if (response.data != null) {
            final contentType = response.headers.value('content-type');
            final ext = _extensionFromContentType(contentType);
            final bytes = decodeImageResponseBytes(
              Uint8List.fromList(response.data as List<int>),
              images[i].responseEncoding,
            );
            await File('$dir/$baseName$ext').writeAsBytes(bytes);
          }
          completed++;
          onProgress?.call(completed, images.length);
          return;
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            rethrow;
          }
          attempt++;
          if (attempt > _maxImageRetries) {
            failedIndexes.add(i);
            onProgress?.call(completed, images.length);
            return;
          }
        }
      }
    }

    try {
      for (
        var start = 0;
        start < images.length;
        start += _maxConcurrentImagesPerChapter
      ) {
        final end = (start + _maxConcurrentImagesPerChapter).clamp(
          0,
          images.length,
        );
        await Future.wait([for (var i = start; i < end; i++) downloadOne(i)]);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return ChapterDownloadResult(
          cancelled: true,
          completedImages: completed,
          failedImageIndexes: failedIndexes.toList()..sort(),
        );
      }
      rethrow;
    }

    return ChapterDownloadResult(
      cancelled: false,
      completedImages: completed,
      failedImageIndexes: failedIndexes.toList()..sort(),
    );
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
