import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/utils/crypto_utils.dart';

/// Base64 of `IV || AES-128-CBC(PKCS7)` produced offline with the real 51manga
/// key `9S8$vJnU2ANeSRoF` and the fixed IV `0123456789abcdef`.
/// Plaintext: `{"ok":true,"msg":"51manga"}`
///
/// Re-verify this vector independently of Dart (`tail -c +17` drops the
/// 16-byte IV prefix so only the ciphertext reaches openssl):
///
/// ```sh
/// echo -n 'MDEyMzQ1Njc4OWFiY2RlZg3jWjN/qoD6bo2MJ85/CU9d6d1jHc/1vHQsEOQqB99M' \
///   | base64 -d | tail -c +17 \
///   | openssl enc -d -aes-128-cbc \
///       -K 39533824764a6e5532414e6553526f46 \
///       -iv 30313233343536373839616263646566
/// # -> {"ok":true,"msg":"51manga"}
/// ```
///
/// `-K`/`-iv` are the hex forms of the UTF-8 key and IV above.
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
      //
      // The message predicate is essential, not decoration: RangeError and
      // IndexError both EXTEND ArgumentError, so a bare isA<ArgumentError>()
      // would also be satisfied by an accidental out-of-range crash and would
      // still pass if the length guard were deleted outright.
      expect(
        () => aesDecryptBase64PrefixedIv('MDEyMzQ1Njc4OWFiY2RlZg==', kPicKey),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(
              contains('decoded payload is 16 bytes'),
              contains('need more than 16'),
            ),
          ),
        ),
      );
    });

    test('throws a PKCS7 pad-check failure on a wrong key of the correct '
        'length', () {
      // The pad check is the ONLY thing that makes a wrong key throw here.
      // Encrypter.decrypt utf8-decodes with allowMalformed: true, so garbage
      // plaintext would otherwise come back as U+FFFD mojibake, not an error.
      expect(
        () => aesDecryptBase64PrefixedIv(kSimplePayload, 'wrongkey12345678'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('Invalid or corrupted pad block'),
          ),
        ),
      );
    });

    test('throws FormatException when the payload is not valid base64', () {
      // base64.decode (not our guard) rejects this, so the type is
      // FormatException rather than ArgumentError. Matters because Task 5
      // scrapes this payload out of HTML. Note base64.decode IS tolerant of
      // missing '=' padding and of the base64url alphabet, so this fixture
      // uses a character outside both alphabets.
      expect(
        () => aesDecryptBase64PrefixedIv('not!valid!base64', kPicKey),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid character'),
          ),
        ),
      );
    });
  });
}
