import 'package:equatable/equatable.dart';
import 'package:comic_reader/app/theme/app_theme.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class SettingsState extends Equatable {
  final AppSettings settings;
  final List<PluginInfo> plugins;
  final bool isLoading;

  const SettingsState({
    this.settings = const AppSettings(),
    this.plugins = const [],
    this.isLoading = true,
  });

  AppThemeMode get themeMode => settings.themeMode;
  LayoutMode get layoutMode => settings.layoutMode;
  ReadingDirection get readingDirection => settings.readingDirection;
  bool get autoPageTurn => settings.autoPageTurn;
  int get autoPageTurnInterval => settings.autoPageTurnInterval;
  Set<String> get disabledSources => settings.disabledSources;
  bool get proxyEnabled => settings.proxyEnabled;
  String get proxyAddress => settings.proxyAddress;
  bool get adultUnlocked => settings.adultUnlocked;

  /// Plugins to display in the plugin management UI. When adult content is
  /// locked, adult-flagged sources are hidden entirely instead of merely
  /// being filtered out of search/discovery results.
  List<PluginInfo> get visiblePlugins => adultUnlocked
      ? plugins
      : plugins.where((p) => !p.isAdult).toList();

  SettingsState copyWith({
    AppSettings? settings,
    List<PluginInfo>? plugins,
    bool? isLoading,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      plugins: plugins ?? this.plugins,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [settings, plugins, isLoading];
}
