import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum SearchStatus { initial, loading, loaded, error, loadingMore }

/// Per-source search result slice, used in cross-source (aggregate) mode.
///
/// Each enabled source runs its own search independently; a slice tracks that
/// one source's results, pagination and status so a single source failing or
/// still loading never blocks the others.
class SourceSearchSlice extends Equatable {
  final String sourceId;
  final SearchStatus status;
  final List<MangaSummary> results;
  final int currentPage;
  final bool hasMore;
  final String? errorMessage;

  const SourceSearchSlice({
    required this.sourceId,
    this.status = SearchStatus.initial,
    this.results = const [],
    this.currentPage = 1,
    this.hasMore = true,
    this.errorMessage,
  });

  SourceSearchSlice copyWith({
    SearchStatus? status,
    List<MangaSummary>? results,
    int? currentPage,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SourceSearchSlice(
      sourceId: sourceId,
      status: status ?? this.status,
      results: results ?? this.results,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [sourceId, status, results, currentPage, hasMore, errorMessage];
}

class SearchState extends Equatable {
  // --- Single-source fields (backward compatible) ---
  final SearchStatus status;
  final List<MangaSummary> results;
  final String keyword;
  final String sourceId;
  final int currentPage;
  final bool hasMore;
  final String? errorMessage;

  // --- Cross-source (aggregate) fields ---
  /// When true, the search fans out over every enabled source and results are
  /// grouped per source in [slices]. When false, only the single [sourceId]
  /// path is used (legacy behavior).
  final bool aggregateMode;

  /// Per-source slices keyed by sourceId. Only populated in aggregate mode.
  final Map<String, SourceSearchSlice> slices;

  // --- AI (natural-language search) fields ---
  /// When true, submitting the query first runs it through the AI intent
  /// parser (#15) to extract search keywords before searching. Falls back to a
  /// plain search when AI is unusable or extraction fails.
  final bool aiMode;

  /// Human-readable note of how the AI interpreted the last query (e.g. the
  /// original natural-language input and the extracted keyword). Empty when AI
  /// was not used or did not alter the query.
  final String aiInterpretation;

  const SearchState({
    this.status = SearchStatus.initial,
    this.results = const [],
    this.keyword = '',
    this.sourceId = '',
    this.currentPage = 1,
    this.hasMore = true,
    this.errorMessage,
    this.aggregateMode = false,
    this.slices = const {},
    this.aiMode = false,
    this.aiInterpretation = '',
  });

  /// Flattened, de-duplicated results across all source slices, ordered by the
  /// slice insertion order (registry.enabled order). Only meaningful in
  /// aggregate mode.
  List<MangaSummary> get aggregatedResults {
    final out = <MangaSummary>[];
    for (final slice in slices.values) {
      out.addAll(slice.results);
    }
    return out;
  }

  /// True while any source slice is still loading its first page.
  bool get anySourceLoading =>
      slices.values.any((s) => s.status == SearchStatus.loading);

  SearchState copyWith({
    SearchStatus? status,
    List<MangaSummary>? results,
    String? keyword,
    String? sourceId,
    int? currentPage,
    bool? hasMore,
    String? errorMessage,
    bool? aggregateMode,
    Map<String, SourceSearchSlice>? slices,
    bool? aiMode,
    String? aiInterpretation,
  }) {
    return SearchState(
      status: status ?? this.status,
      results: results ?? this.results,
      keyword: keyword ?? this.keyword,
      sourceId: sourceId ?? this.sourceId,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
      aggregateMode: aggregateMode ?? this.aggregateMode,
      slices: slices ?? this.slices,
      aiMode: aiMode ?? this.aiMode,
      aiInterpretation: aiInterpretation ?? this.aiInterpretation,
    );
  }

  @override
  List<Object?> get props => [
        status,
        results,
        keyword,
        sourceId,
        currentPage,
        hasMore,
        errorMessage,
        aggregateMode,
        slices,
        aiMode,
        aiInterpretation,
      ];
}
