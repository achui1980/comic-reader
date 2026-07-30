import 'package:comic_reader/data/local/local_storage.dart';

/// Stores authentication cookies/tokens per manga source.
/// Used for Cloudflare bypass and login-based auth.
class AuthStore {
  static const _storeKey = 'auth';

  final LocalStorage _storage;
  Map<String, Map<String, dynamic>> _cache = {};

  AuthStore({required LocalStorage storage}) : _storage = storage;

  Future<void> init() async {
    final raw = await _storage.read(_storeKey);
    if (raw != null && raw.isNotEmpty) {
      _cache = Map<String, Map<String, dynamic>>.from(
        raw.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map))),
      );
    }
  }

  /// Get stored extra data for a source (cookies, tokens, etc.)
  Map<String, dynamic>? getExtra(String sourceId) => _cache[sourceId];

  /// Get cookie string for a source
  String? getCookie(String sourceId) => _cache[sourceId]?['cookie'] as String?;

  /// Get user agent used during verification
  String? getUserAgent(String sourceId) => _cache[sourceId]?['userAgent'] as String?;

  /// Save extra data for a source
  Future<void> saveExtra(String sourceId, Map<String, dynamic> data) async {
    _cache[sourceId] = {...?_cache[sourceId], ...data};
    await _persist();
  }

  /// Clear all auth data for a source
  Future<void> clearSource(String sourceId) async {
    _cache.remove(sourceId);
    await _persist();
  }

  /// Clear all auth data
  Future<void> clearAll() async {
    _cache.clear();
    await _persist();
  }

  /// Check if a source has stored auth data
  bool hasAuth(String sourceId) => _cache.containsKey(sourceId) && _cache[sourceId]!.isNotEmpty;

  Future<void> _persist() async {
    await _storage.write(_storeKey, _cache);
  }
}
