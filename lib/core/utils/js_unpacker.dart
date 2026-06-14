import 'package:comic_reader/core/utils/lz_string.dart';

/// Dean Edwards JavaScript unpacker for packed/obfuscated JS.
///
/// Handles scripts in the format:
/// `eval(function(p,a,c,k,e,d){...}('data',radix,count,'keywords'.split('|'),0,{}))`
/// Also handles ManhuaGui variant with hex-escaped method names and LZ-compressed keywords:
/// `function(p,a,c,k,e,d){...}('data',radix,count,'lz_base64'['\x73\x70\x6c\x69\x63']('\x7c'),0,{})`
class JsUnpacker {
  /// Standard format: }('...',N,N,'...'.split('|')...)
  static final _packedPattern = RegExp(
    r"}\('(.*)',\s*(\d+),\s*(\d+),\s*'(.*?)'\s*\.split\('\|'\)",
    dotAll: true,
  );

  /// ManhuaGui format with hex escapes:
  /// }('...',N,N,'...'['\x73\x70\x6c\x69\x63']('\x7c'),0,{})
  static final _packedPatternHex = RegExp(
    r"}\('(.*)',\s*(\d+),\s*(\d+),\s*'(.*?)'\s*\[",
    dotAll: true,
  );

  /// Attempts to unpack a Dean Edwards packed JavaScript string.
  /// Returns the unpacked source or null if the input is not packed.
  static String? unpack(String scriptContent) {
    // Try standard format first
    var match = _packedPattern.firstMatch(scriptContent);
    if (match != null) {
      final payload = match.group(1)!;
      final radix = int.parse(match.group(2)!);
      final keywords = match.group(4)!.split('|');
      return _replaceWords(payload, radix, keywords);
    }

    // Try ManhuaGui hex-escaped format
    match = _packedPatternHex.firstMatch(scriptContent);
    if (match != null) {
      final payload = match.group(1)!;
      final radix = int.parse(match.group(2)!);
      final keywordsRaw = match.group(4)!;

      // Keywords are LZ-String base64 compressed, then split by |
      List<String> keywords;
      if (keywordsRaw.contains('|')) {
        keywords = keywordsRaw.split('|');
      } else {
        // LZ-String decompression
        final decompressed = LZString.decompressFromBase64(keywordsRaw);
        if (decompressed != null && decompressed.isNotEmpty) {
          keywords = decompressed.split('|');
        } else {
          return null;
        }
      }
      return _replaceWords(payload, radix, keywords);
    }

    return null;
  }

  /// Replace encoded word references with actual keywords.
  static String _replaceWords(String source, int radix, List<String> keywords) {
    // Match word boundaries - tokens are base-N encoded integers
    final pattern = RegExp(r'\b(\w+)\b');
    return source.replaceAllMapped(pattern, (match) {
      final word = match.group(1)!;
      final index = _parseInt(word, radix);
      if (index != null && index < keywords.length && keywords[index].isNotEmpty) {
        return keywords[index];
      }
      return word;
    });
  }

  /// Parse an integer from a string in the given radix (base).
  static int? _parseInt(String str, int radix) {
    if (radix <= 36) {
      try {
        return int.parse(str, radix: radix);
      } catch (_) {
        return null;
      }
    }
    // For radix > 36, use custom encoding
    return _parseHighRadix(str, radix);
  }

  /// Parse integers in bases > 36 (up to 62).
  /// Uses 0-9, a-z, A-Z encoding.
  static int? _parseHighRadix(String str, int radix) {
    int result = 0;
    for (int i = 0; i < str.length; i++) {
      final c = str.codeUnitAt(i);
      int digit;
      if (c >= 48 && c <= 57) {
        // 0-9
        digit = c - 48;
      } else if (c >= 97 && c <= 122) {
        // a-z -> 10-35
        digit = c - 87;
      } else if (c >= 65 && c <= 90) {
        // A-Z -> 36-61
        digit = c - 29;
      } else {
        return null;
      }
      if (digit >= radix) return null;
      result = result * radix + digit;
    }
    return result;
  }

  /// Extract the packed script content from a full HTML page script.
  /// Looks for patterns like: eval(function(p,a,c,k,e,d){...})
  static String? findPackedScript(String html) {
    // Match the entire eval(...) block
    final evalPattern = RegExp(
      r'''eval\(function\(p,a,c,k,e,d\)\{.*?\}\('.*?',\s*\d+,\s*\d+,\s*'.*?'\.split\('\|'\)\s*,\s*\d+\s*,\s*\{?\}?\s*\)\)''',
      dotAll: true,
    );
    final match = evalPattern.firstMatch(html);
    if (match == null) return null;
    return match.group(0);
  }
}
