import 'dart:convert';

import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/local/secure_store.dart';

/// Supported AI providers. The user brings their own API key (BYOK), so the
/// app never ships a key and never proxies through a first-party backend.
enum AiProvider {
  /// OpenAI-compatible Chat Completions API (`/v1/chat/completions`).
  /// Also covers the many OpenAI-compatible gateways (DeepSeek, Moonshot,
  /// OpenRouter, local llama.cpp/Ollama gateways, …) by overriding [baseUrl].
  openai,

  /// Google Gemini `generateContent` API.
  gemini,
}

extension AiProviderX on AiProvider {
  String get id {
    switch (this) {
      case AiProvider.openai:
        return 'openai';
      case AiProvider.gemini:
        return 'gemini';
    }
  }

  String get label {
    switch (this) {
      case AiProvider.openai:
        return 'OpenAI 兼容';
      case AiProvider.gemini:
        return 'Google Gemini';
    }
  }

  /// Default endpoint used when the user leaves [AiConfig.baseUrl] empty.
  String get defaultBaseUrl {
    switch (this) {
      case AiProvider.openai:
        return 'https://api.openai.com';
      case AiProvider.gemini:
        return 'https://generativelanguage.googleapis.com';
    }
  }

  /// A sensible default model so first-time users don't have to guess.
  String get defaultModel {
    switch (this) {
      case AiProvider.openai:
        return 'gpt-4o-mini';
      case AiProvider.gemini:
        return 'gemini-1.5-flash';
    }
  }

  static AiProvider fromId(String? id) {
    switch (id) {
      case 'gemini':
        return AiProvider.gemini;
      case 'openai':
      default:
        return AiProvider.openai;
    }
  }
}

/// Immutable AI configuration. The API key is intentionally NOT part of this
/// object's persisted JSON — it lives in [SecureStore]. This object only
/// carries the non-secret settings plus an in-memory [apiKey] convenience
/// field populated by [AiConfigStore.load].
class AiConfig {
  const AiConfig({
    this.enabled = false,
    this.provider = AiProvider.openai,
    this.baseUrl = '',
    this.model = '',
    this.apiKey = '',
  });

  /// Master switch. When false, [AiService] silently degrades to non-AI paths.
  final bool enabled;
  final AiProvider provider;

  /// Optional base URL override. Empty → [AiProviderX.defaultBaseUrl].
  final String baseUrl;

  /// Optional model override. Empty → [AiProviderX.defaultModel].
  final String model;

  /// The BYOK secret. Loaded from [SecureStore]; never serialized to JSON.
  final String apiKey;

  /// Effective (non-empty) base URL, trailing slash trimmed.
  String get effectiveBaseUrl {
    final raw = baseUrl.trim().isEmpty ? provider.defaultBaseUrl : baseUrl.trim();
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  /// Effective (non-empty) model name.
  String get effectiveModel =>
      model.trim().isEmpty ? provider.defaultModel : model.trim();

  /// Whether AI features can actually run (enabled + a key present).
  bool get isUsable => enabled && apiKey.trim().isNotEmpty;

  AiConfig copyWith({
    bool? enabled,
    AiProvider? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    return AiConfig(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.id,
        'baseUrl': baseUrl,
        'model': model,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    return AiConfig(
      enabled: json['enabled'] as bool? ?? false,
      provider: AiProviderX.fromId(json['provider'] as String?),
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
    );
  }
}

/// Persists [AiConfig]: non-secret fields go to [LocalStorage] under a single
/// JSON key; the API key goes to [SecureStore]. Mirrors the app's existing
/// store pattern (see AuthStore / SettingsStore).
class AiConfigStore {
  AiConfigStore({required LocalStorage storage, SecureStore? secureStore})
      : _storage = storage,
        _secureStore = secureStore ?? SecureStore();

  static const _storeKey = 'ai_config';
  static const _apiKeySecureKey = 'ai_api_key';

  final LocalStorage _storage;
  final SecureStore _secureStore;

  AiConfig _cache = const AiConfig();
  bool _loaded = false;

  /// Loads config (non-secret from LocalStorage + key from SecureStore).
  Future<AiConfig> load() async {
    final raw = await _storage.read(_storeKey);
    var config =
        raw == null ? const AiConfig() : AiConfig.fromJson(raw);
    final key = await _secureStore.read(_apiKeySecureKey) ?? '';
    config = config.copyWith(apiKey: key);
    _cache = config;
    _loaded = true;
    return config;
  }

  /// Cached config; call [load] first for accurate data.
  AiConfig get current => _cache;
  bool get isLoaded => _loaded;

  /// Persists config. The API key is stored separately in SecureStore and
  /// removed from secure storage entirely when empty.
  Future<void> save(AiConfig config) async {
    await _storage.write(_storeKey, config.toJson());
    final key = config.apiKey.trim();
    await _secureStore.write(_apiKeySecureKey, key.isEmpty ? null : key);
    _cache = config;
    _loaded = true;
  }

  /// Convenience: encode/decode helper kept for symmetry with other stores.
  String debugEncode() => jsonEncode(_cache.toJson());
}
