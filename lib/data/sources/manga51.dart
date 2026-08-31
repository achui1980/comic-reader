import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/utils/crypto_utils.dart';
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

  /// Single source of truth for the Referer sent with page requests
  /// ([defaultHeaders]) and image requests ([_imageHeaders]). The image CDN
  /// (`img1.baipiaoguai.org`) answers 403 without a Referer, and a page-vs-image
  /// mismatch is a classic silent 403 on anti-hotlink setups, so the two must
  /// stay byte-identical — including the trailing slash.
  ///
  /// As of the [defaultHeaders] fix the two maps are not merely consistent, they
  /// are the SAME map. Keep it that way: an earlier version had `defaultHeaders`
  /// carry only the Referer while `_imageHeaders` carried Referer + UA, and the
  /// asymmetry was undocumented and unintended.
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

  /// Host that `pic-v3.js` prepends to any chapter image path that is not
  /// already absolute. Read only by [_absoluteImageUrl], whose doc explains why
  /// that path is never taken in practice. Note this is also (one of) the cover
  /// hosts — see [_extractCoverUrl], which must NOT assume it.
  static const String _imageCdn = 'https://img1.baipiaoguai.org';

  /// AES key for the chapter image payload. 16 bytes, i.e. AES-128.
  ///
  /// Reverse-engineered out of the site's own
  /// `https://www.51manga.com/template/pc/51manga/js/pic-v3.js` — a 10699-byte
  /// obfuscated CryptoJS bundle. The literal does NOT appear anywhere in that
  /// file (verified 2026-08-31): every string in it, this one included, is
  /// rebuilt at runtime through a `_0x392f(index, seed)` table decoder, so
  /// re-deriving this value means running the deobfuscator, not grepping.
  ///
  /// That makes it simultaneously the value in this file MOST likely to rotate
  /// and the most expensive to recover. If chapters start failing with
  /// 「章节图片解密失败」, suspect this first.
  ///
  /// MUST stay a raw string: it contains `$v`, so an ordinary literal would
  /// parse as an interpolation of `vJnU2ANeSRoF`. Today that happens to be a
  /// compile error (no such name), which is luck rather than protection — the
  /// safety net disappears the moment any identifier by that name exists.
  static const String _picKey = r'9S8$vJnU2ANeSRoF';

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

  /// WEBVIEW ONLY. Nothing on this source's normal request path reads this.
  ///
  /// `FetchPipeline.mergeHeaders` (`fetch_pipeline.dart`) builds every Dio
  /// request from `defaultHeaders` + `config.headers` + `extraHeaders` and never
  /// consults this getter; its only readers are `webview_native.dart` (the
  /// Cloudflare verification WebView) and the `webview_fetcher_*` chain. With
  /// `needsCloudflare == false` and `usesWebViewFetch == false` neither runs here,
  /// so **[defaultHeaders] is what actually transmits the UA** — see below.
  ///
  /// Kept anyway, deliberately. It costs one line, 20 of the 34 sources declare
  /// it, and it becomes live the moment this source needs Cloudflare or
  /// WebView-fetch — at which point the WebView MUST present the same UA as Dio
  /// or the session/cookie pair mismatches. Deleting it would make that future
  /// flip silently fall back to the app-default desktop UA, which is the exact
  /// mirror image of the bug this comment exists to prevent.
  @override
  String? get userAgent => _mobileUa;

  /// The headers the framework actually sends with every page request.
  ///
  /// The UA belongs HERE, not only in [userAgent]. Without it every request goes
  /// out as `Dart/3.x (dart:io)` — which is what happened until this was fixed,
  /// meaning the whole live verification campaign (which always passed the mobile
  /// UA explicitly) ran a configuration the app never reproduced. This site gates
  /// on headers, so that mismatch was the one unforced risk in the source.
  ///
  /// Deliberately the very same map as [_imageHeaders]: pages and images must
  /// present an identical Referer/UA pair on an anti-hotlink setup. 24 of the 34
  /// sources put the UA in `defaultHeaders`; the mobile-host siblings
  /// (`manhuagui_mobile.dart`, `ikan_manhua.dart`, `baozi_manga.dart`) all do.
  @override
  Map<String, String>? get defaultHeaders => _imageHeaders;

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
          // PROVENANCE: these 29 ids come from PC `/category` recon, not from the
          // mobile host this source otherwise uses. Only 867-877 are advertised
          // anywhere in the mobile UI, and 10 of those 11 are declared (873 is
          // dropped as a duplicate label), so **19 of the 29 are UNVERIFIED** —
          // never confirmed to return results. They cannot be verified from here
          // now either; see [_chapterIdPattern] on the 403.
          //
          // Kept rather than trimmed to 11, because a dead id degrades gently and
          // the precedent says the backend honours more than the mobile UI shows:
          // `order` is not advertised on the mobile page AT ALL, yet
          // `order=addtime` demonstrably returns a different first item than
          // `order=hits`. Trimming to only the advertised ids would throw away
          // most of the filter for a risk the site itself contradicts.
          //
          // A dead id degrades to: HTTP 200 with an empty grid -> parseDiscovery
          // returns [] -> discovery_cubit emits `status: loaded, manga: [],
          // hasMore: false` -> discovery_screen has no empty-state widget, so the
          // user sees a blank grid and no error. Not good, but already the
          // accepted outcome for multi-filter combinations, since the site's own
          // filter links REPLACE rather than combine segments.
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
    // FIRST, before every other branch. The origin's block page has no title
    // element of either kind, so letting it reach the checks below would report a
    // template change (「详情页标题选择器可能已失效」) for what is an upstream IP
    // block — a wrong cause, printed verbatim on the user's screen by
    // detail_cubit.dart. That is the same misdiagnosis the 不存在-vs-selector
    // split exists to prevent, arriving from one layer further out.
    _assertNotOriginBlock(htmlStr, 'mangaId=$mangaId');
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
      // (verified live 2026-08-31). That 24 is NOT a typo for the 25 used
      // elsewhere in this file: 24 counts ids tapped from a listing, of which
      // this 1 was the stub, leaving the 25-page detail samples cited below —
      // two different measurements that happen to sit one apart.
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
    final zuixinText = _cleanText(zuixin?.querySelector('p')?.text);
    // Cleaned TWICE on purpose, and in this order. The first call trims, so the
    // `^` anchor can reach 最新话 even when the markup indents it; stripping the
    // label can then leave nothing at all (a bare 最新话：), and the second call
    // is what turns that back into null instead of ''. Folding this into one
    // `_cleanText(raw?.replaceFirst(...))` looks tidier but silently breaks the
    // anchor on untrimmed input.
    final latestChapter =
        _cleanText(zuixinText?.replaceFirst(RegExp(r'^最新话[:：]\s*'), ''));

    // The whole chapter list ships with this page, which is why
    // prepareChapterListFetch returns null. Emitted in document order, so callers
    // get the site's own order; reader_bloc.dart depends on ascending (earliest
    // first) for next/previous chapter navigation.
    //
    // HONEST STATE OF THAT INVARIANT: ascending order was confirmed by checking
    // that the final row equals div.zuixin's 最新话 on the 16 chapter-bearing
    // pages of an EARLIER sample (2026-08-31). A later, larger sample from a
    // different id set found 17 chapter-bearing pages, and the equality check was
    // NOT re-run on it. So "16" and "17" are two samples, not one sample with a
    // failure in it — but equally, no single measurement covers all 17, and the
    // site is now returning 403 to our egress IP on every cache MISS (openresty,
    // 159-byte body, exactly correlated with `x-cache: BYPASS`; `HIT`s still
    // return 200; still in force at the time of writing), so this cannot be
    // closed from here. Treat ascending order as well-supported but not fully
    // verified, and do not restate it as "all pages".
    final rows = document.querySelectorAll('ul.chapter-list li a');
    final chapters = <ChapterItem>[];
    for (final a in rows) {
      // Match the parsed PATH, anchored — same contract as [_mangaIdPattern],
      // for the same reasons. Uri.tryParse never throws: it returns null on a
      // malformed href, and for `javascript:void(0);` yields the path
      // `void(0);`, which the anchor rejects. Every live chapter href sampled
      // matched — see [_chapterIdPattern].
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

    // Rows present but NONE recognised can only mean the href shape changed —
    // [_chapterIdPattern] requires a trailing `.html` and rejects `-`/`_`, which
    // its own doc calls out as deliberately the brittlest regex in this file. So
    // dropping `.html`, moving to `/read/`, or widening the id charset silently
    // empties every chapter list.
    //
    // Without this guard that is INDISTINGUISHABLE from the 8-9 of 25 sampled
    // pages that legitimately have no chapters: detail_cubit.loadChapters would
    // emit `chaptersLoading: false` with no error and nothing logged. That is the
    // exact conflation parseChapter's 章节图片列表格式异常 guard exists to prevent,
    // and this method was written before it — hence the divergence.
    //
    // Zero rows is NOT this case and must stay silent: it is the site's own
    // chapterless state, the same way `"images":[]` is. Both directions are
    // pinned by tests.
    //
    // Leak invariant, as at every other throw site: only [mangaId] and a count.
    // Never a row's href or text, which are site markup.
    if (rows.isNotEmpty && chapters.isEmpty) {
      throw Exception(
          '51manga: 章节链接格式异常 (mangaId=$mangaId): ${rows.length} 行全部无法识别');
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: _extractCoverUrl(document) ?? '',
      description: _extractDescription(document),
      // `div.comic_hot` as the author is the one selector here with no measured
      // fact behind it, and the least self-evident — a div named "hot" read as an
      // author. It came from the implementation plan and was never verified, and
      // it can no longer be: the site now 403s our egress IP on every cache MISS
      // (see the chapter-order note above), and no detail-page artifact was kept.
      // Treat it as UNMEASURED. If it is wrong the failure is quiet — a wrong or
      // empty author line, never an exception.
      //
      // It also depends on something unpinned: `.text` includes ALL descendant
      // text, and the live markup is
      // `<div class="comic_hot"><i class="iconfont icon-myfill"></i>作者名</div>`.
      // That works only because the `<i>` icon is empty. Give it a text label and
      // the label lands in the author string. The fixture reproduces the empty
      // `<i>`, so no test would catch that either.
      author: _cleanText(document.querySelector('div.comic_hot')?.text) ?? '',
      tags: tags,
      status: _statusFromTags(tags),
      latestChapter: latestChapter,
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

  /// `div#pic-list` on the chapter page is an EMPTY container — there is no
  /// markup to scrape. The real image list is an AES-encrypted blob in an inline
  /// `<script>` just after `</main>`, which [_picKey] decrypts to JSON.
  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    // Before the payload scrape. The block page carries no `params`, so otherwise
    // it reports 「未找到章节图片数据」 — a message whose own comment carefully
    // rules out every cause it knows of, and which would now be quietly wrong
    // about a cause it cannot see.
    _assertNotOriginBlock(htmlStr, 'chapterId=$chapterId');

    final payload = _paramsPattern.firstMatch(htmlStr)?.group(1);
    // The `isEmpty` half is unreachable, not merely unobserved: [_paramsPattern]
    // captures `[^']+`, so a match can never be empty. It is kept only as the
    // honest shape of a "did we get a usable blob" check — do not go looking for
    // a test that distinguishes it, exactly as with [_extractCoverUrl]'s
    // `url.isEmpty`.
    if (payload == null || payload.isEmpty) {
      // Deliberately NEUTRAL wording: it names no cause, because no live cause
      // is known. This is the opposite call to the one parseMangaInfo makes, and
      // for the opposite reason — there, two causes were both observable and had
      // to be told apart; here every candidate cause has been ruled out:
      //  * an image-less chapter is NOT this branch. It ships `params` normally,
      //    carrying `"images":[]` (1 of 18 live chapter pages sampled did
      //    exactly that, verified 2026-08-31), and is handled below as zero
      //    images. A test pins that.
      //  * an unknown chapter id is NOT this branch either: `/show/<bogus>.html`
      //    answers HTTP 404 (redirected to /err/404, a 1556-byte generic page),
      //    so HttpClient rejects it before any of this runs.
      // What is left is a template change, but asserting that would be a guess,
      // and a guess printed verbatim to the user — reader_bloc surfaces this
      // message as-is. So: state the symptom, not a theory.
      throw Exception('51manga: 未找到章节图片数据 (chapterId=$chapterId)');
    }

    // The try covers decryption and JSON parsing ONLY. The shape check below is
    // deliberately outside it: inside, its throw would be caught here and
    // re-reported as a decryption failure, which is a different fault with a
    // different fix.
    final Object? decoded;
    try {
      decoded = json.decode(aesDecryptBase64PrefixedIv(payload, _picKey));
    } catch (e) {
      // Surface a key rotation / corrupt blob loudly rather than showing an
      // empty chapter. 解密失败 is what distinguishes this from the throw above;
      // both interpolate chapterId, so the phrase is the only discriminator and
      // a test depends on it.
      //
      // `e.runtimeType` and NOT `$e`, holding the same line as
      // [_payloadShapeExcerpt]: nothing derived from payload or plaintext content
      // may reach this string, because reader_bloc prints it verbatim.
      //
      // Raw `$e` breaks that. Measured against this call site, 2026-08-31:
      //  * json.decode's FormatException quotes up to 78 characters of DECRYPTED
      //    PLAINTEXT — in production that is a complete image URL. This is the
      //    serious one, and a test reproduces it with a sentinel.
      //  * base64.decode's FormatException (79 chars) quotes a window of the
      //    base64 payload.
      //  * the `ArgumentError.value(payload, ...)` length guard (138 chars)
      //    quotes the payload in full — though only ever a short one, since it
      //    fires only when the blob decodes to <= 16 bytes, i.e. at most ~24
      //    base64 characters. It CANNOT emit a wall of base64: a full-size blob
      //    never reaches that guard.
      //  * a wrong key on a full-size blob is `Invalid or corrupted pad block`
      //    (51 chars) and leaks nothing — so the leak is worst exactly where the
      //    key still WORKS and the format changed.
      //
      // A type name is a compile-time constant, so this is a structural guarantee
      // rather than a bet on some future toString() staying short — and it keeps
      // the signal that actually drives the diagnosis: ArgumentError means bad
      // key/padding/length, FormatException means it decrypted to something that
      // is not JSON. `payload.length` is a count, not content, and restores the
      // one thing the type alone loses: whether we received a plausibly-sized
      // blob at all. What is given up is FormatException's character offset,
      // which is both the least actionable field and the one sitting directly
      // against the leak.
      throw Exception('51manga: 章节图片解密失败 (chapterId=$chapterId): '
          '${e.runtimeType}, payload ${payload.length} 字符');
    }

    // `host`, `source_id`, `comic_id`, `comic_down` and `lazy` are the other five
    // keys (identical key set on 18 of 18 live payloads, verified 2026-08-31) and
    // all are ignored on purpose: `host` only exists so the site's own JS can
    // refuse to render a payload cross-domain, and the rest drive its
    // lazy-loading UI. There are no prev/next keys, which is why
    // [ChapterResult.canLoadMore] below is a constant.
    final Object? imagesValue = decoded is Map ? decoded['images'] : null;
    if (imagesValue is! List) {
      // A missing or non-list `images` can ONLY mean the payload shape changed.
      // It is not the site's legitimate image-less chapter: that ships
      // `"images":[]` — a real, empty List — which passes this guard and is
      // handled below as zero images (pinned by its own test). Returning empty
      // here instead would make a template break indistinguishable from that
      // state, the same conflation the two throws above exist to avoid.
      //
      // Symptom, not theory: it reports WHAT was found, not why. The shape
      // excerpt is bounded — see [_payloadShapeExcerpt].
      throw Exception('51manga: 章节图片列表格式异常 (chapterId=$chapterId): '
          'images=${imagesValue.runtimeType}, ${_payloadShapeExcerpt(decoded)}');
    }
    final List<dynamic> rawImages = imagesValue;

    final images = <ChapterImage>[];
    for (final raw in rawImages) {
      // Unobserved defensive skip: all 821 image entries sampled are non-empty
      // Strings (0 non-String, 0 empty, across 18 chapter pages from 12 manga,
      // verified live 2026-08-31). Kept so one malformed entry costs one page
      // instead of the whole chapter.
      if (raw is! String || raw.isEmpty) continue;
      images.add(ChapterImage(
        // The CDN answers 403 with no Referer and 200 with ours — measured
        // directly against a live payload URL, 2026-08-31.
        url: _absoluteImageUrl(raw),
        headers: _imageHeaders,
      ));
    }

    final document = html_parser.parse(htmlStr);
    // Exactly one non-empty `header .title h2` on 18 of 18 live chapter pages
    // (verified 2026-08-31), holding e.g. 第01话. The `?? chapterId` fallback is
    // therefore unobserved, and exists so a renamed selector yields an ugly
    // heading rather than a blank one.
    final title =
        _cleanText(document.querySelector('header .title h2')?.text) ??
            chapterId;

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
      ),
      // No in-chapter pagination: the payload holds every page of the chapter at
      // once (up to 215 images in one payload among those sampled, from a
      // 23104-character base64 blob for a 152-image chapter — do not assume this
      // blob is small) and carries no prev/next cursor.
      canLoadMore: false,
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    // PC layout reads better in a real browser.
    return '$_pcBaseUrl/show/$chapterId.html';
  }

  // --- Private helpers ---

  /// The origin's block page, identified by nginx/openresty's `server_tokens`
  /// footer: `<hr><center>openresty/1.27.1.2</center>`.
  ///
  /// The block page verbatim (fetched 2026-08-31 from `/mh/YyZJyLgV6q`,
  /// `/mh/4aNek4246W` and `/show/Vd3Q3uKzVB.html` — all three byte-identical,
  /// sha256 `3ceb7483…ba6c`, 159 bytes, CRLF):
  ///
  /// ```html
  /// <html>
  /// <head><title>403 Forbidden</title></head>
  /// <body>
  /// <center><h1>403 Forbidden</h1></center>
  /// <hr><center>openresty/1.27.1.2</center>
  /// </body>
  /// </html>
  /// ```
  ///
  /// **Why not the substring `403`.** Because it false-positives on real content,
  /// measured rather than imagined: `403` occurs 3 times in one live listing page
  /// (`/category/order/hits/page/2`, 35892 bytes, 2026-08-31) — inside cover URLs
  /// for book ids 7403, 44032 and 134403. A title or chapter name could do the
  /// same at any time.
  ///
  /// **Why this cannot false-positive.** It requires the DEPRECATED `<center>`
  /// tag immediately followed by a web-server name. Across every real artifact
  /// sampled — 2 chapter pages, 2 listing pages, the site's own `/err/404` body
  /// and `pic-v3.js`, 145850 bytes total, 2026-08-31 — `<center>` occurs 0 times,
  /// `openresty` 0 times and `nginx` 0 times. The site's templates simply do not
  /// emit that tag, and manga metadata cannot place a server name directly inside
  /// one. Both halves would have to appear, adjacent, for a false positive.
  ///
  /// The version suffix is deliberately not matched, so `server_tokens off`
  /// (`<center>openresty</center>`) still trips it. `nginx` is included because
  /// openresty IS nginx and the footer changes with configuration.
  ///
  /// KNOWN FALSE NEGATIVE, accepted: a block page WITHOUT this footer (a custom
  /// error page, or a different intermediary) is not detected and falls through to
  /// the old, wrong message. That is today's behaviour, so no regression — and the
  /// bias is deliberate, since a false positive would tell a user with a perfectly
  /// good connection that their IP is banned.
  static final RegExp _originBlockPattern =
      RegExp(r'<center>\s*(?:openresty|nginx)', caseSensitive: false);

  /// Throws if [htmlStr] is the origin's block page rather than site content.
  ///
  /// Must be called BEFORE any selector-based branch in every entry point that
  /// parses a page body, because the block page satisfies none of the site's
  /// selectors and would otherwise be misreported as a template change or as
  /// missing data. [context] is an id or a route label for diagnosability.
  ///
  /// Two live facts make this necessary rather than defensive:
  ///  * A CDN cache **HIT** serves real content with HTTP 200 even from a banned
  ///    egress, while a **MISS** serves this page — so the same session sees both,
  ///    and a source cannot infer the state from one response.
  ///    Measured 2026-08-31: `/show/X3QXKiznL5.html` → 200, 27394 bytes,
  ///    `x-cache: HIT, policy, disk`; `/mh/4aNek4246W` → 159 bytes,
  ///    `x-cache: BYPASS, Status: 403`.
  ///  * The block page sometimes arrives with an HTTP **200** status line, with
  ///    the real code visible only inside `x-cache: BYPASS, Status: 403`. Dio then
  ///    raises nothing and hands the body straight to us, which is precisely why
  ///    this has to be a BODY check and cannot be left to `http_client.dart`.
  ///    UNMEASURED BY THIS AUTHOR: every probe from this egress
  ///    (2026-08-31) returned a genuine `403` status line, so Dio would have
  ///    thrown first. The 200-with-403-body form is a SECOND SAMPLE, reported
  ///    2026-08-31 from egress IP 38.246.228.36, corroborated by a user runtime
  ///    log showing the genuine-403 form as well. Both forms are therefore
  ///    believed to occur; only the genuine-403 form was reproduced here.
  static void _assertNotOriginBlock(String htmlStr, String context) {
    if (!_originBlockPattern.hasMatch(htmlStr)) return;
    // Names the real cause and explicitly disclaims the one a reader would
    // otherwise assume. Avoids the token 解析失败 on purpose, so it stays
    // substring-disjoint from 「解析失败：详情页标题选择器可能已失效」.
    //
    // Leak invariant, as at every other throw site: only our own literals plus
    // [context], which is an id or a route label. Never any part of the body.
    throw Exception('51manga: 源站拒绝了请求：IP 可能被限流或封禁'
        '（openresty 403 拦截页，不是页面结构变化）($context)');
  }

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
  /// Every live chapter href sampled was exactly `/show/<10 alnum>.html`: all of
  /// them matched, and every captured id was 10 characters, across the
  /// chapter-bearing pages of a 25-detail-page sample (measured 2026-08-31).
  ///
  /// **No absolute total is cited, on purpose.** This slot has now held three
  /// different totals (6271, then 4436, then 2145) and every one of them provoked
  /// a contradiction, because a per-sample href total is meaningless next to any
  /// other sample's: one manga with 1800+ chapters moves it by more than an
  /// entire 25-page sample. The claims that survive comparison are the RATIO
  /// (all matched, none skipped) and the ID WIDTH (10). Those are what this regex
  /// rests on; a fourth number would only restart the cycle.
  ///
  /// It also cannot be re-derived from here: the site answers 403 to our egress
  /// IP on every cache MISS (openresty, 159 bytes, exact correlation with
  /// `x-cache: BYPASS`, while `HIT`s still return 200 — IP-scoped, not UA- or
  /// TLS-scoped). Anyone re-measuring needs a different egress.
  ///
  /// The `+` quantifier over-accepts on purpose, since a length rule would start
  /// dropping real chapters the day the site widens its ids. The trailing `\.html`
  /// is NOT over-accepted — every sampled href carried it — which makes this the
  /// most brittle regex in the file, and is why [parseMangaInfo] now throws
  /// 章节链接格式异常 when rows exist but none of them match.
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
    // Quieter than the detail page but no less wrong: without this a blocked
    // response yields zero cards, and discovery_cubit emits
    // `status: loaded, manga: []`. discovery_screen has no empty-state widget, so
    // the user gets a blank grid and no hint that anything failed.
    _assertNotOriginBlock(htmlStr, 'listing');
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
  /// **Excluding that subtree is treated as the load-bearing guard**, and it is
  /// the only one a test pins. Be clear that this ranking is a JUDGEMENT CALL, not
  /// a measurement: on observed data NEITHER half is load-bearing, because
  /// `div.metas-desc` holds exactly 2 paragraphs (advert + blurb) on 25/25 pages,
  /// so exclusion-plus-`.last` and `.first`-alone give byte-identical output on
  /// every page sampled. The ranking rests on which HYPOTHETICAL page each half
  /// defends against, and the exclusion wins that argument only because a
  /// blurb-less manga (where the advert would become the description) seems far
  /// likelier than a page gaining a leading non-advert paragraph. No sampled page
  /// is either.
  ///
  /// `.last` is unpinned belt-and-braces, retained only against the site one day
  /// adding a leading non-advert `<p>`. Do NOT mistake `.last` for the thing that
  /// defeats the advert — an earlier version of this comment did, which would have
  /// led a maintainer to delete the exclusion as the "redundant" half.
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

  /// Conservative shape of a JSON key that is safe to echo verbatim: an
  /// identifier, nothing else. A URL cannot match it — `://` alone disqualifies —
  /// which is the whole point. See [_payloadShapeExcerpt].
  static final RegExp _plainKeyPattern = RegExp(r'^[A-Za-z0-9_]{1,24}$');

  /// A short, BOUNDED description of a decrypted payload's shape, for the
  /// 「章节图片列表格式异常」 message.
  ///
  /// This string is user-facing — reader_bloc prints the exception verbatim — and
  /// it describes a full chapter payload (17328 plaintext bytes for one 152-image
  /// chapter measured live 2026-08-31). So values are never exposed, and keys are
  /// filtered rather than merely truncated.
  ///
  /// The filter matters because **map keys ARE decrypted plaintext**, and this
  /// branch exists precisely for "the shape changed". A payload shaped
  /// `{"https://img1.…/a.webp": 1}` would otherwise put a real image URL on
  /// screen — a length cap alone would just decide how much of it. So each key is
  /// echoed only if it matches [_plainKeyPattern]; anything else collapses to its
  /// length. That is the same structural-over-volumetric choice made for the
  /// 解密失败 message, and it costs nothing diagnostically: keys are useful here
  /// only when they are short identifiers (`images`, `imgs`, `pics`), which is
  /// exactly what the pattern admits.
  ///
  /// Still bounded belt-and-braces: at most 8 keys and at most 100 characters of
  /// them, with `decoded.length` included so truncation is visible.
  static String _payloadShapeExcerpt(Object? decoded) {
    if (decoded is! Map) return '顶层=${decoded.runtimeType}';
    var keys = decoded.keys.take(8).map((k) {
      final name = '$k';
      return _plainKeyPattern.hasMatch(name) ? name : '<${name.length}字符>';
    }).join(',');
    if (keys.length > 100) keys = '${keys.substring(0, 100)}…';
    return '顶层=Map(${decoded.length}), keys=[$keys]';
  }

  /// The encrypted chapter payload, out of
  /// `var tpl_path = '...', params = '<base64>';`.
  ///
  /// Scraping raw HTML instead of walking `<script>` nodes is safe here rather
  /// than merely convenient, but only because of the lookbehind. What is measured
  /// is that the TOKEN `params` occurs exactly once in the whole chapter document
  /// (1 of 1 on the page grepped in full, and never more than one match across 18
  /// sampled pages, verified live 2026-08-31) — and `(?<![\w$])` is what makes
  /// the regex actually test for that token, rather than for any identifier
  /// merely ENDING in it.
  ///
  /// That distinction is load-bearing, not pedantry. Unanchored, a `tpl_params`
  /// would not just tie with the real assignment, it would WIN, because
  /// `firstMatch` takes the earliest match and the decoy comes first. And the
  /// live page puts `tpl_path` in the very same `var` statement as `params`, so
  /// this is a single template rename away, not a remote hypothetical. A test
  /// pins it with exactly that decoy.
  ///
  /// `[^']+` is greedy but quote-bounded — the negated class, not laziness, is
  /// what stops it at the closing quote. Since the captured blob is base64 it can
  /// contain no `'`, so the capture cannot terminate early either.
  static final RegExp _paramsPattern =
      RegExp(r"""(?<![\w$])params\s*=\s*'([^']+)'""");

  /// Absolutize one image path out of the decrypted payload.
  ///
  /// **Both relative branches are unobserved.** Every live path sampled is
  /// already absolute `https://img1.baipiaoguai.org/...` — 821 of 821 across 18
  /// chapter pages from 12 manga, zero relative, zero protocol-relative, one
  /// single host (verified live 2026-08-31). Only the pass-through arm runs.
  ///
  /// The fallback is kept because `pic-v3.js` has one:
  ///
  /// ```js
  /// if (/^(?!https?:\/\/).*/.test(imgDataSrc)) {
  ///     if (params.source_id == 12) {
  ///         imgDataSrc = 'https://img1.baipiaoguai.org' + imgDataSrc;
  ///     }
  /// }
  /// ```
  ///
  /// Three conscious divergences from that snippet, all confined to the
  /// unobserved path, so none is a live behaviour difference:
  ///  * it concatenates with NO separator, so a bare relative path would give it
  ///    `...baipiaoguai.orgstatic/x.webp`. We insert the `/` instead of
  ///    reproducing a URL that could not possibly load.
  ///  * its `source_id == 12` gate is dropped. All 18 payloads sampled carry
  ///    `source_id: "12"`, so the gate has no observable effect, and a second
  ///    source id would need its own CDN identified before it could be honoured.
  ///  * `startsWith('http')` is looser than `^https?://`: it would also pass
  ///    through a path literally beginning `http`. Accepted as harmless — no
  ///    such path is plausible, and over-accepting here merely emits the URL
  ///    unchanged, whereas the alternative failure prepends a CDN to an absolute
  ///    URL.
  static String _absoluteImageUrl(String raw) {
    if (raw.startsWith('http')) return raw;
    return raw.startsWith('/') ? '$_imageCdn$raw' : '$_imageCdn/$raw';
  }
}
