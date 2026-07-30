import 'dart:convert' show utf8;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto_lib;
import 'package:flutter/material.dart';

/// Calculate segment count for JMC unscrambling.
///
/// Pure function — mirrors the original `_MangaImageState._calculateSegments`.
/// [width]/[height] are accepted (and forwarded through the
/// `calculateSegments` callback type used by [JmcUnscrambledImage]) but,
/// as in the original implementation, are not used in the calculation
/// itself. [chapterId], [url], and [scrambleId] replace the
/// `widget.chapterId` / `widget.image.url` / `widget.image.scrambleId`
/// references from the original State-bound method.
int calculateJmcSegments(
  int width,
  int height, {
  required String? chapterId,
  required String url,
  required int? scrambleId,
}) {
  final resolvedChapterId = chapterId ?? '';
  // aid = photo_id (chapter ID), NOT album_id
  final aid = int.tryParse(resolvedChapterId) ?? 0;

  // Extract filename from URL (e.g., "00001.webp" from full URL)
  final filename = url.split('/').last.split('?').first;
  // Remove extension for the hash calculation
  final filenameNoExt = filename.contains('.')
      ? filename.substring(0, filename.lastIndexOf('.'))
      : filename;

  // Use dynamic scramble_id from API if available, otherwise fallback to default
  final resolvedScrambleId = scrambleId ?? 220980;
  const scramble268850 = 268850;
  const scramble421926 = 421926;

  if (aid < resolvedScrambleId) return 0;
  if (aid < scramble268850) return 10;

  final x = aid < scramble421926 ? 10 : 8;
  final s = '$aid$filenameNoExt';
  final hash = crypto_lib.md5.convert(utf8.encode(s)).toString();
  final lastChar = hash.codeUnitAt(hash.length - 1);
  final num = lastChar % x;
  return num * 2 + 2;
}

/// Widget that displays an unscrambled JMC image.
class JmcUnscrambledImage extends StatelessWidget {
  final ui.Image image;
  final BoxFit fit;
  final Alignment alignment;
  final int Function(int width, int height) calculateSegments;

  const JmcUnscrambledImage({
    super.key,
    required this.image,
    required this.fit,
    required this.calculateSegments,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final segments = calculateSegments(image.width, image.height);

    if (segments <= 0) {
      // No scrambling needed, render directly
      return RawImage(image: image, fit: fit);
    }

    return FittedBox(
      fit: fit,
      alignment: alignment,
      child: SizedBox(
        width: w,
        height: h,
        child: CustomPaint(
          size: Size(w, h),
          painter: JmcUnscramblePainter(image: image, segments: segments),
        ),
      ),
    );
  }
}

/// Paints the unscrambled JMC image by rearranging horizontal strips.
///
/// Algorithm (from jmcomic-crawler-python JmImageTool.decode_and_save):
/// The image is split into [segments] horizontal strips.
/// Each strip is moved from its scrambled position to its correct position.
/// The strips are reordered from bottom-to-top of source to top-to-bottom of dest.
///
/// Shared by both the JMC unscramble path (via [JmcUnscrambledImage]) and
/// the wu55 memory-image path (via `_Wu55MemoryImage` in
/// manga_image.dart) — do not rename this file to imply JMC-only ownership
/// without updating both call sites.
class JmcUnscramblePainter extends CustomPainter {
  final ui.Image image;
  final int segments;

  JmcUnscramblePainter({required this.image, required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;

    final over = h.toInt() % segments;

    // Only add overlap for low segment counts (JMC: 2-20 segments).
    // For high segment counts (wu55: 44-80 segments), overlap causes visible
    // artifacts because strips are very narrow (~10px).
    final useOverlap = segments <= 20;

    for (int i = 0; i < segments; i++) {
      final move = (h ~/ segments).toDouble();

      // Source Y (from bottom up)
      double ySrc = h - (move * (i + 1)) - over;
      // Destination Y (from top down)
      double yDst = move * i;

      double segHeight = move;
      if (i == 0) {
        segHeight += over;
      } else {
        yDst += over;
      }

      // Add 0.5px overlap to prevent sub-pixel gaps on iOS (low segment counts only)
      final overlap = (useOverlap && i < segments - 1) ? 0.5 : 0.0;

      final srcRect = Rect.fromLTWH(0, ySrc, w, segHeight + overlap);
      final dstRect = Rect.fromLTWH(0, yDst, w, segHeight + overlap);
      canvas.drawImageRect(image, srcRect, dstRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant JmcUnscramblePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.segments != segments;
  }
}
