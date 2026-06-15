import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';
import 'widgets/horizontal_reader.dart';
import 'widgets/vertical_reader.dart';
import 'widgets/reader_controls.dart';

/// Full-screen immersive manga reader.
/// Hides system UI, provides gesture-based navigation,
/// and supports horizontal (page-flip) and vertical (webtoon scroll) modes.
class ReaderScreen extends StatefulWidget {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final List<dynamic> chapterList;
  final int initialPage;

  const ReaderScreen({
    super.key,
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    this.chapterList = const [],
    this.initialPage = 0,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final ReaderBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = ReaderBloc(
      repository: GetIt.instance<MangaRepository>(),
      readingHistoryStore: GetIt.instance<ReadingHistoryStore>(),
    );
    // Cast chapter list items to ChapterItem
    final chapters = widget.chapterList
        .whereType<ChapterItem>()
        .toList();
    _bloc.add(LoadChapter(
      sourceId: widget.sourceId,
      mangaId: widget.mangaId,
      chapterId: widget.chapterId,
      chapterList: chapters,
      initialPage: widget.initialPage,
    ));
    _enterImmersiveMode();
  }

  @override
  void dispose() {
    _exitImmersiveMode();
    _bloc.close();
    super.dispose();
  }

  void _enterImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
  }

  void _exitImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BlocBuilder<ReaderBloc, ReaderState>(
          builder: (context, state) {
            return Stack(
              children: [
                // Main reader content
                _buildReaderContent(state),
                // Persistent page indicator (always visible)
                if (state.status == ReaderStatus.loaded)
                  _buildPageIndicator(state),
                // Controls overlay (animated)
                _buildControlsOverlay(state),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReaderContent(ReaderState state) {
    switch (state.status) {
      case ReaderStatus.initial:
      case ReaderStatus.loading:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      case ReaderStatus.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              Text(
                state.errorMessage ?? '加载失败',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _bloc.add(LoadChapter(
                  sourceId: widget.sourceId,
                  mangaId: widget.mangaId,
                  chapterId: state.chapterId.isNotEmpty
                      ? state.chapterId
                      : widget.chapterId,
                )),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      case ReaderStatus.loaded:
        if (state.layoutMode == LayoutMode.vertical) {
          return VerticalReader(
            images: state.images,
            initialPage: state.currentPage,
          );
        }
        return HorizontalReader(
          images: state.images,
          initialPage: state.currentPage,
          direction: state.direction,
        );
    }
  }

  Widget _buildControlsOverlay(ReaderState state) {
    return AnimatedOpacity(
      opacity: state.showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !state.showControls,
        child: const ReaderControls(),
      ),
    );
  }

  Widget _buildPageIndicator(ReaderState state) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 12,
      right: 16,
      child: AnimatedOpacity(
        opacity: state.showControls ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${state.currentPage + 1} / ${state.totalPages}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
