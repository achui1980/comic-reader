import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'reader_state.dart';

abstract class ReaderEvent extends Equatable {
  const ReaderEvent();

  @override
  List<Object?> get props => [];
}

/// Load a chapter by source/manga/chapter IDs
class LoadChapter extends ReaderEvent {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final List<ChapterItem> chapterList;
  final int initialPage;

  const LoadChapter({
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    this.chapterList = const [],
    this.initialPage = 0,
  });

  @override
  List<Object?> get props =>
      [sourceId, mangaId, chapterId, chapterList, initialPage];
}

/// User changed the current page
class PageChanged extends ReaderEvent {
  final int page;

  const PageChanged(this.page);

  @override
  List<Object?> get props => [page];
}

/// Toggle controls overlay visibility
class ToggleControls extends ReaderEvent {
  const ToggleControls();
}

/// Hide controls (used by auto-hide timer)
class HideControls extends ReaderEvent {
  const HideControls();
}

/// Change layout mode (horizontal/vertical)
class ChangeLayoutMode extends ReaderEvent {
  final LayoutMode mode;

  const ChangeLayoutMode(this.mode);

  @override
  List<Object?> get props => [mode];
}

/// Change reading direction (LTR/RTL)
class ChangeDirection extends ReaderEvent {
  final ReadingDirection direction;

  const ChangeDirection(this.direction);

  @override
  List<Object?> get props => [direction];
}

/// Load next chapter
class LoadNextChapter extends ReaderEvent {
  const LoadNextChapter();
}

/// Load previous chapter
class LoadPreviousChapter extends ReaderEvent {
  const LoadPreviousChapter();
}

/// Seek to a specific page (from slider)
class SeekToPage extends ReaderEvent {
  final int page;
  const SeekToPage(this.page);

  @override
  List<Object?> get props => [page];
}

/// Start auto page-turn at a given interval
class StartAutoPageTurn extends ReaderEvent {
  final int intervalSeconds;
  const StartAutoPageTurn({required this.intervalSeconds});

  @override
  List<Object?> get props => [intervalSeconds];
}

/// Stop auto page-turn
class StopAutoPageTurn extends ReaderEvent {
  const StopAutoPageTurn();
}

/// Internal tick event for auto page-turn
class AutoPageTick extends ReaderEvent {
  const AutoPageTick();
}
