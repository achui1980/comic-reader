import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum SearchStatus { initial, loading, loaded, error, loadingMore }

class SearchState extends Equatable {
  final SearchStatus status;
  final List<MangaSummary> results;
  final String keyword;
  final String sourceId;
  final int currentPage;
  final bool hasMore;
  final String? errorMessage;

  const SearchState({
    this.status = SearchStatus.initial,
    this.results = const [],
    this.keyword = '',
    this.sourceId = '',
    this.currentPage = 1,
    this.hasMore = true,
    this.errorMessage,
  });

  SearchState copyWith({
    SearchStatus? status,
    List<MangaSummary>? results,
    String? keyword,
    String? sourceId,
    int? currentPage,
    bool? hasMore,
    String? errorMessage,
  }) {
    return SearchState(
      status: status ?? this.status,
      results: results ?? this.results,
      keyword: keyword ?? this.keyword,
      sourceId: sourceId ?? this.sourceId,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, results, keyword, sourceId, currentPage, hasMore, errorMessage];
}
