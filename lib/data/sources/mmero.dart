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
    FilterOption(
      name: 'tagId',
      label: '标签',
      defaultValue: 'all',
      choices: [
        FilterChoice(label: '全部', value: 'all'),
        // 角色/职业
        FilterChoice(label: '熟女', value: '50'),
        FilterChoice(label: '学生', value: '70'),
        FilterChoice(label: '魔法少女', value: '129'),
        FilterChoice(label: '辣妹', value: '159'),
        FilterChoice(label: '巫女', value: '167'),
        FilterChoice(label: '女骑士', value: '196'),
        FilterChoice(label: '姐姐', value: '295'),
        FilterChoice(label: '妹妹', value: '307'),
        FilterChoice(label: '青梅竹马', value: '348'),
        FilterChoice(label: '护士', value: '412'),
        FilterChoice(label: '人妻', value: '510'),
        FilterChoice(label: '女僕', value: '602'),
        FilterChoice(label: '未亡人', value: '603'),
        FilterChoice(label: '修女', value: '604'),
        FilterChoice(label: '女王', value: '605'),
        FilterChoice(label: '公主', value: '606'),
        FilterChoice(label: '病娇', value: '607'),
        FilterChoice(label: '女忍者', value: '608'),
        FilterChoice(label: '女战士', value: '609'),
        FilterChoice(label: '御姐', value: '617'),
        FilterChoice(label: '女医', value: '627'),
        // 服装/样貌
        FilterChoice(label: '幽灵', value: '9'),
        FilterChoice(label: '巨乳', value: '25'),
        FilterChoice(label: '萝莉', value: '30'),
        FilterChoice(label: '泳装', value: '36'),
        FilterChoice(label: '兽耳', value: '39'),
        FilterChoice(label: '眼镜', value: '74'),
        FilterChoice(label: '贫乳', value: '82'),
        FilterChoice(label: '兔女郎', value: '86'),
        FilterChoice(label: '扶他', value: '112'),
        FilterChoice(label: '正太', value: '113'),
        FilterChoice(label: '精灵', value: '135'),
        FilterChoice(label: 'OL', value: '408'),
        FilterChoice(label: '痴女', value: '466'),
        FilterChoice(label: '碧池', value: '490'),
        FilterChoice(label: '运动服', value: '565'),
        FilterChoice(label: '黑长直', value: '610'),
        FilterChoice(label: '雌小鬼', value: '611'),
        FilterChoice(label: '魅魔', value: '612'),
        FilterChoice(label: '人外', value: '618'),
        FilterChoice(label: '黑肉', value: '619'),
        FilterChoice(label: '金发', value: '620'),
        // 倾向
        FilterChoice(label: '后宫', value: '12'),
        FilterChoice(label: '口交', value: '38'),
        FilterChoice(label: '洗脑/催眠', value: '59'),
        FilterChoice(label: '百合', value: '77'),
        FilterChoice(label: '触手', value: '85'),
        FilterChoice(label: '中出', value: '101'),
        FilterChoice(label: '颜射', value: '126'),
        FilterChoice(label: '绑缚', value: '174'),
        FilterChoice(label: '肛交', value: '181'),
        FilterChoice(label: '堕落', value: '184'),
        FilterChoice(label: '足交', value: '220'),
        FilterChoice(label: 'BL', value: '263'),
        FilterChoice(label: '援交', value: '271'),
        FilterChoice(label: '黑丝', value: '319'),
        FilterChoice(label: 'SM', value: '329'),
        FilterChoice(label: '凌辱', value: '398'),
        FilterChoice(label: '多人', value: '511'),
        FilterChoice(label: '裸足', value: '613'),
        FilterChoice(label: '轮姦', value: '616'),
        FilterChoice(label: '妊娠', value: '626'),
        // 剧情
        FilterChoice(label: '近未来', value: '11'),
        FilterChoice(label: '校园', value: '24'),
        FilterChoice(label: 'NTR', value: '143'),
        FilterChoice(label: '性转', value: '209'),
        FilterChoice(label: '纯爱', value: '338'),
        FilterChoice(label: '异世界', value: '379'),
        FilterChoice(label: '职场', value: '621'),
        FilterChoice(label: '历史', value: '625'),
        // 重口
        FilterChoice(label: '猎奇', value: '520'),
        FilterChoice(label: '人体改造', value: '614'),
        FilterChoice(label: '兽姦', value: '629'),
        // 作品属性
        FilterChoice(label: '中文', value: '312'),
        FilterChoice(label: '全彩', value: '33'),
        FilterChoice(label: '无修正', value: '71'),
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
    final tagId = int.tryParse(filters['tagId'] ?? '');
    if (tagId != null) queryParameters['tagIds'] = tagId;
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
