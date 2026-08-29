import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/local/download_manager.dart';

void main() {
  group('DownloadTask', () {
    test('new fields default correctly when constructed', () {
      final task = DownloadTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Title',
        chapterTitle: 'Chapter 1',
      );
      expect(task.totalImages, 0);
      expect(task.completedImages, 0);
      expect(task.failedImageIndexes, isEmpty);
      expect(task.retryCount, 0);
      expect(task.pausedAt, isNull);
      expect(task.priority, 0);
    });

    test('toJson/fromJson round-trips new fields', () {
      final task = DownloadTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Title',
        chapterTitle: 'Chapter 1',
        status: DownloadTaskStatus.partiallyFailed,
        totalImages: 10,
        completedImages: 7,
        failedImageIndexes: [3, 8],
        retryCount: 2,
        priority: 5,
      );
      final restored = DownloadTask.fromJson(task.toJson());
      expect(restored.totalImages, 10);
      expect(restored.completedImages, 7);
      expect(restored.failedImageIndexes, [3, 8]);
      expect(restored.retryCount, 2);
      expect(restored.priority, 5);
      expect(restored.status, DownloadTaskStatus.partiallyFailed);
    });

    test('fromJson tolerates legacy JSON missing new fields', () {
      final legacyJson = {
        'sourceId': 's1',
        'mangaId': 'm1',
        'chapterId': 'c1',
        'mangaTitle': 'Title',
        'chapterTitle': 'Chapter 1',
        'status': DownloadTaskStatus.pending.index,
        'progress': 0,
      };
      final restored = DownloadTask.fromJson(legacyJson);
      expect(restored.totalImages, 0);
      expect(restored.completedImages, 0);
      expect(restored.failedImageIndexes, isEmpty);
      expect(restored.retryCount, 0);
      expect(restored.priority, 0);
    });

    test('paused and partiallyFailed statuses exist', () {
      expect(DownloadTaskStatus.values, contains(DownloadTaskStatus.paused));
      expect(
        DownloadTaskStatus.values,
        contains(DownloadTaskStatus.partiallyFailed),
      );
    });
  });
}
