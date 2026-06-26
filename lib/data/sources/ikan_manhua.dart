import 'package:html/parser.dart' as html_parser;
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/manga.dart';
import 'package:comic_reader/domain/entities/chapter.dart';
import 'package:comic_reader/domain/entities/plugin_info.dart';

class IkanManhua extends MangaSource {
  static const String sourceId = 'ikanmanhua';
  static const String _baseUrl = 'https://ikanmanhua.org';
  static const String _imageCdn = 'https://www.jjmh.cc/static/upload/book';

  static const String _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

  @override
  String get id => sourceId;

  @override
  String get name => '爱看漫画';

  @override
  String get shortName => 'IKM';

  @override
  String? get description => '韩漫/日漫';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;

  @override
  String? get userAgent => _mobileUserAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _mobileUserAgent,
        'Referer': '$_baseUrl/',
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'mode',
          label: '模式',
          defaultValue: 'books',
          choices: [
            FilterChoice(label: '分类浏览', value: 'books'),
            FilterChoice(label: '排行榜', value: 'rank'),
          ],
        ),
        FilterOption(
          name: 'tag',
          label: '题材',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '青春', value: '青春'),
            FilterChoice(label: '性感', value: '性感'),
            FilterChoice(label: '长腿', value: '长腿'),
            FilterChoice(label: '御姐', value: '御姐'),
            FilterChoice(label: '巨乳', value: '巨乳'),
            FilterChoice(label: '新婚', value: '新婚'),
            FilterChoice(label: '媳妇', value: '媳妇'),
            FilterChoice(label: '暧昧', value: '暧昧'),
            FilterChoice(label: '清纯', value: '清纯'),
            FilterChoice(label: '调教', value: '调教'),
            FilterChoice(label: '少妇', value: '少妇'),
            FilterChoice(label: '风骚', value: '风骚'),
            FilterChoice(label: '同居', value: '同居'),
            FilterChoice(label: '淫乱', value: '淫乱'),
            FilterChoice(label: '好友', value: '好友'),
            FilterChoice(label: '女神', value: '女神'),
            FilterChoice(label: '诱惑', value: '诱惑'),
            FilterChoice(label: '偷懒', value: '偷懒'),
            FilterChoice(label: '出轨', value: '出轨'),
          ],
        ),
        FilterOption(
          name: 'region',
          label: '地区',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '韩国', value: '韩国'),
            FilterChoice(label: '日本', value: '日本'),
            FilterChoice(label: '台湾', value: '台湾'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '进度',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '连载', value: '0'),
            FilterChoice(label: '完结', value: '1'),
          ],
        ),
        FilterOption(
          name: 'rank_type',
          label: '排行类型',
          defaultValue: 'popular',
          choices: [
            FilterChoice(label: '新番榜', value: 'new'),
            FilterChoice(label: '人气榜', value: 'popular'),
            FilterChoice(label: '完结榜', value: 'completed'),
            FilterChoice(label: '推荐榜', value: 'recommend'),
          ],
        ),
      ];

  // --- Discovery ---

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final mode = filters['mode'] ?? 'books';

    if (mode == 'rank') {
      // Rank page has no pagination; page > 1 will return empty in parse
      return FetchConfig(
        url: '$_baseUrl/rank',
        headers: defaultHeaders,
        extra: {
          'mode': 'rank',
          'rank_type': filters['rank_type'] ?? 'popular',
          'page': page,
        },
      );
    }

    // Category browsing mode with filters
    final queryParams = <String, dynamic>{};
    final tag = filters['tag'] ?? '';
    final region = filters['region'] ?? '';
    final status = filters['status'] ?? '';
    if (tag.isNotEmpty) queryParams['tag'] = tag;
    if (region.isNotEmpty) queryParams['region'] = region;
    if (status.isNotEmpty) queryParams['status'] = status;
    queryParams['page'] = page.toString();

    return FetchConfig(
      url: '$_baseUrl/books',
      queryParameters: queryParams,
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final html = response as String;
    final document = html_parser.parse(html);

    // Rank page has a tablist element; books page does not
    if (document.querySelector('[role="tablist"]') != null) {
      return _parseRankPage(document);
    }

    return _parseGridCards(document);
  }

  /// Parse grid cards from /books or /search pages.
  /// Cards are <a href="/book/{id}"> with nested img and title.
  List<MangaSummary> _parseGridCards(dynamic document) {
    final cards = document.querySelectorAll('a[href^="/book/"]');
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final card in cards) {
      final href = card.attributes['href'] ?? '';
      final match = RegExp(r'/book/(\d+)').firstMatch(href);
      if (match == null) continue;

      final mangaId = match.group(1)!;
      if (seen.contains(mangaId)) continue;
      seen.add(mangaId);

      final titleEl = card.querySelector('.line-clamp-1');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;

      final imgEl = card.querySelector('img');
      final coverUrl = imgEl?.attributes['src'] ??
          '$_imageCdn/$mangaId/cover.jpg';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        headers: defaultHeaders,
      ));
    }

    return results;
  }

  /// Parse rank page — all tabs content is SSR'd in HTML.
  /// Each rank item is an <a href="/book/{id}"> with title/author inside.
  List<MangaSummary> _parseRankPage(dynamic document) {
    // Rank page renders all tab panels; items have a different structure
    // They use flex layout with ranking number, cover, and info
    final cards = document.querySelectorAll('a[href^="/book/"]');
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final card in cards) {
      final href = card.attributes['href'] ?? '';
      final match = RegExp(r'/book/(\d+)').firstMatch(href);
      if (match == null) continue;

      final mangaId = match.group(1)!;
      if (seen.contains(mangaId)) continue;
      seen.add(mangaId);

      // Title is in h3 element
      final titleEl = card.querySelector('h3');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;

      // Author from <p> containing "作者："
      String author = '';
      final paragraphs = card.querySelectorAll('p');
      for (final p in paragraphs) {
        final text = p.text.trim();
        if (text.startsWith('作者：') || text.startsWith('作者:')) {
          author = text.replaceFirst(RegExp(r'^作者[：:]'), '').trim();
          break;
        }
      }

      final imgEl = card.querySelector('img');
      final coverUrl = imgEl?.attributes['src'] ??
          '$_imageCdn/$mangaId/cover.jpg';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        author: author,
        headers: defaultHeaders,
      ));
    }

    return results;
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // TODO: Task 3
    throw UnimplementedError();
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    // TODO: Task 3
    throw UnimplementedError();
  }

  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    // TODO: Task 4
    throw UnimplementedError();
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    // TODO: Task 4
    throw UnimplementedError();
  }

  // --- Chapter List ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    return null; // Chapters are embedded in the manga info page
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // TODO: Task 5
    throw UnimplementedError();
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    // TODO: Task 5
    throw UnimplementedError();
  }
}
