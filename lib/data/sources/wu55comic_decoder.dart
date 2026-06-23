import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

/// Result of decoding a wu55comic encrypted image.
class Wu55ImageDecodeResult {
  final Uint8List imageBytes;
  final bool needsUnscramble;
  final int bookId;
  final int pageNumber;
  final String mimeType;

  const Wu55ImageDecodeResult({
    required this.imageBytes,
    required this.needsUnscramble,
    required this.bookId,
    required this.pageNumber,
    required this.mimeType,
  });
}

/// Handles the wu55comic image decryption pipeline:
/// 1. URL transformation (original → 2 shard URLs on different CDNs)
/// 2. AES-CBC decryption
/// 3. Magic number parsing & file header restoration
/// 4. Slice count calculation for UI unscrambling
class Wu55ComicDecoder {
  // AES key: 16 bytes of 'a' (0x61)
  static final _aesKey =
      encrypt_pkg.Key(Uint8List.fromList(List.filled(16, 0x61)));

  // AES IV: '0123456789aaaaaa' (0x30..0x39 + 6 bytes of 0x61)
  static final _aesIV = encrypt_pkg.IV(Uint8List.fromList([
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, // '01234567'
    0x38, 0x39, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, // '89aaaaaa'
  ]));

  // Real file headers by type code
  static const Map<int, List<int>> _fileHeaders = {
    0: [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01], // JPEG
    3: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], // GIF
    4: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66], // AVIF
  };

  // MIME types by type code
  static const Map<int, String> _mimeTypes = {
    0: 'image/jpeg',
    3: 'image/gif',
    4: 'image/avif',
  };

  /// Build 2 shard URLs from the original image URL.
  ///
  /// Removes the `/break_xxx/` path segment, replaces the file extension
  /// with `.b_0` and `.b_1`, assigns different CDN hosts, and appends
  /// a `?v=YYYYMMDD` cache key.
  static List<String> buildShardUrls(String originalUrl) {
    final uri = Uri.parse(originalUrl);
    final host = uri.host;

    // Determine the two CDN hosts.
    // Shard 0 uses the original host; shard 1 flips the last char before the
    // first hyphen in the subdomain (e.g., "bmigmij" → "bmigmih").
    final hostParts = host.split('.');
    final subdomain = hostParts[0];
    // Derive shard1 host by decrementing the last char of the prefix before
    // the first hyphen by 2 (e.g., "bmigmij-wuwu" → "bmigmih-wuwu")
    final hyphenIdx = subdomain.indexOf('-');
    String shard1Subdomain;
    if (hyphenIdx > 0) {
      final prefix = subdomain.substring(0, hyphenIdx);
      final suffix = subdomain.substring(hyphenIdx);
      shard1Subdomain =
          prefix.substring(0, prefix.length - 1) +
          String.fromCharCode(prefix.codeUnitAt(prefix.length - 1) - 2) +
          suffix;
    } else {
      shard1Subdomain =
          subdomain.substring(0, subdomain.length - 1) +
          String.fromCharCode(subdomain.codeUnitAt(subdomain.length - 1) - 2);
    }
    final shard1Host = [shard1Subdomain, ...hostParts.sublist(1)].join('.');

    // Keep the path as-is (including /break_2/ or /break_avif/ segments).
    // Only the file extension changes to .b_0 / .b_1
    final pathSegments = uri.pathSegments.toList();

    // Replace file extension with shard suffixes
    final lastIdx = pathSegments.length - 1;
    final filename = pathSegments[lastIdx];
    final dotIdx = filename.lastIndexOf('.');
    final baseName = dotIdx >= 0 ? filename.substring(0, dotIdx) : filename;

    // Build date-based cache key
    final now = DateTime.now();
    final cacheKey =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    final shard0Segments = List<String>.from(pathSegments);
    shard0Segments[lastIdx] = '$baseName.b_0';
    final shard0Path = '/${shard0Segments.join('/')}';

    final shard1Segments = List<String>.from(pathSegments);
    shard1Segments[lastIdx] = '$baseName.b_1';
    final shard1Path = '/${shard1Segments.join('/')}';

    final shard0Url = 'https://$host$shard0Path?v=$cacheKey';
    final shard1Url = 'https://$shard1Host$shard1Path?v=$cacheKey';

    return [shard0Url, shard1Url];
  }

  /// Decrypt AES-CBC encrypted data.
  ///
  /// Uses key="aaaaaaaaaaaaaaaa" (16x 0x61) and
  /// IV="0123456789aaaaaa" (0x30-0x39 + 6x 0x61), with PKCS7 padding.
  static Uint8List decryptAES(Uint8List combinedData) {
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(_aesKey, mode: encrypt_pkg.AESMode.cbc, padding: 'PKCS7'),
    );
    final encrypted = encrypt_pkg.Encrypted(combinedData);
    final decrypted = encrypter.decryptBytes(encrypted, iv: _aesIV);
    return Uint8List.fromList(decrypted);
  }

  /// Encrypt data with the same AES-CBC parameters (for testing roundtrips).
  static Uint8List encryptAES(Uint8List plainData) {
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(_aesKey, mode: encrypt_pkg.AESMode.cbc, padding: 'PKCS7'),
    );
    final encrypted = encrypter.encryptBytes(plainData.toList(), iv: _aesIV);
    return encrypted.bytes;
  }

  /// Parse custom magic number bytes and restore real file header.
  ///
  /// Returns a [Wu55ImageDecodeResult] with the restored image bytes
  /// and metadata for unscrambling.
  static Wu55ImageDecodeResult restoreImage(Uint8List decrypted) {
    if (decrypted.length < 8) {
      throw ArgumentError('Decrypted data too short: ${decrypted.length} bytes');
    }

    // byte[0] = file type code: 0=JPEG, 3=GIF, 4=AVIF
    final typeCode = decrypted[0];
    // byte[1] = sub-type: 0="monga" (needs slice unscramble), 1="other"
    final subType = decrypted[1];

    final header = _fileHeaders[typeCode];
    if (header == null) {
      throw ArgumentError('Unknown file type code: $typeCode');
    }

    final mimeType = _mimeTypes[typeCode]!;
    final needsUnscramble = subType == 0; // "monga"

    int bookId = 0;
    int pageNumber = 0;

    if (needsUnscramble) {
      // byte[2]*256 + byte[3] = bookId
      bookId = decrypted[2] * 256 + decrypted[3];
      // byte[4]*16777216 + byte[5]*65536 + byte[6]*256 + byte[7] = pageNumber
      pageNumber = decrypted[4] * 16777216 +
          decrypted[5] * 65536 +
          decrypted[6] * 256 +
          decrypted[7];
    }

    // Replace first N bytes (header length) with the real file magic
    final headerLen = header.length;
    final result = Uint8List(decrypted.length - headerLen + headerLen);
    // Copy real header
    for (int i = 0; i < headerLen; i++) {
      result[i] = header[i];
    }
    // Copy remaining data after custom header area
    for (int i = headerLen; i < decrypted.length; i++) {
      result[i] = decrypted[i];
    }

    return Wu55ImageDecodeResult(
      imageBytes: result,
      needsUnscramble: needsUnscramble,
      bookId: bookId,
      pageNumber: pageNumber,
      mimeType: mimeType,
    );
  }

  /// Calculate the slice count for unscrambling.
  ///
  /// Formula: `44 + (md5("$bookId$pageNumber").lastChar.codeUnitAt(0) % 10) * 4`
  /// Range: 44, 48, 52, 56, 60, 64, 68, 72, 76, 80
  ///
  /// NOTE: JS passes book_id and page_number as STRINGS ("" + number),
  /// so `e + a` in get_corp_count is STRING CONCATENATION, not numeric addition.
  /// e.g., book_id=5336, page_number=1814840 → md5("53361814840") not md5("1820176")
  static int getSliceCount(int bookId, int pageNumber) {
    // JS does: c = e + a where e="5336", a="1814840" → "53361814840" (string concat)
    final input = '$bookId$pageNumber';
    final hash = md5.convert(utf8.encode(input)).toString();
    final lastChar = hash[hash.length - 1];
    final lastCharCode = lastChar.codeUnitAt(0);
    return 44 + (lastCharCode % 10) * 4;
  }

  /// Full decode pipeline: decrypt each shard separately then combine.
  ///
  /// IMPORTANT: Each shard must be decrypted independently (with its own IV),
  /// then concatenated. This is because the server encrypts each shard as a
  /// separate AES-CBC stream. Combining before decryption would corrupt the
  /// data at the shard boundary (wrong CBC chaining).
  static Wu55ImageDecodeResult decode(Uint8List combinedShardData) {
    // Legacy single-buffer API: decrypt as one block (for backward compat)
    final decrypted = decryptAES(combinedShardData);
    return restoreImage(decrypted);
  }

  /// Decode from individual shard buffers (correct method).
  ///
  /// Each shard is decrypted separately with the same key/IV, then
  /// the decrypted results are concatenated.
  static Wu55ImageDecodeResult decodeShards(List<Uint8List> shards) {
    final decryptedParts = shards.map((shard) => decryptAES(shard)).toList();
    // Concatenate decrypted parts
    final totalLength =
        decryptedParts.fold<int>(0, (sum, part) => sum + part.length);
    final combined = Uint8List(totalLength);
    int offset = 0;
    for (final part in decryptedParts) {
      combined.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return restoreImage(combined);
  }
}
