import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/chapter.dart';

enum MangaStatus { ongoing, completed, unknown }

class MangaSummary extends Equatable {
  final String id;
  final String sourceId;
  final String title;
  final String coverUrl;
  final String author;

  /// Alternative titles for this work (original-language name, romanization,
  /// English title, etc.). Used for cross-source matching / dedup. Empty when
  /// the source cannot provide any.
  final List<String> altTitles;
  final String? latestChapter;
  final String? updateTime;
  final Map<String, String>? headers;
  final int? chapterCount;
  final String? popularityText;

  const MangaSummary({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.coverUrl,
    this.author = '',
    this.altTitles = const [],
    this.latestChapter,
    this.updateTime,
    this.headers,
    this.chapterCount,
    this.popularityText,
  });

  @override
  List<Object?> get props => [
        id,
        sourceId,
        title,
        coverUrl,
        author,
        altTitles,
        latestChapter,
        updateTime,
        chapterCount,
        popularityText,
      ];
}

class MangaDetail extends Equatable {
  final String id;
  final String sourceId;
  final String title;
  final String coverUrl;
  final String? description;
  final String author;
  final List<String> tags;

  /// Alternative titles (original-language name, romanization, English title,
  /// etc.). Used for cross-source matching / dedup. Empty when unavailable.
  final List<String> altTitles;
  final MangaStatus status;
  final String? latestChapter;
  final String? updateTime;
  final Map<String, String>? headers;
  final List<ChapterItem> chapters;

  const MangaDetail({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.coverUrl,
    this.description,
    this.author = '',
    this.tags = const [],
    this.altTitles = const [],
    this.status = MangaStatus.unknown,
    this.latestChapter,
    this.updateTime,
    this.headers,
    this.chapters = const [],
  });

  @override
  List<Object?> get props => [id, sourceId, title, coverUrl, description, author, tags, altTitles, status, chapters];
}
