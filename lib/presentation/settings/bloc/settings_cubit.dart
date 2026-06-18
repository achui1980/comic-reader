import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/theme/app_theme.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/main.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final SettingsStore _settingsStore;
  final LocalStorage _localStorage;
  final SourceRegistry _sourceRegistry;

  SettingsCubit({
    required SettingsStore settingsStore,
    required LocalStorage localStorage,
    required SourceRegistry sourceRegistry,
  })  : _settingsStore = settingsStore,
        _localStorage = localStorage,
        _sourceRegistry = sourceRegistry,
        super(const SettingsState());

  Future<void> init() async {
    final settings = await _settingsStore.load();
    final plugins = _sourceRegistry.all.map((s) => s.info).toList();
    emit(state.copyWith(
      settings: settings,
      plugins: plugins,
      isLoading: false,
    ));
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final updated = state.settings.copyWith(themeMode: mode);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setLayoutMode(LayoutMode mode) async {
    final updated = state.settings.copyWith(layoutMode: mode);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setReadingDirection(ReadingDirection direction) async {
    final updated = state.settings.copyWith(readingDirection: direction);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setAutoPageTurn(bool enabled) async {
    final updated = state.settings.copyWith(autoPageTurn: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setAutoPageTurnInterval(int seconds) async {
    final updated = state.settings.copyWith(autoPageTurnInterval: seconds);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> toggleSource(String sourceId, bool enabled) async {
    final disabled = Set<String>.from(state.settings.disabledSources);
    if (enabled) {
      disabled.remove(sourceId);
    } else {
      disabled.add(sourceId);
    }
    final updated = state.settings.copyWith(disabledSources: disabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
    // Update source registry so disabled sources take effect immediately
    _sourceRegistry.setDisabledSources(disabled);
  }

  Future<void> clearFavorites() async {
    await _localStorage.delete('favorites');
  }

  Future<void> clearReadingHistory() async {
    await _localStorage.delete('reading_history');
  }

  Future<void> clearImageCache() async {
    // Clear the Flutter image cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    // Clear chapter download cache
    await ChapterCacheService().clearCache();
  }

  /// Get cache size in bytes for display.
  Future<int> getCacheSize() async {
    return await ChapterCacheService().getCacheSize();
  }

  Future<void> setProxyEnabled(bool enabled) async {
    final updated = state.settings.copyWith(proxyEnabled: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
    _applyProxySettings(updated);
  }

  Future<void> setProxyAddress(String address) async {
    final updated = state.settings.copyWith(proxyAddress: address);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
    _applyProxySettings(updated);
  }

  void _applyProxySettings(AppSettings settings) {
    if (!kIsWeb) {
      final overrides = GetIt.instance<MyHttpOverrides>();
      overrides.updateProxy(
        enabled: settings.proxyEnabled,
        address: settings.proxyAddress,
      );
    }
  }
}
