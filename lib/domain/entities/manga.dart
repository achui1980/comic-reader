import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/chapter.dart';

enum MangaStatus { ongoing, completed, unknown }

class MangaSummary extends Equatable {
  final String id;
  final String sourceId;
  final String title;
  final String coverUrl;
  final String author;
  final String? latestChapter;
  final String? updateTime;
  final Map<String, String>? headers;

  const MangaSummary({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.coverUrl,
    this.author = '',
    this.latestChapter,
    this.updateTime,
    this.headers,
  });

  @override
  List<Object?> get props => [id, sourceId, title, coverUrl, author, latestChapter, updateTime];
}

class MangaDetail extends Equatable {
  final String id;
  final String sourceId;
  final String title;
  final String coverUrl;
  final String? description;
  final String author;
  final List<String> tags;
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
    this.status = MangaStatus.unknown,
    this.latestChapter,
    this.updateTime,
    this.headers,
    this.chapters = const [],
  });

  @override
  List<Object?> get props => [id, sourceId, title, coverUrl, description, author, tags, status, chapters];
}
