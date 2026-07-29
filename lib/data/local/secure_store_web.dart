// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Web secure storage backend.
///
/// Browsers have no hardware-backed secure enclave, so this is a best-effort
/// obfuscation: values are AES-CBC encrypted with an app-embedded key before
/// being written to `localStorage`. A per-record random IV is prepended to the
/// ciphertext (`ivBase64:ciphertextBase64`). This prevents casual inspection of
/// localStorage but is NOT resistant to a determined attacker who has the app
/// bundle (the key is derivable from client code).
class SecureBackend {
  static const _prefix = 'comic_reader_secure_';

  // App-embedded seed. Derived to a 32-byte AES key via SHA-256.
  // Not hardware security; obfuscation only for the web fallback.
  static const _seed = 'comic-reader::secure-store::v1::web-fallback-seed';

  static final encrypt.Encrypter _encrypter = encrypt.Encrypter(
    encrypt.AES(_deriveKey(), mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
  );

  static encrypt.Key _deriveKey() {
    final digest = sha256.convert(utf8.encode(_seed)).bytes;
    return encrypt.Key(Uint8List.fromList(digest));
  }

  Future<String?> read(String key) async {
    final raw = html.window.localStorage['$_prefix$key'];
    if (raw == null) return null;
    try {
      final parts = raw.split(':');
      if (parts.length != 2) return null;
      final iv = encrypt.IV.fromBase64(parts[0]);
      return _encrypter.decrypt64(parts[1], iv: iv);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(value, iv: iv);
    html.window.localStorage['$_prefix$key'] =
        '${iv.base64}:${encrypted.base64}';
  }

  Future<void> delete(String key) async {
    html.window.localStorage.remove('$_prefix$key');
  }

  Future<bool> contains(String key) async {
    return html.window.localStorage.containsKey('$_prefix$key');
  }
}
