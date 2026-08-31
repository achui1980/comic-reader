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
      expect(source.userAgent, contains('iPhone'));
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
    // Mirrors the live m.51manga.com/mh/4aNek4246W markup. Two deliberate
    // deviations from that page, both defensive:
    //  * the `javascript:void(0);` row inside ul.chapter-list. On the live page
    //    the only such href is the `[倒序]` sort toggle, which sits in
    //    div.panel-heading OUTSIDE the list (0 javascript: hrefs occur inside
    //    ul.chapter-list across the 15 chapter-bearing pages sampled).
    //  * only 3 of the page's 12 chapter rows are reproduced.
    // The empty `<div class="mask">` IS faithful: it is present and empty on
    // all 24 live detail pages sampled, which is exactly why div.mask is not a
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

    test('description skips the download-app decoy paragraph', () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.description, startsWith('北宋年间'));
      expect(detail.description, isNot(contains('下载APP')));
    });

    test('extracts tags and infers completed status from them', () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.tags, ['已完结', '国漫', '古风']);
      expect(detail.status, MangaStatus.completed);
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
      // only 1 of 24 sampled detail pages carries a status-bearing tag.
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

    test('falls back to the header title when h1.name is absent', () {
      const html = '<header><div class="title"><h2>兜底标题</h2></div></header>';
      expect(source.parseMangaInfo(html, 'x').title, '兜底标题');
    });

    test('throws on the deleted-manga page instead of returning an empty shell',
        () {
      // Live shape: /mh/<unknown-id> 302s to /err/comic, which serves this
      // sentence. Reachable from real listings — one card on
      // /category/finish/1/page/1 resolved to exactly this stub.
      //
      // What actually trips the throw is `title.isEmpty` (the stub has neither
      // h1.name nor header .title h2), NOT detection of the sentence. The
      // message predicate is what makes this test meaningful: a bare
      // isA<Exception>() would be satisfied by any unrelated crash, including
      // one from deleting the guard and letting a later null deref fire.
      const html =
          '<html><body>很遗憾，该漫画不存在或章节已被删除。</body></html>';
      expect(
        () => source.parseMangaInfo(html, 'deadid'),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('不存在'))),
      );
    });

    test('description is null when metas-desc has no real paragraph', () {
      const html = '<h1 class="name">T</h1>'
          '<div class="metas-desc"><div class="download-app"><p>下载APP，免费看更多精彩漫画</p></div></div>';
      expect(source.parseMangaInfo(html, 'x').description, isNull);
    });

    test('parseChapterList always returns an empty result', () {
      // prepareChapterListFetch returns null, so the framework never calls
      // this; the info page ships every chapter. Verified live: on all 15
      // chapter-bearing pages sampled the last <li> equals div.zuixin's
      // 最新话 (up to 916 rows on r368n70WNX, 1328 on km6KELW8NB), and the
      // only control near ul.chapter-list is a client-side [倒序] toggle.
      expect(
          source.parseChapterList(detailHtml, '4aNek4246W').chapters, isEmpty);
      expect(source.parseChapterList(detailHtml, '4aNek4246W').canLoadMore,
          isFalse);
    });
  });
}
