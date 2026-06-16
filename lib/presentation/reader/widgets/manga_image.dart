import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:crypto/crypto.dart' as crypto_lib;
import 'dart:convert' show utf8;
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/presentation/reader/widgets/manga_image_file.dart'
    if (dart.library.io) 'package:comic_reader/presentation/reader/widgets/manga_image_file_io.dart';

/// Displays a single manga page image with loading and error states.
/// Supports JMC image unscrambling via CustomPainter.
class MangaImage extends StatefulWidget {
  final ChapterImage image;
  final BoxFit fit;
  final String? sourceId;
  final String? mangaId;
  final String? chapterId;
  final int? imageIndex;

  const MangaImage({
    super.key,
    required this.image,
    this.fit = BoxFit.contain,
    this.sourceId,
    this.mangaId,
    this.chapterId,
    this.imageIndex,
  });

  @override
  State<MangaImage> createState() => _MangaImageState();
}

class _MangaImageState extends State<MangaImage> {
  String? _localPath;
  bool _checkedCache = false;

  bool get _canCache =>
      !kIsWeb &&
      widget.sourceId != null &&
      widget.mangaId != null &&
      widget.chapterId != null &&
      widget.imageIndex != null;

  @override
  void initState() {
    super.initState();
    if (_canCache) {
      _checkCache();
    } else {
      _checkedCache = true;
    }
  }

  Future<void> _checkCache() async {
    final cacheService = GetIt.instance<ChapterCacheService>();
    final path = await cacheService.getImageFile(
      widget.sourceId!,
      widget.mangaId!,
      widget.chapterId!,
      widget.imageIndex!,
    );
    if (mounted) {
      setState(() {
        _localPath = path;
        _checkedCache = true;
      });
    }
  }

  Future<void> _saveToCache(ExtendedImageState state) async {
    if (!_canCache || _localPath != null) return;
    try {
      final data = state.extendedImageInfo?.image;
      if (data == null) return;
      final cacheService = GetIt.instance<ChapterCacheService>();
      final url = ImageProxy.url(widget.image.url);
      final file = await getCachedImageFile(url);
      if (file != null) {
        final bytes = await file.readAsBytes();
        await cacheService.saveImage(
          widget.sourceId!,
          widget.mangaId!,
          widget.chapterId!,
          widget.imageIndex!,
          bytes,
        );
      }
    } catch (_) {}
  }

  /// Calculate segment count for JMC unscrambling.
  int _calculateSegments(int width, int height) {
    final chapterId = widget.chapterId ?? '';
    // aid = photo_id (chapter ID), NOT album_id
    final aid = int.tryParse(chapterId) ?? 0;

    // Extract filename from URL (e.g., "00001.webp" from full URL)
    final url = widget.image.url;
    final filename = url.split('/').last.split('?').first;
    // Remove extension for the hash calculation
    final filenameNoExt = filename.contains('.') 
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;

    // scramble_id threshold - default 220980
    const scramble220980 = 220980;
    const scramble268850 = 268850;
    const scramble421926 = 421926;

    if (aid < scramble220980) return 0;
    if (aid < scramble268850) return 10;

    final x = aid < scramble421926 ? 10 : 8;
    final s = '$aid$filenameNoExt';
    final hash = crypto_lib.md5.convert(utf8.encode(s)).toString();
    final lastChar = hash.codeUnitAt(hash.length - 1);
    final num = lastChar % x;
    return num * 2 + 2;
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedCache) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // If we have a local file, load from disk (native only)
    if (_localPath != null) {
      return buildFileImage(
        path: _localPath!,
        fit: widget.fit,
        onFailed: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _localPath = null;
              });
            }
          });
        },
      );
    }

    // Load from network
    final imageUrl = ImageProxy.url(widget.image.url);
    debugPrint('[MangaImage] Loading: $imageUrl');
    return ExtendedImage.network(
      imageUrl,
      fit: widget.fit,
      cache: true,
      headers: ImageProxy.safeHeaders(widget.image.headers),
      enableLoadState: true,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '加载中...',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          case LoadState.completed:
            // Save to local cache asynchronously
            if (_canCache) {
              _saveToCache(state);
            }

            // If image needs unscrambling, use custom painter
            if (widget.image.scrambleType == ScrambleType.jmc) {
              final imageInfo = state.extendedImageInfo;
              if (imageInfo != null) {
                return _UnscrambledImage(
                  image: imageInfo.image,
                  fit: widget.fit,
                  calculateSegments: _calculateSegments,
                );
              }
            }

            return state.completedWidget;
          case LoadState.failed:
            debugPrint('[MangaImage] FAILED: ${widget.image.url} - ${state.lastException}');
            return GestureDetector(
              onTap: () => state.reLoadImage(),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        size: 48, color: Colors.white54),
                    SizedBox(height: 8),
                    Text('点击重试', style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            );
        }
      },
    );
  }
}

/// Widget that displays an unscrambled JMC image.
class _UnscrambledImage extends StatelessWidget {
  final ui.Image image;
  final BoxFit fit;
  final int Function(int width, int height) calculateSegments;

  const _UnscrambledImage({
    required this.image,
    required this.fit,
    required this.calculateSegments,
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

    return CustomPaint(
      size: Size(w, h),
      painter: _JmcUnscramblePainter(image: image, segments: segments),
    );
  }
}

/// Paints the unscrambled JMC image by rearranging horizontal strips.
///
/// Algorithm (from jmcomic-crawler-python JmImageTool.decode_and_save):
/// The image is split into [segments] horizontal strips.
/// Each strip is moved from its scrambled position to its correct position.
/// The strips are reordered from bottom-to-top of source to top-to-bottom of dest.
class _JmcUnscramblePainter extends CustomPainter {
  final ui.Image image;
  final int segments;

  _JmcUnscramblePainter({required this.image, required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final paint = Paint();

    final over = h.toInt() % segments;

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

      final srcRect = Rect.fromLTWH(0, ySrc, w, segHeight);
      final dstRect = Rect.fromLTWH(0, yDst, w, segHeight);
      canvas.drawImageRect(image, srcRect, dstRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _JmcUnscramblePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.segments != segments;
  }
}
