/// Combines plugin source ID, manga ID, and optional chapter ID into a hash string.
/// Format: "sourceId&mangaId" or "sourceId&mangaId&chapterId"
String combineHash(String sourceId, String mangaId, [String? chapterId]) {
  if (chapterId != null) {
    return '$sourceId&$mangaId&$chapterId';
  }
  return '$sourceId&$mangaId';
}

/// Splits a hash back into its components.
/// Returns a record: (sourceId, mangaId, chapterId?)
({String sourceId, String mangaId, String? chapterId}) splitHash(String hash) {
  final parts = hash.split('&');
  if (parts.length < 2) {
    throw ArgumentError('Invalid hash format: $hash');
  }
  return (
    sourceId: parts[0],
    mangaId: parts[1],
    chapterId: parts.length > 2 ? parts[2] : null,
  );
}
