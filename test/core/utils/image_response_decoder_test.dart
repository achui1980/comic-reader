import 'dart:convert';
import 'dart:typed_data';

import 'package:comic_reader/core/utils/image_response_decoder.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeImageResponseBytes', () {
    final jpegBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]);

    test('keeps binary image bytes unchanged', () {
      expect(
        decodeImageResponseBytes(
          jpegBytes,
          ImageResponseEncoding.base64OrBinary,
        ),
        orderedEquals(jpegBytes),
      );
    });

    test('decodes a Base64 image response', () {
      final encoded = Uint8List.fromList(utf8.encode(base64Encode(jpegBytes)));

      expect(
        decodeImageResponseBytes(
          encoded,
          ImageResponseEncoding.base64OrBinary,
        ),
        orderedEquals(jpegBytes),
      );
    });
  });
}
