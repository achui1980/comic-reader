import 'package:comic_reader/domain/entities/entities.dart';

/// Abstract repository interface for manga data operations.
abstract class MangaRepository {
  /// Fetch discovery manga list
  Future<List<MangaSummary>> getDiscovery(String sourceId, int page, Map<String, String> filters);

  /// Search manga
  Future<List<MangaSummary>> searchManga(String sourceId, String keyword, int page, Map<String, String> filters);

  /// Get manga detail info
  Future<MangaDetail> getMangaInfo(String sourceId, String mangaId);

  /// Get chapter list for a manga
  Future<ChapterListResult> getChapterList(String sourceId, String mangaId, int page);

  /// Get chapter content (images)
  Future<ChapterResult> getChapter(String sourceId, String mangaId, String chapterId, int page, {dynamic extra});

  /// Progressive chapter loading - yields partial results as images are resolved.
  Stream<ChapterResult> getChapterStream(String sourceId, String mangaId, String chapterId, int page, {dynamic extra});
}
