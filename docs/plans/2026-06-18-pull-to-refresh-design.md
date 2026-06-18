# Pull-to-Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add pull-to-refresh to Detail, Vertical Reader, and Search pages in comic-reader (Flutter).

**Architecture:** Wrap scrollable widgets with Flutter's `RefreshIndicator`. Each page's BLoC/Cubit gets a `refresh()`/`RefreshChapter` method/event that re-fetches data and returns a Future for the indicator to complete.

**Tech Stack:** Flutter, flutter_bloc, RefreshIndicator (Material)

---

### Task 1: DetailCubit - Add refresh() method

**Files:**
- Modify: `lib/presentation/detail/bloc/detail_cubit.dart`

**Step 1: Add refresh method to DetailCubit**

In `detail_cubit.dart`, add after the `loadDetail()` method:

```dart
Future<void> refresh() async {
  try {
    final manga = await _repository.getMangaInfo(sourceId, mangaId);
    final isFav = await _favoritesStore.isFavorite(sourceId, mangaId);
    emit(state.copyWith(status: DetailStatus.loaded, manga: manga, isFavorite: isFav));
    await loadChapters();
    final readChapters = await _historyStore.getReadChapters(sourceId, mangaId);
    emit(state.copyWith(readChapterIds: readChapters));
  } catch (e) {
    // Silently fail on refresh - don't show error state since we already have data
  }
}
```

Note: Unlike `loadDetail()`, `refresh()` does NOT emit loading state (keeps current content visible during refresh).

**Step 2: Verify no compile errors**

Run: `cd comic-reader && flutter analyze lib/presentation/detail/bloc/detail_cubit.dart`
Expected: No issues found

---

### Task 2: Detail Screen - Add RefreshIndicator

**Files:**
- Modify: `lib/presentation/detail/detail_screen.dart` (around line 108-114)

**Step 1: Wrap CustomScrollView with RefreshIndicator**

Change (line ~108-114):
```dart
          return Scaffold(
            body: CustomScrollView(
              slivers: [
                _buildHeader(context, manga, state.isFavorite),
                _buildInfo(context, manga),
```

To:
```dart
          return Scaffold(
            body: RefreshIndicator(
              onRefresh: () => context.read<DetailCubit>().refresh(),
              child: CustomScrollView(
                slivers: [
                  _buildHeader(context, manga, state.isFavorite),
                  _buildInfo(context, manga),
```

And close the `RefreshIndicator` parenthesis after the `CustomScrollView`'s closing parenthesis (find the matching `)` for `CustomScrollView` and add `)` after it for `RefreshIndicator.child`).

**Step 2: Verify no compile errors**

Run: `cd comic-reader && flutter analyze lib/presentation/detail/detail_screen.dart`
Expected: No issues found

---

### Task 3: ReaderBloc - Add RefreshChapter event and handler

**Files:**
- Modify: `lib/presentation/reader/bloc/reader_event.dart`
- Modify: `lib/presentation/reader/bloc/reader_bloc.dart`

**Step 1: Add RefreshChapter event**

In `reader_event.dart`, add at the end before the file ends:

```dart
/// Refresh current chapter images (pull-to-refresh)
class RefreshChapter extends ReaderEvent {
  const RefreshChapter();
}
```

**Step 2: Register handler in ReaderBloc constructor**

In `reader_bloc.dart`, after `on<AutoPageTick>(_onAutoPageTick);` add:

```dart
    on<RefreshChapter>(_onRefreshChapter);
```

**Step 3: Add handler implementation**

In `reader_bloc.dart`, add the handler method (e.g., after `_onAppendNextChapter`):

```dart
  Future<void> _onRefreshChapter(
      RefreshChapter event, Emitter<ReaderState> emit) async {
    if (state.sourceId.isEmpty || state.mangaId.isEmpty || state.chapterId.isEmpty) return;

    try {
      final result = await _repository.getChapter(
        state.sourceId,
        state.mangaId,
        state.chapterId,
        1,
      );

      final initialBoundary = ChapterBoundary(
        startIndex: 0,
        chapterId: state.chapterId,
        chapterTitle: result.chapter.title,
      );

      emit(state.copyWith(
        images: result.chapter.images,
        totalPages: result.chapter.images.length,
        currentPage: 0,
        chapterBoundaries: [initialBoundary],
        lastLoadedChapterIndex: state.currentChapterIndex,
        isAppendingNext: false,
      ));
    } catch (e) {
      // Silently fail - keep current images on screen
      _log.warning('Failed to refresh chapter: $e');
    }
  }
```

**Step 4: Verify no compile errors**

Run: `cd comic-reader && flutter analyze lib/presentation/reader/bloc/`
Expected: No issues found

---

### Task 4: Vertical Reader - Add RefreshIndicator

**Files:**
- Modify: `lib/presentation/reader/widgets/vertical_reader.dart`

**Step 1: Add Completer import**

Add at top of file:
```dart
import 'dart:async';
```

**Step 2: Add a refresh method to _VerticalReaderState**

After `_onTap` method, add:

```dart
  Future<void> _onRefresh() {
    final completer = Completer<void>();
    final bloc = context.read<ReaderBloc>();
    bloc.add(const RefreshChapter());
    // Listen for state change to complete the future
    late final StreamSubscription sub;
    sub = bloc.stream.listen((state) {
      if (state.status == ReaderStatus.loaded) {
        completer.complete();
        sub.cancel();
      }
    });
    // Timeout after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });
    return completer.future;
  }
```

Also import the event file at the top:
```dart
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
```

**Step 3: Wrap ListView.builder with RefreshIndicator**

In the `build` method, change (inside the `BlocBuilder`'s `builder`):

```dart
          return ListView.builder(
```

To:
```dart
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.builder(
```

And add the closing `)` for RefreshIndicator after `ListView.builder`'s closing `)`.

The `builder` block becomes:
```dart
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: widget.images.length + (state.isAppendingNext ? 1 : 0),
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                if (index >= widget.images.length) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return SizedBox(
                  width: double.infinity,
                  child: MangaImage(
                    image: widget.images[index],
                    fit: BoxFit.fitWidth,
                    disableGesture: true,
                    sourceId: state.sourceId,
                    mangaId: state.mangaId,
                    chapterId: state.chapterId,
                    imageIndex: index,
                  ),
                );
              },
            ),
          );
        },
```

**Step 4: Verify no compile errors**

Run: `cd comic-reader && flutter analyze lib/presentation/reader/widgets/vertical_reader.dart`
Expected: No issues found

---

### Task 5: SearchCubit - Add refresh() method

**Files:**
- Modify: `lib/presentation/search/bloc/search_cubit.dart`

**Step 1: Add refresh method**

After `loadMore()` method, add:

```dart
  Future<void> refresh() async {
    if (state.keyword.isEmpty) return;
    final source = _registry.get(state.sourceId);
    final firstPage = source?.firstPage ?? 1;
    emit(state.copyWith(
      status: SearchStatus.loading,
      currentPage: firstPage,
      hasMore: true,
    ));
    try {
      final results = await _repository.searchManga(state.sourceId, state.keyword, firstPage, {});
      emit(state.copyWith(
        status: SearchStatus.loaded,
        results: results,
        hasMore: results.isNotEmpty,
      ));
    } catch (e) {
      emit(state.copyWith(status: SearchStatus.error, errorMessage: e.toString()));
    }
  }
```

**Step 2: Verify no compile errors**

Run: `cd comic-reader && flutter analyze lib/presentation/search/bloc/search_cubit.dart`
Expected: No issues found

---

### Task 6: Search Screen - Add RefreshIndicator

**Files:**
- Modify: `lib/presentation/search/search_screen.dart`

**Step 1: Wrap ListView.builder with RefreshIndicator**

In the body section where `NotificationListener` wraps `ListView.builder`, change:

```dart
            child: ListView.builder(
```

To:
```dart
            child: RefreshIndicator(
              onRefresh: () => context.read<SearchCubit>().refresh(),
              child: ListView.builder(
```

And add the closing `)` for RefreshIndicator after `ListView.builder`'s closing `)`.

**Step 2: Verify no compile errors**

Run: `cd comic-reader && flutter analyze lib/presentation/search/search_screen.dart`
Expected: No issues found

---

### Task 7: Full project analysis

**Step 1: Run full project analysis**

Run: `cd comic-reader && flutter analyze`
Expected: No issues found

**Step 2: Verify build compiles**

Run: `cd comic-reader && flutter build apk --debug 2>&1 | tail -5`
Expected: Build successful (or at least no new errors introduced)
