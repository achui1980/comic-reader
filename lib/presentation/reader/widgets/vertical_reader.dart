import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';
import 'manga_image.dart';
import 'manga_image_loader.dart';
import 'translation_badge.dart';
import 'reader_translation_overlay_painter.dart';

/// Vertical scrolling (webtoon-style) manga reader.
/// Images are stacked vertically in a scrollable list.
/// Tap center to toggle controls, scroll to bottom to auto-load next chapter.
class VerticalReader extends StatefulWidget {
  final List<ChapterImage> images;
  final int initialPage;

  const VerticalReader({super.key, required this.images, this.initialPage = 0});

  @override
  State<VerticalReader> createState() => _VerticalReaderState();
}

class _VerticalReaderState extends State<VerticalReader> {
  late final ScrollController _scrollController;

  /// Tracks which page indices have already been prefetched this session,
  /// to avoid re-issuing the same download on every scroll tick.
  final Set<int> _prefetchedIndices = {};

  /// Tracks the last page index dispatched via [PageChanged]/translation
  /// requests, to avoid re-issuing the same events on every scroll tick.
  int? _lastKnownPage;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients && widget.images.isNotEmpty) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final scrollOffset = _scrollController.offset;
      final screenWidth = MediaQuery.of(context).size.width;
      final estimatedImageHeight = screenWidth * 1.4;
      final estimatedPage = (scrollOffset / estimatedImageHeight).floor();
      final page = estimatedPage.clamp(0, widget.images.length - 1);
      final bloc = context.read<ReaderBloc>();
      final pageChanged = page != _lastKnownPage;
      if (pageChanged) {
        bloc.add(PageChanged(page));
        _lastKnownPage = page;
      }
      _prefetchWindow(page);
      // Request translation for the page currently scrolled into view; `page`
      // is a scroll-offset heuristic, so this only re-fires when it changes.
      if (pageChanged && bloc.state.translationEnabled) {
        bloc.add(TranslatePageRequested(pageIndex: page));
      }

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (scrollOffset >= maxScroll - viewportHeight * 0.5) {
        if (!bloc.state.isAppendingNext && bloc.state.canAppendNext) {
          bloc.add(const AppendNextChapter());
        }
      }
    }
  }

  /// Prefetches the next 2 images' bytes (mirrors horizontal_reader's
  /// `_precacheAdjacent` window size) so they're already in
  /// [ChapterCacheService] by the time the user scrolls to them.
  void _prefetchWindow(int currentPage) {
    final state = context.read<ReaderBloc>().state;
    for (int i = 1; i <= 2; i++) {
      final nextIdx = currentPage + i;
      if (nextIdx >= widget.images.length) continue;
      if (!_prefetchedIndices.add(nextIdx)) continue; // already prefetched
      final image = widget.images[nextIdx];
      unawaited(
        loadAndCacheImageBytes(
          image: image,
          sourceId: state.sourceId,
          mangaId: state.mangaId,
          chapterId: state.chapterId,
          imageIndex: nextIdx,
        ).catchError((Object e) {
          debugPrint('[VerticalReader] Prefetch failed for index $nextIdx: $e');
          return Uint8List(0);
        }),
      );
    }
  }

  void _showTranslationError(
    BuildContext itemContext,
    int pageIndex,
    String? errorMessage,
  ) {
    ScaffoldMessenger.of(itemContext).showSnackBar(
      SnackBar(
        content: Text(errorMessage ?? '翻译失败'),
        action: SnackBarAction(
          label: '重试',
          onPressed: () => itemContext.read<ReaderBloc>().add(
            TranslatePageRetried(pageIndex: pageIndex),
          ),
        ),
      ),
    );
  }

  void _onTap(TapUpDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    final third = screenWidth / 3;

    if (x > third && x < third * 2) {
      // Center tap: toggle controls
      context.read<ReaderBloc>().add(const ToggleControls());
    }
    // Left/right taps do nothing in vertical mode (scroll is primary navigation)
  }

  Future<void> _onRefresh() {
    final completer = Completer<void>();
    final bloc = context.read<ReaderBloc>();
    bloc.add(const RefreshChapter());
    // Listen for state change to complete the future
    late final StreamSubscription sub;
    sub = bloc.stream.listen((state) {
      if (state.status == ReaderStatus.loaded) {
        completer.complete();
        sub.cancel();
      }
    });
    // Timeout after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: _onTap,
      child: BlocBuilder<ReaderBloc, ReaderState>(
        buildWhen: (prev, curr) =>
            prev.isAppendingNext != curr.isAppendingNext ||
            prev.images != curr.images ||
            prev.pageTranslations != curr.pageTranslations,
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: widget.images.length + (state.isAppendingNext ? 1 : 0),
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                // Loading indicator at the bottom
                if (index >= widget.images.length) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final info =
                    state.pageTranslations[index] ?? PageTranslationInfo.idle;
                return SizedBox(
                  width: double.infinity,
                  child: Stack(
                    children: [
                      MangaImage(
                        image: widget.images[index],
                        fit: BoxFit.fitWidth,
                        disableGesture: true,
                        sourceId: state.sourceId,
                        mangaId: state.mangaId,
                        chapterId: state.chapterId,
                        imageIndex: index,
                      ),
                      if (info.status == PageTranslationStatus.done &&
                          info.translation != null &&
                          info.imageSize != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: ReaderTranslationOverlayPainter(
                                imageSize: info.imageSize!,
                                regions: info.translation!.regions,
                              ),
                            ),
                          ),
                        ),
                      if (info.status == PageTranslationStatus.loading)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: TranslationBadge.loading(),
                        ),
                      if (info.status == PageTranslationStatus.error)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: TranslationBadge.error(
                            onTap: () => _showTranslationError(
                              context,
                              index,
                              info.errorMessage,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
