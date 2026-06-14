import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum ReaderStatus { initial, loading, loaded, error }

enum LayoutMode { horizontal, vertical }

enum ReadingDirection { ltr, rtl }

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
    );
  }

  /// Check if there's a next chapter available
  bool get hasNextChapter =>
      chapterList.isNotEmpty && currentChapterIndex < chapterList.length - 1;

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
      ];
}
