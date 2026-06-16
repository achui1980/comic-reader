import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// PicaComic (哔咔漫画) source plugin.
/// API-based source with HMAC-SHA256 signed requests.
class PicaComic extends MangaSource {
  static const String sourceId = 'pica';
  static const String _baseUrl = 'https://picaapi.picacomic.com';
  static const String _webUrl = 'https://manhuabika.com';

  static const String _apiKey = 'C69BAF41DA5ABD1FFEDC6D2FEA56B';
  static const String _secretKey =
      r'~d}$Q7$eIni=V)9\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn';

  static const Map<String, String> _defaultHeaders = {
    'api-key': _apiKey,
    'Accept': 'application/vnd.picacomic.com.v1+json',
    'App-Channel': '2',
    'App-Uuid': 'defaultUuid',
    'App-Platform': 'android',
    'Image-Quality': 'original',
    'Content-Type': 'application/json; charset=UTF-8',
    'App-Version': '2.2.1.2.3.3',
    'App-Build-Version': '44',
    'User-Agent': 'okhttp/3.8.1',
  };

  String _authToken = '';

  /// Built-in credentials for convenience
  static const String defaultEmail = 'iz9xgh420260616u';
  static const String defaultPassword = 'iz9xgh420260616p';

  @override
  String get id => sourceId;

  @override
  String get name => '哔咔漫画';

  @override
  String get shortName => 'Pica';

  @override
  String? get description => '需要登录账号才能使用';

  @override
  double get score => 4.5;

  @override
  String? get href => _webUrl;

  @override
  Map<String, String>? get defaultHeaders => _defaultHeaders;

  @override
  bool get requiresLogin => true;

  @override
  bool get isAuthenticated => _authToken.isNotEmpty;

  @override
  void syncExtraData(Map<String, dynamic> data) {
    super.syncExtraData(data);
    final token = data['token'] as String?;
    if (token != null && token.isNotEmpty) {
      _authToken = token;
    }
  }

  /// Sign in with email and password.
  /// Returns a FetchConfig for the sign-in request.
  /// The caller should execute this and pass the response to [parseSignIn].
  FetchConfig buildSignInRequest(String email, String password) {
    const path = 'auth/sign-in';
    return FetchConfig(
      url: '$_baseUrl/$path',
      method: HttpMethod.post,
      body: jsonEncode({'email': email, 'password': password}),
      headers: _buildSignedHeaders(path, 'POST'),
    );
  }

  /// Parse sign-in response and return the token, or null on failure.
  /// Also stores the token internally.
  String? parseSignIn(dynamic response) {
    final data = _parseJsonResponse(response);
    if (data == null) return null;
    final token = data['token'] as String?;
    if (token != null && token.isNotEmpty) {
      _authToken = token;
      return token;
    }
    return null;
  }

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'type',
          label: '类型',
          defaultValue: 'leaderboard',
          choices: [
            FilterChoice(label: '排行榜(24h)', value: 'leaderboard_H24'),
            FilterChoice(label: '排行榜(7天)', value: 'leaderboard_D7'),
            FilterChoice(label: '排行榜(30天)', value: 'leaderboard_D30'),
            FilterChoice(label: '大家都在看', value: 'collections'),
            FilterChoice(label: '官方推荐', value: 'random'),
          ],
        ),
      ];

  @override
  List<FilterOption> get searchFilters => const [
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'dd',
          choices: [
            FilterChoice(label: '新到旧', value: 'dd'),
            FilterChoice(label: '旧到新', value: 'da'),
            FilterChoice(label: '最多喜欢', value: 'ld'),
            FilterChoice(label: '最多观看', value: 'vd'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final type = filters['type'] ?? 'leaderboard_H24';

    if (type.startsWith('leaderboard_')) {
      final tt = type.replaceFirst('leaderboard_', '');
      const path = 'comics/leaderboard';
      const url = '$_baseUrl/$path';
      return FetchConfig(
        url: url,
        queryParameters: {'tt': tt, 'ct': 'VC'},
        headers: _buildSignedHeaders(path, 'GET'),
      );
    } else if (type == 'collections') {
      const path = 'collections';
      return FetchConfig(
        url: '$_baseUrl/$path',
        headers: _buildSignedHeaders(path, 'GET'),
      );
    } else {
      // random
      const path = 'comics/random';
      return FetchConfig(
        url: '$_baseUrl/$path',
        headers: _buildSignedHeaders(path, 'GET'),
      );
    }
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final data = _parseJsonResponse(response);
    if (data == null) return [];

    // Leaderboard returns {comics: [...]}
    final comics = data['comics'] as List? ?? data['data']?['comics'] as List? ?? [];
    if (comics.isEmpty) {
      // Try collections format {collections: [{comics: [...]}]}
      final collections = data['collections'] as List? ?? [];
      final results = <MangaSummary>[];
      for (final collection in collections) {
        final cComics = (collection as Map)['comics'] as List? ?? [];
        for (final comic in cComics) {
          final summary = _parseComicToSummary(comic as Map<String, dynamic>);
          if (summary != null) results.add(summary);
        }
      }
      return results;
    }

    return comics
        .map((c) => _parseComicToSummary(c as Map<String, dynamic>))
        .whereType<MangaSummary>()
        .toList();
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final sort = filters['sort'] ?? 'dd';
    const path = 'comics/advanced-search';
    const url = '$_baseUrl/$path';
    final body = jsonEncode({
      'keyword': keyword,
      'sort': sort,
      'categories': <String>[],
    });

    return FetchConfig(
      url: url,
      method: HttpMethod.post,
      queryParameters: {'page': '$page'},
      body: body,
      headers: _buildSignedHeaders('$path?page=$page', 'POST'),
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final data = _parseJsonResponse(response);
    if (data == null) return [];

    final docs =
        (data['comics'] as Map?)?['docs'] as List? ?? [];
    return docs
        .map((c) => _parseComicToSummary(c as Map<String, dynamic>))
        .whereType<MangaSummary>()
        .toList();
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    final path = 'comics/$mangaId';
    return FetchConfig(
      url: '$_baseUrl/$path',
      headers: _buildSignedHeaders(path, 'GET'),
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final data = _parseJsonResponse(response);
    if (data == null) {
      return MangaDetail(
        id: mangaId,
        sourceId: sourceId,
        title: '',
        coverUrl: '',
      );
    }

    final comic = data['comic'] as Map<String, dynamic>? ?? {};
    final title = comic['title'] as String? ?? '';
    final author = comic['author'] as String? ?? '';
    final description = comic['description'] as String? ?? '';
    final thumb = comic['thumb'] as Map? ?? {};
    final coverUrl = _buildImageUrl(thumb);
    final categories = (comic['categories'] as List?)
            ?.map((c) => c.toString())
            .toList() ??
        [];
    final tags =
        (comic['tags'] as List?)?.map((t) => t.toString()).toList() ?? [];
    final finished = comic['finished'] as bool? ?? false;

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: [...categories, ...tags],
      status: finished ? MangaStatus.completed : MangaStatus.ongoing,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    final path = 'comics/$mangaId/eps';
    return FetchConfig(
      url: '$_baseUrl/$path',
      queryParameters: {'page': '$page'},
      headers: _buildSignedHeaders('$path?page=$page', 'GET'),
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final data = _parseJsonResponse(response);
    if (data == null) return const ChapterListResult(chapters: []);

    final eps = data['eps'] as Map? ?? {};
    final docs = eps['docs'] as List? ?? [];
    final pages = eps['pages'] as int? ?? 1;
    final currentPage = eps['page'] as int? ?? 1;

    final chapters = <ChapterItem>[];
    for (final ep in docs) {
      final epMap = ep as Map<String, dynamic>;
      final order = epMap['order']?.toString() ?? '';
      final title = epMap['title'] as String? ?? 'Episode $order';
      chapters.add(ChapterItem(
        id: order,
        mangaId: mangaId,
        title: title,
      ));
    }

    return ChapterListResult(
      chapters: chapters,
      canLoadMore: currentPage < pages,
      nextPage: currentPage < pages ? currentPage + 1 : null,
    );
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    final path = 'comics/$mangaId/order/$chapterId/pages';
    return FetchConfig(
      url: '$_baseUrl/$path',
      queryParameters: {'page': '$page'},
      headers: _buildSignedHeaders('$path?page=$page', 'GET'),
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final data = _parseJsonResponse(response);
    if (data == null) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    final pagesData = data['pages'] as Map? ?? {};
    final docs = pagesData['docs'] as List? ?? [];
    final totalPages = pagesData['pages'] as int? ?? 1;
    final currentPage = pagesData['page'] as int? ?? 1;

    final images = <ChapterImage>[];
    for (final doc in docs) {
      final media = (doc as Map)['media'] as Map? ?? {};
      final imageUrl = _buildImageUrl(media);
      if (imageUrl.isNotEmpty) {
        images.add(ChapterImage(url: imageUrl));
      }
    }

    final ep = data['ep'] as Map? ?? {};
    final title = ep['title'] as String? ?? '';

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
      ),
      canLoadMore: currentPage < totalPages,
      nextPage: currentPage < totalPages ? currentPage + 1 : null,
    );
  }

  // --- Private Helpers ---

  Map<String, String> _buildSignedHeaders(String urlPath, String method) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _generateNonce();

    // Build signature: path + ts + nonce + method + apiKey -> lowercase -> HMAC-SHA256
    final raw =
        (urlPath + ts + nonce + method + _apiKey).toLowerCase();
    final key = utf8.encode(_secretKey);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(utf8.encode(raw));
    final signature = digest.toString();

    final headers = Map<String, String>.from(_defaultHeaders);
    headers['Time'] = ts;
    headers['Nonce'] = nonce;
    headers['Signature'] = signature;
    if (_authToken.isNotEmpty) {
      headers['Authorization'] = _authToken;
    }
    return headers;
  }

  String _generateNonce() {
    const chars =
        'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(
        32, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Map<String, dynamic>? _parseJsonResponse(dynamic response) {
    try {
      Map<String, dynamic> json;
      if (response is String) {
        json = jsonDecode(response) as Map<String, dynamic>;
      } else if (response is Map) {
        json = response as Map<String, dynamic>;
      } else {
        return null;
      }
      // Pica API wraps data in {code: 200, data: {...}}
      if (json.containsKey('data')) {
        return json['data'] as Map<String, dynamic>?;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  MangaSummary? _parseComicToSummary(Map<String, dynamic> comic) {
    final mangaId = comic['_id'] as String? ?? '';
    if (mangaId.isEmpty) return null;

    final title = comic['title'] as String? ?? '';
    final author = comic['author'] as String? ?? '';
    final thumb = comic['thumb'] as Map? ?? {};
    final coverUrl = _buildImageUrl(thumb);
    final finished = comic['finished'] as bool? ?? false;

    return MangaSummary(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      latestChapter: finished ? 'Completed' : null,
    );
  }

  /// Public imgproxy endpoint that doesn't require auth signatures
  static const _imgProxy = 'https://img.picacomic.com';

  String _buildImageUrl(Map? media) {
    if (media == null) return '';
    final fileServer = media['fileServer'] as String? ?? '';
    final path = media['path'] as String? ?? '';
    if (fileServer.isEmpty && path.isEmpty) return '';

    // If path is already a full URL, use it directly
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    // Case 1: tobeimg/ path (imgproxy with signature)
    // Replace storage-b.picacomic.com/tobeimg/ with img.picacomic.com/
    // img.picacomic.com is a public imgproxy that doesn't validate signatures
    if (path.startsWith('tobeimg/')) {
      // path = tobeimg/{sig}/rs:{opts}/g:{gravity}/{base64}.ext
      // We want: img.picacomic.com/{sig}/rs:{opts}/g:{gravity}/{base64}.ext
      final imgproxyPath = path.substring('tobeimg/'.length);
      return '$_imgProxy/$imgproxyPath';
    }

    // Case 2: tobs/ path (chapter images, requires auth on direct access)
    // Convert to static/ URL, then route through img.picacomic.com imgproxy
    if (path.startsWith('tobs/')) {
      final staticPath = path.replaceFirst('tobs/', 'static/');
      final host = fileServer.isNotEmpty ? fileServer : 'https://storage-b.picacomic.com';
      final cleanHost = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
      final sourceUrl = '$cleanHost/$staticPath';
      return _buildImgProxyUrl(sourceUrl);
    }

    // Case 3: path that already starts with static/
    if (path.startsWith('static/')) {
      final host = fileServer.isNotEmpty ? fileServer : 'https://storage-b.picacomic.com';
      final cleanHost = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
      final sourceUrl = '$cleanHost/$path';
      return _buildImgProxyUrl(sourceUrl);
    }

    // Case 4: plain uuid path (e.g., "3c85189f-...jpg" on storage1)
    // Route through imgproxy with fileServer + /static/ + path
    if (fileServer.isNotEmpty) {
      final cleanHost = fileServer.endsWith('/') ? fileServer.substring(0, fileServer.length - 1) : fileServer;
      final sourceUrl = '$cleanHost/static/$path';
      return _buildImgProxyUrl(sourceUrl);
    }

    // Fallback: construct full URL and route through imgproxy
    var base = fileServer;
    if (base.isEmpty) base = 'https://storage-b.picacomic.com';
    if (!base.endsWith('/')) base += '/';
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final sourceUrl = '$base$cleanPath';

    // If it's already on img.picacomic.com, return directly
    if (sourceUrl.contains('img.picacomic.com')) return sourceUrl;

    return _buildImgProxyUrl(sourceUrl);
  }

  /// Build an img.picacomic.com imgproxy URL from a source image URL
  String _buildImgProxyUrl(String sourceUrl) {
    // Determine extension from source URL
    final ext = sourceUrl.contains('.png') ? '.png' : '.jpg';
    // Encode source URL as base64url (no padding)
    final encoded = base64Url.encode(utf8.encode(sourceUrl)).replaceAll('=', '');
    // Use fill with large width for full quality, no signature needed on public imgproxy
    return '$_imgProxy/rs:fill:1920:0:0/g:sm/$encoded$ext';
  }
}
