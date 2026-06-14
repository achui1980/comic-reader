import 'package:comic_reader/app/theme/app_theme.dart';
import 'local_storage.dart';

/// Reading layout mode.
enum LayoutMode { horizontal, vertical }

/// Reading direction.
enum ReadingDirection { ltr, rtl }

/// User-configurable settings data class.
class AppSettings {
  final AppThemeMode themeMode;
  final LayoutMode layoutMode;
  final ReadingDirection readingDirection;
  final bool autoPageTurn;
  final int autoPageTurnInterval; // seconds
  final Set<String> disabledSources;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.layoutMode = LayoutMode.vertical,
    this.readingDirection = ReadingDirection.ltr,
    this.autoPageTurn = false,
    this.autoPageTurnInterval = 5,
    this.disabledSources = const {},
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    LayoutMode? layoutMode,
    ReadingDirection? readingDirection,
    bool? autoPageTurn,
    int? autoPageTurnInterval,
    Set<String>? disabledSources,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      layoutMode: layoutMode ?? this.layoutMode,
      readingDirection: readingDirection ?? this.readingDirection,
      autoPageTurn: autoPageTurn ?? this.autoPageTurn,
      autoPageTurnInterval: autoPageTurnInterval ?? this.autoPageTurnInterval,
      disabledSources: disabledSources ?? this.disabledSources,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.index,
        'layoutMode': layoutMode.index,
        'readingDirection': readingDirection.index,
        'autoPageTurn': autoPageTurn,
        'autoPageTurnInterval': autoPageTurnInterval,
        'disabledSources': disabledSources.toList(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: AppThemeMode.values[json['themeMode'] as int? ?? 3],
      layoutMode: LayoutMode.values[json['layoutMode'] as int? ?? 1],
      readingDirection:
          ReadingDirection.values[json['readingDirection'] as int? ?? 0],
      autoPageTurn: json['autoPageTurn'] as bool? ?? false,
      autoPageTurnInterval: json['autoPageTurnInterval'] as int? ?? 5,
      disabledSources: (json['disabledSources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          {},
    );
  }
}

/// Manages user preferences persistence.
class SettingsStore {
  final LocalStorage _storage;
  static const _key = 'settings';

  AppSettings? _cache;

  SettingsStore({required LocalStorage storage}) : _storage = storage;

  Future<AppSettings> load() async {
    if (_cache != null) return _cache!;
    final data = await _storage.read(_key);
    if (data == null) {
      _cache = const AppSettings();
      return _cache!;
    }
    _cache = AppSettings.fromJson(data);
    return _cache!;
  }

  Future<void> save(AppSettings settings) async {
    _cache = settings;
    await _storage.write(_key, settings.toJson());
  }
}
