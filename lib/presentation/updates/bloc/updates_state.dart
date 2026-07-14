import 'package:equatable/equatable.dart';
import 'package:comic_reader/data/local/update_store.dart';

/// State for the library updates tab.
class UpdatesState extends Equatable {
  final bool isLoading;
  final List<NewChapter> chapters;
  final bool isUpdating;
  final int progress;
  final int total;

  const UpdatesState({
    this.isLoading = true,
    this.chapters = const [],
    this.isUpdating = false,
    this.progress = 0,
    this.total = 0,
  });

  UpdatesState copyWith({
    bool? isLoading,
    List<NewChapter>? chapters,
    bool? isUpdating,
    int? progress,
    int? total,
  }) {
    return UpdatesState(
      isLoading: isLoading ?? this.isLoading,
      chapters: chapters ?? this.chapters,
      isUpdating: isUpdating ?? this.isUpdating,
      progress: progress ?? this.progress,
      total: total ?? this.total,
    );
  }

  @override
  List<Object?> get props => [isLoading, chapters, isUpdating, progress, total];
}
