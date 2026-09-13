import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/mycomic.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() {
  late MyComic source;

  setUp(() {
    source = MyComic();
  });

  group('MyComic metadata', () {
    test('exposes stable identity', () {
      expect(source.id, 'mycomic');
      expect(source.name, '我的漫画');
      expect(source.shortName, 'MYC');
      expect(source.href, 'https://mycomic.com');
      expect(source.isAdult, isTrue);
    });

    test('enables the cloudflare webview-fetch path', () {
      expect(source.needsCloudflare, isTrue);
      expect(source.usesWebViewFetch, isTrue);
      expect(source.cloudflareUrl, 'https://mycomic.com/cn');
      expect(source.defaultHeaders?['Referer'], 'https://mycomic.com/');
      expect(source.defaultHeaders?['User-Agent'], contains('Chrome/124.0.0.0'));
    });

    test('exposes four discovery filters using the site parameter names', () {
      expect(source.discoveryFilters, hasLength(4));
      expect(
        source.discoveryFilters.map((f) => f.name),
        ['sort', 'filter[tag]', 'filter[country]', 'filter[end]'],
      );
      expect(source.searchFilters, isEmpty);
    });

    test('tag filter starts with an "all" choice and covers 38 slugs', () {
      final tag =
          source.discoveryFilters.firstWhere((f) => f.name == 'filter[tag]');
      expect(tag.choices.first.value, '');
      expect(tag.choices, hasLength(39));
      expect(
        tag.choices.map((c) => c.value),
        containsAll(<String>['mohuan', 'baihe', 'danmei', 'zazhi']),
      );
    });
  });

  group('MyComic request builders', () {
    test('discovery omits empty filter values', () {
      final config = source.prepareDiscoveryFetch(1, const {});
      expect(config.url, 'https://mycomic.com/cn/comics');
      expect(config.method, HttpMethod.get);
      expect(config.queryParameters, {'page': '1'});
    });

    test('discovery passes through non-empty filters verbatim', () {
      final config = source.prepareDiscoveryFetch(3, const {
        'sort': '-views',
        'filter[tag]': 'baihe',
        'filter[country]': '',
        'filter[end]': '1',
      });
      expect(config.queryParameters, {
        'page': '3',
        'sort': '-views',
        'filter[tag]': 'baihe',
        'filter[end]': '1',
      });
    });

    test('prepareDiscoveryFetch drops keys not declared in discoveryFilters', () {
      final config = source.prepareDiscoveryFetch(1, const {'unknown': 'x'});
      expect(config.queryParameters, {'page': '1'});
      expect(config.queryParameters?.containsKey('unknown'), isFalse);
    });

    test('search reuses the comics endpoint with a q parameter', () {
      final config = source.prepareSearchFetch('猎人', 2, const {});
      expect(config.url, 'https://mycomic.com/cn/comics');
      expect(config.queryParameters?['q'], '猎人');
      expect(config.queryParameters?['page'], '2');
    });

    test('search ignores discovery-only filter keys', () {
      final config = source.prepareSearchFetch('猎人', 1, const {
        'filter[tag]': 'rexue',
      });
      expect(config.queryParameters, {'q': '猎人', 'page': '1'});
      expect(config.queryParameters?.containsKey('filter[tag]'), isFalse);
    });

    test('manga info targets the numeric comic id', () {
      final config = source.prepareMangaInfoFetch('55355');
      expect(config.url, 'https://mycomic.com/cn/comics/55355');
    });

    test('chapter list needs no extra request', () {
      expect(source.prepareChapterListFetch('55355', 1), isNull);
      expect(source.parseChapterList('', '55355').chapters, isEmpty);
    });

    test('chapter targets the numeric chapter id', () {
      final config = source.prepareChapterFetch('55355', '818144', 1);
      expect(config.url, 'https://mycomic.com/cn/chapters/818144');
      expect(config.timeout, const Duration(seconds: 60));
    });
  });

  group('MyComic list parsing', () {
    test('keeps only real cards and drops the random-comic nav anchor', () {
      final results = source.parseDiscovery(_listFixture);

      expect(results, hasLength(2));

      expect(results[0].id, '55355');
      expect(results[0].sourceId, 'mycomic');
      expect(results[0].title, '猎人游戏W');
      expect(results[0].coverUrl, 'https://biccam.com/comics/55355-9e7018.jpg');
      expect(results[0].latestChapter, '第07话');
      expect(results[0].headers?['Referer'], 'https://mycomic.com/');

      expect(results[1].id, '40001');
      expect(results[1].title, '测试漫画');
      // data-src 优先于占位 src
      expect(results[1].coverUrl, 'https://biccam.com/comics/40001-aa11bb.jpg');
      // 该卡片的 <a> 内没有叶子 div，取不到最新章节
      expect(results[1].latestChapter, isNull);
    });

    test('parseSearch shares the list parser', () {
      expect(source.parseSearch(_listFixture), hasLength(2));
    });

    // 已完结作品的角标是「章节名 + [完]」两行结构，HTML 缩进让原始文本长达数十
    // 字符，会被 `length > 20` 的简介守卫误杀（实测真实列表页 30 张卡片里 13 张
    // 因此丢了 latestChapter）。折叠空白后才既能通过守卫、又保留完整角标文本。
    test('collapses whitespace in the multi-line completed badge', () {
      // 夹具自检：角标 div 的**未折叠**文本必须仍超过 20 字符，否则它不再触发那
      // 条长度守卫，本测试也就不再验证空白折叠。用正则抓第一个不含标签的 div。
      final badge = RegExp(r'<div[^>]*>([^<]*)</div>')
          .firstMatch(_completedCardFixture)!
          .group(1)!;
      expect(badge.trim().length, greaterThan(20),
          reason: '夹具已失去「原始文本超长」性质，本测试不再验证空白折叠');

      final results = source.parseDiscovery(_completedCardFixture);

      expect(results, hasLength(1));
      expect(results.single.id, '55354');
      expect(results.single.latestChapter, '短篇 [完]');
    });
  });

  group('MyComic manga info parsing', () {
    test('takes the description from og:description, not the comment spam', () {
      final detail = source.parseMangaInfo(_detailFixture, '55355');

      expect(detail.id, '55355');
      expect(detail.sourceId, 'mycomic');
      expect(detail.title, '猎人游戏W');
      expect(detail.coverUrl, 'https://biccam.com/comics/55355-9e7018.jpg');
      expect(detail.description, '被卷入死亡游戏的少年们的故事。');
      expect(detail.description, isNot(contains('外送茶')));
      expect(detail.author, '某作者');
      expect(detail.tags, ['百合', '职场']);
      expect(detail.status, MangaStatus.ongoing);
      expect(detail.headers?['Referer'], 'https://mycomic.com/');
    });

    test('reverses the site newest-first order to oldest-first', () {
      final detail = source.parseMangaInfo(_detailFixture, '55355');

      // latestChapter 取反转前的首项
      expect(detail.latestChapter, '第07话');
      expect(detail.chapters.map((c) => c.id), ['818144', '818149', '818150']);
      expect(detail.chapters.first.title, '第01话');
      expect(detail.chapters.first.mangaId, '55355');
      expect(
        detail.chapters.first.href,
        'https://mycomic.com/cn/chapters/818144',
      );
    });

    test('does not truncate titles containing a paired "]"', () {
      final detail = source.parseMangaInfo(_trickyChaptersFixture, '999');

      expect(detail.chapters, hasLength(2));
      expect(detail.chapters.map((c) => c.title), ['第"零"话', '卷1 [完] 特别篇']);
      expect(detail.latestChapter, '卷1 [完] 特别篇');
    });

    test('decodes unicode-escaped titles', () {
      final detail = source.parseMangaInfo(_escapedChaptersFixture, '888');
      expect(detail.chapters.single.title, '第07话');
    });

    test('throws when the embedded chapter payload is gone', () {
      expect(
        () => source.parseMangaInfo(_noChaptersFixture, '777'),
        throwsA(isA<Exception>()),
      );
    });

    test('accepts a legitimately empty chapter array', () {
      final detail = source.parseMangaInfo(_emptyChaptersFixture, '666');
      expect(detail.chapters, isEmpty);
      expect(detail.latestChapter, isNull);
      expect(detail.title, '未上架作品');
    });

    // 上面 `_trickyChaptersFixture` 里的 `]` 是**成对**的，深度计数即使把字符串
    // 内的括号也算进去，仍恰好在正确位置归零；只有**落单**的 `]` 才能证明
    // 「字符串内的括号不参与深度计数」这条规则真的在生效。
    test('keeps counting depth past an unmatched "]" inside a chapter title', () {
      // 夹具自检：`]` 必须恰好比 `[` 多一个（净落单一个右括号）。后人补章节时若
      // 带进第二个落单 `[`（相互抵消）或把这个落单 `]` 写成全角，本测试会静默退化
      // 成「碰巧算对」，故在此显式锁住夹具性质。补**配对**的 `[...]` 不影响。
      final open = _unpairedBracketChaptersFixture.split('[').length - 1;
      final close = _unpairedBracketChaptersFixture.split(']').length - 1;
      expect(close - open, 1,
          reason: '夹具已失去「落单 ]」性质，本测试不再验证字符串内括号被忽略');

      final detail = source.parseMangaInfo(_unpairedBracketChaptersFixture, '444');

      expect(detail.chapters.map((c) => c.title), ['第24话', '第25话 【完结]']);
      expect(detail.latestChapter, '第25话 【完结]');
    });

    // 同理，`_trickyChaptersFixture` 的 `第\"零\"话` 转义引号是**偶数**个，
    // 字符串开合次数守恒；只有**奇数**个转义引号才能证明 `\"` 没有被误认成
    // 字符串的结束引号。
    test('treats a trailing escaped quote as title text, not the closing quote', () {
      // 夹具自检：`\"` 必须是奇数个，否则字符串开合守恒，转义逻辑不再被检验。
      expect(
        RegExp(r'\\"').allMatches(_oddEscapedQuoteChaptersFixture).length.isOdd,
        isTrue,
        reason: '夹具的转义引号变成偶数个，本测试不再验证 \\" 未被误判为结束引号',
      );

      final detail =
          source.parseMangaInfo(_oddEscapedQuoteChaptersFixture, '555');

      expect(detail.chapters.single.title, '第08话 “活着的意义"');
      expect(detail.chapters.single.id, '21');
      expect(detail.latestChapter, '第08话 “活着的意义"');
    });

    // 状态只能从 `[data-flux-badge]` 徽章读：页脚的 `filter[end]` 筛选链接文本
    // 恰好也是「连载中」/「已完结」，且是叶子 `<a>`，全文档扫描会把**没有徽章**的
    // 作品误判成 ongoing（页脚「连载中」在「已完结」之前）。
    test('reports unknown when the status badge is absent', () {
      // 夹具自检：必须真的没有徽章、且页脚干扰链接还在，否则本测试空转。
      expect(_noBadgeDetailFixture, isNot(contains('data-flux-badge')));
      expect(_noBadgeDetailFixture, contains('filter%5Bend%5D=0'));

      final detail = source.parseMangaInfo(_noBadgeDetailFixture, '12321');

      expect(detail.status, MangaStatus.unknown);
    });
  });

  group('MyComic chapter parsing', () {
    test('prefers data-src, keeps order, and drops non-page images', () {
      final result = source.parseChapter(_chapterFixture, '55355', '818144', 1);

      expect(result.canLoadMore, isFalse);
      expect(result.chapter.id, '818144');
      expect(result.chapter.mangaId, '55355');
      expect(result.chapter.title, '第01话');
      expect(result.chapter.images.map((i) => i.url), [
        'https://biccam.com/chapters/818144/1-03ef91.jpg',
        'https://biccam.com/chapters/818144/2-1a2b3c.jpg',
        'https://biccam.com/chapters/818144/3-4d5e6f.jpg',
      ]);
    });

    test('every image carries the CDN Referer and no scrambling', () {
      final result = source.parseChapter(_chapterFixture, '55355', '818144', 1);

      expect(result.chapter.images, isNotEmpty);
      for (final image in result.chapter.images) {
        expect(image.headers?['Referer'], 'https://mycomic.com/');
        expect(image.scrambleType, ScrambleType.none);
      }
      expect(result.chapter.headers?['Referer'], 'https://mycomic.com/');
    });

    // LD-JSON 是章节名的唯一来源（og:title 只有作品名），但它缺失时也不能让
    // `Chapter.title` 变成空串 —— 阅读器标题栏与章节分界标签都靠它。
    test('falls back to og:title when the ld+json breadcrumb is missing', () {
      // 夹具自检：必须真的没有 LD-JSON，否则测不到回退路径。
      expect(_chapterNoLdJsonFixture, isNot(contains('application/ld+json')));

      final result =
          source.parseChapter(_chapterNoLdJsonFixture, '55355', '818144', 1);

      expect(result.chapter.title, '猎人游戏W');
      expect(result.chapter.images, hasLength(1));
    });
  });
}

/// 列表页夹具：3 个负例锚点（每个只违反一条结构不变量）+ 2 张真卡片。
///
/// 负例与被拦截的不变量一一对应，因此 `hasLength(2)` 能证明三条判据都在生效
/// （下列顺序与夹具 HTML 中的出现顺序一致）：
/// - 站点 logo 锚点：有 img 且 alt 非空，但 **href 不是漫画详情页** → 只被①拦；
/// - 「随机漫画」导航锚点：href 匹配 `/comics/\d+`，但**无 img** → 只被②拦；
/// - 装饰性/懒加载图片锚点：href 匹配且有 img，但 **alt 为空** → 只被③拦。
///
/// 第一张卡片的角标是**单层叶子 div**（贴合站点实测结构），且 `<a>` 内在角标之前
/// 还有四个必须被 `_latestChapterText` 跳过的 div，逐一覆盖它的四条跳过分支：
/// 空的 hover 遮罩层（文本为空）、评分行（**非叶子**，内层用 `<span>` 以免自己
/// 被 `querySelectorAll('div')` 选中）、文本等于标题的 div、超过 20 字符的简介。
const String _listFixture = '''
<html><body>
  <nav>
    <a href="/cn/about"><img src="/logo.png" alt="MYCOMIC"></a>
    <a href="https://mycomic.com/cn/comics/12345"
       :href="comicUrl({id: Math.floor(Math.random() * maxComicId)})">随机漫画</a>
  </nav>
  <div class="grid grid-cols-3 md:grid-cols-6">
    <div class="group relative">
      <a href="https://mycomic.com/cn/comics/55355">
        <img src="https://biccam.com/comics/55355-9e7018.jpg" alt="猎人游戏W">
        <div class="absolute inset-0"></div>
        <div class="flex items-center gap-1"><span class="text-xs">9.2</span></div>
        <div class="sr-only">猎人游戏W</div>
        <div class="line-clamp-2 text-xs">一位普通高中生被卷入了一场以生命为赌注的猎人游戏，规则残酷。</div>
        <div class="absolute inset-x-0 bottom-0">第07话</div>
      </a>
      <div class="mt-2 text-center"><div data-flux-subheading>猎人游戏W</div></div>
    </div>
    <div class="group relative">
      <a href="https://mycomic.com/cn/comics/40001">
        <img src="https://biccam.com/img/placeholder.gif"
             data-src="https://biccam.com/comics/40001-aa11bb.jpg" alt="测试漫画">
      </a>
    </div>
    <a href="https://mycomic.com/cn/comics/60001"><img src="x.gif" alt=""></a>
  </div>
</body></html>
''';

/// 已完结作品卡片（站点实抓）：角标 div 里是**两行**内容 —— 章节名 + `[完]` 标记，
/// 中间夹着 HTML 缩进产生的大量空白。
///
/// 结构保真（class 名、两行布局、外层渐变遮罩 div 都是站点原样），但**缩进被缩短过**：
/// 真站 `[完]` 前是 76 个空格、`text.trim().length == 82`，此处缩到 32 个空格、
/// 长度为 38。别拿 38 去反推真站数值。两者都远大于 `length > 20` 守卫，也都折叠成
/// 同一个 6 字符的 `短篇 [完]`，所以这个夹具照样能钉住缺陷与修复。
///
/// 这就是「未折叠空白」缺陷的根源：`div.text.trim()` 在这里长达数十字符，会被
/// `length > 20` 的简介守卫误杀，导致所有已完结作品的 latestChapter 变 null。
/// 外层渐变遮罩 div 有子元素，先被叶子判据跳过；内层角标 div 才是目标。
const String _completedCardFixture = '''
<html><body>
  <div class="group relative">
    <a href="https://mycomic.com/cn/comics/55354">
      <img src="data:image/png;base64,iVBOR" data-src="https://biccam.com/comics/55354-3483fc.jpg"
           alt="1步前进 2步后退" class=" lozad  w-full h-full object-cover">
      <div class="absolute top-0 left-0 w-full h-full bg-gradient-to-t from-black to-30% flex items-end justify-center px-3">
        <div class="text-white text-sm pb-3 truncate">
        短篇
                                [完]
                        </div>
      </div>
    </a>
  </div>
</body></html>
''';

/// 详情页夹具：OG meta + 状态徽章 + 作者/题材筛选链接 + x-data 内嵌章节 JSON
/// + 一段评论区垃圾长文本（用于证明简介不是「取最长文本」）+ 页脚状态筛选链接。
///
/// 状态徽章保真为站点真实的 `data-flux-badge` 形态，含换行缩进（Flux 组件渲染
/// 出来的文本是 `\n        连载中\n    `），用于验证 `_parseStatus` 折叠空白。
/// 页脚那两个 `filter[end]` 链接也是站点真实存在的：它们的文本恰好也是
/// 「连载中」/「已完结」，是全文档扫描方案的干扰源，必须留在夹具里。
const String _detailFixture = '''
<html><head>
  <meta property="og:title" content="猎人游戏W - MYCOMIC - 我的漫画">
  <meta property="og:description" content="被卷入死亡游戏的少年们的故事。">
  <meta property="og:image" content="https://biccam.com/comics/55355-9e7018.jpg">
</head><body>
  <div data-flux-badge="data-flux-badge" class="inline-flex items-center bg-blue-400/20 dark:bg-blue-400/40 mt-2">
        连载中
    </div>
  <a href="/cn/comics?filter%5Bauthor%5D=%E6%9F%90%E4%BD%9C%E8%80%85">某作者</a>
  <a href="/cn/comics?filter%5Btag%5D=baihe">百合</a>
  <a href="/cn/comics?filter%5Btag%5D=zhichang">职场</a>
  <a href="/cn/chapters/818150">开始阅读</a>
  <div x-data='{
    chapters: [{"id":818150,"title":"第07话"},{"id":818149,"title":"第06话"},{"id":818144,"title":"第01话"}],
    decending: true,
    toggleSorting() { this.decending = !this.decending }
  }'>
    <template x-for="chapter in chapters"><a :href="chapterUrl(chapter)"></a></template>
  </div>
  <div class="comments">
    <p>【外送茶】加LINE看照片，全套服務，市區叫小姐外送到府，價格實在，安全可靠，歡迎老闆來電諮詢，我們有各種類型的妹妹可以挑選，保證真人實照，不滿意可換人，二十四小時營業，全台都有服務點，還可以指定時間地點，先看照片再決定，不用先付訂金，見面滿意再付款，絕不強迫消費。</p>
  </div>
  <footer>
    <ul>
      <li><a href="https://mycomic.com/cn/comics?filter%5Bend%5D=0" class="text-sm/6">连载中</a></li>
      <li><a href="https://mycomic.com/cn/comics?filter%5Bend%5D=1" class="text-sm/6">已完结</a></li>
    </ul>
  </footer>
</body></html>
''';

/// 与 `_detailFixture` 同构，但**没有** `data-flux-badge` 徽章（站点上确实存在
/// 状态未标注的作品），只保留页脚那两个 `filter[end]` 筛选链接。
///
/// 全文档叶子扫描方案会命中页脚顶序更靠前的「连载中」`<a>`（它是叶子元素），把
/// 状态未知的作品误判成 ongoing；锚定 `[data-flux-badge]` 才会正确返回 unknown。
const String _noBadgeDetailFixture = '''
<html><head>
  <meta property="og:title" content="无徽章作品 - MYCOMIC - 我的漫画">
  <meta property="og:description" content="站点没给这部作品标状态。">
  <meta property="og:image" content="https://biccam.com/comics/12321-abcdef.jpg">
</head><body>
  <div x-data='{ chapters: [{"id":700001,"title":"第01话"}], decending: true }'></div>
  <footer>
    <ul>
      <li><a href="https://mycomic.com/cn/comics?filter%5Bend%5D=0" class="text-sm/6">连载中</a></li>
      <li><a href="https://mycomic.com/cn/comics?filter%5Bend%5D=1" class="text-sm/6">已完结</a></li>
    </ul>
  </footer>
</body></html>
''';

/// 标题含 `]` 与转义引号——正则方案 `\[.*?\]` 会在这里静默截断。
const String _trickyChaptersFixture = r'''
<html><head>
  <meta property="og:title" content="括号试炼 - MYCOMIC - 我的漫画">
</head><body>
  <div x-data='{
    chapters: [{"id":11,"title":"卷1 [完] 特别篇"},{"id":10,"title":"第\"零\"话"}],
    decending: true
  }'></div>
</body></html>
''';

/// 原始 HTML 里章节标题是 unicode 转义的，交由 jsonDecode 原生处理。
const String _escapedChaptersFixture = r'''
<html><head>
  <meta property="og:title" content="转义试炼 - MYCOMIC - 我的漫画">
</head><body>
  <div x-data='{ chapters: [{"id":818150,"title":"\u7b2c07\u8bdd"}] }'></div>
</body></html>
''';

/// 站点改版移除内嵌章节 —— 必须显式抛错，不能静默返回空。
const String _noChaptersFixture = '''
<html><head>
  <meta property="og:title" content="改版了 - MYCOMIC - 我的漫画">
</head><body><div x-data='{ decending: true }'></div></body></html>
''';

/// 合法的空章节表（尚未上架的作品）。
const String _emptyChaptersFixture = '''
<html><head>
  <meta property="og:title" content="未上架作品 - MYCOMIC - 我的漫画">
</head><body><div x-data='{ chapters: [], decending: true }'></div></body></html>
''';

/// 标题里的方括号**落单**：站点上传者把左括号打成了全角 `【`、右括号仍是半角
/// `]`（中文站常见的混排笔误）。全角括号不参与深度计数，于是整个 JSON 文本里
/// 多出一个无配对的 `]`。
///
/// 若扫描器不忽略字符串内部的括号，读到该 `]` 时深度就提前归零，切出的子串是
/// 被截断的非法 JSON（`jsonDecode` 抛 `FormatException`）。落单的括号必须只有
/// 这一个——再补一个落单的 `[` 就会相互抵消，重新变成「碰巧算对」。
const String _unpairedBracketChaptersFixture = '''
<html><head>
  <meta property="og:title" content="括号笔误 - MYCOMIC - 我的漫画">
</head><body>
  <div x-data='{
    chapters: [{"id":903,"title":"第25话 【完结]"},{"id":902,"title":"第24话"}],
    decending: true
  }'></div>
</body></html>
''';

/// 标题里的引号也**落单**：全角左引号 `“` 配了个半角右引号，于是整段 JSON 文本
/// 中 `\"` 恰好出现**奇数**次（一次），且它紧贴在字符串真正的结束引号之前。
///
/// 若扫描器不处理转义，`\` 会被跳过、随后的 `"` 被当成字符串结束（提前一位），
/// 真正的结束引号则被当成新字符串的开始——字符串开合的奇偶从此翻转，数组末尾的
/// `]` 被误认为在字符串内而被跳过，最终抛「内嵌章节 JSON 数组未闭合」。
///
/// 必须用 raw 字符串：否则 Dart 会先把 `\"` 解释成自己的转义，喂给扫描器的字节
/// 里就没有反斜杠了。
const String _oddEscapedQuoteChaptersFixture = r'''
<html><head>
  <meta property="og:title" content="引号笔误 - MYCOMIC - 我的漫画">
</head><body>
  <div x-data='{
    chapters: [{"id":21,"title":"第08话 “活着的意义\""}],
    decending: true
  }'></div>
</body></html>
''';

/// 阅读器夹具：国旗图标 + 首图仅 src + 两张 lozad 懒加载（data-src 真实、
/// src 为占位）+ 三个负例，与 `parseChapter` 的三条守卫一一对应。
///
/// 国旗 `<img class="flag">` 不匹配 `img.page`，在选择器阶段即被排除；三个负例
/// 则**都带 `page` class**，以确保它们进入循环、真正打到各自那条守卫：
/// - 无 src 也无 data-src（模板漏写 / lozad 尚未注入）→ 只被 `url.isEmpty` 拦；
/// - 仅有占位 src、没有 data-src → 只被 `!url.contains('/chapters/')` 拦；
/// - 与第 1 张真图同址（站点重复渲染）→ 只被 `seen` 去重拦。
///
/// 章节标题部分保真为站点实测形态：`og:title` **只有作品名、不含章节名**，章节名
/// 的唯一来源是页面上唯一一个 `application/ld+json` 里 breadcrumb 的末项
/// （`position` 最大者）。`itemListElement` 的三项结构、`position`、`name` 与
/// `https:\/\/` 的斜杠转义都保真；只精简了 description / image 等无关字段的值。
///
/// 必须用 raw 字符串：否则 Dart 会先把 JSON 里的 `\/` 解释成自己的转义（Dart 对
/// 未识别转义取字符本身），反斜杠会在喂给 `jsonDecode` 之前就消失，夹具也就失去
/// 了「站点真实写法是转义斜杠」这条性质。
const String _chapterFixture = r'''
<html><head>
  <meta property="og:title" content="猎人游戏W - MYCOMIC - 我的漫画">
  <script type="application/ld+json">{"@context":"https:\/\/schema.org","@type":["BreadcrumbList","ComicIssue"],"itemListElement":[{"@type":"ListItem","position":1,"name":"漫画资料库","item":{"@type":"Thing","url":"https:\/\/mycomic.com\/cn\/comics","@id":"https:\/\/mycomic.com\/cn\/comics"}},{"@type":"ListItem","position":2,"name":"猎人游戏W","item":{"@type":"Thing","url":"https:\/\/mycomic.com\/cn\/comics\/55355","@id":"https:\/\/mycomic.com\/cn\/comics\/55355"}},{"@type":"ListItem","position":3,"name":"第01话","item":{"@type":"Thing","url":"https:\/\/mycomic.com\/cn\/chapters\/818144","@id":"https:\/\/mycomic.com\/cn\/chapters\/818144"}}],"issueNumber":1,"audience":{"@type":"Audience","name":"青年"},"author":[{"@type":"Person","name":"晴十ナツメグ"}],"countryOfOrigin":{"@type":"Country","name":"日本"},"datePublished":"2025-06-04T15:00:03+08:00","keywords":["百合","职场"],"position":1,"thumbnailUrl":"https:\/\/biccam.com\/comics\/55355-9e7018.jpg","description":"某段描述","image":"https:\/\/biccam.com\/comics\/55355-9e7018.jpg","name":"猎人游戏W - 第01话","url":"https:\/\/mycomic.com\/cn\/chapters\/818144"}</script>
</head><body>
  <img class="flag" src="https://biccam.com/img/flags/cn.png">
  <img class="page w-full mx-auto"
       src="https://biccam.com/chapters/818144/1-03ef91.jpg">
  <img class="page w-full mx-auto lozad"
       src="data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=="
       data-src="https://biccam.com/chapters/818144/2-1a2b3c.jpg">
  <img class="page w-full mx-auto lozad"
       src="https://biccam.com/img/placeholder.gif"
       data-src="https://biccam.com/chapters/818144/3-4d5e6f.jpg">
  <img class="page w-full mx-auto">
  <img class="page w-full mx-auto lozad"
       src="https://biccam.com/img/placeholder.gif">
  <img class="page w-full mx-auto"
       src="https://biccam.com/chapters/818144/1-03ef91.jpg">
</body></html>
''';

/// 阅读器页缺失 LD-JSON 的降级形态（站点改版 / 结构化数据被裁掉）。
///
/// `og:title` 保持站点真实形态（只有作品名），因此回退路径只能给出作品名 ——
/// 这**不是**理想结果，但必须是个确定的非空值：`Chapter.title` 驱动阅读器标题栏
/// 与连续阅读的章节分界标签，空串会让 UI 出现无名章节。本测试把这条降级行为钉住。
const String _chapterNoLdJsonFixture = '''
<html><head>
  <meta property="og:title" content="猎人游戏W - MYCOMIC - 我的漫画">
</head><body>
  <img class="page w-full mx-auto"
       src="https://biccam.com/chapters/818144/1-03ef91.jpg">
</body></html>
''';
