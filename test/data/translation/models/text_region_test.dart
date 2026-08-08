import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/models/text_region.dart';

void main() {
  test('toJson/fromJson round-trip preserves all fields', () {
    const region = TextRegion(
      box: [10, 20, 100, 50],
      originalText: 'こんにちは',
      translatedText: '你好',
    );
    final decoded = TextRegion.fromJson(region.toJson());
    expect(decoded.box, [10, 20, 100, 50]);
    expect(decoded.originalText, 'こんにちは');
    expect(decoded.translatedText, '你好');
  });

  test('translatedText defaults to null when absent from JSON', () {
    final decoded = TextRegion.fromJson({
      'box': [0, 0, 1, 1],
      'originalText': 'x',
    });
    expect(decoded.translatedText, isNull);
  });

  test('copyWith sets translatedText without mutating the original', () {
    const region = TextRegion(box: [0, 0, 1, 1], originalText: 'x');
    final updated = region.copyWith(translatedText: 'y');
    expect(region.translatedText, isNull);
    expect(updated.translatedText, 'y');
    expect(updated.originalText, 'x');
    expect(updated.box, [0, 0, 1, 1]);
  });
}
