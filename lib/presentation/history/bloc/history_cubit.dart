import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'history_state.dart';

class HistoryCubit extends Cubit<HistoryState> {
  final ReadingHistoryStore _readingHistoryStore;

  HistoryCubit({required ReadingHistoryStore readingHistoryStore})
      : _readingHistoryStore = readingHistoryStore,
        super(const HistoryState());

  Future<void> load() async {
    final entries = await _readingHistoryStore.getHistory();
    emit(state.copyWith(isLoading: false, entries: entries));
  }

  Future<void> clearAll() async {
    await _readingHistoryStore.clearHistory();
    await load();
  }

  Future<void> removeItem(String sourceId, String mangaId) async {
    await _readingHistoryStore.removeHistory(sourceId, mangaId);
    await load();
  }
}
