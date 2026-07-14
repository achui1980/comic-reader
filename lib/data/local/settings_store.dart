import 'package:comic_reader/app/theme/app_theme.dart';
import 'local_storage.dart';

/// Reading layout mode.
enum LayoutMode { horizontal, vertical }

/// Reading direction.
enum ReadingDirection { ltr, rtl }

/// Image scale/fit mode in the reader.
enum ScaleType { fitScreen, fitWidth, fitHeight, original }

/// User-configurable settings data class.
class AppSettings {
  final AppThemeMode themeMode;
  final LayoutMode layoutMode;
  final ReadingDirection readingDirection;
  final bool autoPageTurn;
  final int autoPageTurnInterval; // seconds
  final Set<String> disabledSources;
  final bool proxyEnabled;
  final String proxyAddress; // e.g. "127.0.0.1:2222"
  final bool adultUnlocked;
  // --- Reader enhancements (phase 2) ---
  final bool keepScreenOn; // wakelock; no-op on non-mobile
  final bool cropBorders; // trim white margins
  final ScaleType scaleType; // paged image fit
  final bool splitWidePages; // split landscape pages into two
  final bool showPageNumber; // show page indicator overlay
  final bool volumeKeyTurn; // volume keys turn pages (Android only)
  final bool tapZonesInvert; // invert left/right tap zones
  final bool showTapZones; // show tap-zone overlay hint

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.layoutMode = LayoutMode.vertical,
    this.readingDirection = ReadingDirection.ltr,
    this.autoPageTurn = false,
    this.autoPageTurnInterval = 5,
    this.disabledSources = const {},
    this.proxyEnabled = false,
    this.proxyAddress = '127.0.0.1:2222',
    this.adultUnlocked = false,
    this.keepScreenOn = false,
    this.cropBorders = false,
    this.scaleType = ScaleType.fitWidth,
    this.splitWidePages = false,
    this.showPageNumber = true,
    this.volumeKeyTurn = false,
    this.tapZonesInvert = false,
    this.showTapZones = false,
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    LayoutMode? layoutMode,
    ReadingDirection? readingDirection,
    bool? autoPageTurn,
    int? autoPageTurnInterval,
    Set<String>? disabledSources,
    bool? proxyEnabled,
    String? proxyAddress,
    bool? adultUnlocked,
    bool? keepScreenOn,
    bool? cropBorders,
    ScaleType? scaleType,
    bool? splitWidePages,
    bool? showPageNumber,
    bool? volumeKeyTurn,
    bool? tapZonesInvert,
    bool? showTapZones,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      layoutMode: layoutMode ?? this.layoutMode,
      readingDirection: readingDirection ?? this.readingDirection,
      autoPageTurn: autoPageTurn ?? this.autoPageTurn,
      autoPageTurnInterval: autoPageTurnInterval ?? this.autoPageTurnInterval,
      disabledSources: disabledSources ?? this.disabledSources,
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      proxyAddress: proxyAddress ?? this.proxyAddress,
      adultUnlocked: adultUnlocked ?? this.adultUnlocked,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      cropBorders: cropBorders ?? this.cropBorders,
      scaleType: scaleType ?? this.scaleType,
      splitWidePages: splitWidePages ?? this.splitWidePages,
      showPageNumber: showPageNumber ?? this.showPageNumber,
      volumeKeyTurn: volumeKeyTurn ?? this.volumeKeyTurn,
      tapZonesInvert: tapZonesInvert ?? this.tapZonesInvert,
      showTapZones: showTapZones ?? this.showTapZones,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.index,
        'layoutMode': layoutMode.index,
        'readingDirection': readingDirection.index,
        'autoPageTurn': autoPageTurn,
        'autoPageTurnInterval': autoPageTurnInterval,
        'disabledSources': disabledSources.toList(),
        'proxyEnabled': proxyEnabled,
        'proxyAddress': proxyAddress,
        'adultUnlocked': adultUnlocked,
        'keepScreenOn': keepScreenOn,
        'cropBorders': cropBorders,
        'scaleType': scaleType.index,
        'splitWidePages': splitWidePages,
        'showPageNumber': showPageNumber,
        'volumeKeyTurn': volumeKeyTurn,
        'tapZonesInvert': tapZonesInvert,
        'showTapZones': showTapZones,
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
      proxyEnabled: json['proxyEnabled'] as bool? ?? false,
      proxyAddress: json['proxyAddress'] as String? ?? '127.0.0.1:2222',
      adultUnlocked: json['adultUnlocked'] as bool? ?? false,
      keepScreenOn: json['keepScreenOn'] as bool? ?? false,
      cropBorders: json['cropBorders'] as bool? ?? false,
      scaleType: ScaleType.values[json['scaleType'] as int? ?? 1],
      splitWidePages: json['splitWidePages'] as bool? ?? false,
      showPageNumber: json['showPageNumber'] as bool? ?? true,
      volumeKeyTurn: json['volumeKeyTurn'] as bool? ?? false,
      tapZonesInvert: json['tapZonesInvert'] as bool? ?? false,
      showTapZones: json['showTapZones'] as bool? ?? false,
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
