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
    throw UnimplementedError();
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    throw UnimplementedError();
  }

  // --- Search ---
  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    throw UnimplementedError();
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    throw UnimplementedError();
  }

  // --- Manga Info ---
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    throw UnimplementedError();
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    throw UnimplementedError();
  }

  // --- Chapter List ---
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    throw UnimplementedError();
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    throw UnimplementedError();
  }

  // --- Chapter Content ---
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    throw UnimplementedError();
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    throw UnimplementedError();
  }
}
