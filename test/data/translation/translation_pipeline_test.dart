import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/core/ai/ai_client.dart';
import 'package:comic_reader/core/ai/ai_config.dart';
import 'package:comic_reader/data/translation/manga_text_extractor.dart';
import 'package:comic_reader/data/translation/models/page_translation.dart';
import 'package:comic_reader/data/translation/models/text_region.dart';
import 'package:comic_reader/data/translation/translation_cache_store.dart';
import 'package:comic_reader/data/translation/translation_model_manager.dart';
import 'package:comic_reader/data/translation/translation_pipeline.dart';

class MockMangaTextExtractor extends Mock implements MangaTextExtractor {}

class MockAiClient extends Mock implements AiClient {}

class MockAiConfigStore extends Mock implements AiConfigStore {}

class MockTranslationCacheStore extends Mock implements TranslationCacheStore {}

class MockTranslationModelManager extends Mock
    implements TranslationModelManager {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AiConfig());
    registerFallbackValue(<AiMessage>[]);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const PageTranslation(
      sourceId: '',
      mangaId: '',
      chapterId: '',
      pageIndex: 0,
      regions: [],
      translatedAt: 0,
    ));
  });

  late MockMangaTextExtractor extractor;
  late MockAiClient aiClient;
  late MockAiConfigStore configStore;
  late MockTranslationCacheStore cacheStore;
  late MockTranslationModelManager modelManager;
  late TranslationPipeline pipeline;
  const usableConfig = AiConfig(enabled: true, apiKey: 'k');

  setUp(() {
    extractor = MockMangaTextExtractor();
    aiClient = MockAiClient();
    configStore = MockAiConfigStore();
    cacheStore = MockTranslationCacheStore();
    modelManager = MockTranslationModelManager();
    pipeline = TranslationPipeline(
      extractor: extractor,
      aiClient: aiClient,
      configStore: configStore,
      cacheStore: cacheStore,
      modelManager: modelManager,
    );

    when(() => configStore.isLoaded).thenReturn(true);
    when(() => configStore.current).thenReturn(usableConfig);
    when(() => modelManager.ensureReady()).thenAnswer((_) async {});
    when(() => cacheStore.save(any())).thenAnswer((_) async {});
  });

  test('returns the cached result without touching extractor/aiClient',
      () async {
    final cached = PageTranslation(
      sourceId: 's',
      mangaId: 'm',
      chapterId: 'c',
      pageIndex: 0,
      regions: const [],
      translatedAt: 1,
    );
    when(() => cacheStore.get('s', 'm', 'c', 0))
        .thenAnswer((_) async => cached);

    final result =
        await pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0));

    expect(result, same(cached));
    verifyNever(() => extractor.extract(any()));
    verifyNever(() => aiClient.chat(any(), any(),
        json: any(named: 'json'), temperature: any(named: 'temperature')));
  });

  test('throws TranslationConfigException when AI is not usable', () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => configStore.current)
        .thenReturn(const AiConfig(enabled: false));

    await expectLater(
      pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0)),
      throwsA(isA<TranslationConfigException>()),
    );
  });

  test('extracts regions, translates via aiClient, and caches the result',
      () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => extractor.extract(any())).thenAnswer((_) async => const [
          TextRegion(box: [0, 0, 1, 1], originalText: 'あ'),
          TextRegion(box: [1, 1, 1, 1], originalText: 'い'),
        ]);
    when(() => aiClient.chat(any(), any(),
            json: any(named: 'json'), temperature: any(named: 'temperature')))
        .thenAnswer((_) async => '["啊", "咦"]');

    final result =
        await pipeline.translatePage('s', 'm', 'c', 7, Uint8List(0));

    expect(result.regions.length, 2);
    expect(result.regions[0].translatedText, '啊');
    expect(result.regions[1].translatedText, '咦');
    expect(result.pageIndex, 7);
    verify(() => cacheStore.save(any())).called(1);
  });

  test(
      'mismatched reply length leaves missing entries with null translatedText',
      () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => extractor.extract(any())).thenAnswer((_) async => const [
          TextRegion(box: [0, 0, 1, 1], originalText: 'あ'),
          TextRegion(box: [1, 1, 1, 1], originalText: 'い'),
        ]);
    when(() => aiClient.chat(any(), any(),
            json: any(named: 'json'), temperature: any(named: 'temperature')))
        .thenAnswer((_) async => '["啊"]');

    final result =
        await pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0));

    expect(result.regions[0].translatedText, '啊');
    expect(result.regions[1].translatedText, isNull);
  });

  test('empty extraction result skips the LLM call and caches an empty page',
      () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => extractor.extract(any())).thenAnswer((_) async => const []);

    final result =
        await pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0));

    expect(result.regions, isEmpty);
    verifyNever(() => aiClient.chat(any(), any(),
        json: any(named: 'json'), temperature: any(named: 'temperature')));
    verify(() => cacheStore.save(any())).called(1);
  });

  test('aiClient failure propagates and the page is not cached', () async {
    when(() => cacheStore.get(any(), any(), any(), any()))
        .thenAnswer((_) async => null);
    when(() => extractor.extract(any())).thenAnswer((_) async => const [
          TextRegion(box: [0, 0, 1, 1], originalText: 'あ'),
        ]);
    when(() => aiClient.chat(any(), any(),
            json: any(named: 'json'), temperature: any(named: 'temperature')))
        .thenThrow(AiClientException('boom'));

    await expectLater(
      pipeline.translatePage('s', 'm', 'c', 0, Uint8List(0)),
      throwsA(isA<AiClientException>()),
    );
    verifyNever(() => cacheStore.save(any()));
  });
}
