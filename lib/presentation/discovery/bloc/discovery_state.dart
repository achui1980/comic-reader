import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum DiscoveryStatus { initial, loading, loaded, error, loadingMore }

class DiscoveryState extends Equatable {
  final DiscoveryStatus status;
  final List<MangaSummary> manga;
  final int currentPage;
  final bool hasMore;
  final String? errorMessage;
  final String sourceId;
  final Map<String, String> filters;
  final List<FilterOption> filterOptions;

  const DiscoveryState({
    this.status = DiscoveryStatus.initial,
    this.manga = const [],
    this.currentPage = 1,
    this.hasMore = true,
    this.errorMessage,
    this.sourceId = '',
    this.filters = const {},
    this.filterOptions = const [],
  });

  DiscoveryState copyWith({
    DiscoveryStatus? status,
    List<MangaSummary>? manga,
    int? currentPage,
    bool? hasMore,
    String? errorMessage,
    String? sourceId,
    Map<String, String>? filters,
    List<FilterOption>? filterOptions,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      manga: manga ?? this.manga,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
      sourceId: sourceId ?? this.sourceId,
      filters: filters ?? this.filters,
      filterOptions: filterOptions ?? this.filterOptions,
    );
  }

  @override
  List<Object?> get props => [status, manga, currentPage, hasMore, errorMessage, sourceId, filters, filterOptions];
}
