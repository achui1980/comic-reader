import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

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

  /// Single source of truth for the Referer sent with BOTH page requests
  /// ([defaultHeaders]) and image requests ([_imageHeaders]). The image CDN
  /// (`img1.baipiaoguai.org`) answers 403 without a Referer, and a page-vs-image
  /// mismatch is a classic silent 403 on anti-hotlink setups, so the two must
  /// stay byte-identical — including the trailing slash.
  static const String _referer = '$_pcBaseUrl/';

  static const String _mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  /// Headers attached to every cover/page image URL this source emits.
  static const Map<String, String> _imageHeaders = {
    'Referer': _referer,
    'User-Agent': _mobileUa,
  };

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
  Map<String, String>? get defaultHeaders => const {'Referer': _referer};

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
    return _parseCards(response as String);
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
    return _parseCards(response as String);
  }

  // --- Manga Info ---
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/mh/$mangaId');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final title = _cleanText(document.querySelector('h1.name')?.text) ??
        _cleanText(document.querySelector('header .title h2')?.text) ??
        '';
    if (title.isEmpty) {
      // Two very different causes reach here, and they must NOT share a message:
      // detail_cubit.dart passes `e.toString()` straight to the detail screen, so
      // whatever is thrown is read verbatim by the user.
      //
      // A missing/deleted id 302s to `/err/comic`, a 259-byte body whose first
      // sentence is 「很遗憾，该漫画不存在或章节已被删除。」 and which carries no
      // title element of either kind. This is a hot path, not an edge case: 1 of
      // the 24 ids taken straight off live listing pages resolved to that stub
      // (verified live 2026-08-31).
      if (htmlStr.contains('不存在')) {
        throw Exception('51manga: 该漫画不存在或已被删除 (mangaId=$mangaId)');
      }
      // Otherwise this is real markup whose title we simply failed to find.
      // Reporting THAT as a deletion would tell every user the entire catalogue
      // had been removed the day `h1.name` is renamed, while giving the
      // maintainer no hint to go and look at the selectors.
      throw Exception(
          '51manga: 解析失败：详情页标题选择器可能已失效 (mangaId=$mangaId)');
    }

    // `span.tags_last` is present on every page sampled (25/25) but is usually
    // of no use: 17 of 25 contain NO anchors at all, 7 yield real tag links, and
    // 1 holds the mashed pseudo-tags described below. That is the site's own
    // data, not a selector miss — there is no better tag selector to find.
    //
    // Only ONE `span.tags_last` exists per page (0 of 25 had more), so the
    // `.diy_tags` half of the class is dropped as redundant. The href filter is
    // NOT redundant and IS covered by a test: pages whose tags were never split
    // into real tag links carry `href="/category/"` anchors holding several tag
    // names concatenated with no separator of any kind (e.g.
    // 「热血玄幻古风魔幻魔法」 on r368n70WNX). Those are unsplittable without a
    // segmentation dictionary, so they are dropped rather than surfaced as one
    // nonsense chip — which would additionally hand [_statusFromTags] a single
    // string able to contain BOTH 完结 and 连载, the one case its ordering note
    // assumes cannot arise.
    final tags = <String>[];
    for (final a in document
        .querySelectorAll('span.tags_last a[href^="/category/tags/"]')) {
      final text = _cleanText(a.text);
      if (text != null) tags.add(text);
    }

    final zuixin = document.querySelector('div.zuixin');
    // Reads 「最新话：<name>」; strip the label. Chapterless entries say
    // 「最新话：待浏览」, which is passed through as the site's own wording.
    // The ASCII `:` alternative is an unobserved defensive branch: live pages
    // use the full-width `：` exclusively (25/25, verified live 2026-08-31). It
    // is disclosed rather than removed, matching how the `data-src` and nbsp
    // branches below are handled.
    final latestChapter = _cleanText(zuixin?.querySelector('p')?.text)
        ?.replaceFirst(RegExp(r'^最新话[:：]\s*'), '');

    // The whole chapter list ships with this page, which is why
    // prepareChapterListFetch returns null.
    // Ascending (earliest first): on all 16 chapter-bearing pages sampled the
    // final row equals div.zuixin's 最新话, at up to 1835 rows (verified live
    // 2026-08-31 — a floor that keeps rising, not a bound). Emitted in document
    // order, so callers get that same order; reader_bloc.dart depends on
    // ascending for next/previous chapter navigation.
    final chapters = <ChapterItem>[];
    for (final a in document.querySelectorAll('ul.chapter-list li a')) {
      // Match the parsed PATH, anchored — same contract as [_mangaIdPattern],
      // for the same reasons. Uri.tryParse never throws: it returns null on a
      // malformed href, and for `javascript:void(0);` yields the path
      // `void(0);`, which the anchor rejects. 6271 of 6271 live chapter hrefs
      // sampled match this exactly (verified 2026-08-31).
      final path = Uri.tryParse(a.attributes['href'] ?? '')?.path ?? '';
      final chapterId = _chapterIdPattern.firstMatch(path)?.group(1);
      if (chapterId == null) continue;
      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: _cleanText(a.text) ?? chapterId,
        href: '$_pcBaseUrl/show/$chapterId.html',
      ));
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: _extractCoverUrl(document) ?? '',
      description: _extractDescription(document),
      author: _cleanText(document.querySelector('div.comic_hot')?.text) ?? '',
      tags: tags,
      status: _statusFromTags(tags),
      latestChapter:
          (latestChapter != null && latestChapter.isEmpty) ? null : latestChapter,
      updateTime: _cleanText(zuixin?.querySelector('time')?.text),
      chapters: chapters,
      // The cover CDN 403s without the Referer.
      headers: _imageHeaders,
    );
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

  // --- Private helpers ---

  /// A listing card's manga id, matched against the href's PATH rather than the
  /// raw href, and anchored at both ends. Both properties are load-bearing:
  ///  * unanchored, a wrapper/tracking href like `/go?url=/mh/spam` would yield
  ///    an id out of a query string;
  ///  * without the `$`, `/mh/abc_123` would silently TRUNCATE to `abc` — a
  ///    plausible-looking card that 404s on tap, with nothing in the logs.
  ///    Skipping is strictly better than a wrong id.
  /// Every live id sampled is exactly 10 chars of `[A-Za-z0-9]` — no `_`, no
  /// `-` (120/120 across 4 listing routes, verified live 2026-08-31). The `+`
  /// quantifier deliberately accepts more than that: over-accepting an id is
  /// safe, whereas a length rule would drop real cards the day the site widens.
  static final RegExp _mangaIdPattern = RegExp(r'^/mh/([A-Za-z0-9]+)$');

  /// A chapter row's id. Deliberately the same shape as [_mangaIdPattern] —
  /// matched against the href's PATH, anchored at both ends — because the same
  /// two failure modes apply. Measured against the unanchored-on-raw-href form:
  /// `/show/abc_123.html` TRUNCATES to `abc` (a plausible id that 404s on tap,
  /// silently) and `/go?to=/show/spam1.html` mines `spam1` out of a query
  /// string. Both become a clean skip here, which is the safer loss.
  ///
  /// Every live chapter href sampled is exactly `/show/<10 alnum>.html`
  /// (6271/6271 across 16 chapter-bearing pages, and the captured id is 10 chars
  /// on all 25 pages, verified live 2026-08-31); the `+` quantifier
  /// over-accepts on purpose, since a length rule would start dropping real
  /// chapters the day the site widens its ids. The trailing `\.html` is NOT
  /// over-accepted: every one of those 6271 hrefs carries the suffix.
  ///
  /// Pinned by the `chapter id must be the whole path` test, which is the
  /// sibling of the `manga id must be the whole path` table.
  static final RegExp _chapterIdPattern =
      RegExp(r'^/show/([A-Za-z0-9]+)\.html$');

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  /// Parse `.comic-item` cards, shared by /category and /search.
  ///
  /// `div.mask` is intentionally not read. On listing routes it is a status
  /// badge (完结 / 已完结 / 连载 / 连载中), but on the homepage the same selector
  /// holds a chapter name, so it is NOT a site-wide status selector.
  /// [MangaSummary] has no status field regardless; status is surfaced only on
  /// the detail page.
  ///
  /// Cover URLs are emitted verbatim. Every listing cover sampled is absolute
  /// (120/120, zero relative or protocol-relative, verified live 2026-08-31), so
  /// the base-URL join is consciously omitted rather than overlooked — note the
  /// failure would be silent, as a protocol-relative (`//host/x.jpg`) or
  /// root-relative (`/static/y.jpg`) cover would pass through and merely render
  /// broken.
  ///
  /// The query is deliberately NOT scoped to `#comic-list`. That id is present
  /// on every listing route today, but scoping to it would turn any container
  /// rename into a silently EMPTY discovery screen. The `title.isEmpty` guard
  /// below already discards foreign `.comic-item` shapes — notably the detail
  /// page's "related" strip, which uses `a.pic > img` and puts its title in
  /// `<b><a>` — so an unscoped query degrades to a few dropped cards instead of
  /// a blank page.
  List<MangaSummary> _parseCards(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    for (final item in document.querySelectorAll('div.comic-item')) {
      final href = item.querySelector('a')?.attributes['href'] ?? '';
      // Uri.path strips any origin, so an absolute href resolves too.
      final path = Uri.tryParse(href)?.path ?? '';
      final mangaId = _mangaIdPattern.firstMatch(path)?.group(1);
      // Defensive: skip anything in the grid that is not a /mh/ manga link.
      // (As of this writing every card on /category and /search is one — 120 of
      // 120 sampled, verified live 2026-08-31; this guard exists so a template
      // change degrades to fewer cards, not wrong ids.)
      if (mangaId == null) continue;

      final img = item.querySelector('div.pic img');
      // `data-src` is checked first purely as cheap defense: no live page emits
      // it and no lazy-load library is referenced anywhere on the site — covers
      // ship in plain `src`. For coverless entries the site serves its own
      // absolute `packs/mccms/empty.png`, which is passed through as-is: it is a
      // real graphic, and blanking it would make "no cover" indistinguishable
      // from "parse failed".
      final cover =
          img?.attributes['data-src'] ?? img?.attributes['src'] ?? '';

      final title = _cleanText(item.querySelector('h3.title')?.text) ??
          _cleanText(img?.attributes['alt']) ??
          '';
      // A titleless card would render as a blank, unlabelled tile and would
      // collide with every other empty title in cross-source dedup, so drop it.
      if (title.isEmpty) continue;

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: cover,
        latestChapter:
            _cleanText(item.querySelector('div.field-info .txt')?.text),
        headers: _imageHeaders,
      ));
    }

    return results;
  }

  /// Trim and collapse internal whitespace; returns null when nothing is left.
  ///
  /// No explicit nbsp/entity handling is needed, for two independent reasons:
  /// `\s` already covers U+00A0 and U+3000 anyway, and no U+00A0 (literal or
  /// `&nbsp;`) or U+3000 occurs on any sampled listing, detail or home page
  /// (verified live 2026-08-31). An earlier `replaceAll('\u00a0', ' ')` here was
  /// therefore dead code twice over and was removed; do not re-add it. A test
  /// feeds a synthetic U+00A0 to pin the `\s` semantics — that fixture is not
  /// evidence the site emits one.
  static String? _cleanText(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(_whitespacePattern, ' ').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static final RegExp _coverUrlPattern =
      RegExp(r'''background-image:\s*url\(\s*['"]?(.*?)['"]?\s*\)''');

  /// The detail cover is an inline style, not an `<img>`:
  /// `style="background-image: url('...'); display: block;"`.
  ///
  /// The URL is emitted verbatim. Every cover sampled is absolute, but the host
  /// and path both vary widely — `img1.baipiaoguai.org/static/upload{,2,3}/`,
  /// `cover1.baozimh.org/cover/kuaikan/`, `s2.325784.xyz/<base64>/`, and the
  /// site's own `www.51manga.com/packs/mccms/` placeholder all occur across the
  /// 25 pages sampled (verified live 2026-08-31) — so nothing here may assume a
  /// fixed CDN path.
  ///
  /// Returns null when no cover is found. The `url.isEmpty` half of that guard
  /// is not observable through [parseMangaInfo], whose `?? ''` collapses null
  /// and `''` into the same value — so do not go looking for a test that
  /// distinguishes them. The nullable return is kept because it is the honest
  /// contract for a lookup that can miss.
  static String? _extractCoverUrl(Document document) {
    final style =
        document.querySelector('div.comic_cover')?.attributes['style'] ?? '';
    final url = _coverUrlPattern.firstMatch(style)?.group(1);
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// `div.metas-desc` opens with a `div.download-app` advert whose own `<p>`
  /// reads 「下载APP，免费看更多精彩漫画」, on every page sampled (25/25, verified
  /// live 2026-08-31).
  ///
  /// **Excluding that subtree is the load-bearing guard**, and the only one a
  /// test pins. It is sufficient on its own, because it drops the advert
  /// regardless of which surviving paragraph is then picked. Delete it and the
  /// advert becomes the description of every blurb-less manga.
  ///
  /// `.last` is unpinned belt-and-braces, retained only against the site one day
  /// adding a leading non-advert `<p>`. There is NO live evidence of such a
  /// paragraph: `div.metas-desc` holds exactly 2 (advert + blurb) on 25/25
  /// pages, so `.last` and `.first` yield byte-identical output on every page
  /// sampled. Do NOT mistake `.last` for the thing that defeats the advert — an
  /// earlier version of this comment did, which would have led a maintainer to
  /// delete the exclusion as the "redundant" half.
  ///
  /// The exclusion is non-destructive on purpose. It previously called
  /// `ad.remove()`, which mutated the caller's [Document] and made correctness
  /// depend on an invisible ordering constraint (cover and chapters had to be
  /// read first).
  static String? _extractDescription(Document document) {
    final container = document.querySelector('div.metas-desc');
    if (container == null) return null;
    final paragraphs = container
        .querySelectorAll('p')
        .where((p) => !_isAdvertParagraph(p, container))
        .toList();
    if (paragraphs.isEmpty) return null;
    return _cleanText(paragraphs.last.text);
  }

  /// Whether [p] sits inside a `.download-app` advert. The walk stops at
  /// [container] so that a `.download-app` ancestor somewhere ABOVE
  /// `div.metas-desc` could not blank out every paragraph on the page.
  static bool _isAdvertParagraph(Element p, Element container) {
    for (Element? e = p; e != null && e != container; e = e.parent) {
      if (e.classes.contains('download-app')) return true;
    }
    return false;
  }

  /// The mobile detail page carries no status field, so status is inferred from
  /// the tag texts. Be aware this almost always yields [MangaStatus.unknown]:
  /// exactly one of the 25 pages sampled carried a status-bearing tag. A second,
  /// independent sample of comparable size also found exactly one — a different
  /// page, carrying the OTHER branch — so both `完结` and `连载` do occur live,
  /// but at roughly one page in twenty-five either way. Do not read a particular
  /// tag id or value into this; neither sample is evidence of a specific case.
  ///
  /// That is a genuine ceiling rather than a weak selector: the substring
  /// `完结` occurs ANYWHERE in the raw HTML of only 3 of those 25 pages, and
  /// `连载` in 2 (verified live 2026-08-31; sample-specific, so treat these as
  /// an order of magnitude rather than a rate). `div.mask` is emphatically not a
  /// better signal — it is present and EMPTY on all 25.
  ///
  /// The `完结`-before-`连载` order is arbitrary and untested — no sampled tag
  /// contains both substrings, so no evidence says which should win. Do not
  /// read intent into it.
  static MangaStatus _statusFromTags(List<String> tags) {
    for (final tag in tags) {
      if (tag.contains('完结')) return MangaStatus.completed;
      if (tag.contains('连载')) return MangaStatus.ongoing;
    }
    return MangaStatus.unknown;
  }
}
