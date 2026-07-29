import 'dart:convert';

import 'package:comic_reader/core/ai/ai_client.dart';
import 'package:comic_reader/core/ai/ai_config.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:logging/logging.dart';

/// Result of parsing a natural-language search query into structured search
/// terms. The LLM only performs keyword/tag/intent extraction — it never
/// invents titles; real works come from source scraping downstream.
class SearchIntent {
  const SearchIntent({
    this.keywords = const [],
    this.tags = const [],
    this.excludes = const [],
  });

  final List<String> keywords;
  final List<String> tags;
  final List<String> excludes;

  bool get isEmpty => keywords.isEmpty && tags.isEmpty && excludes.isEmpty;

  /// The single best query string to feed a keyword search. Falls back to the
  /// first tag when no explicit keyword was extracted.
  String get primaryQuery {
    if (keywords.isNotEmpty) return keywords.first;
    if (tags.isNotEmpty) return tags.first;
    return '';
  }

  factory SearchIntent.fromJson(Map<String, dynamic> json) {
    List<String> list(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    return SearchIntent(
      keywords: list(json['keywords']),
      tags: list(json['tags']),
      excludes: list(json['excludes']),
    );
  }
}

/// AI-normalized metadata for a single manga (feature B, #16).
class AiMetadata {
  const AiMetadata({
    this.normalizedTags = const [],
    this.summary = '',
    this.originalTitle = '',
  });

  final List<String> normalizedTags;
  final String summary;
  final String originalTitle;

  bool get isEmpty =>
      normalizedTags.isEmpty && summary.isEmpty && originalTitle.isEmpty;

  Map<String, dynamic> toJson() => {
        'normalizedTags': normalizedTags,
        'summary': summary,
        'originalTitle': originalTitle,
      };

  factory AiMetadata.fromJson(Map<String, dynamic> json) {
    List<String> list(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    return AiMetadata(
      normalizedTags: list(json['normalizedTags']),
      summary: json['summary'] as String? ?? '',
      originalTitle: json['originalTitle'] as String? ?? '',
    );
  }
}

/// High-level AI orchestration: owns config loading, graceful degradation
/// (returns null when AI is unusable rather than throwing), a light in-memory
/// cache, and the two shipping features — natural-language search intent
/// parsing (#15) and metadata normalization (#16).
class AiService {
  AiService({required AiClient client, required AiConfigStore configStore})
      : _client = client,
        _configStore = configStore;

  final AiClient _client;
  final AiConfigStore _configStore;
  final _log = Logger('AiService');

  final Map<String, SearchIntent> _intentCache = {};

  /// Whether AI features are configured and usable right now.
  Future<bool> get isUsable async {
    final config = await _config();
    return config.isUsable;
  }

  Future<AiConfig> _config() async {
    if (_configStore.isLoaded) return _configStore.current;
    return _configStore.load();
  }

  /// Feature A (#15): parse a natural-language query into structured search
  /// terms. Returns null when AI is unusable or the call fails, so callers can
  /// degrade to a plain keyword search.
  Future<SearchIntent?> parseSearchIntent(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    if (_intentCache.containsKey(trimmed)) return _intentCache[trimmed];

    final config = await _config();
    if (!config.isUsable) return null;

    const system = '你是一个漫画搜索意图解析器。用户会用自然语言描述想看的漫画，'
        '你只负责从中抽取用于关键词搜索的结构化信息，绝不能编造具体作品名。'
        '严格只输出 JSON 对象，包含三个字段：'
        '"keywords"（用于站内搜索的核心关键词数组，通常是作品名/主题词，1-3 个）、'
        '"tags"（题材/风格标签数组，如 校园、恋爱、热血）、'
        '"excludes"（用户明确不想要的元素数组）。'
        '不要输出任何解释文字。';

    try {
      final reply = await _client.chat(
        config,
        [AiMessage.system(system), AiMessage.user(trimmed)],
        json: true,
      );
      final map = _parseJsonObject(reply);
      if (map == null) return null;
      final intent = SearchIntent.fromJson(map);
      if (intent.isEmpty) return null;
      _intentCache[trimmed] = intent;
      return intent;
    } catch (e) {
      _log.warning('parseSearchIntent failed: $e');
      return null;
    }
  }

  /// Feature B (#16): normalize a manga's metadata. Returns null when AI is
  /// unusable or the call fails. Caching to disk is handled by the caller
  /// (ai_metadata_store) so results persist across sessions.
  Future<AiMetadata?> normalizeMetadata(MangaDetail detail) async {
    final config = await _config();
    if (!config.isUsable) return null;

    const system = '你是一个漫画元数据整理助手。根据给定的漫画信息，输出规范化结果。'
        '严格只输出 JSON 对象，包含三个字段：'
        '"normalizedTags"（去重、归一化后的题材标签数组，使用简体中文通用标签）、'
        '"summary"（一句话到两句话的中文简介，若原简介已足够可精炼它，不得编造剧情）、'
        '"originalTitle"（作品原名/外文原名，若无法确定则留空字符串）。'
        '不要输出任何解释文字。';

    final payload = <String, dynamic>{
      'title': detail.title,
      'author': detail.author,
      'tags': detail.tags,
      'description': detail.description ?? '',
    };

    try {
      final reply = await _client.chat(
        config,
        [
          AiMessage.system(system),
          AiMessage.user(jsonEncode(payload)),
        ],
        json: true,
      );
      final map = _parseJsonObject(reply);
      if (map == null) return null;
      final meta = AiMetadata.fromJson(map);
      if (meta.isEmpty) return null;
      return meta;
    } catch (e) {
      _log.warning('normalizeMetadata failed: $e');
      return null;
    }
  }

  /// Defensively extracts a JSON object from an LLM reply that may be wrapped
  /// in prose or a ```json fenced block.
  Map<String, dynamic>? _parseJsonObject(String reply) {
    var text = reply.trim();
    if (text.isEmpty) return null;
    // Strip fenced code blocks if present.
    if (text.startsWith('```')) {
      final firstNewline = text.indexOf('\n');
      if (firstNewline != -1) text = text.substring(firstNewline + 1);
      final fenceEnd = text.lastIndexOf('```');
      if (fenceEnd != -1) text = text.substring(0, fenceEnd);
      text = text.trim();
    }
    // Fall back to the first balanced-looking {...} slice.
    if (!text.startsWith('{')) {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start != -1 && end > start) {
        text = text.substring(start, end + 1);
      }
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // ignore
    }
    return null;
  }
}
