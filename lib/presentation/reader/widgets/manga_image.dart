import 'dart:convert' show base64Decode;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/core/utils/save_image.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/reader/widgets/manga_image_file.dart'
    if (dart.library.io) 'package:comic_reader/presentation/reader/widgets/manga_image_file_io.dart';
import 'package:comic_reader/presentation/reader/widgets/web_direct_image.dart'
    if (dart.library.html) 'package:comic_reader/presentation/reader/widgets/web_direct_image_web.dart';
import 'jmc_unscramble.dart';
import 'manga_image_network_view.dart';
import 'wu55_memory_image.dart';

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

  @override
  void didUpdateWidget(covariant MangaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.url == widget.image.url &&
        oldWidget.image.responseEncoding == widget.image.responseEncoding) {
      return;
    }
    _localPath = null;
    if (_canCache) {
      _checkedCache = false;
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

  /// Whether this image must be rendered via a raw `<img>` element on web
  /// (bypassing Dio/the CORS proxy) so the browser attaches its own
  /// Cloudflare cookies. Only applies on web, and only for sources that
  /// opt in via [MangaSource.webDirectImage]. Such images manage their own
  /// loading and must never be double-fetched through [MangaImageNetworkView].
  bool get _usesWebDirectImage {
    if (!kIsWeb || widget.sourceId == null) return false;
    final source = GetIt.instance<SourceRegistry>().get(widget.sourceId!);
    return source != null && source.webDirectImage;
  }

  /// Calculate segment count for JMC unscrambling. Delegates to the pure
  /// [calculateJmcSegments] function (jmc_unscramble.dart), supplying the
  /// State-bound inputs it needs.
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
        responseEncoding: widget.image.responseEncoding,
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
        return Wu55MemoryImage(
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
                  return JmcUnscrambledImage(
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
      debugPrint('[MangaImage] data: URI detected, scrambleType=${widget.image.scrambleType}, '
          'bookId=${widget.image.wu55BookId}, pageNumber=${widget.image.wu55PageNumber}');
      return _buildMemoryImage();
    }

    // Web direct image: bypass CORS proxy for sources with CF-protected CDN.
    // Uses a raw HTML <img> element so the browser sends its own CF cookies.
    if (_usesWebDirectImage) {
      final viewId = '${widget.sourceId}_${widget.image.url.hashCode}';
      final directWidget = buildWebDirectImage(
        imageUrl: widget.image.url,
        fit: widget.fit,
        viewId: viewId,
      );
      if (directWidget != null) {
        return directWidget;
      }
    }

    // All other images -- both `binary` and `base64OrBinary` responses --
    // are downloaded as raw bytes through the shared HttpClient (with
    // retries + integrity checks) and rendered locally via
    // ExtendedImage.memory. This unifies native/web behavior instead of
    // relying on extended_image's built-in network loader, whose
    // retry/timeLimit options are dead code on web (network_image_web.dart
    // never reads them) and which has no way to detect a truncated-but-200
    // response from a misbehaving CDN/proxy.
    return MangaImageNetworkView(
      image: widget.image,
      fit: widget.fit,
      disableGesture: widget.disableGesture,
      sourceId: widget.sourceId,
      mangaId: widget.mangaId,
      chapterId: widget.chapterId,
      imageIndex: widget.imageIndex,
      jmcAlignment: widget.jmcAlignment,
    );
  }
}
