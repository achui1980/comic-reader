import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/translation_cache_store.dart';
import 'package:comic_reader/data/translation/models/page_translation.dart';
import 'package:comic_reader/data/translation/models/text_region.dart';

void main() {
  late Directory tempDir;
  late TranslationCacheStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('translation_cache_test_');
    store = TranslationCacheStore(baseDirResolver: () async => tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('get returns null when nothing cached', () async {
    expect(await store.get('src', 'manga', 'ch1', 0), isNull);
  });

  test('save then get round-trips the same data', () async {
    final page = PageTranslation(
      sourceId: 'src',
      mangaId: 'manga',
      chapterId: 'ch1',
      pageIndex: 2,
      regions: const [
        TextRegion(box: [1, 2, 3, 4], originalText: 'あ', translatedText: '啊'),
      ],
      translatedAt: 123,
    );
    await store.save(page);
    final loaded = await store.get('src', 'manga', 'ch1', 2);
    expect(loaded, isNotNull);
    expect(loaded!.regions.single.originalText, 'あ');
    expect(loaded.regions.single.translatedText, '啊');
    expect(loaded.pageIndex, 2);
  });

  test('save writes one file per page under sourceId/mangaId/chapterId',
      () async {
    final page = PageTranslation(
      sourceId: 'src',
      mangaId: 'manga',
      chapterId: 'ch1',
      pageIndex: 5,
      regions: const [],
      translatedAt: 1,
    );
    await store.save(page);
    final file =
        File('${tempDir.path}/translation_cache/src/manga/ch1/5.json');
    expect(await file.exists(), isTrue);
  });

  test('clearChapter deletes all cached pages for that chapter',
      () async {
    final page = PageTranslation(
      sourceId: 'src',
      mangaId: 'manga',
      chapterId: 'ch1',
      pageIndex: 0,
      regions: const [],
      translatedAt: 1,
    );
    await store.save(page);
    expect(await store.get('src', 'manga', 'ch1', 0), isNotNull);
    await store.clearChapter('src', 'manga', 'ch1');
    expect(await store.get('src', 'manga', 'ch1', 0), isNull);
  });

  test('get returns null when the cached file has invalid JSON',
      () async {
    final dir = Directory('${tempDir.path}/translation_cache/src/manga/ch1');
    await dir.create(recursive: true);
    await File('${dir.path}/9.json').writeAsString('not json');
    expect(await store.get('src', 'manga', 'ch1', 9), isNull);
  });

  test('clearAll removes every cached page', () async {
    await store.save(const PageTranslation(
      sourceId: 's',
      mangaId: 'm',
      chapterId: 'c',
      pageIndex: 0,
      regions: [],
      translatedAt: 1,
    ));
    await store.save(const PageTranslation(
      sourceId: 's2',
      mangaId: 'm2',
      chapterId: 'c2',
      pageIndex: 3,
      regions: [],
      translatedAt: 1,
    ));

    await store.clearAll();

    expect(await store.get('s', 'm', 'c', 0), isNull);
    expect(await store.get('s2', 'm2', 'c2', 3), isNull);
  });

  test('clearAll is a no-op when the cache directory does not exist',
      () async {
    await store.clearAll();
    await expectLater(store.clearAll(), completes);
  });
}
