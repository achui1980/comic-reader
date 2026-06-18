import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';

/// Transparent overlay with reader controls.
/// Shows a top bar (back button, title) and bottom bar (page slider, chapter nav).
class ReaderControls extends StatelessWidget {
  const ReaderControls({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReaderBloc, ReaderState>(
      builder: (context, state) {
        return Column(
          children: [
            // Top bar
            _TopBar(
              title: state.chapterTitle ?? '',
              sourceId: state.sourceId,
              mangaId: state.mangaId,
              chapterId: state.chapterId,
            ),
            const Spacer(),
            // Bottom bar
            _BottomBar(
              currentPage: state.currentPage,
              totalPages: state.totalPages,
              hasPrevious: state.hasPreviousChapter,
              hasNext: state.hasNextChapter,
              layoutMode: state.layoutMode,
            ),
          ],
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String sourceId;
  final String mangaId;
  final String chapterId;
  const _TopBar({required this.title, required this.sourceId, required this.mangaId, required this.chapterId});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 4,
        right: 16,
        bottom: 12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Open in built-in browser button
          IconButton(
            icon: const Icon(Icons.open_in_browser, color: Colors.white),
            onPressed: () {
              final registry = GetIt.instance<SourceRegistry>();
              final source = registry.get(sourceId);
              if (source != null) {
                final url = source.getChapterWebUrl(mangaId, chapterId);
                if (url != null) {
                  context.push(
                    AppRoutes.webviewPath(sourceId),
                    extra: {'url': url},
                  );
                }
              }
            },
            tooltip: '浏览器阅读',
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final bool hasPrevious;
  final bool hasNext;
  final LayoutMode layoutMode;

  const _BottomBar({
    required this.currentPage,
    required this.totalPages,
    required this.hasPrevious,
    required this.hasNext,
    required this.layoutMode,
  });

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ReaderBloc>();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        left: 16,
        right: 16,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Page indicator + layout toggle
          Row(
            children: [
              Text(
                '${currentPage + 1} / $totalPages',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              // Layout toggle button
              IconButton(
                icon: Icon(
                  layoutMode == LayoutMode.horizontal
                      ? Icons.view_day_outlined
                      : Icons.view_carousel_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () {
                  bloc.add(ChangeLayoutMode(
                    layoutMode == LayoutMode.horizontal
                        ? LayoutMode.vertical
                        : LayoutMode.horizontal,
                  ));
                },
                tooltip: layoutMode == LayoutMode.horizontal ? '切换竖向' : '切换横向',
              ),
            ],
          ),
          // Page slider
          if (totalPages > 1)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: currentPage.toDouble(),
                min: 0,
                max: (totalPages - 1).toDouble(),
                onChanged: (value) {
                  bloc.add(SeekToPage(value.round()));
                },
              ),
            ),
          // Chapter navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: hasPrevious
                    ? () => bloc.add(const LoadPreviousChapter())
                    : null,
                icon: const Icon(Icons.skip_previous, size: 18),
                label: const Text('上一话'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
              TextButton.icon(
                onPressed:
                    hasNext ? () => bloc.add(const LoadNextChapter()) : null,
                icon: const Icon(Icons.skip_next, size: 18),
                label: const Text('下一话'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
