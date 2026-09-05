import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum DetailStatus { initial, loading, loaded, error }

class DetailState extends Equatable {
  final DetailStatus status;
  final MangaDetail? manga;
  final List<ChapterItem> chapters;
  final bool chaptersLoading;
  final bool canLoadMoreChapters;
  final int chapterPage;
  final String? errorMessage;

  /// Set when the most recent chapter-list fetch attempt (initial load or
  /// a retry via [loadMoreChapters]-style pagination) failed. `null` means
  /// the last attempt succeeded (or none has failed yet). Distinct from
  /// [errorMessage], which covers the manga-info fetch, not pagination.
  final String? chaptersError;
  final bool isFavorite;
  final bool chaptersReversed;
  final Set<String> readChapterIds;

  const DetailState({
    this.status = DetailStatus.initial,
    this.manga,
    this.chapters = const [],
    this.chaptersLoading = false,
    this.canLoadMoreChapters = false,
    this.chapterPage = 1,
    this.errorMessage,
    this.chaptersError,
    this.isFavorite = false,
    this.chaptersReversed = false,
    this.readChapterIds = const {},
  });

  DetailState copyWith({
    DetailStatus? status,
    MangaDetail? manga,
    List<ChapterItem>? chapters,
    bool? chaptersLoading,
    bool? canLoadMoreChapters,
    int? chapterPage,
    String? errorMessage,
    String? chaptersError,
    /// Pass `true` to explicitly clear [chaptersError] back to `null`.
    /// Needed because the default `??` merge below can only ever set a
    /// new non-null value, never clear an existing one.
    bool clearChaptersError = false,
    bool? isFavorite,
    bool? chaptersReversed,
    Set<String>? readChapterIds,
  }) {
    return DetailState(
      status: status ?? this.status,
      manga: manga ?? this.manga,
      chapters: chapters ?? this.chapters,
      chaptersLoading: chaptersLoading ?? this.chaptersLoading,
      canLoadMoreChapters: canLoadMoreChapters ?? this.canLoadMoreChapters,
      chapterPage: chapterPage ?? this.chapterPage,
      errorMessage: errorMessage ?? this.errorMessage,
      chaptersError:
          clearChaptersError ? null : (chaptersError ?? this.chaptersError),
      isFavorite: isFavorite ?? this.isFavorite,
      chaptersReversed: chaptersReversed ?? this.chaptersReversed,
      readChapterIds: readChapterIds ?? this.readChapterIds,
    );
  }

  List<ChapterItem> get displayChapters =>
      chaptersReversed ? chapters.reversed.toList() : chapters;

  @override
  List<Object?> get props => [
        status,
        manga,
        chapters,
        chaptersLoading,
        canLoadMoreChapters,
        chapterPage,
        errorMessage,
        chaptersError,
        isFavorite,
        chaptersReversed,
        readChapterIds,
      ];
}
