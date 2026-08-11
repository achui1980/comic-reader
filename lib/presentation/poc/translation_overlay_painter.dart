import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/translation/models/text_region.dart';

/// Paints the original manga page image with each detected [TextRegion]
/// masked by a white box and overlaid with translated (or original) text.
///
/// Layout follows the region's box aspect ratio: a box taller than it is
/// wide is rendered as vertical text in right-to-left columns (matching the
/// typical manga speech-bubble convention); a box wider than it is tall is
/// rendered as wrapped, centered horizontal text.
class TranslationOverlayPainter extends CustomPainter {
  TranslationOverlayPainter({required this.image, required this.regions});

  final ui.Image image;
  final List<TextRegion> regions;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / image.width;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(image, src, Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (final region in regions) {
      if (region.box.length < 4) continue;
      final rect = Rect.fromLTWH(
        region.box[0] * scale,
        region.box[1] * scale,
        region.box[2] * scale,
        region.box[3] * scale,
      );
      if (rect.width <= 0 || rect.height <= 0) continue;

      _paintMask(canvas, rect);

      final text = (region.translatedText != null && region.translatedText!.trim().isNotEmpty)
          ? region.translatedText!
          : region.originalText;
      if (text.trim().isEmpty) continue;

      if (region.box[2] < region.box[3]) {
        _paintVertical(canvas, rect, text);
      } else {
        _paintHorizontal(canvas, rect, text);
      }
    }
  }

  void _paintMask(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFDDDDDD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintHorizontal(Canvas canvas, Rect rect, String text) {
    var fontSize = _clamp(rect.width / 4, 10, 34);
    fontSize = _clamp(fontSize, 10, rect.height / 2);

    List<String> lines = const [];
    while (true) {
      lines = _wrapHorizontal(text, fontSize, rect.width - 8);
      final totalHeight = lines.length * fontSize * 1.3;
      if (totalHeight <= rect.height - 4 || fontSize <= 10) break;
      fontSize -= 1;
    }

    var dy = rect.top + (rect.height - lines.length * fontSize * 1.3) / 2;
    for (final line in lines) {
      final tp = TextPainter(
        text: TextSpan(text: line, style: TextStyle(color: Colors.black, fontSize: fontSize)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 4);
      tp.paint(canvas, Offset(rect.left + (rect.width - tp.width) / 2, dy));
      dy += fontSize * 1.3;
    }
  }

  List<String> _wrapHorizontal(String text, double fontSize, double maxWidth) {
    final maxChars = (maxWidth / fontSize).floor().clamp(1, 999);
    final lines = <String>[];
    var buffer = StringBuffer();
    for (final ch in text.runes.map(String.fromCharCode)) {
      buffer.write(ch);
      if (buffer.length >= maxChars) {
        lines.add(buffer.toString());
        buffer = StringBuffer();
      }
    }
    if (buffer.isNotEmpty) lines.add(buffer.toString());
    return lines.isEmpty ? [text] : lines;
  }

  void _paintVertical(Canvas canvas, Rect rect, String text) {
    final chars = text.runes.map(String.fromCharCode).toList();
    var fontSize = _clamp(rect.width / 2.4, 10, 34);
    fontSize = _clamp(fontSize, 10, rect.height / 3);

    List<List<String>> columns = const [];
    while (true) {
      columns = _columnsFor(chars, rect.height, fontSize);
      final colWidth = fontSize * 1.15;
      final totalWidth = columns.length * colWidth;
      if (totalWidth <= rect.width - 4 || fontSize <= 10) break;
      fontSize -= 1;
    }

    final colWidth = fontSize * 1.15;
    final totalWidth = columns.length * colWidth;
    var colRight = rect.right - (rect.width - totalWidth) / 2;
    for (final col in columns) {
      final colLeft = colRight - colWidth;
      var dy = rect.top + (rect.height - col.length * fontSize * 1.15) / 2;
      for (final ch in col) {
        final tp = TextPainter(
          text: TextSpan(text: ch, style: TextStyle(color: Colors.black, fontSize: fontSize)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(colLeft + (colWidth - tp.width) / 2, dy));
        dy += fontSize * 1.15;
      }
      colRight = colLeft;
    }
  }

  List<List<String>> _columnsFor(List<String> chars, double height, double fontSize) {
    final perCol = (height / (fontSize * 1.15)).floor().clamp(1, 999);
    final columns = <List<String>>[];
    for (var i = 0; i < chars.length; i += perCol) {
      columns.add(chars.sublist(i, (i + perCol).clamp(0, chars.length)));
    }
    return columns;
  }

  double _clamp(double value, double min, double max) {
    if (max < min) return min;
    return value.clamp(min, max);
  }

  @override
  bool shouldRepaint(covariant TranslationOverlayPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.regions != regions;
  }
}
