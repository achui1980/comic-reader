import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'detail_state.dart';

class DetailCubit extends Cubit<DetailState> {
  final MangaRepository _repository;
  final FavoritesStore _favoritesStore;
  final ReadingHistoryStore _historyStore;
  final String sourceId;
  final String mangaId;

  DetailCubit({
    required MangaRepository repository,
    required FavoritesStore favoritesStore,
    required ReadingHistoryStore historyStore,
    required this.sourceId,
    required this.mangaId,
  })  : _repository = repository,
        _favoritesStore = favoritesStore,
        _historyStore = historyStore,
        super(const DetailState());

  Future<void> loadDetail() async {
    emit(state.copyWith(status: DetailStatus.loading));
    try {
      final manga = await _repository.getMangaInfo(sourceId, mangaId);
      final isFav = await _favoritesStore.isFavorite(sourceId, mangaId);
      emit(state.copyWith(status: DetailStatus.loaded, manga: manga, isFavorite: isFav));
      await loadChapters();
      final readChapters = await _historyStore.getReadChapters(sourceId, mangaId);
      emit(state.copyWith(readChapterIds: readChapters));
    } catch (e) {
      emit(state.copyWith(status: DetailStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> refresh() async {
    try {
      final manga = await _repository.getMangaInfo(sourceId, mangaId);
      final isFav = await _favoritesStore.isFavorite(sourceId, mangaId);
      emit(state.copyWith(status: DetailStatus.loaded, manga: manga, isFavorite: isFav));
      await loadChapters();
      final readChapters = await _historyStore.getReadChapters(sourceId, mangaId);
      emit(state.copyWith(readChapterIds: readChapters));
    } catch (e) {
      // Silently fail on refresh - don't show error state since we already have data
    }
  }

  Future<void> loadChapters() async {
    emit(state.copyWith(chaptersLoading: true, clearChaptersError: true));
    // Tracks whether at least the first page succeeded during *this* call,
    // so the catch block below knows whether to reset pagination back to
    // "retry from page 1" or leave the already-correct in-progress
    // pagination state (canLoadMoreChapters/chapterPage) alone.
    var firstPageSucceeded = false;
    try {
      // Some sources embed chapters directly in manga info (e.g., ManhuaGui)
      if (state.manga != null && state.manga!.chapters.isNotEmpty) {
        emit(state.copyWith(
          chapters: state.manga!.chapters,
          chaptersLoading: false,
          canLoadMoreChapters: false,
          chapterPage: 1,
        ));
        return;
      }

      final result = await _repository.getChapterList(sourceId, mangaId, 1);
      firstPageSucceeded = true;
      var allChapters = result.chapters;
      var canLoadMore = result.canLoadMore;
      var page = 1;

      // Emit the first page immediately so the UI shows something fast.
      emit(state.copyWith(
        chapters: allChapters,
        chaptersLoading: canLoadMore,
        canLoadMoreChapters: canLoadMore,
        chapterPage: page,
      ));

      // The detail UI has no scroll-triggered lazy loading, so eagerly
      // fetch every remaining page here until the source reports no more.
      final seen = allChapters.map((c) => c.id).toSet();
      const maxPages = 200; // safety cap to avoid infinite loops
      while (canLoadMore && page < maxPages) {
        page++;
        final next = await _repository.getChapterList(sourceId, mangaId, page);
        final newChapters =
            next.chapters.where((c) => seen.add(c.id)).toList();
        // A page can legitimately yield no new chapters even while the source
        // still has more pages — e.g. MangaDex filters out non-Chinese chapters
        // per page, so an all-foreign page collapses to empty. Keep paging as
        // long as the source reports more; only the source's own canLoadMore
        // (plus the maxPages cap) decides when to stop. Bailing out on an empty
        // page here would hide later Chinese chapters entirely.
        canLoadMore = next.canLoadMore;
        if (newChapters.isEmpty) {
          if (!canLoadMore) break;
          continue;
        }
        allChapters = [...allChapters, ...newChapters];
        emit(state.copyWith(
          chapters: allChapters,
          chaptersLoading: canLoadMore,
          canLoadMoreChapters: canLoadMore,
          chapterPage: page,
        ));
      }

      emit(state.copyWith(
        chapters: allChapters,
        chaptersLoading: false,
        canLoadMoreChapters: false,
        chapterPage: page,
      ));
    } catch (e) {
      if (firstPageSucceeded) {
        // A later page failed mid-pagination. The state already has the
        // correct canLoadMoreChapters/chapterPage from the last successful
        // page emit above, so leave them alone — loadMoreChapters() will
        // retry the exact page that just failed.
        emit(state.copyWith(chaptersLoading: false, chaptersError: e.toString()));
      } else {
        // Not even page 1 succeeded. Force canLoadMoreChapters back to
        // true and chapterPage to 0 so loadMoreChapters() retries page 1
        // (chapterPage + 1), regardless of whatever stale pagination state
        // may be left over from a previous successful load (e.g. refresh()
        // re-calling loadChapters() after chapters were already fully
        // loaded once).
        emit(state.copyWith(
          chaptersLoading: false,
          chaptersError: e.toString(),
          canLoadMoreChapters: true,
          chapterPage: 0,
        ));
      }
    }
  }

  /// Retries/continues fetching the next page of chapters. Used both for
  /// (currently unused, no scroll-triggered lazy loading in the UI beyond
  /// this) continued pagination and — more importantly — as the manual
  /// "retry" action surfaced in the UI when [DetailState.chaptersError] is
  /// set, since it naturally re-fetches whichever page last failed.
  Future<void> loadMoreChapters() async {
    if (state.chaptersLoading || !state.canLoadMoreChapters) return;
    emit(state.copyWith(chaptersLoading: true, clearChaptersError: true));
    try {
      final nextPage = state.chapterPage + 1;
      final result = await _repository.getChapterList(sourceId, mangaId, nextPage);
      emit(state.copyWith(
        chapters: [...state.chapters, ...result.chapters],
        chaptersLoading: false,
        canLoadMoreChapters: result.canLoadMore,
        chapterPage: nextPage,
      ));
    } catch (e) {
      emit(state.copyWith(chaptersLoading: false, chaptersError: e.toString()));
    }
  }

  void toggleSortOrder() {
    emit(state.copyWith(chaptersReversed: !state.chaptersReversed));
  }

  Future<void> toggleFavorite() async {
    final manga = state.manga;
    if (manga == null) return;

    final willBeFavorite = !state.isFavorite;
    emit(state.copyWith(isFavorite: willBeFavorite));

    if (willBeFavorite) {
      await _favoritesStore.add(MangaSummary(
        id: manga.id,
        sourceId: manga.sourceId,
        title: manga.title,
        coverUrl: manga.coverUrl,
        author: manga.author,
        latestChapter: manga.latestChapter,
        updateTime: manga.updateTime,
        headers: manga.headers,
      ));
    } else {
      await _favoritesStore.remove(sourceId, mangaId);
    }
  }
}
