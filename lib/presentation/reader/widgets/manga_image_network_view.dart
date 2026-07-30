import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/chapter.dart';
import 'jmc_unscramble.dart';
import 'manga_image_loader.dart';

/// Renders a network-sourced manga page image: downloads/caches the raw
/// bytes (via [loadAndCacheImageBytes]), then displays them through
/// [ExtendedImage.memory] with gesture-zoom initialization and JMC
/// unscrambling support.
///
/// Extracted from `_MangaImageState._buildEncodedNetworkImage` in
/// `manga_image.dart`.
class MangaImageNetworkView extends StatefulWidget {
  const MangaImageNetworkView({
    super.key,
    required this.image,
    required this.fit,
    required this.disableGesture,
    this.sourceId,
    this.mangaId,
    this.chapterId,
    this.imageIndex,
    this.jmcAlignment = Alignment.topCenter,
  });

  final ChapterImage image;
  final BoxFit fit;
  final bool disableGesture;
  final String? sourceId;
  final String? mangaId;
  final String? chapterId;
  final int? imageIndex;
  /// Alignment for JMC unscrambled images within FittedBox. Mirrors
  /// [MangaImage.jmcAlignment] — see that field's doc comment.
  final Alignment jmcAlignment;

  @override
  State<MangaImageNetworkView> createState() => _MangaImageNetworkViewState();
}

class _MangaImageNetworkViewState extends State<MangaImageNetworkView> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant MangaImageNetworkView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mirrors `_MangaImageState.didUpdateWidget`'s reset condition prior to
    // this widget's extraction: only restart the fetch when the underlying
    // image actually changed (e.g. widget reused at the same list/page
    // position with a different page's image).
    if (oldWidget.image.url == widget.image.url &&
        oldWidget.image.responseEncoding == widget.image.responseEncoding) {
      return;
    }
    setState(_startLoad);
  }

  void _startLoad() {
    _future = loadAndCacheImageBytes(
      image: widget.image,
      sourceId: widget.sourceId,
      mangaId: widget.mangaId,
      chapterId: widget.chapterId,
      imageIndex: widget.imageIndex,
    );
  }

  /// Calculate segment count for JMC unscrambling. Delegates to the pure
  /// [calculateJmcSegments] function (jmc_unscramble.dart), supplying the
  /// widget-bound inputs it needs.
  int _calculateSegments(int width, int height) {
    return calculateJmcSegments(
      width,
      height,
      chapterId: widget.chapterId,
      url: widget.image.url,
      scrambleId: widget.image.scrambleId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                SizedBox(height: 8),
                Text(
                  '加载中...',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          debugPrint('[MangaImage] FAILED: ${widget.image.url} - ${snapshot.error}');
          return GestureDetector(
            onTap: () => setState(_startLoad),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
                  SizedBox(height: 8),
                  Text('点击重试', style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          );
        }

        final bytes = snapshot.data!;
        final isJmcScrambled = widget.image.scrambleType == ScrambleType.jmc;
        // Disable gesture mode for JMC scrambled images because they render
        // via JmcUnscrambledImage (CustomPaint). The gesture system's transform
        // conflicts with the FittedBox sizing in JmcUnscrambledImage, causing
        // broken display in horizontal page view mode.
        final useGesture = !widget.disableGesture && !isJmcScrambled;

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            return ExtendedImage.memory(
              bytes,
              fit: widget.fit,
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
                if (state.extendedImageLoadState != LoadState.completed) {
                  return null;
                }
                // If image needs unscrambling, use custom painter
                if (isJmcScrambled) {
                  final imageInfo = state.extendedImageInfo;
                  if (imageInfo != null) {
                    final segs = _calculateSegments(imageInfo.image.width, imageInfo.image.height);
                    debugPrint('[JMC Unscramble] chapterId=${widget.chapterId}, url=${widget.image.url}, imgSize=${imageInfo.image.width}x${imageInfo.image.height}, segments=$segs');
                    return JmcUnscrambledImage(
                      image: imageInfo.image,
                      fit: widget.fit,
                      alignment: widget.jmcAlignment,
                      calculateSegments: _calculateSegments,
                    );
                  }
                }
                return state.completedWidget;
              },
            );
          },
        );
      },
    );
  }
}
