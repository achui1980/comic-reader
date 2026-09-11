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
  /// Effective scramble info for [_localPath], resolved from this
  /// chapter's on-disk scramble manifest (see [resolveScrambleFromManifest]
  /// / [ChapterCacheService.readScrambleManifest]) when available. `null`
  /// means "use `widget.image` as-is" (no manifest, or no local file to
  /// look one up for). Only computed for the local-file render path -- the
  /// live-network path (`MangaImageNetworkView`) always has a freshly-
  /// parsed [ChapterImage] and doesn't need this.
  ChapterImage? _manifestImage;

  /// Cache of the bytes decoded from a `data:` URI, plus the exact url
  /// String instance they came from.
  ///
  /// Sources that pre-decode images in the repository layer (HanabiManga,
  /// wu55comic) hand us a `data:image/...;base64,<payload>` URI whose
  /// payload is the entire image -- for HanabiManga (raw-pixel PNG
  /// re-encode) that is routinely multiple megabytes. Without this cache,
  /// every single widget rebuild re-ran `base64Decode` over that whole
  /// payload *and* produced a fresh `Uint8List`, which meant a fresh
  /// `MemoryImage` identity, which meant Flutter's image cache missed and
  /// re-decoded the PNG from scratch. That combination burned huge amounts
  /// of CPU while scrolling and made every page visibly flash each time
  /// the widget rebuilt (e.g. on every progressive-loading state emission).
  ///
  /// Keyed by `identical()` on the url String rather than `==` on purpose:
  /// comparing multi-megabyte strings for equality is itself expensive, and
  /// the ChapterImage objects we get from ReaderBloc's state are stable
  /// instances, so reference identity is both correct and O(1) here.
  Uint8List? _dataUriBytes;
  String? _dataUriSource;

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
    // Compare by reference first: for pre-decoded `data:` URI sources the
    // url is a multi-megabyte string, so falling straight through to `==`
    // on every widget update was itself a measurable CPU cost while
    // scrolling. ReaderBloc hands out stable ChapterImage instances, so an
    // identical url almost always short-circuits here; `==` remains as the
    // correctness fallback for genuinely-distinct-but-equal strings.
    final sameUrl = identical(oldWidget.image.url, widget.image.url) ||
        oldWidget.image.url == widget.image.url;
    if (sameUrl &&
        oldWidget.image.responseEncoding == widget.image.responseEncoding) {
      return;
    }
    _localPath = null;
    _manifestImage = null;
    _dataUriBytes = null;
    _dataUriSource = null;
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
    ChapterImage? manifestImage;
    if (path != null) {
      final manifest = await cacheService.readScrambleManifest(
        widget.sourceId!,
        widget.mangaId!,
        widget.chapterId!,
      );
      manifestImage = resolveScrambleFromManifest(
        widget.image,
        manifest,
        widget.imageIndex!,
      );
    }
    if (mounted) {
      setState(() {
        _localPath = path;
        _manifestImage = manifestImage;
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
    final effectiveImage = _manifestImage ?? widget.image;
    return calculateJmcSegments(
      width,
      height,
      chapterId: widget.chapterId,
      url: effectiveImage.url,
      scrambleId: effectiveImage.scrambleId,
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
        sourceId: widget.sourceId,
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
      // Reuse the previously-decoded bytes when this build is for the same
      // url instance (see [_dataUriBytes] for why this matters so much).
      var bytes = _dataUriBytes;
      if (bytes == null || !identical(_dataUriSource, uri)) {
        final commaIdx = uri.indexOf(',');
        if (commaIdx < 0) {
          return const Center(child: Text('Invalid data URI'));
        }
        bytes = base64Decode(uri.substring(commaIdx + 1));
        _dataUriBytes = bytes;
        _dataUriSource = uri;
      }

      // If wu55 scrambled, use custom unscramble painter
      if (widget.image.scrambleType == ScrambleType.wu55) {
        return Wu55MemoryImage(
          imageBytes: bytes,
          fit: widget.fit,
          alignment: widget.jmcAlignment,
          bookId: widget.image.wu55BookId ?? 0,
          pageNumber: widget.image.wu55PageNumber ?? 0,
        );
      }

      // Not scrambled, render directly. Passing the cached Uint8List
      // straight through (rather than copying it via Uint8List.fromList)
      // keeps the MemoryImage identity stable across rebuilds so Flutter's
      // image cache hits instead of re-decoding the PNG every time.
      return Image.memory(
        bytes,
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
      // Prefer the manifest-resolved scramble info (accurate as of
      // download time) over `widget.image`'s, which for a previously-
      // downloaded/cached chapter may reflect a stale live re-derivation
      // (see `resolveScrambleFromManifest` doc for why).
      final effectiveImage = _manifestImage ?? widget.image;
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
        onCompleted: effectiveImage.scrambleType == ScrambleType.jmc
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
