import 'text_region.dart';

/// Translation result for one manga page, persisted by
/// [TranslationCacheStore] and looked up before re-running the pipeline.
class PageTranslation {
  const PageTranslation({
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    required this.pageIndex,
    required this.regions,
    required this.translatedAt,
  });

  final String sourceId;
  final String mangaId;
  final String chapterId;
  final int pageIndex;
  final List<TextRegion> regions;

  /// Epoch milliseconds when this translation was produced.
  final int translatedAt;

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'mangaId': mangaId,
        'chapterId': chapterId,
        'pageIndex': pageIndex,
        'regions': regions.map((r) => r.toJson()).toList(),
        'translatedAt': translatedAt,
      };

  factory PageTranslation.fromJson(Map<String, dynamic> json) {
    final rawRegions = json['regions'] as List? ?? const [];
    return PageTranslation(
      sourceId: json['sourceId'] as String? ?? '',
      mangaId: json['mangaId'] as String? ?? '',
      chapterId: json['chapterId'] as String? ?? '',
      pageIndex: json['pageIndex'] as int? ?? 0,
      regions: rawRegions
          .map((e) => TextRegion.fromJson(e as Map<String, dynamic>))
          .toList(),
      translatedAt: json['translatedAt'] as int? ?? 0,
    );
  }
}
