import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;

/// AES-CBC decryption used by CopyManga.
///
/// [contentKey] format: first 16 characters are the IV (UTF-8),
/// remainder is hex-encoded ciphertext.
/// [key] is the AES key as a UTF-8 string.
String aesDecrypt(String contentKey, String key) {
  final iv = contentKey.substring(0, 16);
  final hexCiphertext = contentKey.substring(16);

  // Convert hex string to bytes
  final ciphertextBytes = _hexDecode(hexCiphertext);

  final encrypter = encrypt.Encrypter(
    encrypt.AES(
      encrypt.Key.fromUtf8(key),
      mode: encrypt.AESMode.cbc,
      padding: 'PKCS7',
    ),
  );

  final decrypted = encrypter.decrypt(
    encrypt.Encrypted(ciphertextBytes),
    iv: encrypt.IV.fromUtf8(iv),
  );

  return decrypted;
}

/// AES-128-CBC decryption where [payload] is base64-encoded and, once decoded,
/// its first 16 BYTES are the IV and the remainder is the ciphertext.
///
/// [key] is the AES key as a UTF-8 string (16 bytes for AES-128).
/// Padding is PKCS7 and the plaintext is decoded as UTF-8.
///
/// This is the scheme used by 51manga's `pic-v3.js`. It is deliberately
/// separate from [aesDecrypt], which uses 16 leading *characters* as the IV
/// plus *hex* ciphertext (the CopyManga scheme).
///
/// Throws [ArgumentError] if the decoded payload has no ciphertext.
String aesDecryptBase64PrefixedIv(String payload, String key) {
  final raw = base64.decode(payload);
  if (raw.length <= 16) {
    throw ArgumentError.value(
      payload,
      'payload',
      'decoded payload is ${raw.length} bytes; need more than 16 '
          '(16-byte IV prefix plus ciphertext)',
    );
  }

  final iv = encrypt.IV(Uint8List.sublistView(raw, 0, 16));
  final ciphertext = encrypt.Encrypted(Uint8List.sublistView(raw, 16));

  final encrypter = encrypt.Encrypter(
    encrypt.AES(
      encrypt.Key.fromUtf8(key),
      mode: encrypt.AESMode.cbc,
      padding: 'PKCS7',
    ),
  );

  return encrypter.decrypt(ciphertext, iv: iv);
}

Uint8List _hexDecode(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}
