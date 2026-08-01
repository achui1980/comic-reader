import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/haokan_manhua.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() {
  late HaokanManhua source;

  setUp(() {
    source = HaokanManhua();
  });

  group('HaokanManhua metadata and request builders', () {
    test('declares a non-adult haokan source with discovery filters', () {
      expect(source.id, 'haokan');
      expect(source.name, '好看漫画');
      expect(source.shortName, 'HK');
      expect(source.score, 3.5);
      expect(source.href, 'https://www.haokantxt.com');
      expect(source.isAdult, isFalse);
      expect(source.needsProxy, isFalse);
      expect(source.discoveryFilters.map((f) => f.name), ['tags', 'finish', 'order']);
      final tags = source.discoveryFilters[0];
      expect(tags.defaultValue, '');
      expect(tags.choices.first.value, ''); // 全部
      expect(tags.choices.map((c) => c.value), contains('6')); // 热血
      final finish = source.discoveryFilters[1];
      expect(finish.choices.map((c) => c.value), ['', '1', '2']);
      final order = source.discoveryFilters[2];
      expect(order.choices.map((c) => c.value), ['addtime', 'hits']);
    });
  });

  group('HaokanManhua discovery', () {
    test('builds a filtered category request with path segments', () {
      final config = source.prepareDiscoveryFetch(2, {
        'tags': '6',
        'finish': '2',
        'order': 'hits',
      });
      expect(config.url, 'https://www.haokantxt.com/category/tags/6/finish/2/order/hits/page/2');
      expect(config.method, HttpMethod.get);
    });

    test('builds a bare category request when no filters given', () {
      final config = source.prepareDiscoveryFetch(1, const {});
      expect(config.url, 'https://www.haokantxt.com/category/page/1');
    });

    test('parses category cards into summaries', () {
      const html = '''
      <div class="comic-list">
        <div class="comic-item">
          <a class="comic-cover" href="/comic_yirenzhixia.html">
            <img src="https://comic.5um.net/comic/cover/yirenzhixia.webp" />
            <span class="update-badge">连载中</span>
          </a>
          <h3><a href="/comic_yirenzhixia.html">一人之下</a></h3>
          <p class="comic-author">米二</p>
        </div>
      </div>
      ''';
      final results = source.parseDiscovery(html);
      expect(results, hasLength(1));
      expect(results.single.id, 'yirenzhixia');
      expect(results.single.sourceId, 'haokan');
      expect(results.single.title, '一人之下');
      expect(results.single.coverUrl, 'https://comic.5um.net/comic/cover/yirenzhixia.webp');
      expect(results.single.author, '米二');
    });

    test('skips cards without a resolvable slug', () {
      const html = '<div class="comic-list"><div class="comic-item"><a class="comic-cover" href="/notacomic"></a></div></div>';
      expect(source.parseDiscovery(html), isEmpty);
    });
  });

  group('HaokanManhua search', () {
    test('builds a path-form search request (page in path, keyword encoded)', () {
      final config = source.prepareSearchFetch('一人之下', 2, const {});
      expect(config.method, HttpMethod.get);
      expect(
        config.url,
        'https://www.haokantxt.com/search/${Uri.encodeComponent('一人之下')}/2',
      );
    });

    test('parses search result cards', () {
      const html = '''
      <div class="listbox"><div class="comic-list">
        <div class="comic-item">
          <a class="comic-cover" href="/comic_lianai.html">
            <img src="https://comic.5um.net/comic/cover/lianai.webp" />
          </a>
          <h3><a href="/comic_lianai.html">恋爱</a></h3>
          <p class="comic-author"></p>
        </div>
      </div></div>
      ''';
      final results = source.parseSearch(html);
      expect(results, hasLength(1));
      expect(results.single.id, 'lianai');
      expect(results.single.title, '恋爱');
    });
  });

  group('HaokanManhua manga info', () {
    test('builds detail request from slug', () {
      final config = source.prepareMangaInfoFetch('yirenzhixia');
      expect(config.url, 'https://www.haokantxt.com/comic_yirenzhixia.html');
      expect(config.method, HttpMethod.get);
    });

    test('does not request a separate chapter list', () {
      expect(source.prepareChapterListFetch('yirenzhixia', 1), isNull);
    });

    test('parses detail via ld+json and embedded chapters with numeric mangaId', () {
      const html = '''
      <html><head>
      <script type="application/ld+json">
      {"@type":"Book","name":"《一人之下》","author":{"name":"米二"},
       "description":"道术漫画","genre":"玄幻",
       "image":"https://comic.5um.net/comic/cover/yirenzhixia.webp",
       "workExample":{"bookEdition":"第100话","datePublished":"2026-07-02"}}
      </script></head>
      <body>
        <a data-id="13871" class="btn--collect"></a>
        <div class="comic-tags"><span class="tag">玄幻</span><span class="tag">连载</span></div>
        <div class="chapter-list" id="chapter-list">
          <div class="chapter-item"><a href="/chapter_13871_4992.html">第1话</a></div>
          <div class="chapter-item"><a href="/chapter_13871_4993.html">第2话</a></div>
        </div>
      </body></html>
      ''';
      final detail = source.parseMangaInfo(html, 'yirenzhixia');
      expect(detail.id, 'yirenzhixia');
      expect(detail.sourceId, 'haokan');
      expect(detail.title, '一人之下'); // 书名号已 strip
      expect(detail.author, '米二');
      expect(detail.description, '道术漫画');
      expect(detail.coverUrl, 'https://comic.5um.net/comic/cover/yirenzhixia.webp');
      expect(detail.status, MangaStatus.ongoing);
      expect(detail.latestChapter, '第100话');
      expect(detail.chapters.map((c) => c.id), ['4992', '4993']);
      expect(detail.chapters.map((c) => c.mangaId), ['13871', '13871']);
      expect(detail.chapters.first.title, '第1话');
      expect(detail.chapters.first.href, 'https://www.haokantxt.com/chapter_13871_4992.html');
    });

    test('falls back to DOM when ld+json is absent', () {
      const html = '''
      <html><body>
        <a data-id="13871"></a>
        <div class="comic-meta-info"><h1>《测试漫画》</h1></div>
        <div class="comic-cover-large"><img src="https://comic.5um.net/comic/cover/test.webp" /></div>
        <div class="comic-tags"><span class="tag">热血</span><span class="tag">完结</span></div>
        <div class="comic-description"><p>简介文本</p></div>
        <div class="chapter-list" id="chapter-list">
          <div class="chapter-item"><a href="/chapter_13871_5000.html">第1话</a></div>
        </div>
      </body></html>
      ''';
      final detail = source.parseMangaInfo(html, 'test');
      expect(detail.title, '测试漫画');
      expect(detail.coverUrl, 'https://comic.5um.net/comic/cover/test.webp');
      expect(detail.description, '简介文本');
      expect(detail.status, MangaStatus.completed);
      expect(detail.chapters.single.id, '5000');
    });

    test('falls back to slug for chapter mangaId when numeric id missing', () {
      const html = '''
      <html><body>
        <div class="comic-meta-info"><h1>无id漫画</h1></div>
        <div class="chapter-list" id="chapter-list"></div>
      </body></html>
      ''';
      final detail = source.parseMangaInfo(html, 'noidmanga');
      expect(detail.title, '无id漫画');
      expect(detail.chapters, isEmpty);
    });
  });
}
