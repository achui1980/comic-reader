import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';

void main() {
  group('buildShardUrls', () {
    test('keeps break segment and produces correct shard extensions', () {
      const originalUrl =
          'https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/3751/13411/299297.jpg';
      final urls = Wu55ComicDecoder.buildShardUrls(originalUrl);

      expect(urls.length, 2);
      // Shard 0 keeps original host
      expect(urls[0], contains('bmigmij-wuwu.sqxxov.com'));
      // Shard 1 uses decremented subdomain host
      expect(urls[1], contains('bmigmih-wuwu.sqxxov.com'));
      // break_2 segment is preserved
      expect(urls[0], contains('/break_2/'));
      expect(urls[1], contains('/break_2/'));
    });

    test('replaces file extension with .b_0 and .b_1', () {
      const originalUrl =
          'https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/3751/13411/299297.jpg';
      final urls = Wu55ComicDecoder.buildShardUrls(originalUrl);

      expect(urls[0], contains('299297.b_0'));
      expect(urls[1], contains('299297.b_1'));
      // Should not contain original extension in filename
      expect(urls[0], isNot(contains('.jpg')));
      expect(urls[1], isNot(contains('.jpg')));
    });

    test('preserves /break_xxx/ path segment', () {
      const originalUrl =
          'https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/3751/13411/299297.jpg';
      final urls = Wu55ComicDecoder.buildShardUrls(originalUrl);

      expect(urls[0], contains('/break_2/'));
      expect(urls[1], contains('/break_2/'));
      // Path should still contain the rest
      expect(urls[0], contains('/static/upload/book/3751/13411/'));
      expect(urls[1], contains('/static/upload/book/3751/13411/'));
    });

    test('appends ?v=YYYYMMDD cache key', () {
      const originalUrl =
          'https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/3751/13411/299297.jpg';
      final urls = Wu55ComicDecoder.buildShardUrls(originalUrl);

      // Cache key should match today's date
      final now = DateTime.now();
      final expected =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      expect(urls[0], endsWith('?v=$expected'));
      expect(urls[1], endsWith('?v=$expected'));
    });

    test('handles URL with break- prefix variant', () {
      const originalUrl =
          'https://abcdefg-wuwu.sqxxov.com/break-5/images/test/file.png';
      final urls = Wu55ComicDecoder.buildShardUrls(originalUrl);

      expect(urls[0], contains('/break-5/'));
      expect(urls[1], contains('/break-5/'));
      expect(urls[0], contains('file.b_0'));
      expect(urls[1], contains('file.b_1'));
      // Host derivation: abcdefg → abcdefe (decrement last char of prefix by 2)
      expect(urls[0], contains('abcdefg-wuwu.sqxxov.com'));
      expect(urls[1], contains('abcdefe-wuwu.sqxxov.com'));
    });
  });

  group('getSliceCount', () {
    test('returns value in range 44-80', () {
      // Test a variety of inputs
      for (int bookId = 1; bookId <= 100; bookId++) {
        for (int page = 1; page <= 10; page++) {
          final count = Wu55ComicDecoder.getSliceCount(bookId, page);
          expect(count, greaterThanOrEqualTo(44));
          expect(count, lessThanOrEqualTo(80));
        }
      }
    });

    test('returns multiples of 4 starting at 44', () {
      for (int bookId = 1; bookId <= 50; bookId++) {
        for (int page = 1; page <= 5; page++) {
          final count = Wu55ComicDecoder.getSliceCount(bookId, page);
          expect((count - 44) % 4, 0);
        }
      }
    });

    test('is deterministic for same inputs', () {
      final count1 = Wu55ComicDecoder.getSliceCount(3751, 299297);
      final count2 = Wu55ComicDecoder.getSliceCount(3751, 299297);
      expect(count1, count2);
    });

    test('matches manual MD5 calculation', () {
      // Manual calculation for bookId=3751, pageNumber=13411
      const bookId = 3751;
      const pageNumber = 13411;
      final input = '${bookId + pageNumber}';
      final hash = md5.convert(utf8.encode(input)).toString();
      final lastChar = hash[hash.length - 1];
      final lastCharCode = lastChar.codeUnitAt(0);
      final expected = 44 + (lastCharCode % 10) * 4;

      final actual = Wu55ComicDecoder.getSliceCount(bookId, pageNumber);
      expect(actual, expected);
    });

    test('different inputs may produce different counts', () {
      // Collect unique values across many inputs
      final values = <int>{};
      for (int i = 0; i < 1000; i++) {
        values.add(Wu55ComicDecoder.getSliceCount(i, i + 1));
      }
      // Should produce more than one distinct value
      expect(values.length, greaterThan(1));
    });
  });

  group('restoreImage', () {
    test('restores JPEG header for type code 0', () {
      // Build fake decrypted data with type=0 (JPEG), subtype=1 (no unscramble)
      final fakeData = Uint8List(100);
      fakeData[0] = 0; // JPEG
      fakeData[1] = 1; // "other" - no unscramble
      // Fill rest with identifiable pattern
      for (int i = 2; i < 100; i++) {
        fakeData[i] = i & 0xFF;
      }

      final result = Wu55ComicDecoder.restoreImage(fakeData);

      // JPEG header: FF D8 FF E0 00 10 4A 46 49 46 00 01
      expect(result.imageBytes[0], 0xFF);
      expect(result.imageBytes[1], 0xD8);
      expect(result.imageBytes[2], 0xFF);
      expect(result.imageBytes[3], 0xE0);
      expect(result.imageBytes[4], 0x00);
      expect(result.imageBytes[5], 0x10);
      expect(result.imageBytes[6], 0x4A);
      expect(result.imageBytes[7], 0x46);
      expect(result.imageBytes[8], 0x49);
      expect(result.imageBytes[9], 0x46);
      expect(result.imageBytes[10], 0x00);
      expect(result.imageBytes[11], 0x01);
      expect(result.mimeType, 'image/jpeg');
      expect(result.needsUnscramble, false);
    });

    test('restores GIF header for type code 3', () {
      final fakeData = Uint8List(50);
      fakeData[0] = 3; // GIF
      fakeData[1] = 1; // "other"
      for (int i = 2; i < 50; i++) {
        fakeData[i] = i & 0xFF;
      }

      final result = Wu55ComicDecoder.restoreImage(fakeData);

      // GIF header: 47 49 46 38 39 61
      expect(result.imageBytes[0], 0x47);
      expect(result.imageBytes[1], 0x49);
      expect(result.imageBytes[2], 0x46);
      expect(result.imageBytes[3], 0x38);
      expect(result.imageBytes[4], 0x39);
      expect(result.imageBytes[5], 0x61);
      expect(result.mimeType, 'image/gif');
    });

    test('restores AVIF header for type code 4', () {
      final fakeData = Uint8List(50);
      fakeData[0] = 4; // AVIF
      fakeData[1] = 1; // "other"
      for (int i = 2; i < 50; i++) {
        fakeData[i] = i & 0xFF;
      }

      final result = Wu55ComicDecoder.restoreImage(fakeData);

      // AVIF header: 00 00 00 20 66 74 79 70 61 76 69 66
      expect(result.imageBytes[0], 0x00);
      expect(result.imageBytes[1], 0x00);
      expect(result.imageBytes[2], 0x00);
      expect(result.imageBytes[3], 0x20);
      expect(result.imageBytes[4], 0x66);
      expect(result.imageBytes[5], 0x74);
      expect(result.imageBytes[6], 0x79);
      expect(result.imageBytes[7], 0x70);
      expect(result.imageBytes[8], 0x61);
      expect(result.imageBytes[9], 0x76);
      expect(result.imageBytes[10], 0x69);
      expect(result.imageBytes[11], 0x66);
      expect(result.mimeType, 'image/avif');
    });

    test('extracts monga metadata when subtype is 0', () {
      final fakeData = Uint8List(100);
      fakeData[0] = 0; // JPEG
      fakeData[1] = 0; // "monga" - needs unscramble
      // bookId = 3751 → byte[2]*256 + byte[3]
      fakeData[2] = 3751 ~/ 256; // 14
      fakeData[3] = 3751 % 256; // 167
      // pageNumber = 299297 → byte[4]*16777216 + byte[5]*65536 + byte[6]*256 + byte[7]
      fakeData[4] = (299297 ~/ 16777216) & 0xFF; // 0
      fakeData[5] = (299297 ~/ 65536) & 0xFF; // 4
      fakeData[6] = (299297 ~/ 256) & 0xFF; // 144 → wait let me recalculate
      // 299297 = 0*16777216 + 4*65536 + 144*256 + 33? Let's verify:
      // 4*65536 = 262144, 299297-262144 = 37153, 37153/256 = 145.12..
      // Actually: 299297 / 65536 = 4.56..., floor = 4
      // 299297 - 4*65536 = 299297 - 262144 = 37153
      // 37153 / 256 = 145.12..., floor = 145
      // 37153 - 145*256 = 37153 - 37120 = 33
      fakeData[4] = 0;
      fakeData[5] = 4;
      fakeData[6] = 145;
      fakeData[7] = 33;
      // Fill rest
      for (int i = 8; i < 100; i++) {
        fakeData[i] = i & 0xFF;
      }

      final result = Wu55ComicDecoder.restoreImage(fakeData);

      expect(result.needsUnscramble, true);
      expect(result.bookId, 3751);
      expect(result.pageNumber, 299297);
    });

    test('throws on unknown type code', () {
      final fakeData = Uint8List(20);
      fakeData[0] = 99; // Unknown type
      fakeData[1] = 0;

      expect(
        () => Wu55ComicDecoder.restoreImage(fakeData),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on data too short', () {
      final fakeData = Uint8List(4);
      expect(
        () => Wu55ComicDecoder.restoreImage(fakeData),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('decryptAES', () {
    test('roundtrip: encrypt then decrypt returns original', () {
      final original = Uint8List.fromList(
        utf8.encode('Hello, wu55comic decryption test! This is a test payload.'),
      );

      final encrypted = Wu55ComicDecoder.encryptAES(original);
      final decrypted = Wu55ComicDecoder.decryptAES(encrypted);

      expect(decrypted, original);
    });

    test('roundtrip with binary data', () {
      // Binary data with all byte values
      final original = Uint8List(256);
      for (int i = 0; i < 256; i++) {
        original[i] = i;
      }

      final encrypted = Wu55ComicDecoder.encryptAES(original);
      final decrypted = Wu55ComicDecoder.decryptAES(encrypted);

      expect(decrypted, original);
    });

    test('encrypted data differs from original', () {
      final original = Uint8List.fromList(
        utf8.encode('Some plaintext data for encryption testing.'),
      );

      final encrypted = Wu55ComicDecoder.encryptAES(original);

      // Encrypted should not equal original
      expect(encrypted, isNot(equals(original)));
      // Encrypted should be padded to block size (16 bytes)
      expect(encrypted.length % 16, 0);
    });

    test('decryption with wrong data throws or returns garbage', () {
      // Random non-encrypted data that's aligned to block size
      final garbage = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        garbage[i] = (i * 7 + 3) & 0xFF;
      }

      // Decrypting garbage may throw (bad padding) or return garbage
      // Either outcome is acceptable - we just verify it doesn't crash the test
      try {
        final result = Wu55ComicDecoder.decryptAES(garbage);
        // If it doesn't throw, result should differ from a known good output
        expect(result, isNotNull);
      } catch (e) {
        // Padding error is expected with random data
        expect(e, isNotNull);
      }
    });

    test('roundtrip with large payload simulating image data', () {
      // Simulate a realistic image-like payload
      final original = Uint8List(4096);
      for (int i = 0; i < 4096; i++) {
        original[i] = (i * 13 + 7) & 0xFF;
      }

      final encrypted = Wu55ComicDecoder.encryptAES(original);
      final decrypted = Wu55ComicDecoder.decryptAES(encrypted);

      expect(decrypted, original);
    });
  });

  group('full decode pipeline', () {
    test('encrypts then decodes a fake JPEG monga image', () {
      // Build a fake "decrypted" image payload
      final payload = Uint8List(200);
      payload[0] = 0; // JPEG
      payload[1] = 0; // monga
      // bookId = 1000
      payload[2] = 1000 ~/ 256; // 3
      payload[3] = 1000 % 256; // 232
      // pageNumber = 500
      payload[4] = 0;
      payload[5] = 0;
      payload[6] = 500 ~/ 256; // 1
      payload[7] = 500 % 256; // 244
      for (int i = 8; i < 200; i++) {
        payload[i] = (i * 3) & 0xFF;
      }

      // Encrypt it as if it came from the server
      final encrypted = Wu55ComicDecoder.encryptAES(payload);

      // Now decode it through the full pipeline
      final result = Wu55ComicDecoder.decode(encrypted);

      expect(result.needsUnscramble, true);
      expect(result.bookId, 1000);
      expect(result.pageNumber, 500);
      expect(result.mimeType, 'image/jpeg');
      // Verify JPEG header was restored
      expect(result.imageBytes[0], 0xFF);
      expect(result.imageBytes[1], 0xD8);
    });
  });
}
