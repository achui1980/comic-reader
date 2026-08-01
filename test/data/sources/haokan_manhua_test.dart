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
}
