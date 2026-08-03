import 'dart:typed_data';

import 'package:comic_reader/core/utils/image_response_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isJpegBytesComplete', () {
    test('returns true for a complete JPEG (FFD8 ... FFD9)', () {
      final bytes = Uint8List.fromList([
        0xff, 0xd8, // SOI
        0xff, 0xe0, 0x00, 0x10, // APP0 header (arbitrary body)
        0x01, 0x02, 0x03, 0x04,
        0xff, 0xd9, // EOI
      ]);
      expect(isJpegBytesComplete(bytes), isTrue);
    });

    test('returns true when FFD9 is followed by trailing padding bytes', () {
      final bytes = Uint8List.fromList([
        0xff, 0xd8,
        0x01, 0x02, 0x03,
        0xff, 0xd9, // EOI
        0x00, 0x00, 0x00, // trailing padding after EOI
      ]);
      expect(isJpegBytesComplete(bytes), isTrue);
    });

    test('returns false for a truncated JPEG (FFD8 without any FFD9)', () {
      final bytes = Uint8List.fromList([
        0xff, 0xd8, // SOI
        0xff, 0xe0, 0x00, 0x10,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, // scan data, cut off, no EOI
      ]);
      expect(isJpegBytesComplete(bytes), isFalse);
    });

    test('returns true for non-JPEG bytes (PNG) — not our concern', () {
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // PNG signature
        0x00, 0x00, 0x00, 0x0d,
      ]);
      expect(isJpegBytesComplete(png), isTrue);
    });

    test('returns true for empty or too-short bytes (nothing to reject)', () {
      expect(isJpegBytesComplete(Uint8List.fromList([])), isTrue);
      expect(isJpegBytesComplete(Uint8List.fromList([0xff])), isTrue);
    });

    test('returns false for JPEG header only (2 bytes, truncated)', () {
      expect(isJpegBytesComplete(Uint8List.fromList([0xff, 0xd8])), isFalse);
    });
  });
}
