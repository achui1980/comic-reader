import 'dart:ui' show Size;

import 'package:flutter/widgets.dart' show BoxFit;
import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/data/local/settings_store.dart' show ScaleType;
import 'package:comic_reader/data/translation/models/page_translation.dart';

enum ReaderStatus { initial, loading, loaded, error }

enum LayoutMode { horizontal, vertical }

enum ReadingDirection { ltr, rtl }

enum PageTranslationStatus { idle, loading, done, error }

/// Per-page translation UI state, keyed by page index in
/// [ReaderState.pageTranslations]. Not persisted — lives only in memory for
/// the current [ReaderBloc] instance / reading session.
class PageTranslationInfo {
  const PageTranslationInfo({
    required this.status,
    this.translation,
    this.errorMessage,
    this.imageSize,
  });

  final PageTranslationStatus status;
  final PageTranslation? translation;
  final String? errorMessage;

  /// Original image pixel size, used by [ReaderTranslationOverlayPainter]
  /// to scale [TextRegion.box] coordinates onto the rendered widget size.
  final Size? imageSize;

  static const idle = PageTranslationInfo(status: PageTranslationStatus.idle);
}

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
  final String mangaTitle;
  final String coverUrl;
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

  // --- Reader enhancements (phase 2) ---
  final bool cropBorders;
  final ScaleType scaleType;
  final bool splitWidePages;
  final bool showPageNumber;
  final bool tapZonesInvert;
  final bool showTapZones;

  // --- Manga translation overlay (vertical reader only) ---
  /// 漫画翻译功能总开关（AppSettings.mangaTranslationEnabled 的镜像）。
  /// 由 ReaderBloc 构造时读一次，决定顶栏是否渲染翻译按钮。
  final bool translationFeatureEnabled;
  /// Whether the user has toggled on translation for the current session.
  /// Not persisted; resets to false every time the reader is opened.
  final bool translationEnabled;
  /// Per-page translation state, keyed by page index.
  final Map<int, PageTranslationInfo> pageTranslations;

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
    this.mangaTitle = '',
    this.coverUrl = '',
    this.chapterList = const [],
    this.currentChapterIndex = -1,
    this.lastLoadedChapterIndex = 0,
    this.seekPage,
    this.chapterBoundaries = const [],
    this.isAppendingNext = false,
    this.isProgressiveLoading = false,
    this.cropBorders = false,
    this.scaleType = ScaleType.fitWidth,
    this.splitWidePages = false,
    this.showPageNumber = true,
    this.tapZonesInvert = false,
    this.showTapZones = false,
    this.translationFeatureEnabled = false,
    this.translationEnabled = false,
    this.pageTranslations = const {},
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
    String? mangaTitle,
    String? coverUrl,
    List<ChapterItem>? chapterList,
    int? currentChapterIndex,
    int? lastLoadedChapterIndex,
    int? seekPage,
    List<ChapterBoundary>? chapterBoundaries,
    bool? isAppendingNext,
    bool? isProgressiveLoading,
    bool? cropBorders,
    ScaleType? scaleType,
    bool? splitWidePages,
    bool? showPageNumber,
    bool? tapZonesInvert,
    bool? showTapZones,
    bool? translationFeatureEnabled,
    bool? translationEnabled,
    Map<int, PageTranslationInfo>? pageTranslations,
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
      mangaTitle: mangaTitle ?? this.mangaTitle,
      coverUrl: coverUrl ?? this.coverUrl,
      chapterList: chapterList ?? this.chapterList,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      lastLoadedChapterIndex: lastLoadedChapterIndex ?? this.lastLoadedChapterIndex,
      seekPage: seekPage,
      chapterBoundaries: chapterBoundaries ?? this.chapterBoundaries,
      isAppendingNext: isAppendingNext ?? this.isAppendingNext,
      isProgressiveLoading: isProgressiveLoading ?? this.isProgressiveLoading,
      cropBorders: cropBorders ?? this.cropBorders,
      scaleType: scaleType ?? this.scaleType,
      splitWidePages: splitWidePages ?? this.splitWidePages,
      showPageNumber: showPageNumber ?? this.showPageNumber,
      tapZonesInvert: tapZonesInvert ?? this.tapZonesInvert,
      showTapZones: showTapZones ?? this.showTapZones,
      translationFeatureEnabled:
          translationFeatureEnabled ?? this.translationFeatureEnabled,
      translationEnabled: translationEnabled ?? this.translationEnabled,
      pageTranslations: pageTranslations ?? this.pageTranslations,
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

  /// Maps the configured [scaleType] to a Flutter [BoxFit] for the image widget.
  BoxFit get scaleBoxFit {
    switch (scaleType) {
      case ScaleType.fitScreen:
        return BoxFit.contain;
      case ScaleType.fitWidth:
        return BoxFit.fitWidth;
      case ScaleType.fitHeight:
        return BoxFit.fitHeight;
      case ScaleType.original:
        return BoxFit.none;
    }
  }

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
        mangaTitle,
        coverUrl,
        chapterList,
        currentChapterIndex,
        lastLoadedChapterIndex,
        seekPage,
        chapterBoundaries,
        isAppendingNext,
        isProgressiveLoading,
        cropBorders,
        scaleType,
        splitWidePages,
        showPageNumber,
        tapZonesInvert,
        showTapZones,
        translationFeatureEnabled,
        translationEnabled,
        pageTranslations,
      ];
}
