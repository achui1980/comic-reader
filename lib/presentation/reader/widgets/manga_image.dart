import 'dart:ui' as ui;
import 'dart:convert' show base64Decode, utf8;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:crypto/crypto.dart' as crypto_lib;
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/core/utils/save_image.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';
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
  /// When true, disables gesture mode and auto-zoom scaling.
  /// Used in vertical scroll mode where images should simply fit width.
  final bool disableGesture;
  /// Alignment for JMC unscrambled images within FittedBox.
  /// Defaults to topCenter (good for vertical scroll).
  /// Use Alignment.center for horizontal page view mode.
  final Alignment jmcAlignment;

  const MangaImage({
    super.key,
    required this.image,
    this.fit = BoxFit.contain,
    this.sourceId,
    this.mangaId,
    this.chapterId,
    this.imageIndex,
    this.disableGesture = false,
    this.jmcAlignment = Alignment.topCenter,
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

    // Use dynamic scramble_id from API if available, otherwise fallback to default
    final scrambleId = widget.image.scrambleId ?? 220980;
    const scramble268850 = 268850;
    const scramble421926 = 421926;

    if (aid < scrambleId) return 0;
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

    return GestureDetector(
      onLongPress: kIsWeb ? null : () => _showSaveDialog(context),
      child: _buildImageContent(),
    );
  }

  Future<void> _showSaveDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存图片'),
        content: const Text('是否保存此图片到相册？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在保存...')),
      );
      final success = await saveImageToGallery(
        widget.image.url,
        headers: widget.image.headers,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '已保存到相册' : '保存失败')),
        );
      }
    }
  }

  /// Build image from data: URI (for pre-decoded images like wu55comic)
  Widget _buildMemoryImage() {
    try {
      final uri = widget.image.url;
      // Parse "data:image/jpeg;base64,XXXXX"
      final commaIdx = uri.indexOf(',');
      if (commaIdx < 0) {
        return const Center(child: Text('Invalid data URI'));
      }
      final base64Data = uri.substring(commaIdx + 1);
      final bytes = base64Decode(base64Data);

      // If wu55 scrambled, use custom unscramble painter
      if (widget.image.scrambleType == ScrambleType.wu55) {
        return _Wu55MemoryImage(
          imageBytes: Uint8List.fromList(bytes),
          fit: widget.fit,
          alignment: widget.jmcAlignment,
          bookId: widget.image.wu55BookId ?? 0,
          pageNumber: widget.image.wu55PageNumber ?? 0,
        );
      }

      // Not scrambled, render directly
      return Image.memory(
        Uint8List.fromList(bytes),
        fit: widget.fit,
        errorBuilder: (_, error, __) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
              SizedBox(height: 8),
              Text('图片解码失败', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white54),
            const SizedBox(height: 8),
            Text('数据错误: $e', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }
  }

  Widget _buildImageContent() {
    // Placeholder for images not yet resolved (progressive loading)
    if (widget.image.url.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 8),
            Text(
              '加载中...',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
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
        onCompleted: widget.image.scrambleType == ScrambleType.jmc
            ? (state) {
                final imageInfo = state.extendedImageInfo;
                if (imageInfo != null) {
                  return _UnscrambledImage(
                    image: imageInfo.image,
                    fit: widget.fit,
                    alignment: widget.jmcAlignment,
                    calculateSegments: _calculateSegments,
                  );
                }
                return state.completedWidget;
              }
            : null,
      );
    }

    // Load from network
    // Handle data: URIs (pre-decoded binary, e.g. wu55comic)
    if (widget.image.url.startsWith('data:')) {
      return _buildMemoryImage();
    }

    final imageUrl = ImageProxy.url(widget.image.url);
    debugPrint('[MangaImage] Loading: $imageUrl');
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final isJmcScrambled = widget.image.scrambleType == ScrambleType.jmc;
        // Disable gesture mode for JMC scrambled images because they render
        // via _UnscrambledImage (CustomPaint). The gesture system's transform
        // conflicts with the FittedBox sizing in _UnscrambledImage, causing
        // broken display in horizontal page view mode.
        final useGesture = !widget.disableGesture && !isJmcScrambled;
        return ExtendedImage.network(
          imageUrl,
          fit: widget.fit,
          cache: true,
          retries: 3,
          timeLimit: const Duration(seconds: 15),
          headers: ImageProxy.safeHeaders(widget.image.headers),
          enableLoadState: true,
          mode: useGesture
              ? ExtendedImageMode.gesture
              : ExtendedImageMode.none,
          initGestureConfigHandler: !useGesture
              ? null
              : (state) {
                  double initialScale = 1.0;
                  InitialAlignment alignment = InitialAlignment.topCenter;

                  final imageInfo = state.extendedImageInfo;
                  if (imageInfo != null &&
                      screenWidth > 0 &&
                      screenHeight > 0) {
                    final double imgW = imageInfo.image.width.toDouble();
                    final double imgH = imageInfo.image.height.toDouble();
                    final double imageAspect = imgW / imgH;
                    final double screenAspect = screenWidth / screenHeight;

                    if (imageAspect > screenAspect) {
                      // Wide image: fitWidth makes it too short. Scale up to fill height.
                      // With fitWidth, displayed height = screenWidth / imageAspect
                      // We want displayed height = screenHeight
                      // scale = screenHeight / (screenWidth / imageAspect)
                      initialScale =
                          (screenHeight * imageAspect) / screenWidth;
                      alignment = InitialAlignment.centerLeft;
                    }
                    // Tall image: fitWidth already fills width, user scrolls vertically
                  }

                  const double minScale = 1.0;
                  const double maxScale = 5.0;
                  initialScale = initialScale.clamp(minScale, maxScale);

                  return GestureConfig(
                    minScale: minScale,
                    animationMinScale: 0.8,
                    maxScale: maxScale,
                    animationMaxScale: 5.5,
                    speed: 1.0,
                    inertialSpeed: 100.0,
                    initialScale: initialScale,
                    inPageView: true,
                    initialAlignment: alignment,
                  );
                },
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
                    final segs = _calculateSegments(imageInfo.image.width, imageInfo.image.height);
                    debugPrint('[JMC Unscramble] chapterId=${widget.chapterId}, url=${widget.image.url}, imgSize=${imageInfo.image.width}x${imageInfo.image.height}, segments=$segs');
                    return _UnscrambledImage(
                      image: imageInfo.image,
                      fit: widget.fit,
                      alignment: widget.jmcAlignment,
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
      },
    );
  }
}

/// Widget that displays an unscrambled JMC image.
class _UnscrambledImage extends StatelessWidget {
  final ui.Image image;
  final BoxFit fit;
  final Alignment alignment;
  final int Function(int width, int height) calculateSegments;

  const _UnscrambledImage({
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
          painter: _JmcUnscramblePainter(image: image, segments: segments),
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
class _JmcUnscramblePainter extends CustomPainter {
  final ui.Image image;
  final int segments;

  _JmcUnscramblePainter({required this.image, required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final paint = Paint()..isAntiAlias = false;

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

      // Add 0.5px overlap to prevent sub-pixel gaps on iOS
      final overlap = (i < segments - 1) ? 0.5 : 0.0;

      final srcRect = Rect.fromLTWH(0, ySrc, w, segHeight + overlap);
      final dstRect = Rect.fromLTWH(0, yDst, w, segHeight + overlap);
      canvas.drawImageRect(image, srcRect, dstRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _JmcUnscramblePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.segments != segments;
  }
}

/// Displays a wu55 memory image with slice unscrambling.
/// Decodes bytes to ui.Image, then uses CustomPainter to rearrange slices.
class _Wu55MemoryImage extends StatefulWidget {
  final Uint8List imageBytes;
  final BoxFit fit;
  final Alignment alignment;
  final int bookId;
  final int pageNumber;

  const _Wu55MemoryImage({
    required this.imageBytes,
    required this.fit,
    required this.alignment,
    required this.bookId,
    required this.pageNumber,
  });

  @override
  State<_Wu55MemoryImage> createState() => _Wu55MemoryImageState();
}

class _Wu55MemoryImageState extends State<_Wu55MemoryImage> {
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
    final w = image.width.toDouble();
    final h = image.height.toDouble();

    print('[Wu55Unscramble] bookId=${widget.bookId}, pageNumber=${widget.pageNumber}, '
        'sliceCount=$sliceCount, imageSize=${w.toInt()}x${h.toInt()}, '
        'base_h=${(h ~/ sliceCount)}, remainder=${h.toInt() % sliceCount}');

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
          painter: _JmcUnscramblePainter(image: image, segments: sliceCount),
        ),
      ),
    );
  }
}
