import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Native secure storage backend backed by the platform secure enclave
/// (Keychain on iOS/macOS, Keystore/EncryptedSharedPreferences on Android,
/// libsecret on Linux, DPAPI on Windows).
class SecureBackend {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    // Local/debug macOS builds are typically unsigned or ad-hoc signed,
    // which lacks the entitlement required for the Data Protection Keychain
    // (kSecUseDataProtectionKeychain) and fails with errSecMissingEntitlement
    // (-34018). Falling back to the legacy Keychain API avoids that
    // requirement while still storing values securely in the login keychain.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<bool> contains(String key) => _storage.containsKey(key: key);
}
