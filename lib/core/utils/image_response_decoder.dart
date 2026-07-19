import 'dart:convert';
import 'dart:typed_data';

import 'package:comic_reader/domain/entities/entities.dart';

Uint8List decodeImageResponseBytes(
  Uint8List bytes,
  ImageResponseEncoding responseEncoding,
) {
  if (responseEncoding == ImageResponseEncoding.binary ||
      _hasImageSignature(bytes)) {
    return bytes;
  }

  var encoded = utf8.decode(bytes).trim();
  if (encoded.startsWith('data:')) {
    final commaIndex = encoded.indexOf(',');
    if (commaIndex < 0) throw const FormatException('Invalid image data URI');
    encoded = encoded.substring(commaIndex + 1);
  }
  return Uint8List.fromList(base64Decode(encoded));
}

bool _hasImageSignature(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
    return true;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return true;
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return true;
  }
  return bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;
}
