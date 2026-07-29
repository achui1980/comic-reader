/// Text normalization helpers for cross-source work matching.
///
/// Shared by the search deduper and the [WorkGroup] matcher so both use the
/// exact same notion of "same title".
library;

/// Normalize a title/author for cross-source matching: fold full-width ASCII
/// into half-width, collapse whitespace, lowercase, and trim.
///
/// So "ＯＮＥ　ＰＩＥＣＥ" and "one piece" produce the same key.
String normalizeTitle(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    // Full-width ASCII (！-～, U+FF01–U+FF5E) → half-width (U+0021–U+007E).
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      // Full-width space → normal space.
      buffer.writeCharCode(0x20);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
