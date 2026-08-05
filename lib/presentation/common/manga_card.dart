import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'manga_cover_image.dart';

/// Grid-style manga card. This is the original `_MangaCard` from
/// `discovery_screen.dart`, extracted so it can be shared and tested
/// independently of the screen.
class MangaGridCard extends StatelessWidget {
  final MangaSummary manga;
  const MangaGridCard({super.key, required this.manga});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.detailPath(manga.sourceId, manga.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MangaCoverImage(
                imageUrl: manga.coverUrl,
                headers: manga.headers,
                sourceId: manga.sourceId,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          if (_metaText != null)
            Text(
              _metaText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  /// Chapter count + popularity text, joined with ' · '. Returns null
  /// (hiding the row) when both are missing.
  String? get _metaText {
    final parts = <String>[];
    if (manga.chapterCount != null) {
      parts.add('${manga.chapterCount}章');
    }
    if (manga.popularityText != null && manga.popularityText!.isNotEmpty) {
      parts.add(manga.popularityText!);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// List-style manga item (方案C·详情列表). Shows a larger cover plus
/// title, author, dynamic chips (chapter count / popularity / update
/// time), and an optional description.
class MangaListItem extends StatelessWidget {
  final MangaSummary manga;
  const MangaListItem({super.key, required this.manga});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(AppRoutes.detailPath(manga.sourceId, manga.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 136,
                child: MangaCoverImage(
                  imageUrl: manga.coverUrl,
                  headers: manga.headers,
                  sourceId: manga.sourceId,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    manga.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _buildChips(context),
                  ),
                  if (manga.description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      manga.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds one chip per available field among chapterCount /
  /// popularityText / updateTime, skipping missing/empty ones. Returns
  /// an empty list (Wrap collapses to zero height, no blank row) when
  /// all three are missing.
  List<Widget> _buildChips(BuildContext context) {
    final chips = <Widget>[];
    if (manga.chapterCount != null) {
      chips.add(_buildChip(context, '${manga.chapterCount}章'));
    }
    if (manga.popularityText != null && manga.popularityText!.isNotEmpty) {
      chips.add(_buildChip(context, manga.popularityText!));
    }
    if (manga.updateTime != null && manga.updateTime!.isNotEmpty) {
      chips.add(_buildChip(context, manga.updateTime!));
    }
    return chips;
  }

  Widget _buildChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
