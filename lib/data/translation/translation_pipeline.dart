import 'dart:convert';
import 'dart:typed_data';

import 'package:comic_reader/core/ai/ai_client.dart';
import 'package:comic_reader/core/ai/ai_config.dart';

import 'manga_text_extractor.dart';
import 'models/page_translation.dart';
import 'models/text_region.dart';
import 'translation_cache_store.dart';
import 'translation_model_manager.dart';

/// Thrown by [TranslationPipeline.translatePage] when the app-wide AI
/// config is disabled or missing an API key.
class TranslationConfigException implements Exception {
  TranslationConfigException(this.message);
  final String message;
  @override
  String toString() => 'TranslationConfigException: $message';
}

const _systemPrompt = '你是专业的漫画翻译。将日文或韩文的漫画对话翻译成简体中文，'
    '要求自然、口语化，符合中文漫画阅读习惯，结合整页语境。'
    '严格按输入的序号返回，条数必须完全一致，只返回一个 JSON 数组，'
    '每个元素是对应序号气泡的中文译文字符串，不要任何解释或额外字段。';

String _buildUserPrompt(List<TextRegion> regions) {
  final buffer =
      StringBuffer('请翻译以下 ${regions.length} 个漫画气泡文字（按序号）：\n');
  for (var i = 0; i < regions.length; i++) {
    buffer.writeln('${i + 1}. ${regions[i].originalText}');
  }
  return buffer.toString();
}

/// Defensively extracts a JSON array of strings from an LLM reply that may
/// be wrapped in prose or a ```json fenced block. Returns null when no
/// array can be parsed out.
List<String>? parseJsonStringArray(String reply) {
  var text = reply.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('```')) {
    final firstNewline = text.indexOf('\n');
    if (firstNewline != -1) text = text.substring(firstNewline + 1);
    final fenceEnd = text.lastIndexOf('```');
    if (fenceEnd != -1) text = text.substring(0, fenceEnd);
    text = text.trim();
  }
  if (!text.startsWith('[')) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start != -1 && end > start) {
      text = text.substring(start, end + 1);
    }
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is List) {
      return decoded.map((e) => e?.toString() ?? '').toList();
    }
  } catch (_) {
    // ignore
  }
  return null;
}

/// Orchestrates: cache lookup -> on-device text extraction -> whole-page
/// LLM translation (via the app-wide BYOK [AiClient]) -> persistent cache
/// write.
class TranslationPipeline {
  TranslationPipeline({
    required this.extractor,
    required this.aiClient,
    required this.configStore,
    required this.cacheStore,
    required this.modelManager,
  });

  final MangaTextExtractor extractor;
  final AiClient aiClient;
  final AiConfigStore configStore;
  final TranslationCacheStore cacheStore;
  final TranslationModelManager modelManager;

  Future<PageTranslation> translatePage(
    String sourceId,
    String mangaId,
    String chapterId,
    int pageIndex,
    Uint8List imageBytes,
  ) async {
    final cached =
        await cacheStore.get(sourceId, mangaId, chapterId, pageIndex);
    if (cached != null) return cached;

    final config =
        configStore.isLoaded ? configStore.current : await configStore.load();
    if (!config.isUsable) {
      throw TranslationConfigException('AI 未启用或未配置 API Key');
    }

    await modelManager.ensureReady();
    final regions = await extractor.extract(imageBytes);

    final translatedRegions =
        regions.isEmpty ? regions : await _translate(config, regions);

    final result = PageTranslation(
      sourceId: sourceId,
      mangaId: mangaId,
      chapterId: chapterId,
      pageIndex: pageIndex,
      regions: translatedRegions,
      translatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await cacheStore.save(result);
    return result;
  }

  Future<List<TextRegion>> _translate(
      AiConfig config, List<TextRegion> regions) async {
    final reply = await aiClient.chat(
      config,
      [
        AiMessage.system(_systemPrompt),
        AiMessage.user(_buildUserPrompt(regions)),
      ],
      json: true,
      temperature: 0.3,
    );
    final translations = parseJsonStringArray(reply);
    return [
      for (var i = 0; i < regions.length; i++)
        regions[i].copyWith(
          translatedText: translations != null && i < translations.length
              ? translations[i]
              : null,
        ),
    ];
  }
}
