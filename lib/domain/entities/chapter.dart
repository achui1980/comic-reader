import 'package:equatable/equatable.dart';

enum ScrambleType { none, jmc, rm5, wu55, hanabi }

/// How the image endpoint represents image bytes in its HTTP response.
enum ImageResponseEncoding { binary, base64OrBinary }

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
  final ImageResponseEncoding responseEncoding;
  final Map<String, String>? headers;
  /// The scramble_id threshold used for JMC unscrambling.
  /// Only relevant when scrambleType == ScrambleType.jmc.
  final int? scrambleId;
  /// wu55comic book ID, used for slice count calculation.
  /// Only relevant when scrambleType == ScrambleType.wu55.
  final int? wu55BookId;
  /// wu55comic page number (1-based index), used for slice count calculation.
  /// Only relevant when scrambleType == ScrambleType.wu55.
  final int? wu55PageNumber;
  /// Base64-encoded WASM unscramble ticket, from the reader API's
  /// metadata.scrambleInfo.ticket field. Only relevant when
  /// scrambleType == ScrambleType.hanabi.
  final String? hanabiTicket;
  /// Base64-encoded WASM unscramble nonce, from metadata.scrambleInfo.nonce.
  /// Only relevant when scrambleType == ScrambleType.hanabi.
  final String? hanabiNonce;
  /// Scramble grid column count, from metadata.scrambleInfo.cols.
  /// Only relevant when scrambleType == ScrambleType.hanabi.
  final int? hanabiCols;
  /// Scramble grid row count, from metadata.scrambleInfo.rows.
  /// Only relevant when scrambleType == ScrambleType.hanabi.
  final int? hanabiRows;

  const ChapterImage({
    required this.url,
    this.scrambleType = ScrambleType.none,
    this.responseEncoding = ImageResponseEncoding.binary,
    this.headers,
    this.scrambleId,
    this.wu55BookId,
    this.wu55PageNumber,
    this.hanabiTicket,
    this.hanabiNonce,
    this.hanabiCols,
    this.hanabiRows,
  });

  @override
  List<Object?> get props => [
    url,
    scrambleType,
    responseEncoding,
    scrambleId,
    wu55BookId,
    wu55PageNumber,
    hanabiTicket,
    hanabiNonce,
    hanabiCols,
    hanabiRows,
  ];
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
