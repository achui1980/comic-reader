import 'dart:convert';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/manga.dart';
import 'package:comic_reader/domain/entities/chapter.dart';
import 'package:comic_reader/domain/entities/plugin_info.dart';

class Komiic extends MangaSource {
  static const String sourceId = 'komiic';
  static const String _baseUrl = 'https://komiic.com';
  static const String _apiUrl = 'https://komiic.com/api/query';
  static const int _pageSize = 30;

  static const String _userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

  @override
  String get id => sourceId;

  @override
  String get name => 'Komiic';

  @override
  String get shortName => 'KMC';

  @override
  String? get description => '日漫/韓漫';

  @override
  double get score => 4.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;

  @override
  String? get userAgent => _userAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/',
        'Content-Type': 'application/json',
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'mode',
          label: '模式',
          defaultValue: 'hot',
          choices: [
            FilterChoice(label: '热门', value: 'hot'),
            FilterChoice(label: '最新更新', value: 'recent'),
            FilterChoice(label: '按分类', value: 'category'),
          ],
        ),
        FilterOption(
          name: 'orderBy',
          label: '排序',
          defaultValue: 'DATE_UPDATED',
          choices: [
            FilterChoice(label: '更新时间', value: 'DATE_UPDATED'),
            FilterChoice(label: '本月人气', value: 'MONTH_VIEWS'),
            FilterChoice(label: '总观看数', value: 'VIEWS'),
            FilterChoice(label: '收藏数', value: 'FAVORITE_COUNT'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '状态',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '连载', value: 'ONGOING'),
            FilterChoice(label: '完结', value: 'END'),
          ],
        ),
        FilterOption(
          name: 'category',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '愛情', value: '1'),
            FilterChoice(label: '後宮', value: '2'),
            FilterChoice(label: '神鬼', value: '3'),
            FilterChoice(label: '校園', value: '4'),
            FilterChoice(label: '搞笑', value: '5'),
            FilterChoice(label: '生活', value: '6'),
            FilterChoice(label: '懸疑', value: '7'),
            FilterChoice(label: '冒險', value: '8'),
            FilterChoice(label: '恐怖', value: '9'),
            FilterChoice(label: '職場', value: '10'),
            FilterChoice(label: '科幻', value: '17'),
            FilterChoice(label: '百合', value: '18'),
            FilterChoice(label: '治癒', value: '19'),
            FilterChoice(label: '熱血', value: '21'),
            FilterChoice(label: '競技', value: '22'),
            FilterChoice(label: '運動', value: '40'),
            FilterChoice(label: '異世界', value: '47'),
            FilterChoice(label: '成人', value: '51'),
            FilterChoice(label: '戰鬥', value: '54'),
            FilterChoice(label: '日常', value: '78'),
            FilterChoice(label: '劇情', value: '97'),
            FilterChoice(label: '奇幻', value: '189'),
            FilterChoice(label: 'BL', value: '274'),
          ],
        ),
      ];

  // --- Helper: Build GraphQL request body ---
  String _buildGraphqlBody(
      String operationName, String query, Map<String, dynamic> variables) {
    return jsonEncode({
      'operationName': operationName,
      'query': query,
      'variables': variables,
    });
  }

  // --- Discovery ---
  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final mode = filters['mode'] ?? 'hot';
    final orderBy = filters['orderBy'] ?? 'DATE_UPDATED';
    final status = filters['status'] ?? '';
    final category = filters['category'] ?? '';

    final pagination = {
      'offset': (page - 1) * _pageSize,
      'limit': _pageSize,
      'orderBy': orderBy,
      'status': status,
      'asc': false,
    };

    String operationName;
    String query;
    Map<String, dynamic> variables;

    if (mode == 'category' && category.isNotEmpty) {
      operationName = 'comicByCategories';
      query = '''query comicByCategories(\$categoryId: [ID!]!, \$pagination: Pagination!) {
  comics: comicByCategories(categoryId: \$categoryId, pagination: \$pagination) {
    id title status imageUrl
    authors { id name }
    categories { id name }
  }
}''';
      variables = {
        'categoryId': [category],
        'pagination': pagination,
      };
    } else if (mode == 'recent') {
      operationName = 'recentUpdate';
      query = '''query recentUpdate(\$pagination: Pagination!) {
  comics: recentUpdate(pagination: \$pagination) {
    id title status imageUrl
    authors { id name }
    categories { id name }
  }
}''';
      variables = {'pagination': pagination};
    } else {
      operationName = 'hotComics';
      query = '''query hotComics(\$pagination: Pagination!) {
  comics: hotComics(pagination: \$pagination) {
    id title status imageUrl
    authors { id name }
    categories { id name }
  }
}''';
      variables = {'pagination': pagination};
    }

    return FetchConfig(
      url: _apiUrl,
      method: HttpMethod.post,
      headers: defaultHeaders,
      body: _buildGraphqlBody(operationName, query, variables),
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseComicsList(response);
  }

  /// Shared parser for comic list responses (discovery, search, category)
  List<MangaSummary> _parseComicsList(dynamic response) {
    final Map<String, dynamic> json;
    if (response is String) {
      json = jsonDecode(response) as Map<String, dynamic>;
    } else {
      json = response as Map<String, dynamic>;
    }

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return [];

    final List<dynamic>? comics = data['comics'] as List<dynamic>?;
    if (comics == null) return [];

    return comics.map<MangaSummary>((item) {
      final comic = item as Map<String, dynamic>;
      final authors = (comic['authors'] as List<dynamic>?)
              ?.map((a) => (a as Map<String, dynamic>)['name'] as String)
              .join(', ') ??
          '';

      return MangaSummary(
        id: comic['id'].toString(),
        sourceId: sourceId,
        title: comic['title'] as String? ?? '',
        coverUrl: comic['imageUrl'] as String? ?? '',
        author: authors,
      );
    }).toList();
  }

  // --- Search ---
  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    const operationName = 'searchComicAndAuthor';
    const query = '''query searchComicAndAuthor(\$keyword: String!) {
  searchComicsAndAuthors(keyword: \$keyword) {
    comics {
      id title status imageUrl
      authors { id name }
      categories { id name }
    }
  }
}''';

    return FetchConfig(
      url: _apiUrl,
      method: HttpMethod.post,
      headers: defaultHeaders,
      body: _buildGraphqlBody(operationName, query, {'keyword': keyword}),
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final Map<String, dynamic> json;
    if (response is String) {
      json = jsonDecode(response) as Map<String, dynamic>;
    } else {
      json = response as Map<String, dynamic>;
    }

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return [];

    final searchResult =
        data['searchComicsAndAuthors'] as Map<String, dynamic>?;
    if (searchResult == null) return [];

    final comics = searchResult['comics'] as List<dynamic>?;
    if (comics == null) return [];

    return comics.map<MangaSummary>((item) {
      final comic = item as Map<String, dynamic>;
      final authors = (comic['authors'] as List<dynamic>?)
              ?.map((a) => (a as Map<String, dynamic>)['name'] as String)
              .join(', ') ??
          '';

      return MangaSummary(
        id: comic['id'].toString(),
        sourceId: sourceId,
        title: comic['title'] as String? ?? '',
        coverUrl: comic['imageUrl'] as String? ?? '',
        author: authors,
      );
    }).toList();
  }

  // --- Manga Info ---
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    const operationName = 'comicById';
    const query = '''query comicById(\$comicId: ID!) {
  comicById(comicId: \$comicId) {
    id title description status imageUrl
    authors { id name }
    categories { id name }
    dateUpdated
  }
}''';

    return FetchConfig(
      url: _apiUrl,
      method: HttpMethod.post,
      headers: defaultHeaders,
      body: _buildGraphqlBody(operationName, query, {'comicId': mangaId}),
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final Map<String, dynamic> json;
    if (response is String) {
      json = jsonDecode(response) as Map<String, dynamic>;
    } else {
      json = response as Map<String, dynamic>;
    }

    final data = json['data'] as Map<String, dynamic>?;
    final comic = data?['comicById'] as Map<String, dynamic>? ?? {};

    final authors = (comic['authors'] as List<dynamic>?)
            ?.map((a) => (a as Map<String, dynamic>)['name'] as String)
            .join(', ') ??
        '';

    final categories = (comic['categories'] as List<dynamic>?)
            ?.map((c) => (c as Map<String, dynamic>)['name'] as String)
            .toList() ??
        [];

    final statusStr = comic['status'] as String? ?? '';
    final status = switch (statusStr) {
      'ONGOING' => MangaStatus.ongoing,
      'END' => MangaStatus.completed,
      _ => MangaStatus.unknown,
    };

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: comic['title'] as String? ?? '',
      coverUrl: comic['imageUrl'] as String? ?? '',
      description: comic['description'] as String?,
      author: authors,
      tags: categories,
      status: status,
      updateTime: comic['dateUpdated'] as String?,
    );
  }

  // --- Chapter List ---
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // API returns all chapters at once, no pagination needed
    if (page > 1) return null;

    const operationName = 'chapterByComicId';
    const query = '''query chapterByComicId(\$comicId: ID!) {
  chaptersByComicId(comicId: \$comicId) {
    id serial type size dateCreated dateUpdated
  }
}''';

    return FetchConfig(
      url: _apiUrl,
      method: HttpMethod.post,
      headers: defaultHeaders,
      body: _buildGraphqlBody(operationName, query, {'comicId': mangaId}),
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final Map<String, dynamic> json;
    if (response is String) {
      json = jsonDecode(response) as Map<String, dynamic>;
    } else {
      json = response as Map<String, dynamic>;
    }

    final data = json['data'] as Map<String, dynamic>?;
    final chaptersList = data?['chaptersByComicId'] as List<dynamic>? ?? [];

    // Separate by type: prefer 'chapter' over 'book'
    final chapters = chaptersList
        .where((c) => (c as Map<String, dynamic>)['type'] == 'chapter')
        .toList();
    final books = chaptersList
        .where((c) => (c as Map<String, dynamic>)['type'] == 'book')
        .toList();

    // Use chapters if available, otherwise fall back to books
    final items = chapters.isNotEmpty ? chapters : books;
    final isBookType = chapters.isEmpty && books.isNotEmpty;

    final chapterItems = items.map<ChapterItem>((item) {
      final ch = item as Map<String, dynamic>;
      final serial = ch['serial']?.toString() ?? '0';
      final title = isBookType ? '第$serial卷' : '第$serial話';

      return ChapterItem(
        id: ch['id'].toString(),
        mangaId: mangaId,
        title: title,
      );
    }).toList();

    return ChapterListResult(
      chapters: chapterItems,
      canLoadMore: false,
    );
  }

  // --- Chapter Content ---
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    const operationName = 'imagesByChapterId';
    const query = '''query imagesByChapterId(\$chapterId: ID!) {
  imagesByChapterId(chapterId: \$chapterId) {
    id kid height width
  }
}''';

    return FetchConfig(
      url: _apiUrl,
      method: HttpMethod.post,
      headers: defaultHeaders,
      body: _buildGraphqlBody(operationName, query, {'chapterId': chapterId}),
      extra: {'mangaId': mangaId, 'chapterId': chapterId},
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final Map<String, dynamic> json;
    if (response is String) {
      json = jsonDecode(response) as Map<String, dynamic>;
    } else {
      json = response as Map<String, dynamic>;
    }

    final data = json['data'] as Map<String, dynamic>?;
    final imagesList = data?['imagesByChapterId'] as List<dynamic>? ?? [];

    // Build image headers with the required Referer
    final imageHeaders = {
      'User-Agent': _userAgent,
      'Referer': '$_baseUrl/comic/$mangaId/chapter/$chapterId/images/all',
    };

    final images = imagesList.map<ChapterImage>((item) {
      final img = item as Map<String, dynamic>;
      final kid = img['kid'] as String;

      return ChapterImage(
        url: '$_baseUrl/api/image/$kid',
        headers: imageHeaders,
      );
    }).toList();

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: images,
      ),
      canLoadMore: false,
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/comic/$mangaId/chapter/$chapterId/images/all';
  }
}
