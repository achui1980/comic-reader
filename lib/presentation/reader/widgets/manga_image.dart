import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Displays a single manga page image with loading and error states.
class MangaImage extends StatelessWidget {
  final ChapterImage image;
  final BoxFit fit;

  const MangaImage({
    super.key,
    required this.image,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return ExtendedImage.network(
      image.url,
      fit: fit,
      cache: true,
      headers: image.headers,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          case LoadState.completed:
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
