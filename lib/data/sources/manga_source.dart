import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Abstract base class for all manga source plugins.
/// Each plugin must implement prepare*/parse* method pairs.
abstract class MangaSource {
  /// Unique identifier for this source
  String get id;

  /// Human-readable name
  String get name;

  /// Short name for UI constraints
  String get shortName;

  /// Description of this source
  String? get description;

  /// Quality/reliability score (0-5)
  double get score;

  /// Source website URL
  String? get href;

  /// Custom user agent for requests
  String? get userAgent => null;

  /// Default headers for all requests from this source
  Map<String, String>? get defaultHeaders => null;

  /// Whether this source is disabled
  bool get disabled => false;

  /// Rate limiting delay between batch requests (ms)
  int get batchDelay => 1500;

  /// Discovery page filter options
  List<FilterOption> get discoveryFilters => const [];

  /// Search page filter options
  List<FilterOption> get searchFilters => const [];

  /// Build PluginInfo from this source
  PluginInfo get info => PluginInfo(
    id: id,
    name: name,
    shortName: shortName,
    description: description,
    score: score,
    href: href,
    disabled: disabled,
  );

  // --- Discovery ---
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters);
  List<MangaSummary> parseDiscovery(dynamic response);

  // --- Search ---
  FetchConfig prepareSearchFetch(String keyword, int page, Map<String, String> filters);
  List<MangaSummary> parseSearch(dynamic response);

  // --- Manga Info ---
  FetchConfig prepareMangaInfoFetch(String mangaId);
  MangaDetail parseMangaInfo(dynamic response, String mangaId);

  // --- Chapter List ---
  FetchConfig? prepareChapterListFetch(String mangaId, int page);
  ChapterListResult parseChapterList(dynamic response, String mangaId);

  // --- Chapter Content ---
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra});
  ChapterResult parseChapter(dynamic response, String mangaId, String chapterId, int page);
}
