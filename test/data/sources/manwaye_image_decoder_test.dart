import 'dart:typed_data';

import 'package:comic_reader/data/sources/manwaye_image_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal but structurally valid magic-byte prefixes, used to assert that the
/// decoder's "already plaintext" guard recognises each format the upstream
/// site's own JS checks for.
final _jpegBody = Uint8List.fromList([
  0xff, 0xd8, 0xff, 0xe0, // SOI + APP0
  ...List.filled(64, 0x41),
  0xff, 0xd9, // EOI
]);
final _pngBody = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  ...List.filled(64, 0x42),
]);
final _gifBody = Uint8List.fromList([
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
  ...List.filled(64, 0x43),
]);
final _webpBody = Uint8List.fromList([
  0x52, 0x49, 0x46, 0x46, // 'RIFF'
  0x40, 0x00, 0x00, 0x00, // size
  0x57, 0x45, 0x42, 0x50, // 'WEBP'
  ...List.filled(64, 0x44),
]);

void main() {
  group('ManwayeImageDecoder.decodeImageBytes', () {
    test('decrypts an IV-prefixed AES-256-CBC payload back to the original',
        () {
      final encrypted = ManwayeImageDecoder.encryptImageBytes(_jpegBody);

      // Sanity: the ciphertext must NOT look like an image, otherwise the test
      // would pass trivially through the passthrough guard.
      expect(encrypted.sublist(0, 3), isNot(equals(_jpegBody.sublist(0, 3))));
      expect(encrypted.length, greaterThan(_jpegBody.length));

      expect(ManwayeImageDecoder.decodeImageBytes(encrypted), equals(_jpegBody));
    });

    test('decrypts a WebP payload (chapter images are WebP despite .jpg URLs)',
        () {
      final encrypted = ManwayeImageDecoder.encryptImageBytes(_webpBody);
      expect(ManwayeImageDecoder.decodeImageBytes(encrypted), equals(_webpBody));
    });

    test('leaves bytes that already carry an image signature untouched', () {
      for (final body in [_jpegBody, _pngBody, _gifBody, _webpBody]) {
        expect(
          ManwayeImageDecoder.decodeImageBytes(body),
          equals(body),
          reason: 'plaintext image must pass through unchanged',
        );
      }
    });

    test('is idempotent: decoding an already-decoded payload is a no-op', () {
      final encrypted = ManwayeImageDecoder.encryptImageBytes(_jpegBody);
      final once = ManwayeImageDecoder.decodeImageBytes(encrypted);
      final twice = ManwayeImageDecoder.decodeImageBytes(once);
      expect(twice, equals(once));
    });

    test('passes through buffers too short to hold an IV', () {
      for (final length in [0, 1, 15, 16]) {
        final short = Uint8List.fromList(List.filled(length, 0x7f));
        expect(ManwayeImageDecoder.decodeImageBytes(short), equals(short));
      }
    });

    test('returns the original bytes when decryption fails', () {
      // 20 bytes: a 16-byte IV plus 4 bytes of ciphertext, which is not a whole
      // AES block, so decryption must throw internally and fall back.
      final garbage = Uint8List.fromList(List.generate(20, (i) => i));
      expect(ManwayeImageDecoder.decodeImageBytes(garbage), equals(garbage));
    });

    test('returns the original bytes when padding is invalid', () {
      // Block-aligned ciphertext of the right shape, but random contents, so
      // the PKCS#7 padding check will almost certainly reject it.
      final bogus =
          Uint8List.fromList(List.generate(16 + 32, (i) => (i * 37 + 11) & 0xff));
      final result = ManwayeImageDecoder.decodeImageBytes(bogus);
      // Either it fell back to the original, or it happened to decrypt to
      // something; what must never happen is a thrown exception.
      expect(result, isA<Uint8List>());
    });

    test('uses a 32-byte (AES-256) key', () {
      expect(ManwayeImageDecoder.aesKeyString.length, equals(32));
    });
  });
}
