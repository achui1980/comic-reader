import 'secure_store_io.dart'
    if (dart.library.html) 'secure_store_web.dart' as platform;

/// Secure key/value store for sensitive data (API keys, activation tokens,
/// per-source auth tokens/cookies).
///
/// Native (iOS/Android/macOS/Linux/Windows): backed by the platform secure
/// enclave (Keychain / Keystore) via `flutter_secure_storage`.
///
/// Web: browsers have no true secure enclave, so values are AES-encrypted with
/// the `encrypt` package before being written to `localStorage`. This is a
/// best-effort obfuscation, NOT hardware-backed security.
///
/// All values are plain strings. Callers that need structured data should
/// JSON-encode before writing and JSON-decode after reading.
class SecureStore {
  final platform.SecureBackend _backend = platform.SecureBackend();

  /// Reads the value for [key], or `null` if absent.
  Future<String?> read(String key) => _backend.read(key);

  /// Writes [value] under [key]. Passing `null` deletes the key.
  Future<void> write(String key, String? value) {
    if (value == null) {
      return _backend.delete(key);
    }
    return _backend.write(key, value);
  }

  /// Deletes the value for [key] if present.
  Future<void> delete(String key) => _backend.delete(key);

  /// Whether [key] currently has a stored value.
  Future<bool> contains(String key) => _backend.contains(key);
}
