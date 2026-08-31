import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/utils/crypto_utils.dart';
import 'package:comic_reader/data/sources/manga51.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Base64 of `IV || AES-128-CBC(PKCS7)` produced offline with the real 51manga
/// key `9S8$vJnU2ANeSRoF` and the fixed IV `0123456789abcdef`.
/// Plaintext: `{"ok":true,"msg":"51manga"}`
///
/// Re-verify this vector independently of Dart (`tail -c +17` drops the
/// 16-byte IV prefix so only the ciphertext reaches openssl):
///
/// ```sh
/// echo -n 'MDEyMzQ1Njc4OWFiY2RlZg3jWjN/qoD6bo2MJ85/CU9d6d1jHc/1vHQsEOQqB99M' \
///   | base64 -d | tail -c +17 \
///   | openssl enc -d -aes-128-cbc \
///       -K 39533824764a6e5532414e6553526f46 \
///       -iv 30313233343536373839616263646566
/// # -> {"ok":true,"msg":"51manga"}
/// ```
///
/// `-K`/`-iv` are the hex forms of the UTF-8 key and IV above.
const String kSimplePayload =
    'MDEyMzQ1Njc4OWFiY2RlZg3jWjN/qoD6bo2MJ85/CU9d6d1jHc/1vHQsEOQqB99M';

const String kPicKey = r'9S8$vJnU2ANeSRoF';

/// The origin's block page, BYTE-EXACT as fetched 2026-08-31 from
/// `m.51manga.com/mh/YyZJyLgV6q`, `/mh/4aNek4246W` and `/show/Vd3Q3uKzVB.html`
/// with the source's own mobile UA and PC Referer. All three were identical:
/// 159 bytes, CRLF line endings, sha256
/// `3ceb748352630dacd912caa738f2c52a0f1e34073e5eeb84ac4d545cfb98ba6c`.
/// A test asserts the length, so this cannot be "tidied" into an LF copy.
///
/// This is what 51manga's origin returns on a CDN cache MISS once the egress IP
/// is rate-limited or banned. A cache HIT still returns real content with HTTP
/// 200 from the very same IP, so a single session sees both.
///
/// Note the version suffix on `openresty/1.27.1.2`: an earlier hand-written
/// reproduction of this page rendered the footer as a bare `openresty`, which
/// would have broken any discriminator keyed on the exact string.
const String kOriginBlockHtml = '<html>\r\n'
    '<head><title>403 Forbidden</title></head>\r\n'
    '<body>\r\n'
    '<center><h1>403 Forbidden</h1></center>\r\n'
    '<hr><center>openresty/1.27.1.2</center>\r\n'
    '</body>\r\n'
    '</html>\r\n';

void main() {
  // Fresh instance per test: MangaSource holds mutable auth state
  // (`_extraHeaders`), so later tasks' tests must not inherit it.
  late Manga51 source;

  setUp(() {
    source = Manga51();
  });

  group('aesDecryptBase64PrefixedIv', () {
    test('decrypts a known payload to its known plaintext', () {
      expect(
        aesDecryptBase64PrefixedIv(kSimplePayload, kPicKey),
        '{"ok":true,"msg":"51manga"}',
      );
    });

    test('throws when the payload is 16 bytes or shorter (no ciphertext)', () {
      // 16 bytes: IV only, nothing left to decrypt.
      //
      // The message predicate is essential, not decoration: RangeError and
      // IndexError both EXTEND ArgumentError, so a bare isA<ArgumentError>()
      // would also be satisfied by an accidental out-of-range crash and would
      // still pass if the length guard were deleted outright.
      expect(
        () => aesDecryptBase64PrefixedIv('MDEyMzQ1Njc4OWFiY2RlZg==', kPicKey),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(
              contains('decoded payload is 16 bytes'),
              contains('need more than 16'),
            ),
          ),
        ),
      );
    });

    test('throws a PKCS7 pad-check failure on a wrong key of the correct '
        'length', () {
      // The pad check is the ONLY thing that makes a wrong key throw here.
      // Encrypter.decrypt utf8-decodes with allowMalformed: true, so garbage
      // plaintext would otherwise come back as U+FFFD mojibake, not an error.
      expect(
        () => aesDecryptBase64PrefixedIv(kSimplePayload, 'wrongkey12345678'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('Invalid or corrupted pad block'),
          ),
        ),
      );
    });

    test('throws FormatException when the payload is not valid base64', () {
      // base64.decode (not our guard) rejects this, so the type is
      // FormatException rather than ArgumentError. Matters because Task 5
      // scrapes this payload out of HTML. Note base64.decode IS tolerant of
      // missing '=' padding and of the base64url alphabet, so this fixture
      // uses a character outside both alphabets.
      expect(
        () => aesDecryptBase64PrefixedIv('not!valid!base64', kPicKey),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid character'),
          ),
        ),
      );
    });
  });

  group('Manga51 metadata', () {
    test('identity getters', () {
      expect(source.id, 'manga51');
      expect(source.name, '51漫画');
      expect(source.shortName, '51漫');
      expect(source.score, 4.0);
      expect(source.href, 'https://www.51manga.com');
    });

    test('flags', () {
      expect(source.isAdult, isTrue);
      expect(source.needsProxy, isFalse);
      expect(source.needsCloudflare, isFalse);
      expect(source.disabled, isFalse);
      expect(source.firstPage, 1,
          reason: 'prepareSearchFetch treats page <= 1 as the bare, '
              'page-segment-less URL, which is only correct while the first '
              'page is numbered 1');
    });

    test('sends a mobile UA and a PC-host Referer', () {
      // Assert defaultHeaders, NOT source.userAgent. FetchPipeline.mergeHeaders
      // builds Dio requests from defaultHeaders + config.headers + extraHeaders
      // and never reads the userAgent getter — that getter reaches only the
      // Cloudflare WebView, which this source does not use. An earlier version of
      // this test asserted `source.userAgent` while being NAMED for the
      // behaviour, so it passed for months while every real request went out as
      // `Dart/3.x (dart:io)`. Assert what the framework transmits.
      expect(source.defaultHeaders?['User-Agent'], contains('iPhone'));
      expect(source.defaultHeaders?['Referer'], 'https://www.51manga.com/');
    });

    test('exposes the four discovery filters in order', () {
      expect(
        source.discoveryFilters.map((f) => f.name).toList(),
        ['list', 'tags', 'finish', 'order'],
      );
    });

    test('search takes a keyword only, with no filters', () {
      expect(source.searchFilters, isEmpty,
          reason: 'the site has no search-side filter UI; search is '
              'keyword-only, so prepareSearchFetch ignores its filters arg');
    });

    test('tag filter labels are unique (site duplicates id 872/873 as 恋爱)', () {
      final tags = source.discoveryFilters.firstWhere((f) => f.name == 'tags');
      final labels = tags.choices.map((c) => c.label).toList();
      expect(labels.toSet().length, labels.length,
          reason: 'duplicate labels would render two identical dropdown rows');
      expect(tags.choices.map((c) => c.value), isNot(contains('873')));
    });
  });

  group('Manga51 request builders', () {
    test('prepareDiscoveryFetch with no filters', () {
      expect(
        source.prepareDiscoveryFetch(1, {}).url,
        'https://m.51manga.com/category/page/1',
      );
    });

    test('prepareDiscoveryFetch emits EVERY declared discovery filter', () {
      // Drift guard. prepareDiscoveryFetch iterates a hardcoded segment list
      // that runs parallel to discoveryFilters (deliberately, so the site's
      // required segment order is not tied to the UI dropdown order). Without
      // this test, adding a 5th FilterOption and forgetting the segment list
      // would silently drop it from every discovery URL with all tests green.
      //
      // Derived from discoveryFilters rather than hardcoded, so it keeps
      // working as filters are added and does NOT care about their order.
      final filters = <String, String>{
        for (final option in source.discoveryFilters)
          // The builder skips empty values, and most options offer a "全部"
          // choice whose value is '' — picking that would make this vacuous.
          option.name: option.choices
              .map((c) => c.value)
              .firstWhere((v) => v.isNotEmpty, orElse: () => 'probe'),
      };

      final url = source.prepareDiscoveryFetch(1, filters).url;

      expect(filters, isNotEmpty, reason: 'sanity: filters were derived');
      filters.forEach((name, value) {
        expect(url, contains('/$name/$value'),
            reason: 'prepareDiscoveryFetch dropped the "$name" filter — its '
                'hardcoded segment list is out of sync with discoveryFilters');
      });
    });

    test('prepareDiscoveryFetch emits segments in the site order', () {
      // Deliberately insert the map keys out of order to prove the builder
      // does not depend on map iteration order.
      final config = source.prepareDiscoveryFetch(3, {
        'order': 'hits',
        'finish': '2',
        'list': '1',
        'tags': '889',
      });
      expect(
        config.url,
        'https://m.51manga.com/category/list/1/tags/889/finish/2/order/hits/page/3',
      );
    });

    test('prepareDiscoveryFetch skips empty filter values', () {
      expect(
        source.prepareDiscoveryFetch(2, {'list': '', 'tags': '870', 'order': ''}).url,
        'https://m.51manga.com/category/tags/870/page/2',
      );
    });

    test('prepareSearchFetch page 1 has no trailing page segment', () {
      final url = source.prepareSearchFetch('妹妹', 1, {}).url;
      expect(url, 'https://m.51manga.com/search/%E5%A6%B9%E5%A6%B9');
    });

    test('prepareSearchFetch page 2 uses a bare number, never /page/', () {
      final url = source.prepareSearchFetch('妹妹', 2, {}).url;
      expect(url, 'https://m.51manga.com/search/%E5%A6%B9%E5%A6%B9/2');
      expect(url, isNot(contains('/page/')),
          reason: '/page/N silently returns page 1 on the SEARCH route '
              '(discovery, by contrast, requires /page/N)');
    });

    test('prepareMangaInfoFetch', () {
      expect(
        source.prepareMangaInfoFetch('4aNek4246W').url,
        'https://m.51manga.com/mh/4aNek4246W',
      );
    });

    test('prepareChapterListFetch is null (chapters ship with the info page)', () {
      expect(source.prepareChapterListFetch('4aNek4246W', 1), isNull);
    });

    test('prepareChapterFetch uses the mobile host', () {
      expect(
        source.prepareChapterFetch('4aNek4246W', 'Vd3Q3uKzVB', 1).url,
        'https://m.51manga.com/show/Vd3Q3uKzVB.html',
      );
    });

    test('getChapterWebUrl uses the PC host for in-browser reading', () {
      expect(
        source.getChapterWebUrl('4aNek4246W', 'Vd3Q3uKzVB'),
        'https://www.51manga.com/show/Vd3Q3uKzVB.html',
      );
    });
  });

  group('Manga51 card parsing', () {
    // Mirrors live /category and /search markup. Both routes render the same
    // cards. Covers are in plain `src` (no `data-src` occurs anywhere on the
    // real site), and the second card carries the site's own absolute
    // placeholder, which is what coverless entries actually serve.
    const listHtml = '''
<div id="comic-list">
  <div class="comic-item">
    <a href="/mh/4aNek4246W">
      <div class="pic">
        <img src="https://img1.baipiaoguai.org/static/upload3/book/id/520879/cover_1.jpg?v=1" alt="溯古之黄鹤楼">
        <div class="mask">已完结</div>
      </div>
      <div class="field-info">
        <h3 class="title">溯古之黄鹤楼</h3>
        <div class="txt">最终章 释然</div>
      </div>
    </a>
  </div>
  <div class="comic-item">
    <a href="/mh/r368n70WNX">
      <div class="pic">
        <img src="https://www.51manga.com/packs/mccms/empty.png" alt="魔皇大管家">
        <div class="mask">连载</div>
      </div>
      <div class="field-info">
        <h3 class="title">魔皇大管家</h3>
        <div class="txt">第916话</div>
      </div>
    </a>
  </div>
  <div class="comic-item">
    <a href="/redirect/code/toP0LT"><div class="pic"><img src="x.jpg"></div></a>
  </div>
</div>
''';

    test('parseDiscovery extracts id, title, cover and latest chapter', () {
      final results = source.parseDiscovery(listHtml);
      expect(results, hasLength(2), reason: 'the non-/mh/ card must be skipped');

      expect(results[0].id, '4aNek4246W');
      expect(results[0].sourceId, 'manga51');
      expect(results[0].title, '溯古之黄鹤楼');
      expect(
        results[0].coverUrl,
        'https://img1.baipiaoguai.org/static/upload3/book/id/520879/cover_1.jpg?v=1',
      );
      expect(results[0].latestChapter, '最终章 释然');
    });

    test("passes the site's own empty.png placeholder through unchanged", () {
      // Coverless entries (3 of 30 on /category/page/1) get this absolute URL in
      // plain `src`. It must NOT be normalised to '': it is a real graphic the
      // site designed for this case, and blanking it would substitute the app's
      // error widget and make "no cover" indistinguishable from "parse failed".
      final results = source.parseDiscovery(listHtml);
      expect(results[1].coverUrl, 'https://www.51manga.com/packs/mccms/empty.png');
    });

    test('prefers data-src when present (defensive; live pages use plain src)',
        () {
      // No live 51manga page emits data-src and the site references no
      // lazy-load library, so this branch is speculative armour, not observed
      // behaviour. It lives in its own fixture so listHtml above stays a
      // faithful record of the real markup.
      const lazyHtml = '''
<div class="comic-item">
  <a href="/mh/r368n70WNX">
    <div class="pic">
      <img data-src="https://img1.baipiaoguai.org/lazy.jpg" src="/packs/mccms/empty.png" alt="魔皇大管家">
    </div>
    <div class="field-info"><h3 class="title">魔皇大管家</h3></div>
  </a>
</div>
''';
      final results = source.parseDiscovery(lazyHtml);
      expect(results.single.coverUrl, 'https://img1.baipiaoguai.org/lazy.jpg');
    });

    test('every summary carries the anti-hotlink headers', () {
      for (final s in source.parseDiscovery(listHtml)) {
        expect(s.headers?['Referer'], 'https://www.51manga.com/');
        expect(s.headers?['User-Agent'], contains('iPhone'));
      }
    });

    test('parseSearch uses the same card parser', () {
      final results = source.parseSearch(listHtml);
      expect(results.map((s) => s.id).toList(), ['4aNek4246W', 'r368n70WNX']);
    });

    test('parseDiscovery returns empty on unrelated HTML', () {
      expect(source.parseDiscovery('<html><body>nope</body></html>'), isEmpty);
    });

    test('falls back to img alt for the title and nulls a blank latest chapter',
        () {
      // Covers the two _cleanText paths the fixture above never reaches: the
      // h3.title-missing fallback to `alt`, and the collapse of a
      // whitespace-only .txt to null rather than ''. Both matter because a
      // latestChapter of '' renders as an empty badge in the UI, and a blank
      // title makes the card unidentifiable.
      //
      // The \u00a0 in the alt also pins that Dart's `\s` matches nbsp, which is
      // why _cleanText needs no explicit nbsp handling.
      const html = '''
<div class="comic-item">
  <a href="/mh/Zz9Qq1">
    <div class="pic"><img src="c.jpg" alt="  标题\u00a0 有空格 "></div>
    <div class="field-info"><div class="txt">   </div></div>
  </a>
</div>
''';
      final results = source.parseDiscovery(html);
      expect(results, hasLength(1));
      expect(results[0].title, '标题 有空格');
      expect(results[0].latestChapter, isNull);
    });

    test('skips cards with no usable title', () {
      // Real shape: the /mh/ DETAIL page carries 6 `div.comic-item` cards in a
      // "related" strip whose markup is incompatible — `a.pic > img` instead of
      // `div.pic > img`, title in `<b><a>`, no h3.title, no .field-info. The
      // href IS a valid /mh/ link, so the id guard passes and this parser would
      // otherwise emit summaries with empty title AND empty cover, which
      // manga_card.dart renders as blank unlabelled tiles.
      //
      // This is also why the selector is not scoped to `#comic-list`: the title
      // guard handles the foreign shape without betting discovery on a
      // container id.
      //
      // The `alt` is present because the real markup carries one. That makes
      // the `div.` prefix on the img selector load-bearing and tested: broaden
      // it to `.pic img` and all six related cards are emitted with real titles
      // scraped from `alt`, exactly as they would be off the live page.
      const relatedHtml = '''
<div class="comic-item">
  <a class="pic" href="/mh/rgoqMjdwoY" target="_blank"><img alt="相关漫画" src="r.jpg"></a>
  <b><a href="/mh/rgoqMjdwoY" target="_blank">相关漫画</a></b>
</div>
''';
      expect(source.parseDiscovery(relatedHtml), isEmpty);
    });

    test('manga id must be the whole path, not a substring of it', () {
      // Table of href -> expected id (null = card must be skipped). Documents
      // the id charset contract that Task 4's sibling chapter-id pattern should
      // copy. The truncation cases matter most: a wrong-but-plausible id sends
      // the user to a 404 detail page silently, so skipping is the safer loss.
      const cases = <String, String?>{
        '/mh/4aNek4246W': '4aNek4246W',
        // Uri.path strips the origin, so absolute hrefs resolve too.
        'https://m.51manga.com/mh/abc123': 'abc123',
        // Ids live in the path only; a query string must not smuggle one.
        '/go?url=/mh/spam1&id=9': null,
        '/ad/click?to=/mh/PROMO1': null,
        // Would truncate to 'abc' / 'abc123' if the pattern were unanchored.
        '/mh/abc_123': null,
        '/mh/abc-123': null,
        '/mh/abc123.html': null,
        // No id at all.
        '/mh/': null,
        '/redirect/code/toP0LT': null,
      };

      String cardFor(String href) => '''
<div class="comic-item">
  <a href="$href">
    <div class="pic"><img src="c.jpg" alt="T"></div>
    <div class="field-info"><h3 class="title">T</h3></div>
  </a>
</div>
''';

      cases.forEach((href, expected) {
        final ids = source.parseDiscovery(cardFor(href)).map((s) => s.id);
        expect(ids, expected == null ? isEmpty : [expected],
            reason: 'href $href');
      });
    });
  });

  group('Manga51 detail parsing', () {
    // Mirrors the live m.51manga.com/mh/4aNek4246W markup. Three deliberate
    // deviations from that page, all defensive:
    //  * the `javascript:void(0);` row inside ul.chapter-list. On the live page
    //    the only such href is the `[倒序]` sort toggle, which sits in
    //    div.panel-heading OUTSIDE the list (0 javascript: hrefs occur inside
    //    ul.chapter-list across the 16 chapter-bearing pages sampled).
    //  * only 3 of the page's 12 chapter rows are reproduced.
    //  * the trailing `href="/category/"` tag anchor. That page has only real
    //    `/category/tags/N` links; this row is lifted from r368n70WNX, where the
    //    tags were never split and arrive concatenated. It is here so the href
    //    filter in parseMangaInfo is actually exercised — without it every
    //    fixture anchor conforms and dropping the filter changes nothing.
    // The empty `<div class="mask">` IS faithful: it is present and empty on
    // all 25 live detail pages sampled, which is exactly why div.mask is not a
    // status selector here even though it is one on listing routes.
    const detailHtml = '''
<html><body>
<header><div class="title"><h2>头部标题</h2></div></header>
<div class="comic_cover" style="background-image: url('https://img1.baipiaoguai.org/static/upload3/book/id/520879/cover_1.jpg?v=1786032820'); display: block;"></div>
<div class="mask"></div>
<h1 class="name">溯古之黄鹤楼</h1>
<span class="tags_last diy_tags" style="color: #fff;">
  <a target="_blank" href="/category/tags/1025">已完结</a>
  <a target="_blank" href="/category/tags/2843">国漫</a>
  <a target="_blank" href="/category/tags/2593">古风</a>
  <a target="_blank" href="/category/">热血玄幻古风魔幻魔法</a>
</span>
<div class="comic_hot"><i class="iconfont icon-myfill"></i>剧象漫画</div>
<div class="zuixin">
  <p>最新话：最终章 释然</p>
  <time>2026-08-08 01:26</time>
</div>
<div class="metas-desc">
  <div class="download-app">
    <p>下载APP，免费看更多精彩漫画</p>
    <a href="/redirect/code/toP0LT" target="_blank">立即下载</a>
  </div>
  <p>北宋年间，吕洞宾于黄鹤楼修行之时，点化费祎用橘皮化作的黄鹤。</p>
</div>
<ul class="chapter-list" style="max-height: 100%;">
  <li data-chapter_id="1"><i></i><a href="/show/ARkjkt1m3D.html">预告：2月16日上线</a><span>08-08</span></li>
  <li data-chapter_id="2"><i></i><a href="/show/Vd3Q3uKzVB.html">第1-2话 初遇</a><span>08-08</span></li>
  <li data-chapter_id="3"><i></i><a href="javascript:void(0);">占位</a></li>
</ul>
</body></html>
''';

    test('extracts the scalar fields', () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.id, '4aNek4246W');
      expect(detail.sourceId, 'manga51');
      expect(detail.title, '溯古之黄鹤楼');
      expect(
        detail.coverUrl,
        'https://img1.baipiaoguai.org/static/upload3/book/id/520879/cover_1.jpg?v=1786032820',
      );
      expect(detail.author, '剧象漫画');
      expect(detail.latestChapter, '最终章 释然');
      expect(detail.updateTime, '2026-08-08 01:26');
      expect(detail.headers?['Referer'], 'https://www.51manga.com/');
    });

    test('description comes from metas-desc, not the download-app advert', () {
      // Named for the outcome, not a mechanism. What makes this pass is
      // parseMangaInfo EXCLUDING the .download-app subtree; `.last` alone would
      // also pass here, which is precisely why the old name ("skips the
      // download-app decoy") misattributed the defence.
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.description, startsWith('北宋年间'));
      expect(detail.description, isNot(contains('下载APP')));
    });

    test('extracts tags and infers completed status from them', () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.tags, ['已完结', '国漫', '古风']);
      expect(detail.status, MangaStatus.completed);
    });

    test('drops unsplittable pseudo-tags that are not /category/tags/ links',
        () {
      // 1 of the 25 live pages sampled (r368n70WNX) never had its tags split
      // into real links: they arrive as `href="/category/"` anchors holding
      // several tag names concatenated with NO separator, so they cannot be
      // recovered into individual tags. The href filter drops them.
      //
      // Two things go wrong if that filter is removed: 「热血玄幻古风魔幻魔法」
      // reaches the detail screen as one nonsense chip, and _statusFromTags gets
      // handed a single string that can contain both 完结 and 连载 — the case its
      // ordering note assumes cannot occur.
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.tags, isNot(contains('热血玄幻古风魔幻魔法')));
      expect(detail.tags, hasLength(3),
          reason: 'only the three /category/tags/ anchors are real tags');
    });

    test('infers ongoing status from a 连载 tag', () {
      final html = detailHtml.replaceFirst(
        '<a target="_blank" href="/category/tags/1025">已完结</a>',
        '<a target="_blank" href="/category/tags/1024">连载中</a>',
      );
      expect(source.parseMangaInfo(html, 'x').status, MangaStatus.ongoing);
    });

    test('status is unknown when no tag mentions it', () {
      // This, not the completed/ongoing branches, is the common live outcome:
      // exactly 1 of the 25 pages sampled carries a status-bearing tag.
      const html = '<h1 class="name">T</h1>'
          '<span class="tags_last diy_tags"><a href="/category/tags/1">古风</a></span>';
      expect(source.parseMangaInfo(html, 'x').status, MangaStatus.unknown);
    });

    test('extracts the full ascending chapter list, skipping non-/show/ rows',
        () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.chapters, hasLength(2));

      expect(detail.chapters.first.id, 'ARkjkt1m3D');
      expect(detail.chapters.first.mangaId, '4aNek4246W');
      expect(detail.chapters.first.title, '预告：2月16日上线');
      expect(detail.chapters.first.href,
          'https://www.51manga.com/show/ARkjkt1m3D.html');

      expect(detail.chapters.last.id, 'Vd3Q3uKzVB');
      expect(detail.chapters.last.title, '第1-2话 初遇');
    });

    test('chapter id must be the whole path, not a substring of it', () {
      // Sibling of `manga id must be the whole path, not a substring of it`
      // above — same contract, same failure modes, deliberately the same shape.
      // Table of href -> expected chapter id (null = row must be skipped).
      //
      // The truncation cases matter most: a wrong-but-plausible id sends the
      // user to a 404 reader page silently, so skipping is the safer loss.
      // Without this table nothing distinguishes the anchored pattern from an
      // unanchored one, because the detailHtml fixture's only junk href is
      // `javascript:void(0);`, which both forms reject.
      const cases = <String, String?>{
        '/show/ARkjkt1m3D.html': 'ARkjkt1m3D',
        // Uri.path strips the origin, so absolute hrefs resolve too.
        'https://m.51manga.com/show/abc123.html': 'abc123',
        // Ids live in the path only; a query string must not smuggle one.
        '/go?to=/show/spam1.html': null,
        '/ad/click?to=/show/PROMO1.html': null,
        // Would truncate to 'abc' if the pattern were unanchored.
        '/show/abc_123.html': null,
        '/show/abc-123.html': null,
        // Would yield 'abc123' if the trailing `.html$` anchor were dropped.
        // Every live chapter href sampled carried the suffix — see
        // _chapterIdPattern's doc, and note it deliberately cites no absolute
        // total, because three different ones have each provoked a contradiction.
        // So requiring it is the verified contract, not a guess.
        '/show/abc123': null,
        '/show/abc123.html.bak': null,
        // No id at all.
        '/show/.html': null,
        '/show/': null,
        // A manga href, not a chapter href.
        '/mh/4aNek4246W': null,
        'javascript:void(0);': null,
      };

      // parseMangaInfo throws without a title, so every fixture needs one.
      String rowFor(String href) => '''
<h1 class="name">T</h1>
<ul class="chapter-list">
  <li data-chapter_id="1"><i></i><a href="$href">第1话</a><span>08-08</span></li>
</ul>
''';

      cases.forEach((href, expected) {
        if (expected == null) {
          // Each fixture has exactly ONE row, so a rejected href means every row
          // on the page was rejected — which is now the 章节链接格式异常 condition
          // rather than a silent empty list. This still pins exactly what the
          // table is for (this href must not yield an id), and pins it harder: an
          // observable throw instead of an absence.
          expect(
            () => source.parseMangaInfo(rowFor(href), 'x'),
            throwsA(isA<Exception>().having((e) => e.toString(), 'message',
                contains('章节链接格式异常'))),
            reason: 'href $href must be rejected',
          );
        } else {
          expect(
            source.parseMangaInfo(rowFor(href), 'x').chapters.map((c) => c.id),
            [expected],
            reason: 'href $href',
          );
        }
      });
    });

    test('falls back to the header title when h1.name is absent', () {
      const html = '<header><div class="title"><h2>兜底标题</h2></div></header>';
      expect(source.parseMangaInfo(html, 'x').title, '兜底标题');
    });

    test('throws when chapter rows exist but no href is recognisable', () {
      // The href-shape counterpart of parseChapter's 章节图片列表格式异常. If the
      // site drops `.html`, moves to `/read/`, or widens the id charset, EVERY row
      // stops matching and the detail page would otherwise render title + cover +
      // description with zero chapters — silently, and indistinguishably from the
      // 8-9 of 25 sampled pages that genuinely have none. detail_cubit would emit
      // chaptersLoading: false with no error and nothing logged.
      const html = '''
<h1 class="name">T</h1>
<ul class="chapter-list">
  <li><a href="/read/aaaaaaaaaa">第1话</a></li>
  <li><a href="/read/bbbbbbbbbb">第2话</a></li>
  <li><a href="/read/cccccccccc">第3话</a></li>
</ul>
''';
      expect(
        () => source.parseMangaInfo(html, 'x'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf([
            contains('章节链接格式异常'),
            contains('mangaId=x'),
            // The row count is the actionable part: it says "3 rows were there
            // and all 3 were rejected", which is what separates a shape change
            // from an empty page.
            contains('3 行'),
            // Distinct from all four other messages this source can throw.
            isNot(contains('不存在')),
            isNot(contains('选择器')),
            isNot(contains('未找到章节图片数据')),
            isNot(contains('解密失败')),
            isNot(contains('章节图片列表格式异常')),
            // Leak invariant: never the markup. `/read/` is a path from the
            // fixture's hrefs and must not be echoed.
            isNot(contains('/read/')),
            isNot(contains('第1话')),
          ]),
        )),
      );
    });

    test('a genuinely chapterless page returns normally with no chapters', () {
      // The other direction of the same boundary, and the reason the guard tests
      // `rows.isNotEmpty` rather than `chapters.isEmpty` alone. 8-9 of the 25
      // sampled pages have no chapter rows at all — that is the site's own state
      // (「最新话：待浏览」), exactly as `"images":[]` is for a chapter, and it must
      // stay silent.
      const html = '<h1 class="name">T</h1>'
          '<div class="zuixin"><p>最新话：待浏览</p></div>';
      final detail = source.parseMangaInfo(html, 'x');
      expect(detail.chapters, isEmpty);
      expect(detail.title, 'T');
      expect(detail.latestChapter, '待浏览');
    });

    test('a bare 最新话 label with no chapter name yields null', () {
      // Pins the collapsed empty-handling: _cleanText runs BEFORE the label strip
      // so the `^` anchor survives indented markup, and AGAIN after, so stripping
      // the label down to nothing gives null rather than ''. An empty-string
      // latestChapter renders as a blank badge in the UI.
      const html =
          '<h1 class="name">T</h1><div class="zuixin"><p>  最新话：  </p></div>';
      expect(source.parseMangaInfo(html, 'x').latestChapter, isNull);
    });

    test('throws on the deleted-manga page instead of returning an empty shell',
        () {
      // The REAL /err/comic body (fetched 2026-08-31), verbatim apart from line
      // endings: the wire form is CRLF and 259 bytes, this LF copy is 254.
      // /mh/<unknown-id> 302s here, and it is reachable from real listings — 1
      // of the 24 ids taken off live listing pages resolved to it (24 counts
      // listing-tap ids, not the 25 parsed detail pages cited elsewhere — see
      // parseMangaInfo's note). Note what the
      // idealized fixture used to hide: there is no <html>/<body> wrapper, there
      // is a SECOND sentence, and a <script> redirects to /category after 2s.
      //
      // What trips the throw is `title.isEmpty` (the stub has neither h1.name
      // nor header .title h2); the 不存在 substring then selects WHICH message.
      // The message predicate is what makes this test meaningful: a bare
      // isA<Exception>() would be satisfied by any unrelated crash, including
      // one from deleting the guard and letting a later null deref fire.
      const html =
          '''很遗憾，该漫画不存在或章节已被删除。我们将自动跳转到漫画检索页，在那里您可以发现更多精彩内容。
<script type="text/javascript">
setTimeout(function() {
	window.location.href = '/category';
}, 2000);
</script>''';
      expect(
        () => source.parseMangaInfo(html, 'deadid'),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('不存在'))),
      );
    });

    test('a titleless page that is NOT the deleted stub reports a selector '
        'failure, not a deletion', () {
      // detail_cubit.dart passes e.toString() straight to the detail screen, so
      // these two causes must read differently. If `h1.name` were ever renamed,
      // conflating them would tell every user that the whole catalogue had been
      // deleted, and would point the maintainer nowhere near the selectors.
      const html = '<html><body><div class="comic_article">'
          '<div class="metas-desc"><p>真的简介</p></div>'
          '</div></body></html>';
      expect(
        () => source.parseMangaInfo(html, 'x'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('选择器'), isNot(contains('不存在'))),
        )),
      );
    });

    test('description is null when metas-desc has no real paragraph', () {
      // The one case where excluding .download-app is load-bearing: with no
      // blurb, the advert is the ONLY paragraph, so `.last` cannot save it.
      const html = '<h1 class="name">T</h1>'
          '<div class="metas-desc"><div class="download-app"><p>下载APP，免费看更多精彩漫画</p></div></div>';
      expect(source.parseMangaInfo(html, 'x').description, isNull);
    });

    test('parseChapterList always returns an empty result', () {
      // prepareChapterListFetch returns null, so the framework never calls this;
      // the info page ships every chapter. The last <li> was confirmed to equal
      // div.zuixin's 最新话 on the 16 chapter-bearing pages of an EARLIER sample
      // (r368n70WNX and 85oDJXjmZa were the two largest at 916 and 1835 rows), and
      // the only control near ul.chapter-list is a client-side [倒序] toggle.
      //
      // A later 25-page sample from a different id set found 17 chapter-bearing
      // pages and did NOT re-run the equality check, so 16 and 17 are two samples
      // rather than one sample with a failure. See parseMangaInfo's note: the
      // invariant is well-supported but not fully verified, and the site now 403s
      // our egress IP on cache MISS so it cannot be closed from here.
      expect(
          source.parseChapterList(detailHtml, '4aNek4246W').chapters, isEmpty);
      expect(source.parseChapterList(detailHtml, '4aNek4246W').canLoadMore,
          isFalse);
    });
  });

  group('Manga51 chapter parsing', () {
    /// Base64 of `IV || AES-128-CBC(PKCS7)` built offline with the real key
    /// `9S8$vJnU2ANeSRoF` and IV `0123456789abcdef`, so a wrong key OR wrong
    /// IV handling fails these tests rather than quietly yielding mojibake
    /// (aesDecryptBase64PrefixedIv decodes UTF-8 leniently — see its doc).
    ///
    /// Cross-checked outside Dart before being trusted (288 decoded bytes;
    /// `tail -c +17` drops the 16-byte IV prefix so only ciphertext reaches
    /// openssl):
    ///
    /// ```sh
    /// printf '%s' "$params" | base64 -d | tail -c +17 \
    ///   | openssl enc -d -aes-128-cbc \
    ///       -K 39533824764a6e5532414e6553526f46 \
    ///       -iv 30313233343536373839616263646566
    /// ```
    ///
    /// Plaintext:
    /// {"host":"www.51manga.com","source_id":"12","comic_id":"618431",
    ///  "comic_down":0,"chapter_id":"223165","images":[
    ///    "https://img1.baipiaoguai.org/static/upload3/book/id/1/a.webp",
    ///    "/static/upload3/book/id/1/b.webp",
    ///    "static/upload3/book/id/1/c.webp"],"lazy":false}
    ///
    /// The mixed absolute / leading-slash / bare-relative `images` array is
    /// synthetic: every live path is absolute (see the CDN-prefix test).
    const params =
        'MDEyMzQ1Njc4OWFiY2RlZoJEmtpzKW14ZWHmM1m0alUjXyRvoUP2OgS3xi55GP0dDMqJ'
        'D56Gixfv9pBhogV9slaJqVOKl+lzwk0IIzeYFccF5vpjRO1EbofHrMSy0iCcQ0e2WH6W'
        'eRDxbJjZ80tD/sQjfXc0jXZMBU+O9J0AYlJind9LaCFo3f1yPkrUTNX/N02+m7dOxgJU'
        'GEM0VqOLpXAGdQMO4yZiIYek67LhZJZYPTeAtVqB6+zNnRsQz9w4/DtLZ9/w1ek7mUSp'
        'TsilECJi2yRy7mXvhLQhSWqmP8hDu2gxSuAtQw2OPsuDRPEqqpnM9u7Ax2XNB1kzpAt5'
        'mM/sTnwPTigPfJ/dvi4I8IgWc3trypbEwQpvYk5ogZvj';

    /// Shaped like the live page: `div#pic-list` is an EMPTY container and the
    /// payload sits in a plain `<script>` just after `</main>`.
    const chapterHtml = '''
<html><body>
<header class="x"><div class="title"><h2>第1-2话 初遇</h2></div></header>
<div class="back"><a href="/mh/4aNek4246W">返回</a></div>
<div class="img-box" id="pic-list"></div>
<div class="diy_btn"><a href="/show/ARkjkt1m3D.html">下一话</a></div>
<script>var tpl_path = '/template/wap/51manga/', params = '$params';</script>
</body></html>
''';

    test('decrypts params into the image list', () {
      final result =
          source.parseChapter(chapterHtml, '4aNek4246W', 'Vd3Q3uKzVB', 1);

      expect(result.chapter.id, 'Vd3Q3uKzVB');
      expect(result.chapter.mangaId, '4aNek4246W');
      expect(result.chapter.title, '第1-2话 初遇');
      // The payload carries no prev/next fields (18 of 18 live payloads had the
      // key set [host, source_id, comic_id, comic_down, chapter_id, images,
      // lazy] and nothing else, verified 2026-08-31), and the whole chapter
      // ships in one response — so there is no in-chapter pagination to expose.
      expect(result.canLoadMore, isFalse);
      expect(result.chapter.images, hasLength(3));
    });

    test('absolute URLs pass through and relative paths get the CDN prefix', () {
      final result =
          source.parseChapter(chapterHtml, '4aNek4246W', 'Vd3Q3uKzVB', 1);

      expect(result.chapter.images.map((i) => i.url).toList(), [
        'https://img1.baipiaoguai.org/static/upload3/book/id/1/a.webp',
        'https://img1.baipiaoguai.org/static/upload3/book/id/1/b.webp',
        'https://img1.baipiaoguai.org/static/upload3/book/id/1/c.webp',
      ]);
    });

    test('every image carries the anti-hotlink headers', () {
      // Measured directly against a live payload URL (2026-08-31): the CDN
      // answers 403 with no Referer and 200 with `https://www.51manga.com/`.
      final result =
          source.parseChapter(chapterHtml, '4aNek4246W', 'Vd3Q3uKzVB', 1);
      expect(result.chapter.images, isNotEmpty);
      for (final image in result.chapter.images) {
        expect(image.headers?['Referer'], 'https://www.51manga.com/');
        expect(image.headers?['User-Agent'], contains('iPhone'));
        // These images are not scrambled; the reader must not try to unscramble.
        expect(image.scrambleType, ScrambleType.none);
      }
    });

    test('falls back to chapterId when the title element is missing', () {
      final html =
          chapterHtml.replaceFirst('<h2>第1-2话 初遇</h2>', '<h2></h2>');
      final result = source.parseChapter(html, '4aNek4246W', 'Vd3Q3uKzVB', 1);
      expect(result.chapter.title, 'Vd3Q3uKzVB');
    });

    test('an empty images array yields an empty chapter without throwing', () {
      // Not hypothetical: 1 of the 18 live chapter pages sampled
      // (/show/OAGm8H9pVD.html, 4397 bytes) ships a perfectly valid payload
      // whose `images` is `[]` — a real, published, image-less chapter.
      // Throwing there would report the site's own state as a parse failure,
      // and it is what keeps the missing-`params` throw below unambiguous.
      // That chapter's REAL decrypted payload, re-encrypted offline with the
      // real key and the same `0123456789abcdef` IV as above:
      //   {"host":"m.51manga.com","source_id":"12","comic_id":"424001",
      //    "comic_down":0,"chapter_id":"137658","images":[],"lazy":false}
      const payload =
          'MDEyMzQ1Njc4OWFiY2RlZm1Rw+TYraTSVQcxXFMNl9TZSgakurfTq8PhNHPQ1MrU'
          'F2sxz+b5r/XJqWkJp45fenpo9pcp7S5iw5UR2nOaBS5taPmKq73cNk7LxV5jGB7c'
          'qPAo5rGtoDQrRr9S7uuKZJXeNm7am4dSDhUXiogyrXoGZgPgd3MqgAR1Ki71g2UA';
      const html = "<script>var params = '$payload';</script>";

      final result = source.parseChapter(html, '4aNek4246W', 'OAGm8H9pVD', 1);
      expect(result.chapter.images, isEmpty);
      expect(result.canLoadMore, isFalse);
    });

    test('throws when params is absent instead of returning zero images', () {
      // The message predicate is the point: a bare isA<Exception>() would be
      // satisfied by any unrelated crash — including one caused by deleting the
      // guard and letting a later null deref fire — and would keep passing if
      // this branch silently returned an empty chapter's worth of nothing.
      const html = '<html><body><div id="pic-list"></div></body></html>';
      expect(
        () => source.parseChapter(html, '4aNek4246W', 'Vd3Q3uKzVB', 1),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('未找到章节图片数据'))),
      );
    });

    test('throws with the chapterId in the message when decryption fails', () {
      // Decodes to 33 bytes, i.e. 17 bytes of "ciphertext" after the IV prefix:
      // not block-aligned, so AES-CBC rejects it.
      //
      // `解密失败` is load-bearing, not decoration. Both throw sites interpolate
      // the chapterId, so `contains('BADCHAP')` ALONE cannot tell this branch
      // apart from the missing-`params` one above — a mutation that broke the
      // payload regex would still satisfy it.
      const html =
          "<script>var params = 'bm90LWEtdmFsaWQtcGF5bG9hZC1hdC1hbGwtcmVhbGx5';</script>";
      expect(
        () => source.parseChapter(html, '4aNek4246W', 'BADCHAP', 1),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            allOf(contains('BADCHAP'), contains('解密失败')))),
      );
    });

    test('throws when the payload decrypts but has no usable images list', () {
      // The counterpart of the `"images":[]` test above, and together with it
      // this is what pins the boundary: an EMPTY list is the site's own state and
      // must pass, while a MISSING or non-list `images` can only mean the payload
      // shape changed — no live chapter can produce it, because the one real
      // image-less chapter observed sends `"images":[]`.
      //
      // All three payloads were built offline with the real key and the same
      // `0123456789abcdef` IV, so they exercise the shape guard specifically and
      // not the decrypt path.
      const cases = <String, String>{
        // {"host":"m.51manga.com","source_id":"12","comic_id":"424001",
        //  "chapter_id":"137658","lazy":false}  -- `images` key absent entirely
        'MDEyMzQ1Njc4OWFiY2RlZm1Rw+TYraTSVQcxXFMNl9TZSgakurfTq8PhNHPQ1MrUF2sx'
            'z+b5r/XJqWkJp45feraKnQ9HgINlgtAjVt6TGsxbo4GsAQrTEiLQW4LsvE5DrNu1'
            'lgtO9FrXDJlb5SeAg36fSoR43iBIg+04oPiIql8=': 'images=Null',
        // {"host":"m.51manga.com","chapter_id":"137658","images":"oops",
        //  "lazy":false}  -- present but a String
        'MDEyMzQ1Njc4OWFiY2RlZm1Rw+TYraTSVQcxXFMNl9Sopat8rDlMwNWlkKZ6IHKwz72u'
            '8EefjQjIpLMrBCA1CCPBPchg8j4XsngHJtpNXVdKC4RM5yF84C/7s79fKJkt':
            'images=String',
        // [1,2,3]  -- top level is not even an object
        'MDEyMzQ1Njc4OWFiY2RlZom/71hOuAixYvdjg9BSgSw=': '顶层=List<dynamic>',
        // {"https://img1.baipiaoguai.org/secret/SENTINEL_LEAK_MARKER/9.webp":1,
        //  "lazy":false}
        //
        // The nastiest shape a payload change could take, because map KEYS are
        // decrypted plaintext: echoing them verbatim would print a real image URL.
        // Only identifier-shaped keys are echoed; this one collapses to its
        // length, and `lazy` survives to show the filter is per-key rather than
        // all-or-nothing.
        'MDEyMzQ1Njc4OWFiY2RlZgNb5SL7NH9h4dHk1WRDYbSXS/cxKbWcCNNg8LeNFDRax6'
            '7KYRJrqF7fEV597hDNljNbUhtSmAh5GOODTZgB1hnlASY7G6ej3nZOnSvKLGGKEoXK'
            'JmemGP+IPQSp+xmPjw==': 'keys=[<63字符>,lazy]',
      };

      cases.forEach((payload, expectedDetail) {
        final html = "<script>var params = '$payload';</script>";
        expect(
          () => source.parseChapter(html, '4aNek4246W', 'SHAPE1', 1),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(
              // The distinctive phrase. Asserting it is the whole point: every
              // throw site here interpolates the chapterId, so `contains(id)`
              // discriminates nothing (proved by mutating the decrypt message to
              // equal the missing-`params` one — the chapterId predicate alone
              // did not notice).
              contains('章节图片列表格式异常'),
              contains('SHAPE1'),
              // Must NOT be reported as either neighbouring failure. A shape
              // change is not a missing blob and not a decryption failure, and
              // conflating them sends the maintainer to the wrong place.
              isNot(contains('未找到章节图片数据')),
              isNot(contains('解密失败')),
              // The same leak invariant the 解密失败 message holds: no decrypted
              // content, and a key is decrypted content too.
              isNot(contains('SENTINEL_LEAK_MARKER')),
              isNot(contains('baipiaoguai')),
              // The diagnostic detail is load-bearing too: "shape changed" with
              // no shape is unactionable, and this is what says WHICH key went.
              contains(expectedDetail),
            ),
          )),
          reason: payload,
        );
      });
    });

    test('the decryption-failure message leaks neither plaintext nor payload',
        () {
      // The sibling 章节图片列表格式异常 branch is careful to expose only types and
      // counts (see _payloadShapeExcerpt). This pins the SAME invariant on this
      // branch, which is easy to lose: interpolating the caught exception raw is
      // the obvious thing to write, and both documented failure modes of
      // aesDecryptBase64PrefixedIv embed their input in `toString()`.
      //
      // reader_bloc.dart prints this message verbatim, so a leak here is a leak
      // to the screen and to any log that captures it.
      //
      // A test that only asserted contains('解密失败') could not catch this — the
      // assertions that matter are the negative ones.

      // (a) Decrypts cleanly with the REAL key, then fails json.decode on the
      //     trailing garbage. Plaintext:
      //     {"a":"https://img1.baipiaoguai.org/leak/SENTINEL_LEAK_MARKER/0001.webp"}TRAILING_GARBAGE
      //     A raw `$e` puts the decrypted URL — a real image path in production —
      //     into the message.
      const plaintextLeak =
          'MDEyMzQ1Njc4OWFiY2RlZn+2DlXfSg4oF80CljxRhDBodFp0hZ7tYE7lFX6mX+8w'
          'PokQbPCb/Y+RapHuirD2CrfoLgWrLwHK/FKXrvhKbabKVBZxSm/xGcmL4MJokHl2'
          '7SIQC/AFGF4/uJczHKIL8g==';
      // (b) 16 decoded bytes: IV only. crypto_utils throws
      //     ArgumentError.value(payload, ...), whose toString embeds the payload
      //     itself.
      const payloadLeak = 'MDEyMzQ1Njc4OWFiY2RlZg==';
      // (c) Not valid base64 at all — FormatException from base64.decode, which
      //     also quotes its source.
      const notBase64 = 'not!base64!at!all!!!!';

      for (final payload in [plaintextLeak, payloadLeak, notBase64]) {
        final html = "<script>var params = '$payload';</script>";
        String message;
        try {
          source.parseChapter(html, '4aNek4246W', 'LEAK1', 1);
          fail('expected a throw for $payload');
        } catch (e) {
          message = e.toString();
        }

        // Still diagnosable, and still the distinctive phrase.
        expect(message, contains('解密失败'), reason: payload);
        expect(message, contains('LEAK1'), reason: payload);
        // ...and still distinct from its two neighbours.
        expect(message, isNot(contains('未找到章节图片数据')), reason: payload);
        expect(message, isNot(contains('章节图片列表格式异常')), reason: payload);

        // The invariant. No decrypted plaintext:
        expect(message, isNot(contains('SENTINEL_LEAK_MARKER')),
            reason: payload);
        expect(message, isNot(contains('baipiaoguai')), reason: payload);
        // ...and no payload, not even a fragment of it. A 24-character prefix is
        // far more than any accidental collision and far less than a leak.
        expect(message, isNot(contains(payload.substring(0, 21))),
            reason: payload);
        // Bounded outright. Measured pre-fix, 2026-08-31: case (a) produced a
        // 200+ character message containing a whole image URL, (b) 138 chars
        // quoting the payload, (c) 79 chars quoting the base64. Post-fix all
        // three are ~80. The cap is what makes this structural rather than a hope
        // that some future toString() stays short.
        expect(message.length, lessThan(120), reason: payload);
      }
    });

    test('an identifier merely ENDING in params does not shadow the real one',
        () {
      // Not a remote hypothetical: on the live page `tpl_path` sits in the VERY
      // SAME `var` statement as `params`, so `tpl_params` is one template rename
      // away. And the decoy does not merely tie — it WINS, because it appears
      // first and firstMatch takes the first match.
      //
      // Renaming only `tpl_path`, so the real assignment is untouched and still
      // the one that must be picked.
      final html = chapterHtml.replaceFirst(
        "var tpl_path = '/template/wap/51manga/',",
        "var tpl_params = 'DECOY-NOT-BASE64',",
      );
      expect(html, contains('tpl_params'));

      // Without a left boundary this throws 解密失败 on 'DECOY-NOT-BASE64'.
      final result = source.parseChapter(html, '4aNek4246W', 'Vd3Q3uKzVB', 1);
      expect(result.chapter.images, hasLength(3));
      expect(result.chapter.images.first.url,
          'https://img1.baipiaoguai.org/static/upload3/book/id/1/a.webp');
    });
  });

  group('Manga51 origin-block detection', () {
    // The origin IP-bans scraper egresses. On a CDN cache MISS it serves a
    // 159-byte openresty block page, and that page has been observed arriving
    // with an HTTP 200 status line (the real code hidden in
    // `x-cache: BYPASS, Status: 403`), so Dio raises nothing and the body reaches
    // parse* directly. Every entry point that parses a page body must therefore
    // recognise it BEFORE its own selectors, or it reports a confident wrong cause.

    test('the fixture is the real 159-byte page, CRLF and version included', () {
      // Guards the fixture itself: an editor stripping CRLF, or someone dropping
      // the `/1.27.1.2`, would silently weaken every test below.
      expect(kOriginBlockHtml.length, 159);
      expect(kOriginBlockHtml, contains('\r\n'));
      expect(
          kOriginBlockHtml, contains('<hr><center>openresty/1.27.1.2</center>'));
    });

    test('parseMangaInfo reports an origin block, NOT a selector failure', () {
      // The regression that motivated this. The block page has neither `h1.name`
      // nor `header .title h2` and does not contain 不存在, so it fell through to
      // the selector-failure branch and told the user the site template had
      // changed — a wrong cause, printed verbatim by detail_cubit.dart.
      expect(
        () => source.parseMangaInfo(kOriginBlockHtml, 'YyZJyLgV6q'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf([
            contains('源站拒绝了请求'),
            contains('YyZJyLgV6q'),
            // The message that USED to win here. Pinning its absence is the whole
            // point of this test.
            isNot(contains('选择器')),
            isNot(contains('解析失败')),
            // ...and not any of the other five either.
            isNot(contains('不存在')),
            isNot(contains('章节链接格式异常')),
            isNot(contains('未找到章节图片数据')),
            isNot(contains('章节图片解密失败')),
            isNot(contains('章节图片列表格式异常')),
            // Leak invariant: our own literals plus the id, never the body.
            isNot(contains('<center>')),
            isNot(contains('Forbidden')),
          ]),
        )),
      );
    });

    test('parseDiscovery reports an origin block instead of a blank grid', () {
      // Without the guard this returns [] and discovery_cubit emits
      // `status: loaded, manga: []`; discovery_screen has no empty-state widget,
      // so the user sees an empty grid with no reason for it.
      expect(
        () => source.parseDiscovery(kOriginBlockHtml),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            allOf(contains('源站拒绝了请求'), isNot(contains('选择器'))))),
      );
    });

    test('parseSearch reports an origin block instead of zero results', () {
      // Shares _parseCards with parseDiscovery, but pinned separately: they are
      // two entry points and a refactor could easily guard only one.
      expect(
        () => source.parseSearch(kOriginBlockHtml),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('源站拒绝了请求'))),
      );
    });

    test('parseChapter reports an origin block, NOT missing image data', () {
      // The block page has no `params`, so this used to report
      // 「未找到章节图片数据」 — a message whose own comment carefully rules out
      // every cause it knows of, which would have made it confidently wrong here.
      expect(
        () =>
            source.parseChapter(kOriginBlockHtml, '4aNek4246W', 'Vd3Q3uKzVB', 1),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf([
            contains('源站拒绝了请求'),
            contains('Vd3Q3uKzVB'),
            isNot(contains('未找到章节图片数据')),
            isNot(contains('解密失败')),
            isNot(contains('章节图片列表格式异常')),
          ]),
        )),
      );
    });

    test('a real cover URL containing 403 is not mistaken for a block page', () {
      // The false-positive direction, which matters more than the others: telling
      // a user with a working connection that their IP is banned would be worse
      // than the bug being fixed.
      //
      // A bare `403` check would fail this. `403` occurs 3 times in one live
      // listing page (/category/order/hits/page/2, 35892 bytes, 2026-08-31), every
      // time inside a cover URL — book ids 7403, 44032 and 134403. This fixture
      // reproduces the third. The whole rest of the suite covers the same
      // direction for every other fixture, since none of them may start throwing.
      const coverWith403 = '<div class="comic-item">'
          '<a href="/mh/abcdefghij"><div class="pic">'
          '<img src="https://img1.baipiaoguai.org/static/upload2/book/id/134403/cover_1.jpg">'
          '</div><h3 class="title">全球冰封</h3></a></div>';
      final cards = source.parseDiscovery(coverWith403);
      expect(cards, hasLength(1));
      expect(cards.first.coverUrl, contains('134403'));
    });
  });
}
