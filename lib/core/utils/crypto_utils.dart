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

Uint8List _hexDecode(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}
