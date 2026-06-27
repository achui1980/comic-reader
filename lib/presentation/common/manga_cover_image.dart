import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';
import 'package:comic_reader/presentation/reader/widgets/web_direct_image.dart'
    if (dart.library.html) 'package:comic_reader/presentation/reader/widgets/web_direct_image_web.dart';

/// A cover image widget that handles both normal URLs and wu55comic encrypted URLs.
///
/// For normal URLs: uses CachedNetworkImage.
/// For wu55comic encrypted URLs (containing '/static/upload/book/'): downloads
/// shards, decrypts, unscrambles, and displays the decoded image.
class MangaCoverImage extends StatefulWidget {
  final String imageUrl;
  final Map<String, String>? headers;
  final String sourceId;
  final BoxFit fit;

  const MangaCoverImage({
    super.key,
    required this.imageUrl,
    this.headers,
    required this.sourceId,
    this.fit = BoxFit.cover,
  });

  @override
  State<MangaCoverImage> createState() => _MangaCoverImageState();
}

class _MangaCoverImageState extends State<MangaCoverImage> {
  /// In-memory cache for decoded cover results (shared across all instances).
  static final Map<String, Wu55ImageDecodeResult> _coverCache = {};
  static const int _maxCacheSize = 100;

  Wu55ImageDecodeResult? _decoded;
  ui.Image? _image;
  bool _loading = false;
  bool _error = false;

  bool get _isWu55Encrypted =>
      widget.sourceId == Wu55Comic.sourceId &&
      widget.imageUrl.contains('/static/upload/book/');

  @override
  void initState() {
    super.initState();
    if (_isWu55Encrypted) {
      _loadEncryptedCover();
    }
  }

  @override
  void didUpdateWidget(MangaCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _decoded = null;
      _image?.dispose();
      _image = null;
      _error = false;
      if (_isWu55Encrypted) {
        _loadEncryptedCover();
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _loadEncryptedCover() async {
    final url = widget.imageUrl;

    // Check memory cache
    if (_coverCache.containsKey(url)) {
      final cached = _coverCache[url]!;
      await _decodeToImage(cached);
      return;
    }

    if (_loading) return;
    _loading = true;

    try {
      final httpClient = GetIt.I<HttpClient>();
      final shardUrls = Wu55ComicDecoder.buildShardUrls(url);

      // Download both shards in parallel
      // Note: Do NOT wrap with ImageProxy.url() here - the HttpClient's
      // CorsProxyInterceptor already handles proxy prefixing on web.
      final responses = await Future.wait([
        httpClient.execute(FetchConfig(
          url: shardUrls[0],
          responseType: ResponseType.bytes,
          headers: widget.headers,
        )),
        httpClient.execute(FetchConfig(
          url: shardUrls[1],
          responseType: ResponseType.bytes,
          headers: widget.headers,
        )),
      ]);

      final shard0 = Uint8List.fromList(responses[0].data as List<int>);
      final shard1 = Uint8List.fromList(responses[1].data as List<int>);

      final decoded = Wu55ComicDecoder.decodeShards([shard0, shard1]);

      // Cache the result
      if (_coverCache.length >= _maxCacheSize) {
        final keysToRemove = _coverCache.keys.take(20).toList();
        for (final k in keysToRemove) {
          _coverCache.remove(k);
        }
      }
      _coverCache[url] = decoded;

      await _decodeToImage(decoded);
    } catch (e) {
      debugPrint('[MangaCoverImage] Failed to decrypt cover: $e');
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _decodeToImage(Wu55ImageDecodeResult decoded) async {
    try {
      final codec = await ui.instantiateImageCodec(decoded.imageBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decoded = decoded;
          _image = frame.image;
          _loading = false;
        });
      } else {
        frame.image.dispose();
      }
    } catch (e) {
      debugPrint('[MangaCoverImage] Failed to decode image: $e');
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wu55 encrypted cover
    if (_isWu55Encrypted) {
      if (_image != null && _decoded != null) {
        if (_decoded!.needsUnscramble) {
          final sliceCount = Wu55ComicDecoder.getSliceCount(
            _decoded!.bookId,
            _decoded!.pageNumber,
          );
          return FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _image!.width.toDouble(),
              height: _image!.height.toDouble(),
              child: CustomPaint(
                painter: _CoverUnscramblePainter(
                  image: _image!,
                  segments: sliceCount,
                ),
              ),
            ),
          );
        }
        // No unscramble needed - show directly
        return RawImage(
          image: _image,
          fit: widget.fit,
        );
      }
      if (_error) return _buildErrorWidget();
      return _buildPlaceholder();
    }

    // Normal network image
    if (widget.imageUrl.isEmpty) {
      return _buildPlaceholder();
    }

    // Web direct image: bypass CORS proxy for sources with CF-protected CDN
    if (kIsWeb) {
      final source = GetIt.instance<SourceRegistry>().get(widget.sourceId);
      if (source != null && source.webDirectImage) {
        final viewId = 'cover_${widget.sourceId}_${widget.imageUrl.hashCode}';
        final directWidget = buildWebDirectImage(
          imageUrl: widget.imageUrl,
          fit: widget.fit,
          viewId: viewId,
        );
        if (directWidget != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: directWidget,
          );
        }
      }
    }

    return CachedNetworkImage(
      imageUrl: ImageProxy.url(widget.imageUrl),
      httpHeaders: ImageProxy.safeHeaders(widget.headers),
      fit: widget.fit,
      placeholder: (_, __) => _buildPlaceholder(),
      errorWidget: (_, __, ___) => _buildErrorWidget(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(color: Colors.grey.shade200);
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.broken_image),
    );
  }
}

/// Unscramble painter for wu55comic covers.
/// Same algorithm as _JmcUnscramblePainter: horizontal strips in reverse order.
class _CoverUnscramblePainter extends CustomPainter {
  final ui.Image image;
  final int segments;

  _CoverUnscramblePainter({required this.image, required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final paint = Paint()..filterQuality = FilterQuality.low;
    final over = h.toInt() % segments;

    for (int i = 0; i < segments; i++) {
      final move = (h ~/ segments).toDouble();

      // Source Y: from bottom up
      double ySrc = h - (move * (i + 1)) - over;
      // Destination Y: from top down
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
  bool shouldRepaint(_CoverUnscramblePainter oldDelegate) =>
      image != oldDelegate.image || segments != oldDelegate.segments;
}
