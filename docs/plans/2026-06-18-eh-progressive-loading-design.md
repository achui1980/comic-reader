# EH漫画渐进式加载设计

## 日期
2026-06-18

## 问题
EH源漫画加载需要三阶段批量解析：
1. 获取缩略图页 → 提取所有 `/s/` 图片页面链接
2. 循环获取所有缩略图分页（每页约40张）
3. 对每个图片页面URL逐一发HTTP请求解析真实图片地址

对于100页的画廊，Phase 3 需要发100次HTTP请求，全部完成后才返回给前端。用户需要等待很长时间才能看到第一页。

## 解决方案：仓库层 Stream 化

**核心思路**：Phase 1/2 完成后立即返回总页数和占位符列表，Phase 3 改为 Stream 逐个 yield 解析结果。

**体验目标**：
- 预设总页数 + 渐进填充（阅读器一开始就知道有100页，显示骨架）
- 从第1页开始顺序解析
- 用户可以立即开始看已解析完的页面

## 架构变更

### 数据流

```
Phase 1/2 完成 → yield ChapterInitial(totalPages, placeholders)
              → ReaderBloc 立即渲染骨架（已知总页数）

Phase 3 启动  → 逐个 yield ChapterImageResolved(index, realImage)
              → ReaderBloc 更新 images[index]，UI 自动刷新对应页

Phase 3 结束  → yield ChapterLoadComplete()
```

### 1. 新增数据类型

**文件**：新增 `lib/domain/entities/chapter_load_event.dart`

```dart
sealed class ChapterLoadEvent {}

/// 初始结果：总页数已知，images 列表中包含占位符
class ChapterInitial extends ChapterLoadEvent {
  final ChapterResult result;
  final int totalPages;
}

/// 单个图片URL解析完成
class ChapterImageResolved extends ChapterLoadEvent {
  final int index;
  final ChapterImage image;
}

/// 全部解析完成
class ChapterLoadComplete extends ChapterLoadEvent {}

/// 解析出错（某一页失败，不中断整体流程）
class ChapterImageError extends ChapterLoadEvent {
  final int index;
  final String error;
}
```

### 2. 仓库接口改动

**文件**：`lib/domain/repositories/manga_repository.dart`

新增方法：
```dart
Stream<ChapterLoadEvent> getChapterProgressive(
  String sourceId, String mangaId, String chapterId, int startPage);
```

### 3. 仓库实现

**文件**：`lib/data/repositories/manga_repository_impl.dart`

```dart
@override
Stream<ChapterLoadEvent> getChapterProgressive(...) async* {
  // Phase 1: 获取首页缩略图
  // Phase 2: 收集所有 imagePageUrls（循环分页）
  
  // 立即 yield 初始结果
  final totalPages = allImagePageUrls.length;
  final placeholders = List.generate(
    totalPages,
    (i) => ChapterImage(url: '', index: i, isPlaceholder: true),
  );
  yield ChapterInitial(
    result: ChapterResult(chapter: chapter.copyWith(images: placeholders)),
    totalPages: totalPages,
  );
  
  // Phase 3: 顺序解析每个图片的真实URL
  for (int i = 0; i < allImagePageUrls.length; i++) {
    try {
      final realUrl = await _resolveImageUrl(allImagePageUrls[i]);
      yield ChapterImageResolved(
        index: i,
        image: ChapterImage(url: realUrl, index: i),
      );
    } catch (e) {
      yield ChapterImageError(index: i, error: e.toString());
    }
  }
  
  yield ChapterLoadComplete();
}
```

### 4. Bloc层改动

**文件**：`lib/presentation/reader/bloc/reader_bloc.dart`

- 新增 `StreamSubscription? _chapterSubscription` 字段
- `LoadChapter` 事件处理改为监听 Stream
- 收到 `ChapterImageResolved` 时更新 `images[index]`
- 用户退出阅读器时 `_chapterSubscription?.cancel()`

**文件**：`lib/presentation/reader/bloc/reader_state.dart`

- 新增 `resolvedCount` 字段（已解析页数）
- `images` 列表长度从一开始等于总页数

### 5. UI层改动

**文件**：`lib/presentation/reader/widgets/manga_image.dart`

- 当 `image.isPlaceholder == true` 时显示骨架屏（shimmer + 页码）
- 当URL填入后自动触发图片加载

**阅读器 widgets**（horizontal_reader.dart / vertical_reader.dart）：
- 无需大改，`itemCount` 一开始就设为总页数
- 每个 item 根据 `isPlaceholder` 决定显示内容

### 6. 生命周期

- 退出阅读器 → `cancel()` 停止后台解析
- 非EH源 → 走原有一次性加载逻辑，不受影响
- 解析单页失败 → 标记该页失败可重试，不中断整体

## 影响范围

| 文件 | 改动类型 |
|------|---------|
| `lib/domain/entities/chapter_load_event.dart` | 新增 |
| `lib/domain/entities/chapter.dart` | ChapterImage 新增 isPlaceholder 字段 |
| `lib/domain/repositories/manga_repository.dart` | 新增方法 |
| `lib/data/repositories/manga_repository_impl.dart` | 新增实现 |
| `lib/presentation/reader/bloc/reader_bloc.dart` | 监听 Stream |
| `lib/presentation/reader/bloc/reader_state.dart` | 新增 resolvedCount |
| `lib/presentation/reader/bloc/reader_event.dart` | 新增内部事件 |
| `lib/presentation/reader/widgets/manga_image.dart` | 占位符UI |

## 不影响的部分

- 其他漫画源（仍走原有 `getChapter` 方法）
- 下载管理器
- 本地缓存机制
- 图片代理
