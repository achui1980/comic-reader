import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/utils/crypto_utils.dart';

/// Base64 of `IV || AES-128-CBC(PKCS7)` produced offline with the real 51manga
/// key `9S8$vJnU2ANeSRoF` and the fixed IV `0123456789abcdef`.
/// Plaintext: `{"ok":true,"msg":"51manga"}`
const String kSimplePayload =
    'MDEyMzQ1Njc4OWFiY2RlZg3jWjN/qoD6bo2MJ85/CU9d6d1jHc/1vHQsEOQqB99M';

const String kPicKey = r'9S8$vJnU2ANeSRoF';

void main() {
  group('aesDecryptBase64PrefixedIv', () {
    test('decrypts a known payload to its known plaintext', () {
      expect(
        aesDecryptBase64PrefixedIv(kSimplePayload, kPicKey),
        '{"ok":true,"msg":"51manga"}',
      );
    });

    test('throws when the payload is 16 bytes or shorter (no ciphertext)', () {
      // 16 bytes: IV only, nothing left to decrypt.
      expect(
        () => aesDecryptBase64PrefixedIv('MDEyMzQ1Njc4OWFiY2RlZg==', kPicKey),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on a wrong key rather than returning garbage', () {
      expect(
        () => aesDecryptBase64PrefixedIv(kSimplePayload, 'wrongkey12345678'),
        throwsA(isA<Object>()),
      );
    });
  });
}
