import 'package:comic_reader/data/local/local_storage.dart';

/// Stores authentication cookies/tokens per manga source.
/// Used for Cloudflare bypass and login-based auth.
class AuthStore {
  final LocalStorage _storage;
  Map<String, Map<String, dynamic>> _cache = {};

  AuthStore({required LocalStorage storage}) : _storage = storage;

  Future<void> init() async {
    final data = await _storage.read('auth');
    if (data != null) {
      _cache = Map<String, Map<String, dynamic>>.from(
        data.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map))),
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
    await _storage.write('auth', _cache);
  }

  /// Clear all auth data for a source
  Future<void> clearSource(String sourceId) async {
    _cache.remove(sourceId);
    await _storage.write('auth', _cache);
  }

  /// Clear all auth data
  Future<void> clearAll() async {
    _cache.clear();
    await _storage.write('auth', _cache);
  }

  /// Check if a source has stored auth data
  bool hasAuth(String sourceId) => _cache.containsKey(sourceId) && _cache[sourceId]!.isNotEmpty;
}
