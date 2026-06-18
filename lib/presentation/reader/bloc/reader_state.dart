import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum ReaderStatus { initial, loading, loaded, error }

enum LayoutMode { horizontal, vertical }

enum ReadingDirection { ltr, rtl }

class ChapterBoundary extends Equatable {
  final int startIndex;
  final String chapterId;
  final String chapterTitle;

  const ChapterBoundary({
    required this.startIndex,
    required this.chapterId,
    required this.chapterTitle,
  });

  @override
  List<Object?> get props => [startIndex, chapterId, chapterTitle];
}

class ReaderState extends Equatable {
  final ReaderStatus status;
  final LayoutMode layoutMode;
  final ReadingDirection direction;
  final List<ChapterImage> images;
  final int currentPage;
  final int totalPages;
  final bool showControls;
  final String? chapterTitle;
  final String? errorMessage;

  // Chapter navigation
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final List<ChapterItem> chapterList;
  final int currentChapterIndex;
  final int lastLoadedChapterIndex;

  /// Set when slider seeks to a page - consumed by HorizontalReader to jump.
  final int? seekPage;

  /// Chapter boundaries for infinite scroll: maps image index to chapterId
  final List<ChapterBoundary> chapterBoundaries;
  /// Whether next chapter is currently loading (for vertical append)
  final bool isAppendingNext;
  /// Whether images are still being progressively resolved (EH stream)
  final bool isProgressiveLoading;

  const ReaderState({
    this.status = ReaderStatus.initial,
    this.layoutMode = LayoutMode.horizontal,
    this.direction = ReadingDirection.ltr,
    this.images = const [],
    this.currentPage = 0,
    this.totalPages = 0,
    this.showControls = false,
    this.chapterTitle,
    this.errorMessage,
    this.sourceId = '',
    this.mangaId = '',
    this.chapterId = '',
    this.chapterList = const [],
    this.currentChapterIndex = -1,
    this.lastLoadedChapterIndex = 0,
    this.seekPage,
    this.chapterBoundaries = const [],
    this.isAppendingNext = false,
    this.isProgressiveLoading = false,
  });

  ReaderState copyWith({
    ReaderStatus? status,
    LayoutMode? layoutMode,
    ReadingDirection? direction,
    List<ChapterImage>? images,
    int? currentPage,
    int? totalPages,
    bool? showControls,
    String? chapterTitle,
    String? errorMessage,
    String? sourceId,
    String? mangaId,
    String? chapterId,
    List<ChapterItem>? chapterList,
    int? currentChapterIndex,
    int? lastLoadedChapterIndex,
    int? seekPage,
    List<ChapterBoundary>? chapterBoundaries,
    bool? isAppendingNext,
    bool? isProgressiveLoading,
  }) {
    return ReaderState(
      status: status ?? this.status,
      layoutMode: layoutMode ?? this.layoutMode,
      direction: direction ?? this.direction,
      images: images ?? this.images,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      showControls: showControls ?? this.showControls,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      errorMessage: errorMessage ?? this.errorMessage,
      sourceId: sourceId ?? this.sourceId,
      mangaId: mangaId ?? this.mangaId,
      chapterId: chapterId ?? this.chapterId,
      chapterList: chapterList ?? this.chapterList,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      lastLoadedChapterIndex: lastLoadedChapterIndex ?? this.lastLoadedChapterIndex,
      seekPage: seekPage,
      chapterBoundaries: chapterBoundaries ?? this.chapterBoundaries,
      isAppendingNext: isAppendingNext ?? this.isAppendingNext,
      isProgressiveLoading: isProgressiveLoading ?? this.isProgressiveLoading,
    );
  }

  /// Check if there's a next chapter available (based on current viewing position)
  bool get hasNextChapter =>
      chapterList.isNotEmpty && currentChapterIndex < chapterList.length - 1;

  /// Check if we can append the next chapter (based on last loaded chapter)
  bool get canAppendNext =>
      chapterList.isNotEmpty && lastLoadedChapterIndex < chapterList.length - 1;

  /// Check if there's a previous chapter available
  bool get hasPreviousChapter =>
      chapterList.isNotEmpty && currentChapterIndex > 0;

  @override
  List<Object?> get props => [
        status,
        layoutMode,
        direction,
        images,
        currentPage,
        totalPages,
        showControls,
        chapterTitle,
        errorMessage,
        sourceId,
        mangaId,
        chapterId,
        chapterList,
        currentChapterIndex,
        lastLoadedChapterIndex,
        seekPage,
        chapterBoundaries,
        isAppendingNext,
        isProgressiveLoading,
      ];
}
