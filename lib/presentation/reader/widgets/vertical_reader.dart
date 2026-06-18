import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';
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
    // Update current page based on scroll position
    if (_scrollController.hasClients && widget.images.isNotEmpty) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final scrollOffset = _scrollController.offset;
      // Estimate current page based on typical manga page aspect ratio (~1.4:1)
      final screenWidth = MediaQuery.of(context).size.width;
      final estimatedImageHeight = screenWidth * 1.4;
      final estimatedPage = (scrollOffset / estimatedImageHeight).floor();
      final page = estimatedPage.clamp(0, widget.images.length - 1);
      context.read<ReaderBloc>().add(PageChanged(page));

      // Check if we've scrolled near the bottom - use BLoC state as guard
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (scrollOffset >= maxScroll - viewportHeight * 0.5) {
        final bloc = context.read<ReaderBloc>();
        if (!bloc.state.isAppendingNext && bloc.state.canAppendNext) {
          bloc.add(const AppendNextChapter());
        }
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
            prev.images != curr.images,
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
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                return SizedBox(
                  width: double.infinity,
                  child: MangaImage(
                    image: widget.images[index],
                    fit: BoxFit.fitWidth,
                    disableGesture: true,
                    sourceId: state.sourceId,
                    mangaId: state.mangaId,
                    chapterId: state.chapterId,
                    imageIndex: index,
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
