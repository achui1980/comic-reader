import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:comic_reader/app/theme/app_theme.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/core/activation/activation_service.dart';
import 'package:comic_reader/main.dart';
import 'settings_state.dart';

final _log = Logger('SettingsCubit');

class SettingsCubit extends Cubit<SettingsState> {
  final SettingsStore _settingsStore;
  final LocalStorage _localStorage;
  final SourceRegistry _sourceRegistry;
  final FavoritesStore _favoritesStore;

  SettingsCubit({
    required SettingsStore settingsStore,
    required LocalStorage localStorage,
    required SourceRegistry sourceRegistry,
    required FavoritesStore favoritesStore,
  })  : _settingsStore = settingsStore,
        _localStorage = localStorage,
        _sourceRegistry = sourceRegistry,
        _favoritesStore = favoritesStore,
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

  Future<void> setKeepScreenOn(bool enabled) async {
    final updated = state.settings.copyWith(keepScreenOn: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setCropBorders(bool enabled) async {
    final updated = state.settings.copyWith(cropBorders: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setScaleType(ScaleType type) async {
    final updated = state.settings.copyWith(scaleType: type);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setSplitWidePages(bool enabled) async {
    final updated = state.settings.copyWith(splitWidePages: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setShowPageNumber(bool enabled) async {
    final updated = state.settings.copyWith(showPageNumber: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setMangaTranslationEnabled(bool enabled) async {
    final updated = state.settings.copyWith(mangaTranslationEnabled: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setVolumeKeyTurn(bool enabled) async {
    final updated = state.settings.copyWith(volumeKeyTurn: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setTapZonesInvert(bool enabled) async {
    final updated = state.settings.copyWith(tapZonesInvert: enabled);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
  }

  Future<void> setShowTapZones(bool enabled) async {
    final updated = state.settings.copyWith(showTapZones: enabled);
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

  Future<void> setAdultUnlocked(bool value) async {
    final updated = state.settings.copyWith(adultUnlocked: value);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
    // Update source registry so adult sources take effect immediately
    _sourceRegistry.setAdultUnlocked(value);
  }

  /// Attempts to unlock adult sources with an activation [code].
  ///
  /// On success the code is verified & persisted (in secure storage) by
  /// [ActivationService], the registry is unlocked immediately, and the
  /// plaintext settings flag is mirrored for backward compatibility. Returns
  /// an error message on failure, or `null` on success.
  Future<String?> unlockWithCode(String code) async {
    final activation = GetIt.instance<ActivationService>();
    final result = await activation.verify(code);
    if (!result.success) {
      return result.error ?? '激活码无效';
    }
    final updated = state.settings.copyWith(adultUnlocked: true);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
    _sourceRegistry.setAdultUnlocked(true);
    return null;
  }

  /// Re-locks adult sources: clears the stored activation token and resets the
  /// registry + settings flag.
  Future<void> lockAdult() async {
    await GetIt.instance<ActivationService>().clear();
    final updated = state.settings.copyWith(adultUnlocked: false);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
    _sourceRegistry.setAdultUnlocked(false);
  }

  Future<void> clearFavorites() async {
    await _favoritesStore.clear();
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

  /// 设置自定义下载存储目录（macOS/Windows）。`null` 表示恢复平台默认位置。
  ///
  /// 同步更新 [ChapterCacheService.customDownloadDirectory]，使后续下载/缓存
  /// 读写立即生效，无需重启应用。
  ///
  /// macOS 下额外持久化一份 security-scoped bookmark（见
  /// [saveDownloadDirectoryBookmark]），否则 App Sandbox 授予的目录访问权限
  /// 在应用完全退出后会失效，下次启动写入该目录会报权限错误。当 [path] 为
  /// `null`（用户恢复默认位置）时不写入新 bookmark；旧 bookmark（如果有）
  /// 留在 UserDefaults 中不主动清除——这是安全的，因为启动时（见
  /// `main.dart`）只有在 `AppSettings.downloadDirectory` 非空时才会去解析
  /// bookmark，恢复默认后不会被这份残留 bookmark 复活。
  ///
  /// [saveDownloadDirectoryBookmark] already catches and logs any native
  /// exception internally (never rethrows), so a bookmark-save failure
  /// here is only surfaced via its `bool` return value — it does not
  /// throw and does not block the settings/`customDownloadDirectory`
  /// update above, which already succeeded by this point.
  Future<void> setDownloadDirectory(String? path) async {
    final updated = state.settings.copyWith(downloadDirectory: path);
    emit(state.copyWith(settings: updated));
    await _settingsStore.save(updated);
    ChapterCacheService.customDownloadDirectory = path;
    if (Platform.isMacOS && path != null) {
      final bookmarkSaved = await saveDownloadDirectoryBookmark(path);
      if (!bookmarkSaved) {
        _log.warning(
          'Failed to persist security-scoped bookmark for download '
          'directory "$path"; the custom directory will only remain '
          'writable for the current app session.',
        );
      }
    }
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
