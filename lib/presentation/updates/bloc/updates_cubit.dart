import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:comic_reader/data/local/library_update_service.dart';
import 'package:comic_reader/data/local/update_store.dart';
import 'updates_state.dart';

/// Cubit for the library updates tab.
///
/// Reads the structured list of newly-found chapters from [UpdateStore] and
/// can trigger a full-library refresh via [LibraryUpdateService], reflecting
/// its progress (the service is a [ChangeNotifier]).
class UpdatesCubit extends Cubit<UpdatesState> {
  final UpdateStore _updateStore;
  final LibraryUpdateService _libraryUpdateService;

  UpdatesCubit({
    required UpdateStore updateStore,
    required LibraryUpdateService libraryUpdateService,
  })  : _updateStore = updateStore,
        _libraryUpdateService = libraryUpdateService,
        super(const UpdatesState()) {
    _libraryUpdateService.addListener(_onServiceChanged);
  }

  void _onServiceChanged() {
    if (isClosed) return;
    emit(state.copyWith(
      isUpdating: _libraryUpdateService.isRunning,
      progress: _libraryUpdateService.progress,
      total: _libraryUpdateService.total,
    ));
  }

  Future<void> load() async {
    final chapters = await _updateStore.getNewChapters();
    emit(state.copyWith(
      isLoading: false,
      chapters: chapters,
      isUpdating: _libraryUpdateService.isRunning,
    ));
  }

  /// Trigger a full-library refresh and reload the list afterwards.
  Future<void> refresh() async {
    await _libraryUpdateService.runUpdate();
    await load();
  }

  /// Mark everything as read (clear the whole updates list).
  Future<void> clearAll() async {
    await _updateStore.clearAll();
    await load();
  }

  /// Remove a single manga's update marker.
  Future<void> clearForManga(String sourceId, String mangaId) async {
    await _updateStore.clearUpdate(sourceId, mangaId);
    await load();
  }

  @override
  Future<void> close() {
    _libraryUpdateService.removeListener(_onServiceChanged);
    return super.close();
  }
}
