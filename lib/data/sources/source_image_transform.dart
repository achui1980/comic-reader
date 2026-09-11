import 'dart:typed_data';

import 'package:get_it/get_it.dart' hide Disposable;

import 'source_registry.dart';

/// Applies the per-source raw-image-bytes transform for [sourceId], if any.
///
/// This is the single dispatch point for [MangaSource.transformImageBytes]. It
/// is called from every code path that turns an image HTTP response into bytes:
/// the reader loader, the chapter downloader, the cover widget, and
/// save-to-gallery. Sources that don't override the hook (the vast majority)
/// pay only a map lookup and a boolean check.
///
/// Returns [bytes] unchanged when [sourceId] is null, when no such source is
/// registered, when the source doesn't opt in, or when dependency injection
/// hasn't been configured (which is the case in most unit tests).
Uint8List applySourceImageTransform(Uint8List bytes, String? sourceId) {
  if (sourceId == null || sourceId.isEmpty || bytes.isEmpty) return bytes;
  if (!GetIt.instance.isRegistered<SourceRegistry>()) return bytes;
  final source = GetIt.instance<SourceRegistry>().get(sourceId);
  if (source == null || !source.transformsImageBytes) return bytes;
  return source.transformImageBytes(bytes);
}
