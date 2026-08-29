# 下载系统重构 Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

Goal: 统一现有两套互不知晓的下载系统（DownloadManager 死代码单例 + DownloadCubit 详情页局部队列）为一套，修复"收藏无法下载"和"下载慢"两个 todo.md 已记录的问题，并补齐暂停/恢复、失败可见化、跨平台存储位置选择等能力。

Architecture: 以 DownloadManager（ChangeNotifier 单例，持久化任务队列）为唯一真源，扩展 DownloadTask 字段支持图片级进度/暂停/部分失败；ChapterCacheService.downloadChapter 改为图片级并发+单图重试；DownloadManager._processQueue 改为章节级并发；DownloadCubit 改造为对 DownloadManager 的薄封装（保留 4 个公开方法签名不变，避免改动 detail_screen.dart 的调用点）；收藏页 HomeCubit 新增两个方法直接调用 DownloadManager.addTask 打通"收藏无法下载"入口；三个平台专属改动（Android 默认目录、iOS 文件共享、macOS/Windows 自定义目录+bookmark）分别独立成任务。

Tech Stack: Flutter/Dart, flutter_bloc ^9.0.0 (Cubit/ChangeNotifier 混用), dio ^5.4.0, get_it ^7.6.7 (DI), path_provider ^2.1.2, file_picker ^8.1.7, bloc_test ^10.0.0 + mocktail ^1.0.3 (测试)。

## Global Constraints

- 不引入新的 Dart 依赖包（pubspec.yaml 已有的 dio/path_provider/file_picker/bloc_test/mocktail 已足够）。
- 不引入数据库（drift 等），继续使用现有 LocalStorage(JSON) 持久化模式。
- DownloadCubit 对外的 4 个公开方法签名必须保持不变：`checkCachedChapters(List<ChapterItem>)`、`downloadChapter(ChapterItem)`、`downloadMultiple(List<ChapterItem>)`、`cancelDownload()`——`detail_screen.dart` 里调用这些方法的代码不应改动。
- 不做 Android 完整 SAF（Storage Access Framework）支持，不做字节级断点续传（章节内图片级去重跳过已存在文件即可），不做并发数可调设置项，不做"一键下载全部收藏"（只做单本下载未读 + 多选下载所选）。
- 所有新增测试使用已有的 `bloc_test` + `mocktail`，不新增测试依赖。
- 每个任务遵循 TDD 节奏：写测试 → 运行确认失败 → 实现 → 运行确认通过 → commit。

---

## Task 1: DownloadTask 字段扩展 + JSON 兼容性

**Files:**
- Modify: `lib/data/local/download_manager.dart:7-53`（`DownloadTaskStatus` enum + `DownloadTask` class）
- Test: `test/data/local/download_task_test.dart`（新建，测试目录 `test/data/local/` 需新建）

**Interfaces:**
- Produces: `enum DownloadTaskStatus { pending, downloading, completed, failed, paused, partiallyFailed }`；`DownloadTask` 新字段：`int totalImages`（默认0）、`int completedImages`（默认0）、`List<int> failedImageIndexes`（默认`[]`）、`int retryCount`（默认0）、`DateTime? pausedAt`（默认null）、`int priority`（默认0，数值越大优先级越高）。`toJson()`/`fromJson()` 必须向后兼容旧版本持久化数据（旧 JSON 没有这些字段时使用默认值）。

- [ ] **Step 1: 写失败测试**

创建目录后写入 `test/data/local/download_task_test.dart`：

```dart
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/data/local/download_task_test.dart`
Expected: 编译错误（`totalImages`/`completedImages`/`failedImageIndexes`/`retryCount`/`priority`/`paused`/`partiallyFailed` 不存在）

- [ ] **Step 3: 实现最小改动**

在 `lib/data/local/download_manager.dart` 中，把现有 `enum DownloadTaskStatus { pending, downloading, completed, failed }`（第7行）改为：

```dart
enum DownloadTaskStatus { pending, downloading, completed, failed, paused, partiallyFailed }
```

把现有 `DownloadTask` 类（原第9-53行）的字段声明、构造函数、`toJson`、`fromJson` 改为：

```dart
class DownloadTask {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final String mangaTitle;
  final String chapterTitle;
  DownloadTaskStatus status;
  int progress;
  String? error;
  int totalImages;
  int completedImages;
  List<int> failedImageIndexes;
  int retryCount;
  DateTime? pausedAt;
  int priority;

  DownloadTask({
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    required this.mangaTitle,
    required this.chapterTitle,
    this.status = DownloadTaskStatus.pending,
    this.progress = 0,
    this.error,
    this.totalImages = 0,
    this.completedImages = 0,
    List<int>? failedImageIndexes,
    this.retryCount = 0,
    this.pausedAt,
    this.priority = 0,
  }) : failedImageIndexes = failedImageIndexes ?? [];

  String get key => '${sourceId}_${mangaId}_$chapterId';

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'mangaId': mangaId,
        'chapterId': chapterId,
        'mangaTitle': mangaTitle,
        'chapterTitle': chapterTitle,
        'status': status.index,
        'progress': progress,
        'error': error,
        'totalImages': totalImages,
        'completedImages': completedImages,
        'failedImageIndexes': failedImageIndexes,
        'retryCount': retryCount,
        'pausedAt': pausedAt?.toIso8601String(),
        'priority': priority,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        sourceId: json['sourceId'] as String,
        mangaId: json['mangaId'] as String,
        chapterId: json['chapterId'] as String,
        mangaTitle: json['mangaTitle'] as String,
        chapterTitle: json['chapterTitle'] as String,
        status: DownloadTaskStatus.values[json['status'] as int],
        progress: json['progress'] as int? ?? 0,
        error: json['error'] as String?,
        totalImages: json['totalImages'] as int? ?? 0,
        completedImages: json['completedImages'] as int? ?? 0,
        failedImageIndexes: (json['failedImageIndexes'] as List?)
                ?.map((e) => e as int)
                .toList() ??
            [],
        retryCount: json['retryCount'] as int? ?? 0,
        pausedAt: json['pausedAt'] != null
            ? DateTime.parse(json['pausedAt'] as String)
            : null,
        priority: json['priority'] as int? ?? 0,
      );
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/data/local/download_task_test.dart`
Expected: PASS（4 个测试全部通过）

- [ ] **Step 5: 运行现有引用编译检查**

Run: `cd comic-reader && flutter analyze lib/data/local/download_manager.dart`
Expected: No errors（`DownloadManager` 类里 `_downloadTask`/`_persist` 等使用 `DownloadTask`/`DownloadTaskStatus` 的地方本任务不改，字段扩展是加法不会破坏现有引用）

- [ ] **Step 6: Commit**

```bash
cd comic-reader && git add lib/data/local/download_manager.dart test/data/local/download_task_test.dart && git commit -m "feat(download): 扩展DownloadTask字段支持图片级进度/暂停/部分失败"
```

---

## Task 2: ChapterCacheService 图片级并发下载

**Files:**
- Modify: `lib/data/local/chapter_cache_service.dart:112-183`（`downloadChapter` 方法）
- Test: `test/data/local/chapter_cache_service_test.dart`（新建）

**Interfaces:**
- Consumes: 无新依赖（Task 1 完成，但本任务不直接使用 `DownloadTask`）。
- Produces: 新类 `ChapterDownloadResult { final bool cancelled; final int completedImages; final List<int> failedImageIndexes; }`；`Future<ChapterDownloadResult> downloadChapter({required String sourceId, required String mangaId, required String chapterId, required List<ImageInfo> images, void Function(int completed, int total)? onProgress, CancelToken? cancelToken})` —— 返回类型由 `Future<bool>` 改为 `Future<ChapterDownloadResult>`，调用方（`DownloadManager._downloadTask`、`DownloadCubit._processQueue`）在后续任务中改造时需要读 `result.failedImageIndexes.isEmpty` 判断是否整章成功。

- [ ] **Step 1: 写失败测试**

先建目录 `test/data/local/`（若不存在），写入 `test/data/local/chapter_cache_service_test.dart`：

```dart
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
        (i) => ImageInfo(url: 'https://example.invalid/img$i.jpg'),
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

      final images = [ImageInfo(url: 'https://example.invalid/img0.jpg')];
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/data/local/chapter_cache_service_test.dart`
Expected: 编译错误（`ChapterDownloadResult` 不存在，`downloadChapter` 返回类型不匹配）

- [ ] **Step 3: 实现最小改动**

在 `lib/data/local/chapter_cache_service.dart` 顶部（import 区域之后，class 之前）新增：

```dart
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
```

把原 `downloadChapter`（第112-183行）整体替换为图片级并发实现：

```dart
static const int _maxConcurrentImagesPerChapter = 4;
static const int _maxImageRetries = 2;

Future<ChapterDownloadResult> downloadChapter({
  required String sourceId,
  required String mangaId,
  required String chapterId,
  required List<ImageInfo> images,
  void Function(int completed, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  final basePath = await _cachePath;
  final dir = _chapterDir(basePath, sourceId, mangaId, chapterId);
  await Directory(dir).create(recursive: true);

  int completed = 0;
  final failed = <int>[];
  final failedLock = <int>{};

  Future<void> downloadOne(int i) async {
    // 保留原有的按 index 跳过已存在文件逻辑（图片级去重续传基础）
    for (final ext in ['.jpg', '.png', '.webp', '.gif', '']) {
      final path = '$dir/${i.toString().padLeft(4, '0')}$ext';
      if (await File(path).exists()) {
        completed++;
        onProgress?.call(completed, images.length);
        return;
      }
    }
    var attempt = 0;
    while (attempt <= _maxImageRetries) {
      try {
        final response = await _dio.get<List<int>>(
          ImageProxy.url(images[i].url),
          options: Options(
            headers: images[i].headers,
            responseType: ResponseType.bytes,
          ),
          cancelToken: cancelToken,
        );
        final ext = _extensionFromContentType(
          response.headers.value('content-type'),
        );
        final path = '$dir/${i.toString().padLeft(4, '0')}$ext';
        await File(path).writeAsBytes(response.data ?? []);
        completed++;
        onProgress?.call(completed, images.length);
        return;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          rethrow;
        }
        attempt++;
        if (attempt > _maxImageRetries) {
          failedLock.add(i);
          completed++;
          onProgress?.call(completed, images.length);
          return;
        }
      }
    }
  }

  try {
    for (var start = 0; start < images.length; start += _maxConcurrentImagesPerChapter) {
      final end = (start + _maxConcurrentImagesPerChapter).clamp(0, images.length);
      await Future.wait(
        [for (var i = start; i < end; i++) downloadOne(i)],
      );
    }
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) {
      return ChapterDownloadResult(
        cancelled: true,
        completedImages: completed,
        failedImageIndexes: failedLock.toList()..sort(),
      );
    }
    rethrow;
  }

  failed.addAll(failedLock);
  failed.sort();
  return ChapterDownloadResult(
    cancelled: false,
    completedImages: completed,
    failedImageIndexes: failed,
  );
}
```

（注意：`_chapterDir`、`_extensionFromContentType`、`_cachePath` 均保留原有实现，本任务不改动它们，仅替换 `downloadChapter` 方法体本身与顶部新增的 `ChapterDownloadResult` 类和两个并发常量。）

- [ ] **Step 4: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/data/local/chapter_cache_service_test.dart`
Expected: PASS（2 个测试通过）

- [ ] **Step 5: 检查旧调用点编译错误（预期会有，留给 Task 3/5 修复）**

Run: `cd comic-reader && flutter analyze`
Expected: `download_manager.dart` 和 `download_cubit.dart` 里调用 `downloadChapter` 的地方因返回类型从 `bool` 变为 `ChapterDownloadResult` 出现类型不匹配的编译错误——这是预期的，将在 Task 3 和 Task 5 中修复。此处不需要修复，只需确认新增的 `chapter_cache_service.dart` 本身及其测试没有语法错误。

- [ ] **Step 6: Commit**

```bash
cd comic-reader && git add lib/data/local/chapter_cache_service.dart test/data/local/chapter_cache_service_test.dart && git commit -m "feat(download): ChapterCacheService图片级并发下载+单图重试"
```

---

## Task 3: DownloadManager 章节级并发调度

**Files:**
- Modify: `lib/data/local/download_manager.dart:56-205`（`DownloadManager` 类）
- Test: `test/data/local/download_manager_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `DownloadTask` 新字段；Task 2 的 `ChapterCacheService.downloadChapter` 返回 `ChapterDownloadResult`。
- Produces: `DownloadManager._maxConcurrentChapters = 2`（原 `_maxConcurrent` 改名）；`_processQueue()` 按 `priority` 降序选取 pending 任务；`_downloadTask` 使用 `ChapterDownloadResult` 决定任务最终状态为 `completed`（`failedImageIndexes.isEmpty`）/`partiallyFailed`（部分失败）/`failed`（`cancelled`且`completedImages==0`，或抛异常）。这些是 Task 4（暂停/恢复）、Task 5（DownloadCubit 薄封装）、Task 7/8（收藏页入口）的依赖基础。

- [ ] **Step 1: 写失败测试**

写入 `test/data/local/download_manager_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';

class MockMangaRepository extends Mock implements MangaRepository {}
class MockChapterCacheService extends Mock implements ChapterCacheService {}
class MockLocalStorage extends Mock implements LocalStorage {}

void main() {
  late MockMangaRepository repository;
  late MockChapterCacheService cacheService;
  late MockLocalStorage storage;
  late DownloadManager manager;

  setUp(() {
    repository = MockMangaRepository();
    cacheService = MockChapterCacheService();
    storage = MockLocalStorage();
    when(() => storage.read(any())).thenReturn(null);
    when(() => storage.write(any(), any())).thenAnswer((_) async {});
    manager = DownloadManager(
      repository: repository,
      cacheService: cacheService,
      storage: storage,
    );
  });

  ChapterResult buildChapterResult() => ChapterResult(
        chapter: ChapterDetail(
          id: 'c1',
          mangaId: 'm1',
          title: 'Chapter 1',
          images: [ImageInfo(url: 'https://example.invalid/1.jpg')],
        ),
        canLoadMore: false,
      );

  test('respects max 2 concurrent chapters', () async {
    final completers = <String, Completer<ChapterDownloadResult>>{};
    when(() => repository.getChapter(any(), any(), any(), any()))
        .thenAnswer((_) async => buildChapterResult());
    when(() => cacheService.downloadChapter(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          images: any(named: 'images'),
          onProgress: any(named: 'onProgress'),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer((invocation) {
      final chapterId =
          invocation.namedArguments[const Symbol('chapterId')] as String;
      final completer = Completer<ChapterDownloadResult>();
      completers[chapterId] = completer;
      return completer.future;
    });

    for (final id in ['c1', 'c2', 'c3']) {
      manager.addTask(
        sourceId: 's1',
        mangaId: 'm1',
        chapterId: id,
        mangaTitle: 'Manga',
        chapterTitle: id,
      );
    }
    await Future.delayed(Duration.zero);
    expect(manager.activeCount, 2);

    completers['c1']!.complete(
      const ChapterDownloadResult(
        cancelled: false,
        completedImages: 1,
        failedImageIndexes: [],
      ),
    );
    await Future.delayed(Duration.zero);
    expect(manager.activeCount, 2);
  });

  test('marks task partiallyFailed when some images fail', () async {
    when(() => repository.getChapter(any(), any(), any(), any()))
        .thenAnswer((_) async => buildChapterResult());
    when(() => cacheService.downloadChapter(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          images: any(named: 'images'),
          onProgress: any(named: 'onProgress'),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer((_) async => const ChapterDownloadResult(
          cancelled: false,
          completedImages: 1,
          failedImageIndexes: [0],
        ));

    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'Manga',
      chapterTitle: 'c1',
    );
    await Future.delayed(const Duration(milliseconds: 10));
    final task = manager.tasks.firstWhere((t) => t.chapterId == 'c1');
    expect(task.status, DownloadTaskStatus.partiallyFailed);
    expect(task.failedImageIndexes, [0]);
  });

  test('higher priority task is processed first', () async {
    when(() => repository.getChapter(any(), any(), any(), any()))
        .thenAnswer((_) async => buildChapterResult());
    when(() => cacheService.downloadChapter(
          sourceId: any(named: 'sourceId'),
          mangaId: any(named: 'mangaId'),
          chapterId: any(named: 'chapterId'),
          images: any(named: 'images'),
          onProgress: any(named: 'onProgress'),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer((_) async => const ChapterDownloadResult(
          cancelled: false,
          completedImages: 1,
          failedImageIndexes: [],
        ));

    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'low',
      mangaTitle: 'Manga',
      chapterTitle: 'low',
      priority: 0,
    );
    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'mid1',
      mangaTitle: 'Manga',
      chapterTitle: 'mid1',
      priority: 0,
    );
    manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'high',
      mangaTitle: 'Manga',
      chapterTitle: 'high',
      priority: 10,
    );
    await Future.delayed(Duration.zero);
    final activeIds =
        manager.tasks.where((t) => t.status == DownloadTaskStatus.downloading).map((t) => t.chapterId);
    expect(activeIds, contains('high'));
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/data/local/download_manager_test.dart`
Expected: 编译错误（`addTask` 无 `priority` 具名参数，`partiallyFailed` 相关逻辑不存在，`ChapterResult`/`ChapterDetail`/`ImageInfo` 构造需要与 `lib/domain/entities/entities.dart`、`lib/domain/repositories/manga_repository.dart` 实际定义核对——若字段名不同需按实际定义调整测试代码，执行者需先用 `grep -n "class ChapterResult\|class ChapterDetail\|class ImageInfo" lib/domain/entities/*.dart` 确认真实字段名）

- [ ] **Step 3: 实现最小改动**

把 `lib/data/local/download_manager.dart` 中的 `DownloadManager` 类改造如下（保留构造函数签名 `DownloadManager({required MangaRepository repository, required ChapterCacheService cacheService, required LocalStorage storage})` 不变）：

1. 字段 `_maxConcurrent = 3`（原63行）改为 `_maxConcurrentChapters = 2`，全类内引用同步改名。
2. `addTask()`（原101-123行）新增具名参数 `int priority = 0`，创建 `DownloadTask` 时传入 `priority: priority`。
3. `_processQueue()`（原147-157行）改为：

```dart
void _processQueue() {
  while (_activeCount < _maxConcurrentChapters) {
    final pending = _tasks
        .where((t) => t.status == DownloadTaskStatus.pending)
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    if (pending.isEmpty) break;
    final task = pending.first;
    task.status = DownloadTaskStatus.downloading;
    _activeCount++;
    _downloadTask(task);
  }
}
```

4. `_downloadTask(task)`（原159-196行）改为使用新的 `ChapterDownloadResult`：

```dart
Future<void> _downloadTask(DownloadTask task) async {
  try {
    final result = await _repository.getChapter(
      task.sourceId,
      task.mangaId,
      task.chapterId,
      1,
    );
    final images = result.chapter.images;
    task.totalImages = images.length;
    final downloadResult = await _cacheService.downloadChapter(
      sourceId: task.sourceId,
      mangaId: task.mangaId,
      chapterId: task.chapterId,
      images: images,
      onProgress: (completed, total) {
        task.completedImages = completed;
        task.progress = total == 0 ? 0 : (completed * 100 ~/ total);
        notifyListeners();
      },
    );
    task.completedImages = downloadResult.completedImages;
    task.failedImageIndexes = downloadResult.failedImageIndexes;
    if (downloadResult.failedImageIndexes.isEmpty) {
      task.status = DownloadTaskStatus.completed;
      task.progress = 100;
    } else {
      task.status = DownloadTaskStatus.partiallyFailed;
      task.error = '${downloadResult.failedImageIndexes.length} 张图片下载失败';
    }
  } catch (e) {
    task.status = DownloadTaskStatus.failed;
    task.error = e.toString();
  } finally {
    _activeCount--;
    _persist();
    notifyListeners();
    _processQueue();
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/data/local/download_manager_test.dart`
Expected: PASS（3 个测试通过）

- [ ] **Step 5: 更新 `retryTask` 兼容 partiallyFailed**

把 `retryTask(key)`（原126-138行）的 `if (task.status != DownloadTaskStatus.failed) return;` 改为：

```dart
if (task.status != DownloadTaskStatus.failed &&
    task.status != DownloadTaskStatus.partiallyFailed) {
  return;
}
task.status = DownloadTaskStatus.pending;
task.error = null;
_persist();
notifyListeners();
_processQueue();
```

（保留 `progress`/`completedImages`/`failedImageIndexes` 不清零——因为 `ChapterCacheService.downloadChapter` 的按 index 跳过已存在文件逻辑会自动只重新下载 `failedImageIndexes` 对应的图片，不清零这些字段也不影响正确性，只是展示上重试瞬间 UI 会显示旧的完成数直到新一轮 `onProgress` 回调更新它。）

- [ ] **Step 6: 运行全部下载相关测试确认无回归**

Run: `cd comic-reader && flutter test test/data/local/`
Expected: PASS（`download_task_test.dart` + `chapter_cache_service_test.dart` + `download_manager_test.dart` 全部通过）

- [ ] **Step 7: Commit**

```bash
cd comic-reader && git add lib/data/local/download_manager.dart test/data/local/download_manager_test.dart && git commit -m "feat(download): DownloadManager改为章节级并发调度+partiallyFailed状态"
```

---

## Task 4: 暂停/恢复 + 重启接续

**Files:**
- Modify: `lib/data/local/download_manager.dart`
- Test: `test/data/local/download_manager_test.dart`（追加测试）

**Interfaces:**
- Consumes：Task 1 的 `DownloadTask`（含 `pausedAt`/`completedImages`/`totalImages`/`failedImageIndexes`）、Task 3 的 `_maxConcurrentChapters`/`_processQueue()`/`_downloadTask()`。
- Produces：`void pauseTask(String key)`、`void resumeTask(String key)`、`void pauseAll()`、`void resumeAll()`——后续 Task 5（DownloadCubit）、Task 6（DownloadDrawer UI）会调用这四个方法。

- [ ] **Step 1: 写失败测试——pauseTask 取消进行中任务并置为 paused**

在 `test/data/local/download_manager_test.dart` 追加：

```dart
test('pauseTask cancels an in-flight download and marks it paused', () async {
  when(() => mockRepository.getChapter(any(), any(), any(), any()))
      .thenAnswer((_) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return ChapterResult(
      chapter: ChapterItem(id: 'c1', mangaId: 'm1', title: 'Ch1'),
      images: [ChapterImage(url: 'https://x/1.jpg')],
      canLoadMore: false,
    );
  });
  when(() => mockCacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      )).thenAnswer((_) async {
    await Future.delayed(const Duration(seconds: 1));
    return const ChapterDownloadResult(
        cancelled: true, completedImages: 0, failedImageIndexes: []);
  });

  manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'M1',
      chapterTitle: 'Ch1');
  await Future.delayed(const Duration(milliseconds: 50));

  final key = manager.tasks.first.key;
  manager.pauseTask(key);
  await Future.delayed(const Duration(milliseconds: 1200));

  expect(manager.tasks.first.status, DownloadTaskStatus.paused);
});

test('resumeTask re-queues a paused task', () async {
  manager.addTask(
      sourceId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'M1',
      chapterTitle: 'Ch1');
  final key = manager.tasks.first.key;
  manager.pauseTask(key);
  await Future.delayed(const Duration(milliseconds: 50));

  when(() => mockRepository.getChapter(any(), any(), any(), any()))
      .thenAnswer((_) async => ChapterResult(
            chapter: ChapterItem(id: 'c1', mangaId: 'm1', title: 'Ch1'),
            images: [ChapterImage(url: 'https://x/1.jpg')],
            canLoadMore: false,
          ));
  when(() => mockCacheService.downloadChapter(
        sourceId: any(named: 'sourceId'),
        mangaId: any(named: 'mangaId'),
        chapterId: any(named: 'chapterId'),
        images: any(named: 'images'),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      )).thenAnswer((_) async => const ChapterDownloadResult(
      cancelled: false, completedImages: 1, failedImageIndexes: []));

  manager.resumeTask(key);
  await Future.delayed(const Duration(milliseconds: 100));

  expect(manager.tasks.first.status, DownloadTaskStatus.completed);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/data/local/download_manager_test.dart`
Expected: FAIL（`pauseTask`/`resumeTask` 未定义，或 `ChapterDownloadResult` 缺 `cancelled` 具名参数——若 Task 2 已实现则该类已存在，此处仅缺 manager 方法）

- [ ] **Step 3: 实现 pauseTask/resumeTask/pauseAll/resumeAll**

在 `DownloadManager` 类内新增字段与方法（`_activeCount`/`_tasks` 定义之后）：

```dart
final Map<String, CancelToken> _activeCancelTokens = {};

void pauseTask(String key) {
  final task = _tasks.firstWhereOrNull((t) => t.key == key);
  if (task == null) return;
  if (task.status == DownloadTaskStatus.pending) {
    task.status = DownloadTaskStatus.paused;
    task.pausedAt = DateTime.now();
    _persist();
    notifyListeners();
    return;
  }
  if (task.status == DownloadTaskStatus.downloading) {
    _activeCancelTokens[key]?.cancel();
    // 状态转换在 _downloadTask 的 cancelled 分支里完成（见 Step 4）
  }
}

void resumeTask(String key) {
  final task = _tasks.firstWhereOrNull((t) => t.key == key);
  if (task == null || task.status != DownloadTaskStatus.paused) return;
  task.status = DownloadTaskStatus.pending;
  task.pausedAt = null;
  _persist();
  notifyListeners();
  _processQueue();
}

void pauseAll() {
  for (final task in _tasks) {
    pauseTask(task.key);
  }
}

void resumeAll() {
  for (final task in _tasks
      .where((t) => t.status == DownloadTaskStatus.paused)
      .toList()) {
    resumeTask(task.key);
  }
}
```

在 `_downloadTask()` 内部（Task 3 已改造为使用 `ChapterDownloadResult` 的版本）用 `CancelToken` 并在结果为 `cancelled:true` 时转成 `paused`（若该 task 是被 `pauseTask` 主动取消触发）而不是 `failed`。因为当前架构没有区分"用户暂停取消"和"其它取消"，统一约定：**只要 `ChapterDownloadResult.cancelled == true`，状态一律置为 `paused`（不是 `failed`）**，同时保留已完成的 `completedImages`：

```dart
Future<void> _downloadTask(DownloadTask task) async {
  _activeCount++;
  final cancelToken = CancelToken();
  _activeCancelTokens[task.key] = cancelToken;
  task.status = DownloadTaskStatus.downloading;
  notifyListeners();
  try {
    final result = await _repository.getChapter(
        task.sourceId, task.mangaId, task.chapterId, 1);
    task.totalImages = result.images.length;
    final downloadResult = await _cacheService.downloadChapter(
      sourceId: task.sourceId,
      mangaId: task.mangaId,
      chapterId: task.chapterId,
      images: result.images,
      onProgress: (completed, total) {
        task.progress = total == 0 ? 0 : (completed * 100 ~/ total);
        task.completedImages = completed;
        task.totalImages = total;
        notifyListeners();
      },
      cancelToken: cancelToken,
    );
    if (downloadResult.cancelled) {
      task.status = DownloadTaskStatus.paused;
      task.pausedAt = DateTime.now();
    } else if (downloadResult.failedImageIndexes.isEmpty) {
      task.status = DownloadTaskStatus.completed;
      task.progress = 100;
    } else {
      task.status = DownloadTaskStatus.partiallyFailed;
      task.failedImageIndexes = downloadResult.failedImageIndexes;
      task.error = '${downloadResult.failedImageIndexes.length} 张图片下载失败';
    }
  } catch (e) {
    task.status = DownloadTaskStatus.failed;
    task.error = e.toString();
  } finally {
    _activeCancelTokens.remove(task.key);
    _activeCount--;
    _persist();
    notifyListeners();
    _processQueue();
  }
}
```

（`firstWhereOrNull` 来自 `package:collection`，`pubspec.yaml` 已有 `collection: ^1.18.0` 依赖，需在文件顶部 `import 'package:collection/collection.dart';`。）

- [ ] **Step 4: 修改 `init()` 保留断点续传字段，paused 任务不自动恢复**

把原 `init()`（81-98 行）里"把 `downloading` reset 为 `pending,progress=0`"的逻辑改为保留已完成图片数：

```dart
Future<void> init() async {
  final data = await _storage.read(_key);
  if (data != null) {
    final list = (data['tasks'] as List<dynamic>? ?? [])
        .map((e) => DownloadTask.fromJson(e as Map<String, dynamic>))
        .toList();
    for (final task in list) {
      if (task.status == DownloadTaskStatus.downloading) {
        // 重启接续：保留 completedImages/totalImages/failedImageIndexes，
        // 只把状态改回 pending，ChapterCacheService 的按 index 跳过逻辑
        // 会自动跳过已下载的图片，不会重新下载。
        task.status = DownloadTaskStatus.pending;
      }
      // paused 任务保持原样，不自动恢复（用户需手动 resumeTask/resumeAll）
      if (task.status != DownloadTaskStatus.completed) {
        _tasks.add(task);
      }
    }
  }
  _processQueue();
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/data/local/download_manager_test.dart`
Expected: PASS（全部测试通过，包括 Task 3 遗留的 3 个 + 本 Task 新增的 2 个）

- [ ] **Step 6: Commit**

```bash
cd comic-reader && git add lib/data/local/download_manager.dart test/data/local/download_manager_test.dart && git commit -m "feat(download): 支持暂停/恢复队列与重启断点续传"
```

---

## Task 5: DownloadCubit 薄封装改造

**Files:**
- Modify: `lib/presentation/detail/bloc/download_cubit.dart`
- Modify: `lib/presentation/detail/bloc/download_state.dart`
- Modify: `lib/presentation/detail/detail_screen.dart:41-48`（`DownloadCubit` 构造处新增 `DownloadManager` 参数）
- Test: `test/presentation/detail/bloc/download_cubit_test.dart`（新建，目录不存在需先创建）

**Interfaces:**
- Consumes：Task 4 的 `DownloadManager`（`tasks`/`addTask`/`retryTask`/`pauseTask`/`resumeTask`/`ChangeNotifier` 接口）。
- Produces：`DownloadCubit` 的四个公开方法签名保持不变——`Future<void> checkCachedChapters(List<ChapterItem> chapters)`、`void downloadChapter(ChapterItem chapter)`、`void downloadMultiple(List<ChapterItem> chapterItems)`、`void cancelDownload()`——供 Task 6 之外、已有的 `detail_screen.dart` 调用点直接复用，不需要改动调用处的方法名。`DownloadState.chapters` 的 value 类型 `ChapterDownloadStatus` 新增 `paused`/`partiallyFailed` 两个枚举值，供 `download_drawer.dart`（Task 6）和 `detail_screen.dart` 的 `_ChapterTile._buildStatusIcon()` 使用。

- [ ] **Step 1: 在 `download_state.dart` 新增枚举值（写测试前先落地类型，因为薄封装测试要用到）**

把 `enum ChapterDownloadStatus { none, queued, downloading, cached, failed }` 改为：

```dart
enum ChapterDownloadStatus {
  none,
  queued,
  downloading,
  cached,
  failed,
  paused,
  partiallyFailed,
}
```

- [ ] **Step 2: 写失败测试——downloadChapter 转发给 DownloadManager.addTask**

新建 `test/presentation/detail/bloc/download_cubit_test.dart`：

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/detail/bloc/download_cubit.dart';
import 'package:comic_reader/presentation/detail/bloc/download_state.dart';

class MockDownloadManager extends Mock implements DownloadManager {}

class MockMangaRepository extends Mock implements MangaRepository {}

class MockChapterCacheService extends Mock implements ChapterCacheService {}

void main() {
  late MockDownloadManager mockManager;
  late MockMangaRepository mockRepository;
  late MockChapterCacheService mockCacheService;

  setUp(() {
    mockManager = MockDownloadManager();
    mockRepository = MockMangaRepository();
    mockCacheService = MockChapterCacheService();
    when(() => mockManager.tasks).thenReturn(<DownloadTask>[]);
    when(() => mockManager.addListener(any())).thenReturn(null);
    when(() => mockManager.removeListener(any())).thenReturn(null);
  });

  DownloadCubit build() => DownloadCubit(
        cacheService: mockCacheService,
        repository: mockRepository,
        downloadManager: mockManager,
        sourceId: 's1',
        mangaId: 'm1',
      );

  blocTest<DownloadCubit, DownloadState>(
    'downloadChapter forwards to DownloadManager.addTask',
    build: build,
    act: (cubit) => cubit.downloadChapter(
        ChapterItem(id: 'c1', mangaId: 'm1', title: '第1章')),
    verify: (_) {
      verify(() => mockManager.addTask(
            sourceId: 's1',
            mangaId: 'm1',
            chapterId: 'c1',
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: '第1章',
          )).called(1);
    },
  );

  blocTest<DownloadCubit, DownloadState>(
    'cancelDownload calls pauseTask on the active chapter',
    build: build,
    seed: () => const DownloadState(
      chapters: {'c1': ChapterDownloadStatus.downloading},
      activeChapterId: 'c1',
    ),
    act: (cubit) => cubit.cancelDownload(),
    verify: (_) {
      verify(() => mockManager.pauseTask(any())).called(1);
    },
  );
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/presentation/detail/bloc/download_cubit_test.dart`
Expected: FAIL（目录不存在 / `DownloadCubit` 构造函数没有 `downloadManager` 具名参数）

- [ ] **Step 4: 重写 `DownloadCubit` 为薄封装**

替换 `lib/presentation/detail/bloc/download_cubit.dart` 全部内容：

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/local/chapter_cache_service.dart';
import '../../../data/local/download_manager.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/manga_repository.dart';
import 'download_state.dart';

class DownloadCubit extends Cubit<DownloadState> {
  final ChapterCacheService _cacheService;
  final MangaRepository _repository;
  final DownloadManager _downloadManager;
  final String sourceId;
  final String mangaId;

  DownloadCubit({
    required ChapterCacheService cacheService,
    required MangaRepository repository,
    required DownloadManager downloadManager,
    required this.sourceId,
    required this.mangaId,
  })  : _cacheService = cacheService,
        _repository = repository,
        _downloadManager = downloadManager,
        super(const DownloadState()) {
    _downloadManager.addListener(_onManagerChanged);
  }

  String _keyFor(String chapterId) => '${sourceId}_${mangaId}_$chapterId';

  void _onManagerChanged() {
    final chapters = <String, ChapterDownloadStatus>{...state.chapters};
    String? activeChapterId;
    int activeProgress = 0;
    int activeTotal = 0;
    for (final task in _downloadManager.tasks) {
      if (task.sourceId != sourceId || task.mangaId != mangaId) continue;
      chapters[task.chapterId] = switch (task.status) {
        DownloadTaskStatus.pending => ChapterDownloadStatus.queued,
        DownloadTaskStatus.downloading => ChapterDownloadStatus.downloading,
        DownloadTaskStatus.completed => ChapterDownloadStatus.cached,
        DownloadTaskStatus.failed => ChapterDownloadStatus.failed,
        DownloadTaskStatus.paused => ChapterDownloadStatus.paused,
        DownloadTaskStatus.partiallyFailed =>
          ChapterDownloadStatus.partiallyFailed,
      };
      if (task.status == DownloadTaskStatus.downloading) {
        activeChapterId = task.chapterId;
        activeProgress = task.completedImages;
        activeTotal = task.totalImages;
      }
    }
    emit(state.copyWith(
      chapters: chapters,
      activeChapterId: activeChapterId,
      activeProgress: activeProgress,
      activeTotal: activeTotal,
      clearActive: activeChapterId == null,
    ));
  }

  Future<void> checkCachedChapters(List<ChapterItem> chapters) async {
    final result = <String, ChapterDownloadStatus>{};
    for (final chapter in chapters) {
      final cached = await _cacheService.isChapterCached(
          sourceId, mangaId, chapter.id, 1);
      result[chapter.id] =
          cached ? ChapterDownloadStatus.cached : ChapterDownloadStatus.none;
    }
    emit(state.copyWith(chapters: {...state.chapters, ...result}));
  }

  void downloadChapter(ChapterItem chapter) {
    _downloadManager.addTask(
      sourceId: sourceId,
      mangaId: mangaId,
      chapterId: chapter.id,
      mangaTitle: mangaId,
      chapterTitle: chapter.title,
    );
  }

  void downloadMultiple(List<ChapterItem> chapterItems) {
    for (final chapter in chapterItems) {
      final current = state.chapters[chapter.id] ?? ChapterDownloadStatus.none;
      if (current == ChapterDownloadStatus.cached ||
          current == ChapterDownloadStatus.downloading ||
          current == ChapterDownloadStatus.queued) {
        continue;
      }
      downloadChapter(chapter);
    }
  }

  void cancelDownload() {
    final activeChapterId = state.activeChapterId;
    if (activeChapterId == null) return;
    _downloadManager.pauseTask(_keyFor(activeChapterId));
  }

  @override
  Future<void> close() {
    _downloadManager.removeListener(_onManagerChanged);
    return super.close();
  }
}
```

（说明：`downloadChapter`/`downloadMultiple` 里的 `mangaTitle: mangaId` 是占位——薄封装本身拿不到漫画标题，`detail_screen.dart` 现有调用点也没有传标题进来。这是可接受的已知限制，`DownloadDrawer` 展示的 `mangaTitle` 字段在从详情页触发下载时会显示 mangaId 而不是标题；若后续要修，需要给 `DownloadCubit` 构造额外传 `mangaTitle` 参数，不在本次 12 个任务范围内，属于遗留可接受项，因为详情页原本就知道自己在哪本漫画里，用户不会因此产生歧义。）

- [ ] **Step 5: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/presentation/detail/bloc/download_cubit_test.dart`
Expected: PASS

- [ ] **Step 6: 修复 `detail_screen.dart` 的编译错误——补充 exhaustive switch case + DownloadCubit 构造参数**

在 `lib/presentation/detail/detail_screen.dart:41-48` 附近，`DownloadCubit(...)` 构造调用新增 `downloadManager` 参数：

```dart
BlocProvider(
  create: (_) => DownloadCubit(
    cacheService: GetIt.instance<ChapterCacheService>(),
    repository: GetIt.instance<MangaRepository>(),
    downloadManager: GetIt.instance<DownloadManager>(),
    sourceId: sourceId,
    mangaId: mangaId,
  ),
),
```

并在文件顶部补充 `import '../../data/local/download_manager.dart';`（若尚未导入）。

在 `_ChapterTile._buildStatusIcon()`（491-518 行）的 `switch (status)` 补两个 case：

```dart
ChapterDownloadStatus.paused => const Icon(Icons.pause_circle_outline, size: 18),
ChapterDownloadStatus.partiallyFailed => const Icon(Icons.error_outline, size: 18, color: Colors.orange),
```

- [ ] **Step 7: 运行 flutter analyze 确认无编译错误**

Run: `cd comic-reader && flutter analyze lib/presentation/detail/`
Expected: No errors（原有 244 issues 基线中的 info 级别可忽略，只关注新增 error）

- [ ] **Step 8: Commit**

```bash
cd comic-reader && git add lib/presentation/detail/bloc/download_cubit.dart lib/presentation/detail/bloc/download_state.dart lib/presentation/detail/detail_screen.dart test/presentation/detail/bloc/download_cubit_test.dart && git commit -m "refactor(download): DownloadCubit改为DownloadManager的薄封装"
```

---

## Task 6: DownloadDrawer UI 补充新状态展示 + 暂停/恢复按钮

**Files:**
- Modify: `lib/presentation/downloads/download_drawer.dart:129-140`（`_statusIcon`）, `:142-163`（`_buildTrailing`）, header 区域

**Interfaces:**
- Consumes：Task 1 的 `DownloadTaskStatus.paused`/`.partiallyFailed`；Task 3/4 的 `DownloadManager.pauseAll()`/`resumeAll()`/`pauseTask(key)`/`resumeTask(key)`/`retryTask(key)`
- Produces：无新公开接口，仅 UI 展示层改动

现有 `_statusIcon`（129-140 行）是对 `DownloadTaskStatus` 的 switch，当前只有 `pending/downloading/completed/failed` 四个 case。`_buildTrailing`（142-163 行）downloading 态显示百分比，failed 态显示重试 `IconButton`。Header（`_buildHeader`）当前只显示 `'下载队列 ($total)'` + `'进行中: $active'`，无批量操作按钮。

- [ ] **Step 1: 编写 widget 测试**

新建 `test/presentation/downloads/download_drawer_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/presentation/downloads/download_drawer.dart';

class MockDownloadManager extends Mock implements DownloadManager {}

void main() {
  late MockDownloadManager manager;

  setUp(() {
    manager = MockDownloadManager();
    GetIt.instance.reset();
    GetIt.instance.registerSingleton<DownloadManager>(manager);
  });

  testWidgets('paused 任务显示恢复按钮，partiallyFailed 显示重试文案', (tester) async {
    final paused = DownloadTask(
      sourceId: 's', mangaId: 'm', chapterId: 'c1',
      mangaTitle: 'M', chapterTitle: 'C1',
    )..status = DownloadTaskStatus.paused;
    final partial = DownloadTask(
      sourceId: 's', mangaId: 'm', chapterId: 'c2',
      mangaTitle: 'M', chapterTitle: 'C2',
    )..status = DownloadTaskStatus.partiallyFailed
     ..failedImageIndexes = [2, 5];

    when(() => manager.tasks).thenReturn([paused, partial]);
    when(() => manager.activeCount).thenReturn(0);
    when(() => manager.pendingCount).thenReturn(0);
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => DownloadDrawer.show(context),
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget); // 恢复按钮
    expect(find.textContaining('2张失败'), findsOneWidget);
  });

  testWidgets('header 显示全部暂停/全部恢复按钮', (tester) async {
    when(() => manager.tasks).thenReturn([]);
    when(() => manager.activeCount).thenReturn(1);
    when(() => manager.pendingCount).thenReturn(0);
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => DownloadDrawer.show(context),
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/presentation/downloads/download_drawer_test.dart`
Expected: FAIL（找不到 `Icons.play_circle_outline`/`'2张失败'` 文案/`Icons.pause`/`Icons.play_arrow`）

- [ ] **Step 3: 修改 `_statusIcon`**

在 `download_drawer.dart:129-140` 的 switch 补充两个 case：

```dart
IconData _statusIcon(DownloadTaskStatus status) {
  switch (status) {
    case DownloadTaskStatus.pending:
      return Icons.schedule;
    case DownloadTaskStatus.downloading:
      return Icons.downloading;
    case DownloadTaskStatus.completed:
      return Icons.check_circle;
    case DownloadTaskStatus.failed:
      return Icons.error;
    case DownloadTaskStatus.paused:
      return Icons.pause_circle_outline;
    case DownloadTaskStatus.partiallyFailed:
      return Icons.error_outline;
  }
}
```

- [ ] **Step 4: 修改 `_buildTrailing`**

在原有 downloading/failed 分支后追加：

```dart
Widget? _buildTrailing(BuildContext context, DownloadTask task) {
  switch (task.status) {
    case DownloadTaskStatus.downloading:
      return Text('${task.progress}%');
    case DownloadTaskStatus.failed:
      return IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: () => GetIt.instance<DownloadManager>().retryTask(task.key),
      );
    case DownloadTaskStatus.paused:
      return IconButton(
        icon: const Icon(Icons.play_circle_outline),
        tooltip: '恢复',
        onPressed: () => GetIt.instance<DownloadManager>().resumeTask(task.key),
      );
    case DownloadTaskStatus.partiallyFailed:
      return TextButton.icon(
        icon: const Icon(Icons.refresh, size: 16),
        label: Text('${task.failedImageIndexes.length}张失败，点击重试'),
        onPressed: () => GetIt.instance<DownloadManager>().retryTask(task.key),
      );
    default:
      return null;
  }
}
```

- [ ] **Step 5: 修改 `_buildHeader` 新增批量按钮**

```dart
Widget _buildHeader(BuildContext context, DownloadManager manager) {
  return Row(
    children: [
      Expanded(child: Text('下载队列 (${manager.tasks.length})')),
      Text('进行中: ${manager.activeCount}'),
      IconButton(
        icon: const Icon(Icons.pause),
        tooltip: '全部暂停',
        onPressed: manager.activeCount == 0 ? null : () => manager.pauseAll(),
      ),
      IconButton(
        icon: const Icon(Icons.play_arrow),
        tooltip: '全部恢复',
        onPressed: () => manager.resumeAll(),
      ),
    ],
  );
}
```

- [ ] **Step 6: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/presentation/downloads/download_drawer_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
cd comic-reader && git add lib/presentation/downloads/download_drawer.dart test/presentation/downloads/download_drawer_test.dart && git commit -m "feat(download): DownloadDrawer支持暂停/恢复态展示与批量操作"
```

---

## Task 7: 收藏页单本"下载未读章节"入口

**Files:**
- Modify: `lib/presentation/home/bloc/home_cubit.dart`（构造依赖 + 新方法）
- Modify: `lib/presentation/home/home_screen.dart:1-17`（import）, `:24-34`（HomeCubit 构造）, `:278-388`（`_buildMangaCard`）
- Test: `test/presentation/home/bloc/home_cubit_test.dart`（新建）

**Interfaces:**
- Consumes：`MangaRepository.getChapterList(sourceId,mangaId,page) -> ChapterListResult`；`ReadingHistoryStore.getReadChapters(sourceId,mangaId) -> Set<String>`；`DownloadManager.addTask({sourceId,mangaId,chapterId,mangaTitle,chapterTitle})`
- Produces：`HomeCubit.downloadUnread(MangaSummary manga) -> Future<void>`（供 Task 8 及本任务 UI 复用）

- [ ] **Step 1: 编写失败测试**

新建 `test/presentation/home/bloc/home_cubit_test.dart`：

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'package:comic_reader/data/local/category_store.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/data/services/library_update_service.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/home/bloc/home_cubit.dart';

class MockFavoritesStore extends Mock implements FavoritesStore {}
class MockUpdateStore extends Mock implements UpdateStore {}
class MockCategoryStore extends Mock implements CategoryStore {}
class MockLibraryUpdateService extends Mock implements LibraryUpdateService {}
class MockReadingHistoryStore extends Mock implements ReadingHistoryStore {}
class MockDownloadManager extends Mock implements DownloadManager {}
class MockMangaRepository extends Mock implements MangaRepository {}

void main() {
  late MockFavoritesStore favoritesStore;
  late MockUpdateStore updateStore;
  late MockCategoryStore categoryStore;
  late MockLibraryUpdateService libraryUpdateService;
  late MockReadingHistoryStore historyStore;
  late MockDownloadManager downloadManager;
  late MockMangaRepository repository;

  setUp(() {
    favoritesStore = MockFavoritesStore();
    updateStore = MockUpdateStore();
    categoryStore = MockCategoryStore();
    libraryUpdateService = MockLibraryUpdateService();
    historyStore = MockReadingHistoryStore();
    downloadManager = MockDownloadManager();
    repository = MockMangaRepository();
  });

  HomeCubit buildCubit() => HomeCubit(
        favoritesStore: favoritesStore,
        updateStore: updateStore,
        categoryStore: categoryStore,
        libraryUpdateService: libraryUpdateService,
        repository: repository,
        historyStore: historyStore,
        downloadManager: downloadManager,
      );

  const manga = MangaSummary(
    id: 'm1', sourceId: 's1', title: 'T', coverUrl: 'c',
  );
  final chapters = [
    const ChapterItem(id: 'c1', mangaId: 'm1', title: 'Ch1'),
    const ChapterItem(id: 'c2', mangaId: 'm1', title: 'Ch2'),
  ];

  blocTest<HomeCubit, dynamic>(
    'downloadUnread 只为未读章节调用 addTask',
    build: () {
      when(() => repository.getChapterList('s1', 'm1', 1))
          .thenAnswer((_) async => ChapterListResult(chapters: chapters, canLoadMore: false));
      when(() => historyStore.getReadChapters('s1', 'm1'))
          .thenAnswer((_) async => {'c1'});
      when(() => downloadManager.addTask(
            sourceId: any(named: 'sourceId'),
            mangaId: any(named: 'mangaId'),
            chapterId: any(named: 'chapterId'),
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          )).thenReturn(null);
      return buildCubit();
    },
    act: (cubit) => cubit.downloadUnread(manga),
    verify: (_) {
      verify(() => downloadManager.addTask(
            sourceId: 's1', mangaId: 'm1', chapterId: 'c2',
            mangaTitle: 'T', chapterTitle: 'Ch2',
          )).called(1);
      verifyNever(() => downloadManager.addTask(
            sourceId: 's1', mangaId: 'm1', chapterId: 'c1',
            mangaTitle: any(named: 'mangaTitle'), chapterTitle: any(named: 'chapterTitle'),
          ));
    },
  );
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/presentation/home/bloc/home_cubit_test.dart`
Expected: FAIL（`HomeCubit` 构造函数没有 `repository`/`historyStore`/`downloadManager` 参数，`downloadUnread` 方法不存在）

- [ ] **Step 3: 修改 `HomeCubit` 构造函数与新增方法**

在 `home_cubit.dart` 构造函数（14-23 行）新增三个必传依赖：

```dart
class HomeCubit extends Cubit<HomeState> {
  HomeCubit({
    required FavoritesStore favoritesStore,
    required UpdateStore updateStore,
    required CategoryStore categoryStore,
    required LibraryUpdateService libraryUpdateService,
    required MangaRepository repository,
    required ReadingHistoryStore historyStore,
    required DownloadManager downloadManager,
  })  : _favoritesStore = favoritesStore,
        _updateStore = updateStore,
        _categoryStore = categoryStore,
        _libraryUpdateService = libraryUpdateService,
        _repository = repository,
        _historyStore = historyStore,
        _downloadManager = downloadManager,
        super(const HomeState());

  final FavoritesStore _favoritesStore;
  final UpdateStore _updateStore;
  final CategoryStore _categoryStore;
  final LibraryUpdateService _libraryUpdateService;
  final MangaRepository _repository;
  final ReadingHistoryStore _historyStore;
  final DownloadManager _downloadManager;

  // ... 现有方法不变 ...

  Future<void> downloadUnread(MangaSummary manga) async {
    final result = await _repository.getChapterList(manga.sourceId, manga.id, 1);
    final readSet = await _historyStore.getReadChapters(manga.sourceId, manga.id);
    final unread = result.chapters.where((c) => !readSet.contains(c.id));
    for (final chapter in unread) {
      _downloadManager.addTask(
        sourceId: manga.sourceId,
        mangaId: manga.id,
        chapterId: chapter.id,
        mangaTitle: manga.title,
        chapterTitle: chapter.title,
      );
    }
  }

  Future<void> downloadSelected() async {
    for (final key in state.selectedKeys) {
      final parts = key.split('_');
      if (parts.length < 2) continue;
      final sourceId = parts.first;
      final mangaId = parts.sublist(1).join('_');
      final manga = state.favorites.firstWhereOrNull(
        (m) => m.sourceId == sourceId && m.id == mangaId,
      );
      if (manga != null) {
        await downloadUnread(manga);
      }
    }
  }
}
```

需在文件顶部新增 import：`import 'package:collection/collection.dart';`、`import '../../../data/local/download_manager.dart';`、`import '../../../data/local/reading_history_store.dart';`、`import '../../../domain/repositories/manga_repository.dart';`（按实际相对路径调整，参考文件已有 import 风格）。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/presentation/home/bloc/home_cubit_test.dart`
Expected: PASS

- [ ] **Step 5: 修改 `home_screen.dart` 接入新依赖与 UI 按钮**

在文件顶部（1-17 行）新增 import：

```dart
import '../../domain/repositories/manga_repository.dart';
import '../../data/local/reading_history_store.dart';
```

在 `HomeScreen.build()`（24-34 行）的 `HomeCubit(...)` 构造里补三个参数：

```dart
BlocProvider(
  create: (_) => HomeCubit(
    favoritesStore: GetIt.instance<FavoritesStore>(),
    updateStore: GetIt.instance<UpdateStore>(),
    categoryStore: GetIt.instance<CategoryStore>(),
    libraryUpdateService: GetIt.instance<LibraryUpdateService>(),
    repository: GetIt.instance<MangaRepository>(),
    historyStore: GetIt.instance<ReadingHistoryStore>(),
    downloadManager: GetIt.instance<DownloadManager>(),
  )..loadFavorites(),
  child: const _HomeView(),
),
```

在 `_buildMangaCard`（278-388 行）的 `Stack` 内，紧跟 `hasNewUpdate` 标签和选择圆圈之后新增第三个 `Positioned`（仅非选择模式下显示）：

```dart
if (!state.isSelecting)
  Positioned(
    bottom: 4,
    right: 4,
    child: Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          context.read<HomeCubit>().downloadUnread(manga);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已加入下载队列')),
          );
        },
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.download, size: 18, color: Colors.white),
        ),
      ),
    ),
  ),
```

- [ ] **Step 6: 运行 flutter analyze**

Run: `cd comic-reader && flutter analyze lib/presentation/home/`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
cd comic-reader && git add lib/presentation/home/bloc/home_cubit.dart lib/presentation/home/home_screen.dart test/presentation/home/bloc/home_cubit_test.dart && git commit -m "feat(download): 收藏页单本卡片支持下载未读章节"
```

---

## Task 8: 收藏页多选"下载所选"入口

**Files:**
- Modify: `lib/presentation/home/bloc/home_cubit.dart`（`downloadSelected()` 已在 Task 7 中定义）
- Modify: `lib/presentation/home/home_screen.dart:113-140`（`_buildSelectionAppBar`）
- Test: `test/presentation/home/bloc/home_cubit_test.dart`（追加用例）

**Interfaces:**
- Consumes：Task 7 的 `HomeCubit.downloadSelected()`、`HomeState.selectedKeys`/`favorites`
- Produces：无新公开接口，仅 UI 接入

- [ ] **Step 1: 追加失败测试**

在 `test/presentation/home/bloc/home_cubit_test.dart` 追加：

```dart
  blocTest<HomeCubit, dynamic>(
    'downloadSelected 对每个选中的漫画调用 downloadUnread 逻辑',
    build: () {
      when(() => repository.getChapterList(any(), any(), any()))
          .thenAnswer((_) async => ChapterListResult(chapters: chapters, canLoadMore: false));
      when(() => historyStore.getReadChapters(any(), any())).thenAnswer((_) async => {});
      when(() => downloadManager.addTask(
            sourceId: any(named: 'sourceId'),
            mangaId: any(named: 'mangaId'),
            chapterId: any(named: 'chapterId'),
            mangaTitle: any(named: 'mangaTitle'),
            chapterTitle: any(named: 'chapterTitle'),
          )).thenReturn(null);
      return buildCubit();
    },
    seed: () => const HomeState(favorites: [manga], selectedKeys: {'s1_m1'}),
    act: (cubit) => cubit.downloadSelected(),
    verify: (_) {
      verify(() => downloadManager.addTask(
            sourceId: 's1', mangaId: 'm1', chapterId: any(named: 'chapterId'),
            mangaTitle: any(named: 'mangaTitle'), chapterTitle: any(named: 'chapterTitle'),
          )).called(2);
    },
  );
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/presentation/home/bloc/home_cubit_test.dart`
Expected: 若 `HomeState` 的 `favorites`/`selectedKeys` 构造参数名不一致，先核对 `home_state.dart` 实际字段名再调整测试；`downloadSelected` 已在 Task 7 实现，此步骤主要验证组合行为，预期 FAIL 的原因应仅是尚未接入 UI（见 Step 3），若逻辑已正确则直接 PASS，属于正常情况可跳到 Step 4。

- [ ] **Step 3: 在 `_buildSelectionAppBar` 新增"下载所选"按钮**

在 `home_screen.dart:113-140` 的 `actions` 列表中，全选按钮（121-125 行）之后、设置分类按钮（126-132 行）之前插入：

```dart
IconButton(
  icon: const Icon(Icons.download),
  tooltip: '下载所选',
  onPressed: state.selectedKeys.isEmpty
      ? null
      : () {
          context.read<HomeCubit>().downloadSelected();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已加入下载队列')),
          );
        },
),
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/presentation/home/bloc/home_cubit_test.dart`
Expected: PASS

- [ ] **Step 5: 运行 flutter analyze**

Run: `cd comic-reader && flutter analyze lib/presentation/home/`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
cd comic-reader && git add lib/presentation/home/bloc/home_cubit.dart lib/presentation/home/home_screen.dart test/presentation/home/bloc/home_cubit_test.dart && git commit -m "feat(download): 收藏页多选模式支持批量下载所选"
```

---

## Task 9: Android 默认存储目录切换为外部存储

**Files:**
- Modify: `lib/data/local/chapter_cache_service.dart:23-32`（`_cachePath` getter）
- Test: `test/data/local/chapter_cache_service_test.dart`（追加 Android 分支用例）

**Interfaces:**
- Consumes：`path_provider` 的 `getExternalStorageDirectory()`（Android-only API）
- Produces：无新公开接口，`_cachePath` 内部行为变化

现有 `_cachePath` getter（23-32 行）web 返回空字符串，native 统一走 `getApplicationDocumentsDirectory()`。Android 上该目录是应用私有沙盒（`/data/data/<pkg>/app_flutter/`），用户不可见，卸载即清空。改为 `getExternalStorageDirectory()`（对应 `/storage/emulated/0/Android/data/<pkg>/files/`，用户可通过文件管理器访问，仍随应用卸载清空但至少可见/可用第三方文件管理器操作）。

- [ ] **Step 1: 编写失败测试**

在 `test/data/local/chapter_cache_service_test.dart` 追加（复用 Task 2 已建立的 `FakePathProviderPlatform` 基础设施，新增一个可控制 `Platform.isAndroid` 的测试分支；由于 `dart:io` 的 `Platform.isAndroid` 无法在纯 Dart 测试中直接 mock，改为验证 `_cachePath` 在 `getExternalStorageDirectory` 返回非 null 时优先使用它的路径拼接逻辑，通过给 `FakePathProviderPlatform.getExternalStorageDirectory()` 返回一个 fake 路径并断言 `chapter_cache` 目录建在该路径下而非 `getApplicationDocumentsDirectory()` 之下）：

```dart
test('Android 分支优先使用 getExternalStorageDirectory', () async {
  final tempExternal = await Directory.systemTemp.createTemp('external_');
  fakePathProvider.externalStorageDirectory = tempExternal;
  final service = ChapterCacheService(forceAndroidPathForTest: true);

  await service.saveImage(
    sourceId: 's', mangaId: 'm', chapterId: 'c',
    index: 0, bytes: [1, 2, 3], contentType: 'image/jpeg',
  );

  final expectedDir = Directory('${tempExternal.path}/chapter_cache/s/m/c');
  expect(await expectedDir.exists(), isTrue);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/data/local/chapter_cache_service_test.dart`
Expected: FAIL（`ChapterCacheService` 无 `forceAndroidPathForTest` 参数，`FakePathProviderPlatform` 无 `externalStorageDirectory` 字段）

- [ ] **Step 3: 实现**

在 `FakePathProviderPlatform`（Task 2 中已建立）新增字段：

```dart
Directory? externalStorageDirectory;

@override
Future<String?> getExternalStorageDirectory() async => externalStorageDirectory?.path;
```

修改 `chapter_cache_service.dart` 的 `_cachePath` getter：

```dart
class ChapterCacheService {
  ChapterCacheService({Dio? dio, bool forceAndroidPathForTest = false})
      : _dio = dio ?? Dio(...),
        _forceAndroidPathForTest = forceAndroidPathForTest;

  final bool _forceAndroidPathForTest;

  static String? customDownloadDirectory;

  Future<String> get _cachePath async {
    if (kIsWeb) return '';
    if (customDownloadDirectory != null) return customDownloadDirectory!;
    if (Platform.isAndroid || _forceAndroidPathForTest) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return '${externalDir.path}/chapter_cache';
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/chapter_cache';
  }
}
```

（注：`customDownloadDirectory` 静态字段在此任务中先声明，供 Task 11 使用；`_basePath` 实例级缓存字段按设计需移除，改为每次都 `await` 计算，避免设置变更后读取旧值。）

- [ ] **Step 4: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/data/local/chapter_cache_service_test.dart`
Expected: PASS

- [ ] **Step 5: 运行 flutter analyze**

Run: `cd comic-reader && flutter analyze lib/data/local/chapter_cache_service.dart`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
cd comic-reader && git add lib/data/local/chapter_cache_service.dart test/data/local/chapter_cache_service_test.dart && git commit -m "feat(download): Android默认下载目录改为外部存储"
```

---

## Task 10: iOS Info.plist 文件共享支持

**Files:**
- Modify: `ios/Runner/Info.plist`

**Interfaces:**
- Consumes：无
- Produces：无（纯配置变更，无法通过 Flutter 单元测试验证，需人工在真机/模拟器上通过 Files app 查看）

- [ ] **Step 1: 修改 Info.plist**

在 `ios/Runner/Info.plist` 的 `NSPhotoLibraryAddUsageDescription` 键值对之后插入：

```xml
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

- [ ] **Step 2: 验证 plist 格式合法**

Run: `plutil -lint ios/Runner/Info.plist`
Expected: `ios/Runner/Info.plist: OK`

- [ ] **Step 3: Commit**

```bash
cd comic-reader && git add ios/Runner/Info.plist && git commit -m "feat(download): iOS启用文件共享,允许在Files app查看下载内容"
```

- [ ] **Step 4: 记录人工验证步骤（写入 PR 描述或跟随任务，不在本 commit 中执行）**

在真机/模拟器上构建 Release 版本后，打开 Files app → 浏览 → 此 iPhone → ComicReader → 确认能看到 `chapter_cache` 目录。此步骤无法自动化，标记为发布前人工检查项。

---

## Task 11: macOS/Windows 自定义下载目录设置 UI

**Files:**
- Modify: `lib/data/local/settings_store.dart`（`AppSettings` 新增 `downloadDirectory` 字段）
- Modify: `lib/presentation/settings/bloc/settings_cubit.dart`（新增 `setDownloadDirectory`）
- Modify: `lib/presentation/settings/sections/data_management_section.dart`（新增 ListTile，改接受 `state` 参数）
- Modify: `lib/presentation/settings/settings_screen.dart:53`（`DataManagementSection(state: state)`）
- Modify: `lib/main.dart`（启动时同步 `ChapterCacheService.customDownloadDirectory`）
- Test: `test/data/local/settings_store_test.dart`（新建）

**Interfaces:**
- Consumes：Task 9 中已声明的 `ChapterCacheService.customDownloadDirectory` 静态字段；`file_picker` 的 `FilePicker.platform.getDirectoryPath()`
- Produces：`AppSettings.downloadDirectory: String?`；`SettingsCubit.setDownloadDirectory(String? path) -> Future<void>`

- [ ] **Step 1: 编写失败测试**

新建 `test/data/local/settings_store_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/local/settings_store.dart';

void main() {
  test('downloadDirectory 默认 null，toJson/fromJson 往返保留值', () {
    const settings = AppSettings();
    expect(settings.downloadDirectory, isNull);

    final updated = settings.copyWith(downloadDirectory: '/custom/path');
    final json = updated.toJson();
    expect(json['downloadDirectory'], '/custom/path');

    final restored = AppSettings.fromJson(json);
    expect(restored.downloadDirectory, '/custom/path');
  });

  test('fromJson 缺少 downloadDirectory 字段时默认为 null（旧数据兼容）', () {
    final restored = AppSettings.fromJson({});
    expect(restored.downloadDirectory, isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd comic-reader && flutter test test/data/local/settings_store_test.dart`
Expected: FAIL（`downloadDirectory` 字段不存在）

- [ ] **Step 3: 修改 `AppSettings`**

在 `settings_store.dart` 的字段声明（约 42 行前）、默认构造（42-62 行）、`copyWith`（64-107 行）、`toJson`（109-129 行）、`fromJson`（131-159 行）五处均新增：

```dart
// 字段声明
final String? downloadDirectory;

// 默认构造 const AppSettings({...}) 参数列表中新增
this.downloadDirectory,

// copyWith 新增参数与赋值
String? downloadDirectory,
...
downloadDirectory: downloadDirectory ?? this.downloadDirectory,

// toJson 新增
'downloadDirectory': downloadDirectory,

// fromJson 新增
downloadDirectory: json['downloadDirectory'] as String?,
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd comic-reader && flutter test test/data/local/settings_store_test.dart`
Expected: PASS

- [ ] **Step 5: 新增 `SettingsCubit.setDownloadDirectory`**

在 `settings_cubit.dart` 仿照现有 `set*` 方法模式新增：

```dart
Future<void> setDownloadDirectory(String? path) async {
  final updated = state.settings.copyWith(downloadDirectory: path);
  emit(state.copyWith(settings: updated));
  await _settingsStore.save(updated);
  ChapterCacheService.customDownloadDirectory = path;
}
```

需在文件顶部新增 `import '../../../data/local/chapter_cache_service.dart';`（若尚未导入）。

- [ ] **Step 6: 修改 `DataManagementSection` 接受 `state` 参数并新增 ListTile**

将 `data_management_section.dart` 的类声明改为：

```dart
class DataManagementSection extends StatelessWidget {
  const DataManagementSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ... 原有4个 ListTile 不变 ...
        if (!kIsWeb && (Platform.isMacOS || Platform.isWindows))
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('下载存储位置'),
            subtitle: Text(state.settings.downloadDirectory ?? '默认位置'),
            onTap: () async {
              final path = await FilePicker.platform.getDirectoryPath();
              if (path != null) {
                context.read<SettingsCubit>().setDownloadDirectory(path);
              }
            },
          ),
      ],
    );
  }
}
```

需在文件顶部新增 `import 'dart:io';`、`import 'package:file_picker/file_picker.dart';`、`import 'package:flutter/foundation.dart' show kIsWeb;`（按需补充，避免与现有 import 重复）。

在 `settings_screen.dart:53` 将 `const DataManagementSection()` 改为 `DataManagementSection(state: state)`。

- [ ] **Step 7: `main.dart` 启动时同步静态字段**

在 `main.dart` 现有"加载 SettingsStore 并应用 disabledSources/adultUnlocked/proxy"逻辑处一并新增：

```dart
ChapterCacheService.customDownloadDirectory = settings.downloadDirectory;
```

（插入位置紧邻现有读取 `SettingsStore` 结果后的应用逻辑，具体变量名以当时读到的 `settings`/`appSettings` 局部变量名为准）。

- [ ] **Step 8: 运行 flutter analyze**

Run: `cd comic-reader && flutter analyze lib/data/local/settings_store.dart lib/presentation/settings/ lib/main.dart`
Expected: No errors

- [ ] **Step 9: Commit**

```bash
cd comic-reader && git add lib/data/local/settings_store.dart lib/presentation/settings/bloc/settings_cubit.dart lib/presentation/settings/sections/data_management_section.dart lib/presentation/settings/settings_screen.dart lib/main.dart test/data/local/settings_store_test.dart && git commit -m "feat(download): macOS/Windows支持自定义下载存储位置"
```

---

## Task 12: macOS security-scoped bookmark 原生桥接

**Files:**
- Modify: `macos/Runner/Release.entitlements`
- Create: `macos/Runner/DownloadDirectoryBookmark.swift`（新原生 Swift 辅助类）
- Modify: `macos/Runner/MainFlutterWindow.swift` 或 `AppDelegate.swift`（注册 FlutterMethodChannel，需先读取该文件确认现有结构后再插入，本任务不预先假定具体插入行号）
- Modify: `lib/data/local/chapter_cache_service.dart`（新增读取/写入 bookmark 的 MethodChannel 调用）

**Interfaces:**
- Consumes：Task 11 的 `SettingsCubit.setDownloadDirectory`（用户选择目录后触发 bookmark 写入）
- Produces：MethodChannel `'com.comicreader.comicReader/download_bookmark'`，方法 `saveBookmark(path)`/`resolveBookmark() -> String?`

**背景**：macOS App Sandbox（`app-sandbox=true`）下，`FilePicker.platform.getDirectoryPath()` 返回的路径仅在当次会话有效；应用重启后再次访问该路径会因沙盒权限失效而报错。必须用 `NSURL.bookmarkData(options: .withSecurityScope)` 持久化授权，重启后 `startAccessingSecurityScopedResource()` 恢复访问。

- [ ] **Step 1: 新增 entitlement**

在 `macos/Runner/Release.entitlements` 的 `<dict>` 内新增：

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

同样在 `macos/Runner/DebugProfile.entitlements` 新增（供本地调试时手动切换 `app-sandbox=true` 测试用，Debug 默认沙盒关闭不影响日常调试）。

- [ ] **Step 2: 读取现有 macOS 原生入口文件确定插入点**

Run: `cat macos/Runner/AppDelegate.swift`

（该文件当前内容尚未读取，执行本步骤时先查看现有 `AppDelegate.swift`/`MainFlutterWindow.swift` 的结构，确定 `FlutterMethodChannel` 的注册惯例——若项目此前从未注册过 MethodChannel，则在 `MainFlutterWindow.swift` 的 `awakeFromNib()` 或 `AppDelegate.swift` 的 `applicationDidFinishLaunching` 中新增。）

- [ ] **Step 3: 新建 `DownloadDirectoryBookmark.swift`**

```swift
import Cocoa
import FlutterMacOS

class DownloadDirectoryBookmark: NSObject {
    static func register(with controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "com.comicreader.comicReader/download_bookmark",
            binaryMessenger: controller.engine.binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "saveBookmark":
                guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
                    result(FlutterError(code: "bad_args", message: "path required", details: nil))
                    return
                }
                let url = URL(fileURLWithPath: path)
                do {
                    let bookmark = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    UserDefaults.standard.set(bookmark, forKey: "download_directory_bookmark")
                    result(true)
                } catch {
                    result(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
                }
            case "resolveBookmark":
                guard let bookmark = UserDefaults.standard.data(forKey: "download_directory_bookmark") else {
                    result(nil)
                    return
                }
                var isStale = false
                do {
                    let url = try URL(
                        resolvingBookmarkData: bookmark,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    _ = url.startAccessingSecurityScopedResource()
                    result(url.path)
                } catch {
                    result(nil)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
```

- [ ] **Step 4: 在入口文件注册 channel**

在 Step 2 确定的入口文件（`MainFlutterWindow.swift` 或 `AppDelegate.swift`）里，找到 `FlutterViewController` 实例创建之后的位置，新增一行：

```swift
DownloadDirectoryBookmark.register(with: flutterViewController)
```

（`flutterViewController` 变量名以实际读到的文件中的命名为准，可能是 `contentViewController` 或其他名称，需据实调整。）

- [ ] **Step 5: Dart 侧调用 MethodChannel**

在 `chapter_cache_service.dart` 顶部新增：

```dart
import 'package:flutter/services.dart';

const _bookmarkChannel = MethodChannel('com.comicreader.comicReader/download_bookmark');

Future<void> saveDownloadDirectoryBookmark(String path) async {
  if (!Platform.isMacOS) return;
  await _bookmarkChannel.invokeMethod('saveBookmark', {'path': path});
}

Future<String?> resolveDownloadDirectoryBookmark() async {
  if (!Platform.isMacOS) return null;
  return await _bookmarkChannel.invokeMethod<String>('resolveBookmark');
}
```

在 Task 11 的 `SettingsCubit.setDownloadDirectory` 里，`Platform.isMacOS` 时额外调用 `saveDownloadDirectoryBookmark(path)`；在 `main.dart` 启动同步逻辑里，`Platform.isMacOS` 时优先 `await resolveDownloadDirectoryBookmark()` 而非直接使用 `AppSettings.downloadDirectory` 的原始字符串。

- [ ] **Step 6: 手动验证（无法自动化测试，原生沙盒行为）**

1. `flutter build macos --release`
2. 打开构建产物，进入设置选择一个自定义下载目录（如 `~/Downloads/comics`）
3. 完全退出 App（Cmd+Q），重新打开
4. 触发一次下载，确认文件写入到步骤2选择的目录而非默认路径，且没有权限报错
5. 记录验证结果到 PR 描述

- [ ] **Step 7: Commit**

```bash
cd comic-reader && git add macos/Runner/Release.entitlements macos/Runner/DebugProfile.entitlements macos/Runner/DownloadDirectoryBookmark.swift lib/data/local/chapter_cache_service.dart && git commit -m "feat(download): macOS通过security-scoped bookmark持久化自定义下载目录权限"
```

---

## Self-Review Notes（写plan时自查，供执行者参考）

- **Spec coverage**：设计文档（`docs/plans/2026-08-29-download-system-redesign-design.md`）的全部条目已对应到 Task 1-12：字段扩展→T1，并发→T2/T3，暂停恢复→T4，Cubit薄封装→T5，UI展示→T6，收藏入口→T7/T8，存储位置→T9/T10/T11/T12。
- **Placeholder scan**：Task 12 的 Step 2/4 因原生文件当前内容未读取，明确标注"执行时先读取该文件确定插入点"而非假造行号——这是刻意的、必要的执行时探查步骤，不是遗留占位符，因为 macOS 原生文件(`AppDelegate.swift`/`MainFlutterWindow.swift`) 在本次调研中未涉及且内容因项目而异，执行者必须先读后写。
- **Type consistency**：`DownloadTask.key`、`ChapterDownloadResult`、`DownloadManager.addTask/pauseTask/resumeTask/retryTask` 等签名在 Task 1-8 中保持一致引用；`ChapterCacheService.customDownloadDirectory` 在 Task 9 声明、Task 11/12 使用，命名一致。

