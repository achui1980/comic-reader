import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';

import 'jmc_unscramble.dart';

/// Displays a wu55 memory image with slice unscrambling.
/// Decodes bytes to ui.Image, then uses CustomPainter to rearrange slices.
class Wu55MemoryImage extends StatefulWidget {
  final Uint8List imageBytes;
  final BoxFit fit;
  final Alignment alignment;
  final int bookId;
  final int pageNumber;

  const Wu55MemoryImage({
    super.key,
    required this.imageBytes,
    required this.fit,
    required this.alignment,
    required this.bookId,
    required this.pageNumber,
  });

  @override
  State<Wu55MemoryImage> createState() => _Wu55MemoryImageState();
}

class _Wu55MemoryImageState extends State<Wu55MemoryImage> {
  ui.Image? _image;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _image = frame.image;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null || _image == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
            SizedBox(height: 8),
            Text('解码失败', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    final image = _image!;
    final sliceCount = Wu55ComicDecoder.getSliceCount(widget.bookId, widget.pageNumber);
    debugPrint('[Wu55Unscramble] bookId=${widget.bookId}, pageNumber=${widget.pageNumber}, '
        'imageSize=${image.width}x${image.height}, sliceCount=$sliceCount');
    final w = image.width.toDouble();
    final h = image.height.toDouble();

    if (sliceCount <= 0) {
      return RawImage(image: image, fit: widget.fit);
    }

    return FittedBox(
      fit: widget.fit,
      alignment: widget.alignment,
      child: SizedBox(
        width: w,
        height: h,
        child: CustomPaint(
          size: Size(w, h),
          painter: JmcUnscramblePainter(image: image, segments: sliceCount),
        ),
      ),
    );
  }
}
