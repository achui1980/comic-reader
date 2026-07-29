import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  final MangaRepository _repository;
  final SourceRegistry _registry;

  SearchCubit({
    required MangaRepository repository,
    required SourceRegistry registry,
  })  : _repository = repository,
        _registry = registry,
        super(const SearchState());

  void init([String? initialSourceId]) {
    final id = initialSourceId ?? _registry.defaultSource?.id ?? '';
    if (id.isNotEmpty) {
      emit(state.copyWith(sourceId: id));
    }
  }

  void changeSource(String sourceId) {
    if (sourceId == state.sourceId) return;
    final source = _registry.get(sourceId);
    if (source == null) return;
    emit(state.copyWith(sourceId: sourceId, results: [], status: SearchStatus.initial));
    // Re-search if there's an existing keyword
    if (state.keyword.isNotEmpty) {
      search(state.keyword);
    }
  }

  SourceRegistry get registry => _registry;

  /// Switch between aggregate (cross-source) and single-source modes.
  ///
  /// Re-runs the current keyword (if any) under the newly selected mode so the
  /// UI immediately reflects the switch.
  void setAggregateMode(bool aggregate) {
    if (aggregate == state.aggregateMode) return;
    emit(state.copyWith(
      aggregateMode: aggregate,
      status: SearchStatus.initial,
      results: [],
      slices: const {},
    ));
    if (state.keyword.isNotEmpty) {
      if (aggregate) {
        searchAll(state.keyword);
      } else {
        search(state.keyword);
      }
    }
  }

  // ==========================================================================
  // Single-source path (legacy, backward compatible)
  // ==========================================================================

  Future<void> search(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final source = _registry.get(state.sourceId);
    final firstPage = source?.firstPage ?? 1;
    emit(state.copyWith(
      status: SearchStatus.loading,
      keyword: keyword.trim(),
      results: [],
      currentPage: firstPage,
      hasMore: true,
    ));
    try {
      final results = await _repository.searchManga(state.sourceId, keyword.trim(), firstPage, {});
      emit(state.copyWith(
        status: SearchStatus.loaded,
        results: results,
        hasMore: results.isNotEmpty,
      ));
    } catch (e) {
      emit(state.copyWith(status: SearchStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> loadMore() async {
    if (state.status == SearchStatus.loadingMore || !state.hasMore || state.keyword.isEmpty) return;
    emit(state.copyWith(status: SearchStatus.loadingMore));
    try {
      final nextPage = state.currentPage + 1;
      final results = await _repository.searchManga(state.sourceId, state.keyword, nextPage, {});

      // Detect duplicate content (server returning same page)
      final existingIds = state.results.map((m) => m.id).toSet();
      final newResults = results.where((m) => !existingIds.contains(m.id)).toList();

      if (results.isNotEmpty && newResults.isEmpty) {
        emit(state.copyWith(
          status: SearchStatus.loaded,
          hasMore: false,
        ));
        return;
      }

      emit(state.copyWith(
        status: SearchStatus.loaded,
        results: [...state.results, ...newResults],
        currentPage: nextPage,
        hasMore: newResults.isNotEmpty,
      ));
    } catch (e) {
      emit(state.copyWith(status: SearchStatus.loaded));
    }
  }

  Future<void> refresh() async {
    if (state.keyword.isEmpty) return;
    if (state.aggregateMode) {
      await searchAll(state.keyword);
      return;
    }
    final source = _registry.get(state.sourceId);
    final firstPage = source?.firstPage ?? 1;
    emit(state.copyWith(
      status: SearchStatus.loading,
      currentPage: firstPage,
      hasMore: true,
    ));
    try {
      final results = await _repository.searchManga(state.sourceId, state.keyword, firstPage, {});
      emit(state.copyWith(
        status: SearchStatus.loaded,
        results: results,
        hasMore: results.isNotEmpty,
      ));
    } catch (e) {
      emit(state.copyWith(status: SearchStatus.error, errorMessage: e.toString()));
    }
  }

  // ==========================================================================
  // Cross-source (aggregate) path
  // ==========================================================================

  /// Fan out the search over every enabled source concurrently.
  ///
  /// Each source gets its own [SourceSearchSlice]; a single source failing (or
  /// still loading) only marks that slice and never blocks the others. Slices
  /// are seeded synchronously in `registry.enabled` order so the UI can render
  /// per-source loading placeholders immediately.
  Future<void> searchAll(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final sources = _registry.enabled;
    if (sources.isEmpty) {
      emit(state.copyWith(
        aggregateMode: true,
        keyword: trimmed,
        status: SearchStatus.error,
        errorMessage: 'No enabled sources',
        slices: const {},
      ));
      return;
    }

    // Seed one loading slice per source, preserving enabled order.
    final seeded = <String, SourceSearchSlice>{};
    for (final s in sources) {
      seeded[s.id] = SourceSearchSlice(
        sourceId: s.id,
        status: SearchStatus.loading,
        currentPage: s.firstPage,
      );
    }
    emit(state.copyWith(
      aggregateMode: true,
      keyword: trimmed,
      status: SearchStatus.loading,
      results: [],
      slices: Map.unmodifiable(seeded),
    ));

    await Future.wait(sources.map((s) async {
      try {
        final results = await _repository.searchManga(s.id, trimmed, s.firstPage, {});
        _updateSlice(
          s.id,
          (prev) => prev.copyWith(
            status: SearchStatus.loaded,
            results: results,
            hasMore: results.isNotEmpty,
            clearError: true,
          ),
        );
      } catch (e) {
        _updateSlice(
          s.id,
          (prev) => prev.copyWith(
            status: SearchStatus.error,
            errorMessage: e.toString(),
            hasMore: false,
          ),
        );
      }
    }));

    // Overall status: loaded once every slice settled (loaded or error).
    emit(state.copyWith(status: SearchStatus.loaded));
  }

  /// Load the next page for a single source slice in aggregate mode.
  Future<void> loadMoreSource(String sourceId) async {
    final slice = state.slices[sourceId];
    if (slice == null) return;
    if (slice.status == SearchStatus.loadingMore || !slice.hasMore) return;
    if (state.keyword.isEmpty) return;

    _updateSlice(sourceId, (prev) => prev.copyWith(status: SearchStatus.loadingMore));

    try {
      final nextPage = slice.currentPage + 1;
      final results = await _repository.searchManga(sourceId, state.keyword, nextPage, {});

      final existingIds = slice.results.map((m) => m.id).toSet();
      final newResults = results.where((m) => !existingIds.contains(m.id)).toList();

      if (results.isNotEmpty && newResults.isEmpty) {
        _updateSlice(
          sourceId,
          (prev) => prev.copyWith(status: SearchStatus.loaded, hasMore: false),
        );
        return;
      }

      _updateSlice(
        sourceId,
        (prev) => prev.copyWith(
          status: SearchStatus.loaded,
          results: [...prev.results, ...newResults],
          currentPage: nextPage,
          hasMore: newResults.isNotEmpty,
        ),
      );
    } catch (e) {
      // Keep prior results; just settle the slice.
      _updateSlice(sourceId, (prev) => prev.copyWith(status: SearchStatus.loaded));
    }
  }

  /// Retry a single failed source slice from its first page.
  Future<void> retrySource(String sourceId) async {
    if (state.keyword.isEmpty) return;
    final source = _registry.get(sourceId);
    final firstPage = source?.firstPage ?? 1;

    _updateSlice(
      sourceId,
      (prev) => prev.copyWith(
        status: SearchStatus.loading,
        currentPage: firstPage,
        hasMore: true,
        clearError: true,
      ),
    );

    try {
      final results = await _repository.searchManga(sourceId, state.keyword, firstPage, {});
      _updateSlice(
        sourceId,
        (prev) => prev.copyWith(
          status: SearchStatus.loaded,
          results: results,
          hasMore: results.isNotEmpty,
          clearError: true,
        ),
      );
    } catch (e) {
      _updateSlice(
        sourceId,
        (prev) => prev.copyWith(
          status: SearchStatus.error,
          errorMessage: e.toString(),
          hasMore: false,
        ),
      );
    }
  }

  /// Flattened cross-source results with near-duplicate titles collapsed.
  ///
  /// Slices already contain no intra-source duplicates; this only collapses the
  /// *same work surfaced by multiple sources* using a normalized title key, so
  /// the aggregated list shows each work once (first source in enabled order
  /// wins). Per-source grouped display should read [SearchState.slices] instead.
  List<MangaSummary> get dedupedAggregatedResults {
    final seen = <String>{};
    final out = <MangaSummary>[];
    for (final slice in state.slices.values) {
      for (final m in slice.results) {
        final key = _dedupKey(m);
        if (seen.add(key)) {
          out.add(m);
        }
      }
    }
    return out;
  }

  String _dedupKey(MangaSummary m) {
    final title = _normalizeTitle(m.title);
    final author = _normalizeTitle(m.author);
    return author.isEmpty ? title : '$title\u0000$author';
  }

  /// Normalize a title/author for cross-source matching: trim, collapse
  /// whitespace, lowercase, and fold full-width ASCII into half-width so
  /// "ＯＮＥ ＰＩＥＣＥ" and "one piece" match.
  static String _normalizeTitle(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      // Full-width ASCII (！-～, U+FF01–U+FF5E) → half-width (U+0021–U+007E).
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000) {
        // Full-width space → normal space.
        buffer.writeCharCode(0x20);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Apply [update] to the slice for [sourceId] and emit the new state.
  ///
  /// No-op if the slice no longer exists (e.g. mode switched mid-flight).
  void _updateSlice(
    String sourceId,
    SourceSearchSlice Function(SourceSearchSlice prev) update,
  ) {
    final prev = state.slices[sourceId];
    if (prev == null) return;
    final next = Map<String, SourceSearchSlice>.from(state.slices);
    next[sourceId] = update(prev);
    emit(state.copyWith(slices: Map.unmodifiable(next)));
  }
}
