import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'manga_image.dart';

/// Vertical scrolling (webtoon-style) manga reader.
/// Images are stacked vertically in a scrollable list.
/// Tap center to toggle controls, scroll to bottom to auto-load next chapter.
class VerticalReader extends StatefulWidget {
  final List<ChapterImage> images;
  final int initialPage;

  const VerticalReader({
    super.key,
    required this.images,
    this.initialPage = 0,
  });

  @override
  State<VerticalReader> createState() => _VerticalReaderState();
}

class _VerticalReaderState extends State<VerticalReader> {
  late final ScrollController _scrollController;
  bool _isLoadingNext = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(VerticalReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset loading flag when images change (new chapter loaded)
    if (oldWidget.images != widget.images) {
      _isLoadingNext = false;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Update current page based on scroll position
    if (_scrollController.hasClients && widget.images.isNotEmpty) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final scrollOffset = _scrollController.offset;
      // Estimate current page based on average image height
      final estimatedPage = (scrollOffset / viewportHeight).floor();
      final page = estimatedPage.clamp(0, widget.images.length - 1);
      context.read<ReaderBloc>().add(PageChanged(page));

      // Check if we've scrolled near the bottom
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (scrollOffset >= maxScroll - viewportHeight * 0.5 &&
          !_isLoadingNext) {
        _isLoadingNext = true;
        context.read<ReaderBloc>().add(const LoadNextChapter());
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: _onTap,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: widget.images.length,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          final state = context.read<ReaderBloc>().state;
          return SizedBox(
            width: double.infinity,
            child: MangaImage(
              image: widget.images[index],
              fit: BoxFit.fitWidth,
              sourceId: state.sourceId,
              mangaId: state.mangaId,
              chapterId: state.chapterId,
              imageIndex: index,
            ),
          );
        },
      ),
    );
  }
}
