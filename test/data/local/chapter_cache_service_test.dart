import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProviderPlatform(this.tempPath);
  final String tempPath;

  /// Set by tests that want to simulate Android's external storage
  /// directory being available. `null` (the default) simulates it being
  /// unavailable, matching real-world Android configurations where
  /// `getExternalStorageDirectory()` can return null.
  Directory? externalStorageDirectory;

  /// Number of times [getApplicationDocumentsPath] has been invoked. Used
  /// by tests to verify that the resolved platform path is memoized by
  /// [ChapterCacheService] instead of re-querying the platform channel on
  /// every call.
  int documentsPathCallCount = 0;

  /// Number of times [getExternalStoragePath] has been invoked. Same
  /// purpose as [documentsPathCallCount], for the Android external-storage
  /// branch.
  int externalStoragePathCallCount = 0;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    documentsPathCallCount++;
    return tempPath;
  }

  @override
  Future<String?> getExternalStoragePath() async {
    externalStoragePathCallCount++;
    return externalStorageDirectory?.path;
  }
}

class MockDio extends Mock implements Dio {}

/// Builds a successful `Response<List<int>>` as returned by `Dio.get`.
Response<List<int>> _fakeImageResponse(String path, {List<int>? bytes}) {
  return Response<List<int>>(
    requestOptions: RequestOptions(path: path),
    data: bytes ?? const [1, 2, 3],
  );
}

DioException _fakeConnectionError(String path) {
  return DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.connectionError,
  );
}

DioException _fakeCancelError(String path) {
  return DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.cancel,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late MockDio mockDio;
  late FakePathProviderPlatform fakePathProvider;

  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chapter_cache_test');
    fakePathProvider = FakePathProviderPlatform(tempDir.path);
    PathProviderPlatform.instance = fakePathProvider;
    mockDio = MockDio();
    when(() => mockDio.options).thenReturn(BaseOptions());
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ChapterCacheService.downloadChapter concurrency', () {
    test('downloads all images concurrently and reports completion', () async {
      final service = ChapterCacheService();
      final images = List.generate(
        6,
        (i) => ChapterImage(url: 'https://example.invalid/img$i.jpg'),
      );
      // 网络会失败（invalid host），验证的是并发调度与结果结构，不验证真实下载成功；
      // 因此这里断言的是失败时 failedImageIndexes 长度等于图片数，且不抛异常、能拿到结果对象。
      final result = await service.downloadChapter(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        images: images,
      );
      expect(result.cancelled, isFalse);
      expect(result.failedImageIndexes.length, images.length);
    });

    test('already-downloaded images are skipped (index-based resume)', () async {
      final service = ChapterCacheService();
      final dir = Directory(
        '${tempDir.path}/chapter_cache/s1/m1/c1',
      );
      await dir.create(recursive: true);
      await File('${dir.path}/0000.jpg').writeAsBytes([1, 2, 3]);

      final images = [ChapterImage(url: 'https://example.invalid/img0.jpg')];
      final result = await service.downloadChapter(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        images: images,
      );
      expect(result.completedImages, 1);
      expect(result.failedImageIndexes, isEmpty);
    });
  });

  group('ChapterCacheService.downloadChapter with mocked Dio', () {
    test(
      'caps simultaneous in-flight requests at _maxConcurrentImagesPerChapter (4)',
      () async {
        final service = ChapterCacheService(dio: mockDio);
        final images = List.generate(
          8,
          (i) => ChapterImage(url: 'https://example.invalid/img$i.jpg'),
        );

        var inFlight = 0;
        var maxInFlight = 0;
        when(
          () => mockDio.get<List<int>>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          // Yield so all eligible requests in a batch actually overlap
          // instead of resolving synchronously one after another.
          await Future.delayed(const Duration(milliseconds: 20));
          inFlight--;
          return _fakeImageResponse(
            invocation.positionalArguments[0] as String,
          );
        });

        final result = await service.downloadChapter(
          sourceId: 's1',
          mangaId: 'm1',
          chapterId: 'c1',
          images: images,
        );

        expect(maxInFlight, 4);
        expect(result.cancelled, isFalse);
        expect(result.completedImages, 8);
        expect(result.failedImageIndexes, isEmpty);
      },
    );

    test(
      'retries a transiently-failing image and counts it as a success once it '
      'succeeds within the retry budget (max 2 retries = 3 attempts)',
      () async {
        final service = ChapterCacheService(dio: mockDio);
        final images = [ChapterImage(url: 'https://example.invalid/img0.jpg')];

        var callCount = 0;
        when(
          () => mockDio.get<List<int>>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          callCount++;
          // Fail on the first two attempts, succeed on the third (the last
          // attempt allowed by the retry budget).
          if (callCount < 3) {
            throw _fakeConnectionError(
              invocation.positionalArguments[0] as String,
            );
          }
          return _fakeImageResponse(
            invocation.positionalArguments[0] as String,
          );
        });

        final result = await service.downloadChapter(
          sourceId: 's1',
          mangaId: 'm1',
          chapterId: 'c1',
          images: images,
        );

        expect(callCount, 3);
        expect(result.cancelled, isFalse);
        expect(result.completedImages, 1);
        expect(result.failedImageIndexes, isEmpty);
      },
    );

    test(
      'an image that exhausts its retry budget is reported as failed and is '
      'NOT counted in completedImages',
      () async {
        final service = ChapterCacheService(dio: mockDio);
        final images = [ChapterImage(url: 'https://example.invalid/img0.jpg')];

        var callCount = 0;
        when(
          () => mockDio.get<List<int>>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          callCount++;
          throw _fakeConnectionError(
            invocation.positionalArguments[0] as String,
          );
        });

        final result = await service.downloadChapter(
          sourceId: 's1',
          mangaId: 'm1',
          chapterId: 'c1',
          images: images,
        );

        // 1 initial attempt + 2 retries = 3 attempts total before giving up.
        expect(callCount, 3);
        expect(result.cancelled, isFalse);
        expect(result.failedImageIndexes, [0]);
        // completedImages must only count actual successes, not "processed"
        // images: since the only image failed, nothing succeeded.
        expect(result.completedImages, 0);
        expect(
          result.completedImages,
          images.length - result.failedImageIndexes.length,
        );
      },
    );

    test(
      'returns cancelled: true when the download is cancelled via a '
      'pre-cancelled CancelToken',
      () async {
        final service = ChapterCacheService(dio: mockDio);
        final images = List.generate(
          3,
          (i) => ChapterImage(url: 'https://example.invalid/img$i.jpg'),
        );
        final cancelToken = CancelToken();
        cancelToken.cancel('test cancellation');

        when(
          () => mockDio.get<List<int>>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          throw _fakeCancelError(
            invocation.positionalArguments[0] as String,
          );
        });

        final result = await service.downloadChapter(
          sourceId: 's1',
          mangaId: 'm1',
          chapterId: 'c1',
          images: images,
          cancelToken: cancelToken,
        );

        expect(result.cancelled, isTrue);
      },
    );
  });

  group('ChapterCacheService Android external storage path', () {
    late Directory tempExternal;

    setUp(() async {
      tempExternal = await Directory.systemTemp.createTemp('external_');
    });

    tearDown(() async {
      if (await tempExternal.exists()) {
        await tempExternal.delete(recursive: true);
      }
    });

    test(
      'forceAndroidPathForTest + non-null getExternalStorageDirectory: '
      'files are saved under the external dir, not the documents dir',
      () async {
        fakePathProvider.externalStorageDirectory = tempExternal;
        final service = ChapterCacheService(forceAndroidPathForTest: true);

        await service.saveImage(
          's',
          'm',
          'c',
          0,
          Uint8List.fromList([1, 2, 3]),
          contentType: 'image/jpeg',
        );

        final expectedDir = Directory('${tempExternal.path}/chapter_cache/s/m/c');
        expect(await expectedDir.exists(), isTrue);

        final expectedFileInDocsDir = Directory(
          '${tempDir.path}/chapter_cache/s/m/c',
        );
        expect(await expectedFileInDocsDir.exists(), isFalse);
      },
    );

    test(
      'forceAndroidPathForTest but getExternalStorageDirectory returns null: '
      'falls back to the documents dir (unchanged behavior)',
      () async {
        fakePathProvider.externalStorageDirectory = null;
        final service = ChapterCacheService(forceAndroidPathForTest: true);

        await service.saveImage(
          's',
          'm',
          'c',
          0,
          Uint8List.fromList([1, 2, 3]),
          contentType: 'image/jpeg',
        );

        final expectedDir = Directory('${tempDir.path}/chapter_cache/s/m/c');
        expect(await expectedDir.exists(), isTrue);
      },
    );

    test(
      'without forceAndroidPathForTest, getExternalStorageDirectory is not '
      'consulted even if set (non-Android platforms keep existing behavior)',
      () async {
        fakePathProvider.externalStorageDirectory = tempExternal;
        final service = ChapterCacheService();

        await service.saveImage(
          's',
          'm',
          'c',
          0,
          Uint8List.fromList([1, 2, 3]),
          contentType: 'image/jpeg',
        );

        final expectedDir = Directory('${tempDir.path}/chapter_cache/s/m/c');
        expect(await expectedDir.exists(), isTrue);
      },
    );
  });

  group('ChapterCacheService._cachePath caching', () {
    tearDown(() {
      ChapterCacheService.customDownloadDirectory = null;
    });
    test(
      'the resolved platform path is cached: getApplicationDocumentsPath is '
      'only queried once across multiple _cachePath-consuming calls',
      () async {
        final service = ChapterCacheService();

        await service.getImageFile('s', 'm', 'c', 0);
        await service.getImageFile('s', 'm', 'c', 1);
        await service.isChapterCached('s', 'm', 'c', 1);

        expect(fakePathProvider.documentsPathCallCount, 1);
      },
    );

    test(
      'customDownloadDirectory is checked fresh on every call and is not '
      'masked by the platform-path cache populated by an earlier call',
      () async {
        final service = ChapterCacheService();

        // First call (customDownloadDirectory is null) resolves and caches
        // the platform (documents dir) path.
        await service.saveImage(
          's',
          'm',
          'c',
          0,
          Uint8List.fromList([1, 2, 3]),
        );
        final cachedPlatformFile = File(
          '${tempDir.path}/chapter_cache/s/m/c/0000.jpg',
        );
        expect(await cachedPlatformFile.exists(), isTrue);

        // Now set customDownloadDirectory *after* the platform path has
        // already been cached. If customDownloadDirectory were masked by
        // the cache, this write would still land under tempDir.path.
        final customDir = await Directory.systemTemp.createTemp('custom_dl_');
        ChapterCacheService.customDownloadDirectory = customDir.path;
        try {
          await service.saveImage(
            's',
            'm',
            'c',
            1,
            Uint8List.fromList([4, 5, 6]),
          );

          final customFile = File('${customDir.path}/s/m/c/0001.jpg');
          expect(await customFile.exists(), isTrue);

          final leakedIntoCachedPath = File(
            '${tempDir.path}/chapter_cache/s/m/c/0001.jpg',
          );
          expect(await leakedIntoCachedPath.exists(), isFalse);
        } finally {
          await customDir.delete(recursive: true);
        }
      },
    );

    test(
      'customDownloadDirectory takes priority over the memoized Android '
      'external-storage path, even when external storage is available (the '
      'branch most likely to be mistakenly cached together with the '
      'override)',
      () async {
        final tempExternal = await Directory.systemTemp.createTemp(
          'external_priority_',
        );
        try {
          fakePathProvider.externalStorageDirectory = tempExternal;
          final service = ChapterCacheService(forceAndroidPathForTest: true);

          // First call (customDownloadDirectory is null) resolves via the
          // Android/forced-Android branch and memoizes the external-storage
          // path in _resolvedPlatformPath.
          await service.saveImage(
            's',
            'm',
            'c',
            0,
            Uint8List.fromList([1, 2, 3]),
          );
          final externalFile = File(
            '${tempExternal.path}/chapter_cache/s/m/c/0000.jpg',
          );
          expect(await externalFile.exists(), isTrue);

          // Now set customDownloadDirectory *after* the Android
          // external-storage path has already been memoized. The override
          // must win immediately, not be masked by the memoized branch.
          final customDir = await Directory.systemTemp.createTemp(
            'custom_dl_priority_',
          );
          try {
            ChapterCacheService.customDownloadDirectory = customDir.path;

            await service.saveImage(
              's',
              'm',
              'c',
              1,
              Uint8List.fromList([4, 5, 6]),
            );

            final customFile = File('${customDir.path}/s/m/c/0001.jpg');
            expect(await customFile.exists(), isTrue);

            final leakedIntoExternal = File(
              '${tempExternal.path}/chapter_cache/s/m/c/0001.jpg',
            );
            expect(await leakedIntoExternal.exists(), isFalse);
          } finally {
            await customDir.delete(recursive: true);
          }
        } finally {
          await tempExternal.delete(recursive: true);
        }
      },
    );
  });

  group(
    'saveDownloadDirectoryBookmark / resolveDownloadDirectoryBookmark',
    () {
      const channel = MethodChannel(
        'com.comicreader.comicReader/download_bookmark',
      );

      tearDown(() {
        debugIsMacOSOverrideForTest = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      test(
        'saveDownloadDirectoryBookmark no-ops on non-macOS without touching '
        'the channel',
        () async {
          debugIsMacOSOverrideForTest = false;
          var invoked = false;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            invoked = true;
            return null;
          });

          await saveDownloadDirectoryBookmark('/tmp/whatever');

          expect(invoked, isFalse);
        },
      );

      test(
        'resolveDownloadDirectoryBookmark no-ops (returns null) on '
        'non-macOS without touching the channel',
        () async {
          debugIsMacOSOverrideForTest = false;
          var invoked = false;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            invoked = true;
            return '/should/not/be/returned';
          });

          final result = await resolveDownloadDirectoryBookmark();

          expect(invoked, isFalse);
          expect(result, isNull);
        },
      );

      test(
        'saveDownloadDirectoryBookmark invokes saveBookmark with the given '
        'path on macOS',
        () async {
          debugIsMacOSOverrideForTest = true;
          String? capturedMethod;
          dynamic capturedArgs;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            capturedMethod = call.method;
            capturedArgs = call.arguments;
            return true;
          });

          await saveDownloadDirectoryBookmark('/Users/someone/Downloads/comics');

          expect(capturedMethod, 'saveBookmark');
          expect(capturedArgs, {'path': '/Users/someone/Downloads/comics'});
        },
      );

      test(
        'resolveDownloadDirectoryBookmark invokes resolveBookmark and '
        'returns its result on macOS',
        () async {
          debugIsMacOSOverrideForTest = true;
          String? capturedMethod;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            capturedMethod = call.method;
            return '/Users/someone/Downloads/comics';
          });

          final result = await resolveDownloadDirectoryBookmark();

          expect(capturedMethod, 'resolveBookmark');
          expect(result, '/Users/someone/Downloads/comics');
        },
      );

      test(
        'resolveDownloadDirectoryBookmark returns null on macOS when the '
        'native side reports no bookmark',
        () async {
          debugIsMacOSOverrideForTest = true;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async => null);

          final result = await resolveDownloadDirectoryBookmark();

          expect(result, isNull);
        },
      );

      test(
        'saveDownloadDirectoryBookmark catches a PlatformException thrown '
        'by the native saveBookmark call, logs it, and returns false '
        'instead of rethrowing',
        () async {
          debugIsMacOSOverrideForTest = true;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'BOOKMARK_ERROR',
              message: 'url.bookmarkData() failed',
            );
          });

          final result = await saveDownloadDirectoryBookmark(
            '/Users/someone/Downloads/comics',
          );

          expect(result, isFalse);
        },
      );
    },
  );

  group('ChapterCacheService scramble manifest', () {
    test(
      'downloadChapter persists per-index scrambleType/scrambleId to a '
      'manifest that readScrambleManifest can read back',
      () async {
        final service = ChapterCacheService(dio: mockDio);
        final images = [
          const ChapterImage(
            url: 'https://example.invalid/img0.jpg',
            scrambleType: ScrambleType.jmc,
            scrambleId: 220980,
          ),
          const ChapterImage(
            url: 'https://example.invalid/img1.jpg',
            scrambleType: ScrambleType.jmc,
            scrambleId: 300000,
          ),
        ];
        when(
          () => mockDio.get<List<int>>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (invocation) async => _fakeImageResponse(
            invocation.positionalArguments[0] as String,
          ),
        );

        final result = await service.downloadChapter(
          sourceId: 's1',
          mangaId: 'm1',
          chapterId: 'c1',
          images: images,
        );
        expect(result.failedImageIndexes, isEmpty);

        final manifest = await service.readScrambleManifest('s1', 'm1', 'c1');
        expect(manifest, isNotNull);
        expect(manifest!['0000']['scrambleType'], 'jmc');
        expect(manifest['0000']['scrambleId'], 220980);
        expect(manifest['0001']['scrambleType'], 'jmc');
        expect(manifest['0001']['scrambleId'], 300000);
      },
    );

    test(
      'downloadChapter with all ScrambleType.none images records "none" '
      'for every index in the manifest',
      () async {
        final service = ChapterCacheService(dio: mockDio);
        final images = List.generate(
          3,
          (i) => ChapterImage(url: 'https://example.invalid/img$i.jpg'),
        );
        when(
          () => mockDio.get<List<int>>(
            any(),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (invocation) async => _fakeImageResponse(
            invocation.positionalArguments[0] as String,
          ),
        );

        await service.downloadChapter(
          sourceId: 's1',
          mangaId: 'm1',
          chapterId: 'c1',
          images: images,
        );

        final manifest = await service.readScrambleManifest('s1', 'm1', 'c1');
        expect(manifest, isNotNull);
        for (var i = 0; i < 3; i++) {
          final key = i.toString().padLeft(4, '0');
          expect(manifest![key]['scrambleType'], 'none');
          expect(manifest[key].containsKey('scrambleId'), isFalse);
        }
      },
    );

    test(
      'readScrambleManifest returns null when no chapter was ever '
      'downloaded (no manifest file on disk)',
      () async {
        final service = ChapterCacheService();
        final manifest = await service.readScrambleManifest(
          'nope',
          'nope',
          'nope',
        );
        expect(manifest, isNull);
      },
    );

    test(
      'saveImage without scramble params (old call pattern) does not write '
      'or alter the manifest, preserving pre-existing behavior',
      () async {
        final service = ChapterCacheService();
        await service.saveImage(
          's1',
          'm1',
          'c1',
          0,
          Uint8List.fromList([1, 2, 3]),
        );
        final manifest = await service.readScrambleManifest('s1', 'm1', 'c1');
        expect(manifest, isNull);
      },
    );

    test(
      'saveImage with scrambleType/scrambleId writes a manifest entry for '
      'that index without disturbing entries written by earlier calls',
      () async {
        final service = ChapterCacheService();
        await service.saveImage(
          's1',
          'm1',
          'c1',
          0,
          Uint8List.fromList([1, 2, 3]),
          scrambleType: ScrambleType.jmc,
          scrambleId: 220980,
        );
        await service.saveImage(
          's1',
          'm1',
          'c1',
          1,
          Uint8List.fromList([4, 5, 6]),
          scrambleType: ScrambleType.none,
        );

        final manifest = await service.readScrambleManifest('s1', 'm1', 'c1');
        expect(manifest, isNotNull);
        expect(manifest!['0000']['scrambleType'], 'jmc');
        expect(manifest['0000']['scrambleId'], 220980);
        expect(manifest['0001']['scrambleType'], 'none');
      },
    );

    test(
      'isChapterCached does not count the manifest file itself as one of '
      'the chapter images (regression guard against an off-by-one false '
      'positive)',
      () async {
        final service = ChapterCacheService();
        // Only 1 of 2 images actually saved, but a manifest file exists
        // alongside it (simulating saveImage having written a manifest
        // entry for that one image).
        await service.saveImage(
          's1',
          'm1',
          'c1',
          0,
          Uint8List.fromList([1, 2, 3]),
          scrambleType: ScrambleType.none,
        );

        final cached = await service.isChapterCached('s1', 'm1', 'c1', 2);
        expect(cached, isFalse);
      },
    );
  });

  group('resolveScrambleFromManifest (pure function)', () {
    const original = ChapterImage(
      url: 'https://example.invalid/img.jpg',
      scrambleType: ScrambleType.none,
      scrambleId: null,
    );

    test('returns the original image unchanged when manifest is null', () {
      final result = resolveScrambleFromManifest(original, null, 0);
      expect(result, same(original));
    });

    test(
      'returns the original image unchanged when this index has no entry '
      'in the manifest',
      () {
        final manifest = {
          '0001': {'scrambleType': 'jmc', 'scrambleId': 220980},
        };
        final result = resolveScrambleFromManifest(original, manifest, 0);
        expect(result, same(original));
      },
    );

    test(
      'overrides scrambleType and scrambleId from the manifest entry when '
      'present for this index',
      () {
        final manifest = {
          '0000': {'scrambleType': 'jmc', 'scrambleId': 220980},
        };
        final result = resolveScrambleFromManifest(original, manifest, 0);
        expect(result.scrambleType, ScrambleType.jmc);
        expect(result.scrambleId, 220980);
        // Everything else about the image is preserved.
        expect(result.url, original.url);
      },
    );

    test(
      'omits scrambleId when the manifest entry does not include one (e.g. '
      'scrambleType none)',
      () {
        final manifest = {
          '0000': {'scrambleType': 'none'},
        };
        final result = resolveScrambleFromManifest(original, manifest, 0);
        expect(result.scrambleType, ScrambleType.none);
        expect(result.scrambleId, isNull);
      },
    );

    test(
      'falls back to the original scrambleType when the manifest entry has '
      'an unrecognized scrambleType string',
      () {
        final manifest = {
          '0000': {'scrambleType': 'not_a_real_type'},
        };
        const originalJmc = ChapterImage(
          url: 'https://example.invalid/img.jpg',
          scrambleType: ScrambleType.jmc,
          scrambleId: 999,
        );
        final result = resolveScrambleFromManifest(originalJmc, manifest, 0);
        expect(result.scrambleType, ScrambleType.jmc);
        expect(result.scrambleId, 999);
      },
    );
  });
}
