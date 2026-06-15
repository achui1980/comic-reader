import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';

/// Displays a single manga page image with loading and error states.
/// On native: checks local cache first, saves to cache after network load.
/// On web: always loads from network (online-only).
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
      // Get the raw bytes from the cache manager
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
    } catch (_) {
      // Silently ignore cache save failures
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedCache) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // If we have a local file, load from disk
    if (_localPath != null) {
      return ExtendedImage.file(
        File(_localPath!),
        fit: widget.fit,
        loadStateChanged: (state) {
          switch (state.extendedImageLoadState) {
            case LoadState.loading:
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            case LoadState.completed:
              return state.completedWidget;
            case LoadState.failed:
              // If local file fails, fallback to network
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _localPath = null;
                  });
                }
              });
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
          }
        },
      );
    }

    // Load from network
    return ExtendedImage.network(
      ImageProxy.url(widget.image.url),
      fit: widget.fit,
      cache: true,
      headers: widget.image.headers,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          case LoadState.completed:
            // Save to local cache asynchronously
            if (_canCache) {
              _saveToCache(state);
            }
            return state.completedWidget;
          case LoadState.failed:
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
