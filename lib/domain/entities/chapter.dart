import 'package:equatable/equatable.dart';

enum ScrambleType { none, jmc, rm5 }

class ChapterItem extends Equatable {
  final String id;
  final String mangaId;
  final String title;
  final String? href;

  const ChapterItem({
    required this.id,
    required this.mangaId,
    required this.title,
    this.href,
  });

  @override
  List<Object?> get props => [id, mangaId, title];
}

class ChapterImage extends Equatable {
  final String url;
  final ScrambleType scrambleType;
  final Map<String, String>? headers;

  const ChapterImage({
    required this.url,
    this.scrambleType = ScrambleType.none,
    this.headers,
  });

  @override
  List<Object?> get props => [url, scrambleType];
}

class Chapter extends Equatable {
  final String id;
  final String mangaId;
  final String title;
  final List<ChapterImage> images;
  final Map<String, String>? headers;

  const Chapter({
    required this.id,
    required this.mangaId,
    required this.title,
    required this.images,
    this.headers,
  });

  @override
  List<Object?> get props => [id, mangaId, title, images];
}

class ChapterListResult extends Equatable {
  final List<ChapterItem> chapters;
  final bool canLoadMore;
  final int? nextPage;

  const ChapterListResult({
    required this.chapters,
    this.canLoadMore = false,
    this.nextPage,
  });

  @override
  List<Object?> get props => [chapters, canLoadMore, nextPage];
}

class ChapterResult extends Equatable {
  final Chapter chapter;
  final bool canLoadMore;
  final int? nextPage;
  final dynamic nextExtra;

  const ChapterResult({
    required this.chapter,
    this.canLoadMore = false,
    this.nextPage,
    this.nextExtra,
  });

  @override
  List<Object?> get props => [chapter, canLoadMore, nextPage];
}
