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
  final String? description;

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
    this.description,
  });

  MangaSummary copyWith({
    String? id,
    String? sourceId,
    String? title,
    String? coverUrl,
    String? author,
    List<String>? altTitles,
    String? latestChapter,
    String? updateTime,
    Map<String, String>? headers,
    int? chapterCount,
    String? popularityText,
    String? description,
  }) {
    return MangaSummary(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      author: author ?? this.author,
      altTitles: altTitles ?? this.altTitles,
      latestChapter: latestChapter ?? this.latestChapter,
      updateTime: updateTime ?? this.updateTime,
      headers: headers ?? this.headers,
      chapterCount: chapterCount ?? this.chapterCount,
      popularityText: popularityText ?? this.popularityText,
      description: description ?? this.description,
    );
  }

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
        description,
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
