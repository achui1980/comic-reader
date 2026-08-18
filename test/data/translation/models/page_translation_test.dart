import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/models/page_translation.dart';
import 'package:comic_reader/data/translation/models/text_region.dart';

void main() {
  test('toJson/fromJson round-trip preserves all fields', () {
    final page = PageTranslation(
      sourceId: 'srcA',
      mangaId: 'mangaB',
      chapterId: 'chC',
      pageIndex: 3,
      regions: const [
        TextRegion(box: [1, 2, 3, 4], originalText: 'あ', translatedText: '啊'),
      ],
      translatedAt: 1700000000000,
    );
    final decoded = PageTranslation.fromJson(page.toJson());
    expect(decoded.sourceId, 'srcA');
    expect(decoded.mangaId, 'mangaB');
    expect(decoded.chapterId, 'chC');
    expect(decoded.pageIndex, 3);
    expect(decoded.translatedAt, 1700000000000);
    expect(decoded.regions.length, 1);
    expect(decoded.regions.first.originalText, 'あ');
    expect(decoded.regions.first.translatedText, '啊');
  });

  test('fromJson tolerates a missing regions list', () {
    final decoded = PageTranslation.fromJson({
      'sourceId': 's',
      'mangaId': 'm',
      'chapterId': 'c',
      'pageIndex': 0,
      'translatedAt': 0,
    });
    expect(decoded.regions, isEmpty);
  });
}
