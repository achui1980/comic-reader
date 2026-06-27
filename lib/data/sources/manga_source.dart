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

  /// Whether this source requires a proxy/VPN (科学上网) to access
  bool get needsProxy => false;

  /// First page number for this source (most sources use 1, some use 0)
  int get firstPage => 1;

  /// Rate limiting delay between batch requests (ms)
  int get batchDelay => 1500;

  /// Discovery page filter options
  List<FilterOption> get discoveryFilters => const [];

  /// Search page filter options
  List<FilterOption> get searchFilters => const [];

  /// JavaScript to inject in WebView after page loads.
  /// Should call window.flutter_inappwebview.callHandler('onData', data)
  /// with extracted cookie/token data.
  /// Return null if this source doesn't need WebView verification.
  String? get injectedJavaScript => null;

  /// Cloudflare challenge page title(s) to detect.
  List<String> get cloudflarePageTitles => const ['Just a moment...'];

  /// Whether this source requires Cloudflare verification.
  bool get needsCloudflare => false;

  /// URL to open for Cloudflare verification.
  /// Override when the CF-protected domain differs from [href].
  /// Returns null to use [href] as default.
  String? get cloudflareUrl => null;

  /// Extra headers from stored auth data (cookies, etc.)
  /// These are merged into every request's headers.
  final Map<String, String> _extraHeaders = {};

  /// Get current extra headers (includes auth cookies)
  Map<String, String> get extraHeaders => _extraHeaders;

  /// Receive auth data from WebView (cookie, token, userAgent).
  /// Override to customize how data is applied.
  void syncExtraData(Map<String, dynamic> data) {
    final cookie = data['cookie'] as String?;
    if (cookie != null && cookie.isNotEmpty) {
      _extraHeaders['Cookie'] = cookie;
    }
    final userAgent = data['userAgent'] as String?;
    if (userAgent != null && userAgent.isNotEmpty) {
      _extraHeaders['User-Agent'] = userAgent;
    }
  }

  /// Clear stored auth/extra headers
  void clearExtraData() {
    _extraHeaders.clear();
  }

  /// Whether this source requires login (email/password) instead of WebView.
  bool get requiresLogin => false;

  /// Whether this source currently has valid auth data.
  bool get isAuthenticated => false;

  /// Build PluginInfo from this source
  PluginInfo get info => PluginInfo(
    id: id,
    name: name,
    shortName: shortName,
    description: description,
    score: score,
    href: href,
    disabled: disabled,
    needsProxy: needsProxy,
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

  /// Get the web URL for reading a chapter in browser.
  /// Default implementation uses the URL from prepareChapterFetch.
  /// Override in subclasses if the browser-readable URL differs from the API URL.
  String? getChapterWebUrl(String mangaId, String chapterId) {
    try {
      final config = prepareChapterFetch(mangaId, chapterId, 1);
      return config.url;
    } catch (_) {
      return null;
    }
  }
}
