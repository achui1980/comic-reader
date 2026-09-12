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

    test('does not truncate titles containing "]" or escaped quotes', () {
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

/// 详情页夹具：OG meta + 状态徽章 + 作者/题材筛选链接 + x-data 内嵌章节 JSON
/// + 一段评论区垃圾长文本（用于证明简介不是「取最长文本」）。
const String _detailFixture = '''
<html><head>
  <meta property="og:title" content="猎人游戏W - MYCOMIC - 我的漫画">
  <meta property="og:description" content="被卷入死亡游戏的少年们的故事。">
  <meta property="og:image" content="https://biccam.com/comics/55355-9e7018.jpg">
</head><body>
  <span class="badge">连载中</span>
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
