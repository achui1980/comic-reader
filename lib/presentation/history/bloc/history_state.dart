import 'package:equatable/equatable.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';

class HistoryState extends Equatable {
  final bool isLoading;
  final List<HistoryEntry> entries;

  const HistoryState({
    this.isLoading = true,
    this.entries = const [],
  });

  HistoryState copyWith({
    bool? isLoading,
    List<HistoryEntry>? entries,
  }) {
    return HistoryState(
      isLoading: isLoading ?? this.isLoading,
      entries: entries ?? this.entries,
    );
  }

  @override
  List<Object?> get props => [isLoading, entries];
}
