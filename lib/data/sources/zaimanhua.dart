import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// 再漫画 (zaimanhua.com) data source.
/// Uses JSON API at v4api.zaimanhua.com.
class Zaimanhua extends MangaSource {
  static const String sourceId = 'zaimanhua';
  static const String _baseUrl = 'https://www.zaimanhua.com';
  static const String _apiUrl = 'https://v4api.zaimanhua.com';

  /// Common query parameters required by the API.
  Map<String, dynamic> _commonParams() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return {
      'channel': 'pc',
      'app_name': 'zmh',
      'version': '1.0.0',
      'timestamp': timestamp,
      'uid': '',
    };
  }

  static const Map<String, String> _imageHeaders = {
    'Referer': '$_baseUrl/',
  };

  static const Map<String, String> _apiHeaders = {
    'Platform': 'pc',
    'Referer': '$_baseUrl/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  };

  @override
  String get id => sourceId;

  @override
  String get name => '再漫画';

  @override
  String get shortName => 'ZMH';

  @override
  bool get isAdult => true;

  @override
  String? get description => '免费在线漫画';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;

  @override
  Map<String, String>? get defaultHeaders => _apiHeaders;

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'audience',
          label: '读者',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '少年', value: '3262'),
            FilterChoice(label: '少女', value: '3263'),
            FilterChoice(label: '青年', value: '3264'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '状态',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '连载中', value: '1'),
            FilterChoice(label: '已完结', value: '2'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '人气排序', value: '0'),
            FilterChoice(label: '更新排序', value: '1'),
          ],
        ),
      ];

  // --- Discovery ---

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final params = _commonParams();
    params['status'] = filters['status'] ?? '0';
    params['audience'] = filters['audience'] ?? '0';
    params['theme'] = filters['theme'] ?? '';
    params['cate'] = filters['cate'] ?? '';
    // NOTE: firstLetter must be empty string (not '0') for "all".
    // '0' is treated as filtering for comics starting with digit "0".
    params['firstLetter'] = filters['firstLetter'] ?? '';
    params['sort'] = filters['sort'] ?? '0';
    params['page'] = page.toString();

    return FetchConfig(
      url: '$_apiUrl/api/v1/comic1/filter',
      headers: _apiHeaders,
      queryParameters: params,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final data = response as Map<String, dynamic>;
    if (data['errno'] != 0) return [];

    final comicList =
        (data['data'] as Map<String, dynamic>)['comicList'] as List?;
    if (comicList == null) return [];

    return comicList.map((item) {
      final comic = item as Map<String, dynamic>;
      return MangaSummary(
        id: comic['comic_py'] as String? ?? comic['id'].toString(),
        sourceId: sourceId,
        title: comic['name'] as String? ?? '',
        coverUrl: comic['cover'] as String? ?? '',
        author: _joinAuthors(comic['authors']),
        latestChapter: comic['last_update_chapter_name'] as String?,
        headers: _apiHeaders,
      );
    }).toList();
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final params = _commonParams();
    params['keyword'] = keyword;
    params['source'] = '';
    params['page'] = page.toString();
    params['size'] = '20';

    return FetchConfig(
      url: '$_apiUrl/app/v1/search/index',
      headers: _apiHeaders,
      queryParameters: params,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final data = response as Map<String, dynamic>;
    if (data['errno'] != 0) return [];

    final list = (data['data'] as Map<String, dynamic>)['list'] as List?;
    if (list == null) return [];

    return list.map((item) {
      final comic = item as Map<String, dynamic>;
      return MangaSummary(
        id: comic['comic_py'] as String? ?? comic['id'].toString(),
        sourceId: sourceId,
        title: comic['title'] as String? ?? comic['name'] as String? ?? '',
        coverUrl: comic['cover'] as String? ?? '',
        author: _joinAuthors(comic['authors']),
        latestChapter: comic['last_name'] as String?,
        headers: _apiHeaders,
      );
    }).toList();
  }

  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    final params = _commonParams();
    params['comic_py'] = mangaId;

    return FetchConfig(
      url: '$_apiUrl/api/v1/comic1/comic/detail',
      headers: _apiHeaders,
      queryParameters: params,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final data = response as Map<String, dynamic>;
    if (data['errno'] != 0) {
      return MangaDetail(
        id: mangaId,
        sourceId: sourceId,
        title: mangaId,
        coverUrl: '',
      );
    }

    final comicInfo =
        (data['data'] as Map<String, dynamic>)['comicInfo'] as Map<String, dynamic>;

    final title = comicInfo['title'] as String? ?? '';
    final coverUrl = comicInfo['cover'] as String? ?? '';
    final description = comicInfo['description'] as String?;
    final numericId = comicInfo['id'];

    // Author
    String author = '';
    final authorInfo = comicInfo['authorInfo'];
    if (authorInfo is Map<String, dynamic>) {
      author = authorInfo['authorName'] as String? ?? '';
    } else if (authorInfo is List && authorInfo.isNotEmpty) {
      author = (authorInfo.first as Map<String, dynamic>)['authorName'] as String? ?? '';
    }

    // Status
    MangaStatus status = MangaStatus.unknown;
    final statusVal = comicInfo['status'];
    if (statusVal is int) {
      if (statusVal == 1) {
        status = MangaStatus.ongoing;
      } else if (statusVal == 2) {
        status = MangaStatus.completed;
      }
    } else if (statusVal is String) {
      if (statusVal.contains('连载') || statusVal.contains('連載')) {
        status = MangaStatus.ongoing;
      } else if (statusVal.contains('完结') || statusVal.contains('完結')) {
        status = MangaStatus.completed;
      }
    }

    // Tags/types — API returns either a List or a comma-separated String
    final rawTypes = comicInfo['types'];
    List<String> tags;
    if (rawTypes is List) {
      tags = rawTypes
          .map((t) {
            if (t is Map<String, dynamic>) return t['name'] as String? ?? '';
            return t.toString();
          })
          .where((t) => t.isNotEmpty)
          .toList();
    } else if (rawTypes is String && rawTypes.isNotEmpty) {
      tags = rawTypes.split(',').where((t) => t.trim().isNotEmpty).map((t) => t.trim()).toList();
    } else {
      tags = [];
    }

    // Chapters
    final chapterList = comicInfo['chapterList'] as List?;
    final chapters = <ChapterItem>[];

    if (chapterList != null) {
      for (final group in chapterList) {
        final groupData = group as Map<String, dynamic>;
        final chapterData = groupData['data'] as List?;
        if (chapterData == null) continue;

        for (final ch in chapterData) {
          final chMap = ch as Map<String, dynamic>;
          final chId = chMap['chapter_id']?.toString() ?? '';
          final chapterTitle = chMap['chapter_title'] as String? ?? '';
          if (chId.isEmpty) continue;

          // Encode numeric comic_id into chapter ID so prepareChapterFetch
          // can extract it without needing extra state.
          // Format: "{comic_numeric_id}_{chapter_id}"
          final encodedChapterId = '${numericId}_$chId';

          chapters.add(ChapterItem(
            id: encodedChapterId,
            mangaId: mangaId,
            title: chapterTitle,
          ));
        }
      }
    }

    // Store numeric ID for chapter URL encoding
    final lastUpdateChapter = comicInfo['lastUpdateChapterName'] as String?;

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: tags,
      status: status,
      latestChapter: lastUpdateChapter,
      chapters: chapters,
      headers: _apiHeaders,
    );
  }

  // --- Chapter List ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are embedded in manga info response
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---

  /// Decode encoded chapter ID format: "{comic_numeric_id}_{chapter_id}"
  ({String comicId, String chapterId}) _decodeChapterId(String encoded) {
    final idx = encoded.indexOf('_');
    if (idx > 0) {
      return (comicId: encoded.substring(0, idx), chapterId: encoded.substring(idx + 1));
    }
    // Fallback: assume entire string is the chapter ID
    return (comicId: '', chapterId: encoded);
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    final decoded = _decodeChapterId(chapterId);

    final params = _commonParams();
    params['comic_id'] = decoded.comicId;
    params['chapter_id'] = decoded.chapterId;

    return FetchConfig(
      url: '$_apiUrl/api/v1/comic1/chapter/detail',
      headers: _apiHeaders,
      queryParameters: params,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final data = response as Map<String, dynamic>;
    if (data['errno'] != 0) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    final chapterInfo =
        (data['data'] as Map<String, dynamic>)['chapterInfo'] as Map<String, dynamic>;

    final title = chapterInfo['title'] as String? ?? '';
    final pageUrls = chapterInfo['page_url'] as List?;

    final images = <ChapterImage>[];
    if (pageUrls != null) {
      for (final url in pageUrls) {
        if (url is String && url.isNotEmpty) {
          images.add(ChapterImage(
            url: url,
            headers: _imageHeaders,
          ));
        }
      }
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: _imageHeaders,
      ),
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    final decoded = _decodeChapterId(chapterId);
    return '$_baseUrl/view/$mangaId/${decoded.chapterId}/1';
  }

  // --- Helpers ---

  String _joinAuthors(dynamic authors) {
    if (authors == null) return '';
    if (authors is String) return authors;
    if (authors is List) {
      return authors
          .map((a) {
            if (a is Map<String, dynamic>) return a['name'] as String? ?? '';
            return a.toString();
          })
          .where((s) => s.isNotEmpty)
          .join(', ');
    }
    return '';
  }
}
