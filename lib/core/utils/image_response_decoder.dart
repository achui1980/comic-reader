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

/// Returns whether [bytes] represent a structurally complete image as far as
/// cheap byte-level checks can tell.
///
/// The only case this rejects is a JPEG (starts with the SOI marker `FF D8`)
/// that is missing its End-Of-Image marker (`FF D9`). Some upstream image
/// files are stored truncated: the byte count matches Content-Length (so
/// transport-level truncation checks pass), but the JPEG scan data is
/// incomplete. A lenient decoder like the browser `<img>` tag still paints the
/// partial rows, but stricter decoders (Flutter/Skia) render the missing
/// bottom as a black band. Detecting the missing EOI lets the caller treat the
/// image as a load failure and surface a clear error instead of a half-black
/// image.
///
/// Non-JPEG bytes (PNG/GIF/WEBP), empty, or too-short buffers are treated as
/// "complete" — this function only guards the JPEG case observed in the wild.
bool isJpegBytesComplete(Uint8List bytes) {
  // Not a JPEG (or too short to even have an SOI marker) → not our concern.
  if (bytes.length < 2 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    return true;
  }
  // A JPEG must contain the EOI marker (FF D9). It is normally at the very end
  // but a few files carry trailing padding after it, so scan the tail region
  // (and, defensively, the whole buffer for short inputs) for FF D9.
  for (var i = bytes.length - 2; i >= 1; i--) {
    if (bytes[i] == 0xff && bytes[i + 1] == 0xd9) {
      return true;
    }
  }
  return false;
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
