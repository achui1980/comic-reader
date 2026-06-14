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
  final bool isFavorite;
  final bool chaptersReversed;

  const DetailState({
    this.status = DetailStatus.initial,
    this.manga,
    this.chapters = const [],
    this.chaptersLoading = false,
    this.canLoadMoreChapters = false,
    this.chapterPage = 1,
    this.errorMessage,
    this.isFavorite = false,
    this.chaptersReversed = false,
  });

  DetailState copyWith({
    DetailStatus? status,
    MangaDetail? manga,
    List<ChapterItem>? chapters,
    bool? chaptersLoading,
    bool? canLoadMoreChapters,
    int? chapterPage,
    String? errorMessage,
    bool? isFavorite,
    bool? chaptersReversed,
  }) {
    return DetailState(
      status: status ?? this.status,
      manga: manga ?? this.manga,
      chapters: chapters ?? this.chapters,
      chaptersLoading: chaptersLoading ?? this.chaptersLoading,
      canLoadMoreChapters: canLoadMoreChapters ?? this.canLoadMoreChapters,
      chapterPage: chapterPage ?? this.chapterPage,
      errorMessage: errorMessage ?? this.errorMessage,
      isFavorite: isFavorite ?? this.isFavorite,
      chaptersReversed: chaptersReversed ?? this.chaptersReversed,
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
        isFavorite,
        chaptersReversed,
      ];
}
