import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// 51漫画 (51manga.com) — an MCCMS-based site, same engine family as
/// [HaokanManhua] but with a different template and, crucially, AES-encrypted
/// chapter image lists.
///
/// All requests go to the MOBILE host `m.51manga.com`:
///  * the PC search template is broken (always 0 results),
///  * mobile manga/chapter ids and paths are identical to PC,
///  * the mobile detail page ships the ENTIRE chapter list in one response.
class Manga51 extends MangaSource {
  static const String sourceId = 'manga51';

  /// Host used for every request.
  static const String _baseUrl = 'https://m.51manga.com';

  /// Host used for the anti-hotlink Referer and for opening pages in a browser.
  static const String _pcBaseUrl = 'https://www.51manga.com';

  static const String _mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  @override
  String get id => sourceId;

  @override
  String get name => '51漫画';

  @override
  String get shortName => '51漫';

  @override
  String? get description => 'MCCMS 漫画站，章节图片 AES 加密';

  @override
  double get score => 4.0;

  @override
  String? get href => _pcBaseUrl;

  @override
  bool get isAdult => true;

  @override
  bool get needsProxy => false;

  @override
  String? get userAgent => _mobileUa;

  @override
  Map<String, String>? get defaultHeaders => const {'Referer': '$_pcBaseUrl/'};

  /// Discovery filters. Each `name` here is consumed by
  /// [prepareDiscoveryFetch] as a URL path segment (`/<name>/<value>`), so the
  /// names are site API surface, not just UI labels. Adding an option here
  /// requires adding its name to the segment list in [prepareDiscoveryFetch];
  /// a test enforces that. Declaration order sets the UI dropdown order only —
  /// the URL segment order is fixed separately by the site.
  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'list',
          label: '类型',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '国产漫画', value: '1'),
            FilterChoice(label: '日本漫画', value: '2'),
            FilterChoice(label: '韩国漫画', value: '3'),
            FilterChoice(label: '欧美漫画', value: '4'),
          ],
        ),
        FilterOption(
          name: 'tags',
          label: '题材',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '科幻', value: '867'),
            FilterChoice(label: '后宫', value: '868'),
            FilterChoice(label: '机甲', value: '869'),
            FilterChoice(label: '都市', value: '870'),
            FilterChoice(label: '恋爱生活', value: '871'),
            // Site has both 872 and 873 labelled 恋爱; 873 is dropped so the
            // dropdown does not show two identical rows.
            FilterChoice(label: '恋爱', value: '872'),
            FilterChoice(label: '其他', value: '874'),
            FilterChoice(label: '推理悬疑', value: '875'),
            FilterChoice(label: '魔法', value: '876'),
            FilterChoice(label: '奇幻', value: '877'),
            FilterChoice(label: '异世界', value: '878'),
            FilterChoice(label: '滑稽搞笑', value: '879'),
            FilterChoice(label: '重生', value: '880'),
            FilterChoice(label: '励志', value: '881'),
            FilterChoice(label: '浪漫', value: '882'),
            FilterChoice(label: '逆袭', value: '883'),
            FilterChoice(label: '脑洞', value: '884'),
            FilterChoice(label: '日常', value: '885'),
            FilterChoice(label: '热血机战', value: '886'),
            FilterChoice(label: '魔法/奇幻', value: '887'),
            FilterChoice(label: '武侠经典', value: '888'),
            FilterChoice(label: '韩漫', value: '889'),
            FilterChoice(label: '小说改编', value: '890'),
            FilterChoice(label: '穿越', value: '891'),
            FilterChoice(label: '非现代', value: '892'),
            FilterChoice(label: '大女主', value: '893'),
            FilterChoice(label: '腹黑', value: '894'),
            FilterChoice(label: '校园', value: '895'),
            FilterChoice(label: '剧情', value: '896'),
          ],
        ),
        FilterOption(
          name: 'finish',
          label: '状态',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '连载中', value: '1'),
            FilterChoice(label: '已完结', value: '2'),
          ],
        ),
        FilterOption(
          name: 'order',
          label: '排序',
          defaultValue: 'hits',
          choices: [
            FilterChoice(label: '热门', value: 'hits'),
            FilterChoice(label: '最新', value: 'addtime'),
          ],
        ),
      ];

  // --- Discovery ---
  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    // Segment order is fixed by the site: list -> tags -> finish -> order -> page.
    // This list must stay in sync with the `name`s in [discoveryFilters]; it is
    // deliberately NOT derived from them, because that would tie the site's
    // required segment order to the UI dropdown order.
    final buffer = StringBuffer('$_baseUrl/category');
    for (final key in const ['list', 'tags', 'finish', 'order']) {
      final value = filters[key] ?? '';
      if (value.isNotEmpty) buffer.write('/$key/$value');
    }
    // Discovery REQUIRES the `/page/N` form and paginates correctly with it.
    // (Contrast prepareSearchFetch, where `/page/N` is broken.)
    buffer.write('/page/$page');
    return FetchConfig(url: buffer.toString());
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    throw UnimplementedError();
  }

  // --- Search ---
  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // Pagination on the SEARCH route is a bare numeric segment: `/search/<kw>/2`.
    // Verified live against m.51manga.com with the mobile UA (keyword 妹妹):
    //  * `/search/<kw>` and `/search/<kw>/1` are byte-identical, so the bare
    //    form is merely the site's canonical page-1 URL. This special case is a
    //    stylistic choice, NOT a site requirement — the sibling HaokanManhua
    //    appends `/$page` unconditionally and works fine.
    //  * `/search/<kw>/page/2` returns page 1 SILENTLY (200, same bytes as
    //    page 1). Do not copy the `/page/N` form that prepareDiscoveryFetch
    //    uses; that route needs it, this one breaks on it.
    // `<=` rather than `==` is defensive against a 0-or-negative caller.
    final base = '$_baseUrl/search/${Uri.encodeComponent(keyword)}';
    return FetchConfig(url: page <= 1 ? base : '$base/$page');
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    throw UnimplementedError();
  }

  // --- Manga Info ---
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/mh/$mangaId');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    throw UnimplementedError();
  }

  // --- Chapter List (embedded in the info page) ---
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // chapterId is globally unique; mangaId is intentionally unused.
    return FetchConfig(url: '$_baseUrl/show/$chapterId.html');
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    throw UnimplementedError();
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    // PC layout reads better in a real browser.
    return '$_pcBaseUrl/show/$chapterId.html';
  }
}
