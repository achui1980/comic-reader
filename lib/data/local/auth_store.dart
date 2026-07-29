import 'dart:convert';

import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/local/secure_store.dart';

/// Stores authentication cookies/tokens per manga source.
/// Used for Cloudflare bypass and login-based auth.
///
/// Auth data (cookies/tokens) is sensitive, so it is persisted through
/// [SecureStore] (Keychain/Keystore on native, encrypted localStorage on web).
/// Any legacy plaintext data still living in [LocalStorage] under the `auth`
/// key is migrated into secure storage once on [init] and then removed.
class AuthStore {
  static const _storeKey = 'auth';

  final LocalStorage _storage;
  final SecureStore _secureStore;
  Map<String, Map<String, dynamic>> _cache = {};

  AuthStore({required LocalStorage storage, SecureStore? secureStore})
      : _storage = storage,
        _secureStore = secureStore ?? SecureStore();

  Future<void> init() async {
    // Prefer secure storage.
    final secureRaw = await _secureStore.read(_storeKey);
    if (secureRaw != null && secureRaw.isNotEmpty) {
      _cache = _decode(secureRaw);
      return;
    }

    // Fallback: migrate legacy plaintext data from LocalStorage (one-time).
    final legacy = await _storage.read(_storeKey);
    if (legacy != null && legacy.isNotEmpty) {
      _cache = Map<String, Map<String, dynamic>>.from(
        legacy.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map))),
      );
      await _persist();
      // Remove the plaintext copy after successful migration.
      await _storage.delete(_storeKey);
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
    await _secureStore.write(_storeKey, jsonEncode(_cache));
  }

  Map<String, Map<String, dynamic>> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
      );
    } catch (_) {
      return {};
    }
  }
}
