import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/core/utils/image_response_decoder.dart';
import 'package:comic_reader/data/sources/source_image_transform.dart';

final _log = Logger('ChapterCacheService');

/// Filename used for the per-chapter scramble manifest written alongside
/// the numbered image files (see [ChapterCacheService.saveImage] /
/// [ChapterCacheService.downloadChapter] / [ChapterCacheService.
/// readScrambleManifest]). Dot-prefixed so directory scans that only look
/// for known image extensions (e.g. [ChapterCacheService.getImageFile])
/// never mistake it for a page image; [ChapterCacheService.isChapterCached]
/// explicitly excludes it as well (see [_isManifestFileName]).
const String _scrambleManifestFileName = '.manifest.json';

bool _isManifestFileName(String path) =>
    path.endsWith('/$_scrambleManifestFileName') ||
    path == _scrambleManifestFileName;

/// Resolves the effective scramble info for [original] at [index], using
/// [manifest] (as returned by [ChapterCacheService.readScrambleManifest])
/// when it has an entry for that index, falling back to [original]'s own
/// (live-derived) `scrambleType`/`scrambleId` otherwise.
///
/// This is the pure decision function behind the reader's local-cached-
/// file render path: a previously-downloaded chapter's manifest records
/// the scramble threshold that was accurate at *download* time, which may
/// disagree with a fresh (possibly stale) live re-derivation. See
/// `manga_image.dart`'s local-file branch for the caller.
///
/// - `manifest == null` (chapter was never downloaded via a manifest-aware
///   path, or predates this feature): returns [original] unchanged.
/// - No entry for [index] in [manifest]: returns [original] unchanged.
/// - Entry present but its `scrambleType` string doesn't match any
///   [ScrambleType] value (defensive, e.g. manifest written by a future
///   app version with a new scramble type): falls back to [original]
///   .scrambleType rather than throwing.
ChapterImage resolveScrambleFromManifest(
  ChapterImage original,
  Map<String, dynamic>? manifest,
  int index,
) {
  if (manifest == null) return original;
  final key = index.toString().padLeft(4, '0');
  final entry = manifest[key];
  if (entry is! Map) return original;
  final rawType = entry['scrambleType'];
  ScrambleType? parsedType;
  if (rawType is String) {
    for (final t in ScrambleType.values) {
      if (t.name == rawType) {
        parsedType = t;
        break;
      }
    }
  }
  // Unrecognized/missing scrambleType: treat the whole entry as unusable
  // and fall back to the original image entirely (including its own
  // scrambleId), rather than mixing a fallback type with a manifest-
  // sourced scrambleId that was never validated against it.
  if (parsedType == null) return original;
  final rawScrambleId = entry['scrambleId'];
  final scrambleId = rawScrambleId is int ? rawScrambleId : null;
  return ChapterImage(
    url: original.url,
    scrambleType: parsedType,
    responseEncoding: original.responseEncoding,
    headers: original.headers,
    scrambleId: scrambleId,
    wu55BookId: original.wu55BookId,
    wu55PageNumber: original.wu55PageNumber,
  );
}

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
/// MethodChannel bridging to `macos/Runner/DownloadDirectoryBookmark.swift`.
///
/// Used to persist/resolve a macOS App Sandbox security-scoped bookmark for
/// a user-chosen custom download directory (see [ChapterCacheService.
/// customDownloadDirectory]). Without this, a directory granted via
/// `FilePicker.platform.getDirectoryPath()` is only writable for the
/// current process lifetime; after the app is quit and relaunched, writes
/// to that path fail with a sandbox permission error in a signed Release
/// build.
const MethodChannel _downloadBookmarkChannel = MethodChannel(
  'com.comicreader.comicReader/download_bookmark',
);

/// Test-only override for the platform check used by
/// [saveDownloadDirectoryBookmark] and [resolveDownloadDirectoryBookmark].
/// When non-null, takes priority over the real [Platform.isMacOS], letting
/// tests exercise both the macOS and non-macOS code paths regardless of
/// the OS actually running the test suite. Mirrors the existing
/// [ChapterCacheService.customDownloadDirectory] testing-override pattern
/// in this file. Must be reset to `null` by tests (e.g. in `tearDown`).
@visibleForTesting
bool? debugIsMacOSOverrideForTest;

bool get _isMacOSForBookmark =>
    debugIsMacOSOverrideForTest ?? Platform.isMacOS;

/// Persists a security-scoped bookmark for [path] so it remains writable
/// (via [resolveDownloadDirectoryBookmark]) after the app is relaunched.
///
/// No-op (returns `true` immediately) on any platform other than macOS
/// (App Sandbox / security-scoped bookmarks are a macOS-only concept;
/// other platforms don't need this).
///
/// Returns `true` if the bookmark was saved (or the call was a no-op),
/// `false` if the native side threw (e.g. `url.bookmarkData()` failing on
/// an invalid path or a revoked sandbox extension surfaces as a
/// [PlatformException] on the Dart side). The exception is caught and
/// logged here rather than rethrown, so callers are never forced to
/// handle it, but can still react to the failure via the return value.
Future<bool> saveDownloadDirectoryBookmark(String path) async {
  if (!_isMacOSForBookmark) return true;
  try {
    await _downloadBookmarkChannel.invokeMethod('saveBookmark', {
      'path': path,
    });
    return true;
  } catch (e, stack) {
    _log.warning('Failed to save download directory bookmark: $e', e, stack);
    return false;
  }
}

/// Resolves the previously-saved security-scoped bookmark and starts
/// accessing it, returning the resolved directory path, or `null` if no
/// bookmark has been saved yet or resolution failed.
///
/// No-op (returns `null` immediately) on any platform other than macOS.
Future<String?> resolveDownloadDirectoryBookmark() async {
  if (!_isMacOSForBookmark) return null;
  return _downloadBookmarkChannel.invokeMethod<String>('resolveBookmark');
}

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

  /// Serializes read-modify-write access to each chapter's scramble
  /// manifest file, keyed by chapter directory path. Needed because
  /// [downloadChapter] downloads up to [_maxConcurrentImagesPerChapter]
  /// images concurrently (each wanting to record its own manifest entry),
  /// and the reader's own prefetch (`manga_image_loader.dart`'s
  /// `loadAndCacheImageBytes`, via [saveImage]) can likewise fire multiple
  /// concurrent saves for the same chapter. Without this, concurrent
  /// read-JSON/modify/write-JSON cycles on the same file would race and
  /// silently drop entries.
  final Map<String, Future<void>> _manifestLocks = {};

  Future<void> _runExclusive(String key, Future<void> Function() action) async {
    final previous = _manifestLocks[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _manifestLocks[key] = completer.future;
    try {
      await previous;
      await action();
    } finally {
      completer.complete();
      if (identical(_manifestLocks[key], completer.future)) {
        _manifestLocks.remove(key);
      }
    }
  }

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
  ///
  /// When [scrambleType] is provided, also records (or updates) this
  /// [index]'s entry in the chapter's scramble manifest (see
  /// [readScrambleManifest]) with [scrambleType] and [scrambleId]. Passing
  /// `null` (the default, matching every call site that existed before
  /// this parameter was added) leaves the manifest untouched, preserving
  /// prior behavior exactly.
  Future<void> saveImage(
    String sourceId,
    String mangaId,
    String chapterId,
    int index,
    Uint8List bytes, {
    String? contentType,
    ScrambleType? scrambleType,
    int? scrambleId,
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
    if (scrambleType != null) {
      await _writeManifestEntry(dir, index, scrambleType, scrambleId);
    }
  }

  /// Reads back the scramble manifest previously written by [saveImage] /
  /// [downloadChapter] for this chapter, or `null` if no manifest file
  /// exists (the chapter was never downloaded via a manifest-aware path,
  /// predates this feature, or the file is unreadable/corrupt).
  ///
  /// The returned map's keys are zero-padded image indexes (e.g. `'0000'`)
  /// matching the on-disk image filename convention; each value is a
  /// `{"scrambleType": <ScrambleType.name>, "scrambleId": <int?>}` object
  /// (`scrambleId` omitted when not applicable). See
  /// [resolveScrambleFromManifest] for how a caller should apply this data
  /// to a specific [ChapterImage].
  Future<Map<String, dynamic>?> readScrambleManifest(
    String sourceId,
    String mangaId,
    String chapterId,
  ) async {
    if (kIsWeb) return null;
    final base = await _cachePath;
    final dir = _chapterDir(base, sourceId, mangaId, chapterId);
    final file = File('$dir/$_scrambleManifestFileName');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e) {
      _log.warning('Failed to parse scramble manifest at $dir: $e');
      return null;
    }
  }

  /// Read-modify-write of a single [index] entry into the scramble
  /// manifest file under [dir], serialized per-directory via
  /// [_runExclusive] to survive concurrent callers (see that field's doc).
  Future<void> _writeManifestEntry(
    String dir,
    int index,
    ScrambleType scrambleType,
    int? scrambleId,
  ) async {
    await _runExclusive(dir, () async {
      final file = File('$dir/$_scrambleManifestFileName');
      Map<String, dynamic> manifest = {};
      if (await file.exists()) {
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) manifest = decoded;
        } catch (e) {
          _log.warning(
            'Existing scramble manifest at $dir was unreadable, '
            'recreating: $e',
          );
        }
      }
      final entry = <String, dynamic>{'scrambleType': scrambleType.name};
      if (scrambleId != null) entry['scrambleId'] = scrambleId;
      manifest[index.toString().padLeft(4, '0')] = entry;
      await file.writeAsString(jsonEncode(manifest));
    });
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
    // Count only page-image files. Excludes the scramble manifest file
    // (`.manifest.json`, see `saveImage`/`downloadChapter`), which would
    // otherwise inflate this count by one and could cause a chapter that
    // is actually missing an image to be misreported as fully cached.
    var count = 0;
    await for (final entity in directory.list()) {
      if (entity is File && !_isManifestFileName(entity.path)) count++;
    }
    return count >= totalImages;
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
          // The image file may have been saved by a previous run (possibly
          // before this manifest feature existed, or a run that was
          // interrupted after writing the file but before recording the
          // manifest entry). Ensure the manifest entry exists/is correct
          // regardless, using the scramble info we have right now from
          // [images] -- this keeps the manifest complete even across
          // partial-failure resumes.
          await _writeManifestEntry(
            dir,
            i,
            images[i].scrambleType,
            images[i].scrambleId,
          );
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
            // This download path has its own Dio and never goes through
            // manga_image_loader, so the per-source byte transform has to be
            // applied here as well — otherwise sources that serve encrypted
            // images would write ciphertext to disk permanently (the offline
            // read path renders files as-is and has no byte hook to recover).
            final bytes = applySourceImageTransform(
              decodeImageResponseBytes(
                Uint8List.fromList(response.data as List<int>),
                images[i].responseEncoding,
              ),
              sourceId,
            );
            await saveImage(
              sourceId,
              mangaId,
              chapterId,
              i,
              bytes,
              contentType: contentType,
              scrambleType: images[i].scrambleType,
              scrambleId: images[i].scrambleId,
            );
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
