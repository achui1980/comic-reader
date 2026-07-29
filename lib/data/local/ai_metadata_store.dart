import 'package:comic_reader/core/ai/ai_service.dart';
import 'local_storage.dart';

/// Persistent cache of AI-normalized metadata, keyed by `${sourceId}_${mangaId}`.
///
/// Storage format (key='ai_metadata'):
///   { '<sourceId>_<mangaId>': AiMetadata.toJson(), ... }
///
/// The normalization is expensive (an LLM round-trip) and its result is stable
/// for a given manga, so entries are cached indefinitely. Callers should look
/// up [get] before invoking [AiService.normalizeMetadata], and [save] the
/// result afterwards.
class AiMetadataStore {
  final LocalStorage _storage;
  static const _key = 'ai_metadata';

  Map<String, AiMetadata>? _cache;

  AiMetadataStore({required LocalStorage storage}) : _storage = storage;

  String _entryKey(String sourceId, String mangaId) => '${sourceId}_$mangaId';

  Future<Map<String, AiMetadata>> _getData() async {
    if (_cache != null) return _cache!;
    final raw = await _storage.read(_key);
    if (raw == null) {
      _cache = {};
      return _cache!;
    }
    final result = <String, AiMetadata>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is Map) {
        result[entry.key] =
            AiMetadata.fromJson(Map<String, dynamic>.from(value));
      }
    }
    _cache = result;
    return _cache!;
  }

  Future<void> init() async {
    await _getData();
  }

  /// Return cached AI metadata for a manga, or null if not yet normalized.
  Future<AiMetadata?> get(String sourceId, String mangaId) async {
    final data = await _getData();
    return data[_entryKey(sourceId, mangaId)];
  }

  /// Persist AI metadata for a manga (overwrites any prior entry).
  Future<void> save(String sourceId, String mangaId, AiMetadata metadata) async {
    final data = await _getData();
    data[_entryKey(sourceId, mangaId)] = metadata;
    _cache = data;
    await _persist();
  }

  /// Remove a cached entry (e.g. to force re-normalization).
  Future<void> remove(String sourceId, String mangaId) async {
    final data = await _getData();
    data.remove(_entryKey(sourceId, mangaId));
    _cache = data;
    await _persist();
  }

  Future<void> clearAll() async {
    _cache = {};
    await _storage.write(_key, {});
  }

  Future<void> _persist() async {
    final data = _cache ?? {};
    final json = <String, dynamic>{
      for (final entry in data.entries) entry.key: entry.value.toJson(),
    };
    await _storage.write(_key, json);
  }
}
