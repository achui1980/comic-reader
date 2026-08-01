import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class HaokanManhua extends MangaSource {
  static const String sourceId = 'haokan';
  static const String _baseUrl = 'https://www.haokantxt.com';

  @override
  String get id => sourceId;

  @override
  String get name => '好看漫画';

  @override
  String get shortName => 'HK';

  @override
  String? get description => '国内免费漫画站，MCCMS 系统';

  @override
  double get score => 3.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => false;

  @override
  bool get needsProxy => false;

  @override
  Map<String, String>? get defaultHeaders => {'Referer': _baseUrl};

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'tags',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '热血', value: '6'),
            FilterChoice(label: '冒险', value: '7'),
            FilterChoice(label: '科幻', value: '8'),
            FilterChoice(label: '霸总', value: '9'),
            FilterChoice(label: '玄幻', value: '10'),
            FilterChoice(label: '校园', value: '11'),
            FilterChoice(label: '修真', value: '12'),
            FilterChoice(label: '搞笑', value: '13'),
          ],
        ),
        FilterOption(
          name: 'finish',
          label: '状态',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '连载', value: '1'),
            FilterChoice(label: '完结', value: '2'),
          ],
        ),
        FilterOption(
          name: 'order',
          label: '排序',
          defaultValue: 'addtime',
          choices: [
            FilterChoice(label: '最新', value: 'addtime'),
            FilterChoice(label: '人气', value: 'hits'),
          ],
        ),
      ];

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
  FetchConfig prepareSearchFetch(String keyword, int page, Map<String, String> filters) {
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

  // --- Chapter List (embedded in info page) ---
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra}) {
    throw UnimplementedError();
  }

  @override
  ChapterResult parseChapter(dynamic response, String mangaId, String chapterId, int page) {
    throw UnimplementedError();
  }
}
