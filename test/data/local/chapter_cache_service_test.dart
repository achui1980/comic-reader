import 'dart:io';
import 'package:dio/dio.dart';
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

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;
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

  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chapter_cache_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
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
}
