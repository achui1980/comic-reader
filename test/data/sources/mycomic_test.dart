import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/mycomic.dart';

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
}

/// 列表页夹具：1 个导航「随机漫画」锚点（无 img，须被滤除）+ 2 张真卡片。
const String _listFixture = '''
<html><body>
  <nav>
    <a href="https://mycomic.com/cn/comics/12345"
       :href="comicUrl({id: Math.floor(Math.random() * maxComicId)})">随机漫画</a>
  </nav>
  <div class="grid grid-cols-3 md:grid-cols-6">
    <div class="group relative">
      <a href="https://mycomic.com/cn/comics/55355">
        <img src="https://biccam.com/comics/55355-9e7018.jpg" alt="猎人游戏W">
        <div class="absolute inset-x-0 bottom-0"><div>第07话</div></div>
      </a>
      <div class="mt-2 text-center"><div data-flux-subheading>猎人游戏W</div></div>
    </div>
    <div class="group relative">
      <a href="https://mycomic.com/cn/comics/40001">
        <img src="https://biccam.com/img/placeholder.gif"
             data-src="https://biccam.com/comics/40001-aa11bb.jpg" alt="测试漫画">
      </a>
    </div>
  </div>
</body></html>
''';
