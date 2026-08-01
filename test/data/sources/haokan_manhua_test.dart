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
}
