import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt_pkg;

import 'package:comic_reader/core/utils/image_response_decoder.dart';

/// Decrypts the image payloads served by manwaye.cc (漫蛙漫画).
///
/// The site stores every image — covers *and* chapter pages — AES-256-CBC
/// encrypted at rest. Requests return HTTP 200 with `Content-Type: image/jpeg`,
/// but the body is ciphertext, so a decoder like Flutter/Skia fails with
/// "Invalid image data". The site's own front-end decrypts in the browser
/// (`/static/assets/js/base.js`, `BaseUtil.getSecureImageUrl`) before handing
/// the bytes to an `<img>` tag; this class is the Dart port of that routine.
///
/// Payload layout:
///
/// ```text
/// [ 16-byte IV ][ AES-256-CBC ciphertext, PKCS#7 padded ]
/// ```
///
/// The key is a hardcoded 32-character ASCII string shipped in the site's JS.
///
/// Two behaviours are deliberately copied from the upstream implementation and
/// are what make this transform safe to apply on paths that may receive
/// already-decrypted bytes:
///
///  * **Self-detecting.** If the payload already starts with a known image
///    signature it is returned untouched. Because a successful decryption
///    always yields such a signature, the transform is idempotent.
///  * **Fail-open.** Any error (short buffer, non-block-aligned ciphertext,
///    bad padding) returns the input unchanged rather than throwing, so a
///    non-encrypted or unexpected response still reaches the decoder and
///    produces a normal image error instead of a crash.
///
/// Note that chapter images are actually WebP despite their `.jpg` URLs, so
/// callers that persist the result must derive the file type from the
/// *decrypted* bytes rather than from the response's `Content-Type`.
class ManwayeImageDecoder {
  ManwayeImageDecoder._();

  /// AES key, verbatim from the site's JS (`AES_KEY`). Exactly 32 ASCII
  /// characters, i.e. a 256-bit key.
  static const String aesKeyString = '0B6666A0-BB59-1381-B746-a0E4C9AC';

  /// Length of the IV that prefixes every encrypted payload.
  static const int ivLength = 16;

  /// AES block size, used to validate that the ciphertext is well-formed.
  static const int _blockSize = 16;

  static final encrypt_pkg.Key _key =
      encrypt_pkg.Key(Uint8List.fromList(ascii.encode(aesKeyString)));

  static final encrypt_pkg.Encrypter _encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(_key, mode: encrypt_pkg.AESMode.cbc, padding: 'PKCS7'),
  );

  /// Returns the plaintext image bytes for a manwaye.cc image response.
  ///
  /// Returns [bytes] unchanged when they already look like an image, when they
  /// are too short or misshapen to be an encrypted payload, or when decryption
  /// fails for any reason.
  static Uint8List decodeImageBytes(Uint8List bytes) {
    // Already plaintext (this is also what makes the transform idempotent).
    if (hasImageSignature(bytes)) return bytes;

    // Need at least an IV plus one full ciphertext block.
    if (bytes.length < ivLength + _blockSize) return bytes;

    // CBC ciphertext is always a whole number of blocks.
    if ((bytes.length - ivLength) % _blockSize != 0) return bytes;

    try {
      final iv = encrypt_pkg.IV(Uint8List.sublistView(bytes, 0, ivLength));
      final cipherText = Uint8List.sublistView(bytes, ivLength);
      final decrypted = _encrypter.decryptBytes(
        encrypt_pkg.Encrypted(cipherText),
        iv: iv,
      );
      if (decrypted.isEmpty) return bytes;
      return Uint8List.fromList(decrypted);
    } catch (_) {
      // Fail open: hand the original bytes back and let the image decoder
      // report a normal failure.
      return bytes;
    }
  }

  /// Encrypts [plaintext] using the same parameters, producing an IV-prefixed
  /// payload in the exact shape the site serves.
  ///
  /// Only used to build fixtures for round-trip tests; the app never encrypts.
  static Uint8List encryptImageBytes(Uint8List plaintext, {Uint8List? iv}) {
    final ivBytes = iv ??
        Uint8List.fromList(List.generate(ivLength, (i) => (i * 7 + 3) & 0xff));
    if (ivBytes.length != ivLength) {
      throw ArgumentError.value(iv, 'iv', 'IV must be $ivLength bytes');
    }
    final encrypted = _encrypter.encryptBytes(
      plaintext,
      iv: encrypt_pkg.IV(ivBytes),
    );
    return Uint8List.fromList([...ivBytes, ...encrypted.bytes]);
  }
}
