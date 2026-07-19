import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class MmeroSource extends MangaSource {
  static const String sourceId = 'mmero';
  static const String _baseUrl = 'https://mmero.com';
  static const String _coverBaseUrl = 'https://cover.2thewash.com';
  static const String _imageBaseUrl = 'https://c2.2thewash.com';
  static const int _pageSize = 30;

  @override
  String get id => sourceId;

  @override
  String get name => '摸摸漫画';

  @override
  String get shortName => 'MM';

  @override
  String? get description => '成人漫画';

  @override
  double get score => 3.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => true;

  @override
  List<FilterOption> get discoveryFilters => const [
    FilterOption(
      name: 'channel',
      label: '频道',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '韩漫', value: '1'),
        FilterChoice(label: '同人志', value: '2'),
        FilterChoice(label: '杂志', value: '4'),
        FilterChoice(label: '单行本', value: '5'),
      ],
    ),
    FilterOption(
      name: 'status',
      label: '状态',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        FilterChoice(label: '连载中', value: 'ongoing'),
        FilterChoice(label: '已完结', value: 'completed'),
      ],
    ),
  ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final queryParameters = <String, dynamic>{
      'pageNo': page,
      'pageSize': _pageSize,
    };
    final channel = int.tryParse(filters['channel'] ?? '');
    if (channel != null) queryParameters['channel'] = channel;
    if (filters['status'] == 'ongoing') queryParameters['isEnded'] = false;
    if (filters['status'] == 'completed') queryParameters['isEnded'] = true;
    return FetchConfig(
      url: '$_baseUrl/api/comic/items',
      queryParameters: queryParameters,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) => _parseList(response);

  @override
  FetchConfig prepareSearchFetch(
    String keyword,
    int page,
    Map<String, String> filters,
  ) {
    return FetchConfig(
      url: '$_baseUrl/api/comic/search',
      queryParameters: {
        'keyword': keyword,
        'pageNo': page,
        'pageSize': _pageSize,
        'type': 1,
      },
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) => _parseList(response);

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/api/comic/content',
      method: HttpMethod.post,
      body: {'id': int.parse(mangaId)},
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final data = _map(response);
    final chapters = <ChapterItem>[];
    for (final value in _list(data?['chapters'])) {
      final chapter = _map(value);
      final number = chapter?['number'];
      if (number == null) continue;
      final chapterId = number.toString();
      final title = chapter?['title']?.toString() ?? '';
      chapters.add(
        ChapterItem(
          id: chapterId,
          mangaId: mangaId,
          title: title.isEmpty ? '第$chapterId话' : title,
          href: '$_baseUrl/comics/$mangaId/$chapterId',
        ),
      );
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: data?['title']?.toString() ?? '',
      author: data?['author']?.toString() ?? '',
      description: data?['desc']?.toString(),
      tags: _list(data?['tags'])
          .map(_map)
          .map((tag) => tag?['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList(),
      status: data?['isEnded'] == true
          ? MangaStatus.completed
          : data?['isEnded'] == false
          ? MangaStatus.ongoing
          : MangaStatus.unknown,
      coverUrl: _coverUrl(mangaId),
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  @override
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) {
    return FetchConfig(
      url: '$_baseUrl/api/comic/chapter',
      method: HttpMethod.post,
      body: {'id': int.parse(mangaId), 'chapter': int.parse(chapterId)},
    );
  }

  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) {
    final data = _map(response);
    final rawPageCount = data?['pages'];
    final pageCount = rawPageCount is num ? rawPageCount.toInt() : 0;
    final images = [
      for (var imagePage = 1; imagePage <= pageCount; imagePage++)
        ChapterImage(
          url: '$_imageBaseUrl/comic/$mangaId/$chapterId/$imagePage.jpg',
          responseEncoding: ImageResponseEncoding.base64OrBinary,
        ),
    ];
    final title = data?['title']?.toString() ?? '';
    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title.isEmpty ? '第$chapterId话' : title,
        images: images,
      ),
      canLoadMore: false,
    );
  }

  @override
  String getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/comics/$mangaId/$chapterId';
  }

  List<MangaSummary> _parseList(dynamic response) {
    final data = _map(response);
    final results = <MangaSummary>[];
    for (final value in _list(data?['items'])) {
      final item = _map(value);
      final id = item?['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final chapter = item?['chapter'];
      results.add(
        MangaSummary(
          id: id,
          sourceId: sourceId,
          title: item?['title']?.toString() ?? '',
          coverUrl: _coverUrl(id),
          latestChapter: chapter == null ? null : '第$chapter话',
        ),
      );
    }
    return results;
  }

  String _coverUrl(String mangaId) => '$_coverBaseUrl/comic/$mangaId/cover.jpg';

  Map? _map(dynamic value) => value is Map ? value : null;

  List _list(dynamic value) => value is List ? value : const [];
}
