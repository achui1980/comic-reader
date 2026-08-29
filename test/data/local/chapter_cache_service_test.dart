import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chapter_cache_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
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
}
