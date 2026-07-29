import 'dart:convert';

import 'package:comic_reader/core/ai/ai_config.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:dio/dio.dart' show ResponseType;
import 'package:logging/logging.dart';

/// A single chat message in the provider-agnostic format.
class AiMessage {
  const AiMessage({required this.role, required this.content});

  /// One of: `system`, `user`, `assistant`.
  final String role;
  final String content;

  static const roleSystem = 'system';
  static const roleUser = 'user';
  static const roleAssistant = 'assistant';

  factory AiMessage.system(String content) =>
      AiMessage(role: roleSystem, content: content);
  factory AiMessage.user(String content) =>
      AiMessage(role: roleUser, content: content);
}

/// Thrown when an AI request fails at the transport or protocol level.
class AiClientException implements Exception {
  AiClientException(this.message);
  final String message;
  @override
  String toString() => 'AiClientException: $message';
}

/// Low-level provider adapter. Turns provider-agnostic chat requests into the
/// right [FetchConfig] for the configured provider, sends them through the
/// single app-wide [HttpClient] (so proxy / CORS routing is reused), and
/// extracts the assistant text from the provider-specific response shape.
class AiClient {
  AiClient({required HttpClient httpClient}) : _httpClient = httpClient;

  final HttpClient _httpClient;
  final _log = Logger('AiClient');

  /// Sends [messages] and returns the assistant's reply text.
  ///
  /// When [json] is true, providers are asked to emit a JSON object
  /// (OpenAI `response_format`, Gemini `responseMimeType`). Callers must still
  /// tolerate non-JSON output and parse defensively.
  Future<String> chat(
    AiConfig config,
    List<AiMessage> messages, {
    bool json = false,
    double temperature = 0.2,
  }) async {
    if (config.apiKey.trim().isEmpty) {
      throw AiClientException('未配置 API Key');
    }
    switch (config.provider) {
      case AiProvider.openai:
        return _chatOpenAi(config, messages, json: json, temperature: temperature);
      case AiProvider.gemini:
        return _chatGemini(config, messages, json: json, temperature: temperature);
    }
  }

  Future<String> _chatOpenAi(
    AiConfig config,
    List<AiMessage> messages, {
    required bool json,
    required double temperature,
  }) async {
    final url = '${config.effectiveBaseUrl}/v1/chat/completions';
    final body = <String, dynamic>{
      'model': config.effectiveModel,
      'temperature': temperature,
      'messages': messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList(),
      if (json) 'response_format': {'type': 'json_object'},
    };
    final response = await _execute(FetchConfig(
      url: url,
      method: HttpMethod.post,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey.trim()}',
      },
      body: jsonEncode(body),
      responseType: ResponseType.json,
      timeout: const Duration(seconds: 45),
    ));
    final data = _asMap(response.data);
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = _asMap(choices.first)['message'];
      final content = _asMap(message)['content'];
      if (content is String && content.trim().isNotEmpty) {
        return content;
      }
    }
    throw AiClientException('AI 响应格式异常（OpenAI）');
  }

  Future<String> _chatGemini(
    AiConfig config,
    List<AiMessage> messages, {
    required bool json,
    required double temperature,
  }) async {
    // Gemini has no dedicated system role; fold system prompts into the first
    // user turn as `systemInstruction`.
    final systemText = messages
        .where((m) => m.role == AiMessage.roleSystem)
        .map((m) => m.content)
        .join('\n')
        .trim();
    final contents = messages
        .where((m) => m.role != AiMessage.roleSystem)
        .map((m) => {
              'role': m.role == AiMessage.roleAssistant ? 'model' : 'user',
              'parts': [
                {'text': m.content}
              ],
            })
        .toList();
    final url =
        '${config.effectiveBaseUrl}/v1beta/models/${config.effectiveModel}:generateContent';
    final body = <String, dynamic>{
      'contents': contents,
      if (systemText.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemText}
          ]
        },
      'generationConfig': {
        'temperature': temperature,
        if (json) 'responseMimeType': 'application/json',
      },
    };
    final response = await _execute(FetchConfig(
      url: url,
      method: HttpMethod.post,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': config.apiKey.trim(),
      },
      body: jsonEncode(body),
      responseType: ResponseType.json,
      timeout: const Duration(seconds: 45),
    ));
    final data = _asMap(response.data);
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final content = _asMap(candidates.first)['content'];
      final parts = _asMap(content)['parts'];
      if (parts is List && parts.isNotEmpty) {
        final text = _asMap(parts.first)['text'];
        if (text is String && text.trim().isNotEmpty) {
          return text;
        }
      }
    }
    throw AiClientException('AI 响应格式异常（Gemini）');
  }

  Future<dynamic> _execute(FetchConfig config) async {
    try {
      return await _httpClient.execute(config);
    } on AiClientException {
      rethrow;
    } catch (e) {
      _log.warning('AI request failed: $e');
      throw AiClientException('AI 请求失败：$e');
    }
  }

  /// Normalizes a Dio response body which may already be a decoded Map or a
  /// raw JSON String (depending on the CORS proxy / responseType path).
  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        // fall through
      }
    }
    return const {};
  }
}
