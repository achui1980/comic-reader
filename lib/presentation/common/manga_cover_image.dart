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
import 'package:comic_reader/data/sources/source_image_transform.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';
import 'package:comic_reader/presentation/common/cloudflare_dialog.dart';
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

  /// In-memory cache of *transformed* cover bytes, for sources whose covers are
  /// served encrypted and therefore have to be fetched and decoded manually.
  static final Map<String, Uint8List> _transformedCoverCache = {};

  Wu55ImageDecodeResult? _decoded;
  ui.Image? _image;
  bool _loading = false;
  bool _error = false;

  /// Set to true when a web direct <img> fails to load (typically a
  /// Cloudflare 403 on the image CDN). Triggers the "go verify" placeholder.
  bool _webCfNeeded = false;

  /// Incremented after the user passes the Cloudflare challenge to force a
  /// brand-new <img> element (new viewId), bypassing the factory cache.
  int _reloadNonce = 0;

  bool get _isWu55Encrypted =>
      widget.sourceId == Wu55Comic.sourceId &&
      widget.imageUrl.contains('/static/upload/book/');

  /// Whether this cover's raw bytes need a per-source transform (typically
  /// decryption) before they can be decoded.
  ///
  /// Such covers cannot be rendered by [CachedNetworkImage], which never
  /// exposes the raw response bytes, so they take the manual fetch-and-decode
  /// path instead.
  bool get _needsByteTransform {
    if (widget.imageUrl.isEmpty) return false;
    if (!GetIt.instance.isRegistered<SourceRegistry>()) return false;
    final source = GetIt.instance<SourceRegistry>().get(widget.sourceId);
    return source != null && source.transformsImageBytes;
  }

  /// Kicks off whichever manual load strategy this cover needs, if any.
  void _startManualLoadIfNeeded() {
    if (_isWu55Encrypted) {
      _loadEncryptedCover();
    } else if (_needsByteTransform) {
      _loadTransformedCover();
    }
  }

  @override
  void initState() {
    super.initState();
    _startManualLoadIfNeeded();
  }

  @override
  void didUpdateWidget(MangaCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _decoded = null;
      _image?.dispose();
      _image = null;
      _error = false;
      _webCfNeeded = false;
      _startManualLoadIfNeeded();
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

  /// Fetches a cover whose bytes are encrypted at rest, applies the owning
  /// source's byte transform, and decodes the result.
  Future<void> _loadTransformedCover() async {
    final url = widget.imageUrl;

    final cached = _transformedCoverCache[url];
    if (cached != null) {
      await _decodeBytesToImage(cached);
      return;
    }

    if (_loading) return;
    _loading = true;

    try {
      // Note: Do NOT wrap with ImageProxy.url() here - the HttpClient's
      // CorsProxyInterceptor already handles proxy prefixing on web.
      final response = await GetIt.I<HttpClient>().execute(FetchConfig(
        url: url,
        responseType: ResponseType.bytes,
        headers: widget.headers,
      ));
      final data = response.data;
      if (data is! List<int>) {
        throw const FormatException('Cover response did not contain bytes');
      }
      final bytes = applySourceImageTransform(
        Uint8List.fromList(data),
        widget.sourceId,
      );

      if (_transformedCoverCache.length >= _maxCacheSize) {
        for (final k in _transformedCoverCache.keys.take(20).toList()) {
          _transformedCoverCache.remove(k);
        }
      }
      _transformedCoverCache[url] = bytes;

      await _decodeBytesToImage(bytes);
    } catch (e) {
      debugPrint('[MangaCoverImage] Failed to load cover: $e');
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  /// Decodes already-transformed cover [bytes] into a [ui.Image].
  Future<void> _decodeBytesToImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
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

    // Covers whose raw bytes need a per-source transform (e.g. AES-encrypted
    // images) are fetched and decoded manually above, because
    // CachedNetworkImage never exposes raw bytes. This deliberately takes
    // precedence over the web-direct <img> path below, which cannot apply any
    // transform at all since the bytes never enter Dart.
    if (_needsByteTransform) {
      if (_image != null) {
        return RawImage(image: _image, fit: widget.fit);
      }
      if (_error) return _buildErrorWidget();
      return _buildPlaceholder();
    }

    // Web direct image: bypass CORS proxy for sources with CF-protected CDN
    if (kIsWeb) {
      final source = GetIt.instance<SourceRegistry>().get(widget.sourceId);
      if (source != null && source.webDirectImage) {
        // Image CDN is behind Cloudflare and returned 403 (no cf_clearance
        // cookie yet). Show a "go verify" placeholder instead of a broken img.
        if (_webCfNeeded) {
          return _buildCfPlaceholder(source.name);
        }
        // Nonce makes the viewId (and thus the <img> element) change after the
        // user passes the CF challenge, forcing a fresh load with cookies.
        final viewId =
            'cover_${widget.sourceId}_${widget.imageUrl.hashCode}_$_reloadNonce';
        final directWidget = buildWebDirectImage(
          imageUrl: widget.imageUrl,
          fit: widget.fit,
          viewId: viewId,
          onLoadError: () {
            if (mounted && !_webCfNeeded) {
              setState(() => _webCfNeeded = true);
            }
          },
        );
        if (directWidget != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: directWidget,
          );
        }
      }
    }

    final resolvedUrl = ImageProxy.url(widget.imageUrl);
    return CachedNetworkImage(
      imageUrl: resolvedUrl,
      httpHeaders: ImageProxy.safeHeaders(widget.headers),
      fit: widget.fit,
      placeholder: (_, __) => _buildPlaceholder(),
      imageBuilder: (context, imageProvider) {
        return Image(image: imageProvider, fit: widget.fit);
      },
      errorWidget: (_, url, error) {
        debugPrint(
          '[MangaCoverImage] FAILED sourceId=${widget.sourceId} '
          'url=$url error=$error (${error.runtimeType})',
        );
        return _buildErrorWidget();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(color: Colors.grey.shade200);
  }

  /// Placeholder shown when a web direct image fails due to Cloudflare on the
  /// image CDN. Tapping it opens the CF verification flow; once the user
  /// passes the challenge we rebuild the <img> with a fresh viewId.
  Widget _buildCfPlaceholder(String sourceName) {
    return Material(
      color: Colors.grey.shade200,
      child: InkWell(
        onTap: () async {
          final verified = await showCloudflareDialog(
            context,
            sourceId: widget.sourceId,
            sourceName: sourceName,
          );
          if (verified && mounted) {
            setState(() {
              _webCfNeeded = false;
              _reloadNonce++;
            });
          }
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined,
                  color: Colors.orange.shade700, size: 28),
              const SizedBox(height: 4),
              Text(
                '去验证',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
