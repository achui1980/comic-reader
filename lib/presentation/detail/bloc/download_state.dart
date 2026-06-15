import 'package:equatable/equatable.dart';

/// Download status for a single chapter.
enum ChapterDownloadStatus {
  none,        // Not downloaded, not queued
  queued,      // Waiting in download queue
  downloading, // Currently being downloaded
  cached,      // Fully cached/downloaded
  failed,      // Download failed
}

/// State for the download/cache manager on the detail screen.
class DownloadState extends Equatable {
  /// Per-chapter download status.
  final Map<String, ChapterDownloadStatus> chapters;

  /// Currently downloading chapter ID (null if idle).
  final String? activeChapterId;

  /// Progress of the active download: images completed.
  final int activeProgress;

  /// Total images in the active download.
  final int activeTotal;

  /// Queue of chapter IDs waiting to be downloaded.
  final List<String> queue;

  const DownloadState({
    this.chapters = const {},
    this.activeChapterId,
    this.activeProgress = 0,
    this.activeTotal = 0,
    this.queue = const [],
  });

  DownloadState copyWith({
    Map<String, ChapterDownloadStatus>? chapters,
    String? activeChapterId,
    int? activeProgress,
    int? activeTotal,
    List<String>? queue,
    bool clearActive = false,
  }) {
    return DownloadState(
      chapters: chapters ?? this.chapters,
      activeChapterId: clearActive ? null : (activeChapterId ?? this.activeChapterId),
      activeProgress: activeProgress ?? this.activeProgress,
      activeTotal: activeTotal ?? this.activeTotal,
      queue: queue ?? this.queue,
    );
  }

  @override
  List<Object?> get props => [chapters, activeChapterId, activeProgress, activeTotal, queue];
}
