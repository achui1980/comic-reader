/// Dean Edwards JavaScript unpacker for packed/obfuscated JS.
///
/// Handles scripts in the format:
/// `eval(function(p,a,c,k,e,d){...}('data',radix,count,'keywords'.split('|'),0,{}))`
class JsUnpacker {
  static final _packedPattern = RegExp(
    r"}\('(.*)',\s*(\d+),\s*(\d+),\s*'(.*?)'\s*\.split\('\|'\)",
    dotAll: true,
  );

  /// Attempts to unpack a Dean Edwards packed JavaScript string.
  /// Returns the unpacked source or null if the input is not packed.
  static String? unpack(String scriptContent) {
    final match = _packedPattern.firstMatch(scriptContent);
    if (match == null) return null;

    final payload = match.group(1)!;
    final radix = int.parse(match.group(2)!);
    final count = int.parse(match.group(3)!);
    final keywords = match.group(4)!.split('|');

    if (keywords.length != count) {
      // Mismatch, try anyway with what we have
    }

    // Replace each word token with its keyword from the dictionary
    final result = _replaceWords(payload, radix, keywords);
    return result;
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
