import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:extended_image/extended_image.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';
import 'package:comic_reader/core/utils/image_proxy.dart';
import 'manga_image.dart';

/// Horizontal page-turn manga reader.
/// Tap left/right thirds to navigate pages, tap center to toggle controls.
class HorizontalReader extends StatefulWidget {
  final List<ChapterImage> images;
  final int initialPage;
  final ReadingDirection direction;

  const HorizontalReader({
    super.key,
    required this.images,
    this.initialPage = 0,
    this.direction = ReadingDirection.ltr,
  });

  @override
  State<HorizontalReader> createState() => _HorizontalReaderState();
}

class _HorizontalReaderState extends State<HorizontalReader> {
  late final ExtendedPageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = ExtendedPageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTap(TapUpDetails details, BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    final third = screenWidth / 3;

    if (x < third) {
      // Left third: previous page (or next in RTL)
      _navigatePage(widget.direction == ReadingDirection.ltr ? -1 : 1);
    } else if (x > third * 2) {
      // Right third: next page (or previous in RTL)
      _navigatePage(widget.direction == ReadingDirection.ltr ? 1 : -1);
    } else {
      // Center: toggle controls
      context.read<ReaderBloc>().add(const ToggleControls());
    }
  }

  void _navigatePage(int delta) {
    final newPage = _pageController.page!.round() + delta;
    if (newPage >= 0 && newPage < widget.images.length) {
      _pageController.animateToPage(
        newPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (delta > 0) {
      // Reached end, load next chapter
      context.read<ReaderBloc>().add(const LoadNextChapter());
    } else if (delta < 0) {
      // Reached start, load previous chapter
      context.read<ReaderBloc>().add(const LoadPreviousChapter());
    }
  }

  /// Precache the next 2 images for smoother page turns.
  void _precacheAdjacent(int currentPage) {
    for (int i = 1; i <= 2; i++) {
      final nextIdx = currentPage + i;
      if (nextIdx < widget.images.length) {
        final url = ImageProxy.url(widget.images[nextIdx].url);
        precacheImage(ExtendedNetworkImageProvider(url, cache: true), context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ReaderBloc, ReaderState>(
      listenWhen: (prev, curr) => curr.seekPage != null && curr.seekPage != prev.seekPage,
      listener: (context, state) {
        if (state.seekPage != null && _pageController.hasClients) {
          _pageController.jumpToPage(state.seekPage!);
        }
      },
      child: GestureDetector(
        onTapUp: (details) => _onTap(details, context),
        child: ExtendedImageGesturePageView.builder(
          controller: _pageController,
          itemCount: widget.images.length,
          reverse: widget.direction == ReadingDirection.rtl,
          onPageChanged: (page) {
            context.read<ReaderBloc>().add(PageChanged(page));
            _precacheAdjacent(page);
          },
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final state = context.read<ReaderBloc>().state;
            return MangaImage(
              image: widget.images[index],
              fit: BoxFit.contain,
              sourceId: state.sourceId,
              mangaId: state.mangaId,
              chapterId: state.chapterId,
              imageIndex: index,
            );
          },
        ),
      ),
    );
  }
}
