import 'manga_source.dart';

/// Registry of all available manga source plugins.
class SourceRegistry {
  final Map<String, MangaSource> _sources = {};
  String? _defaultSourceId;
  Set<String> _disabledSourceIds = {};
  bool _adultUnlocked = false;

  /// Register a source plugin
  void register(MangaSource source) {
    _sources[source.id] = source;
    _defaultSourceId ??= source.id;
  }

  /// Set user-disabled source IDs
  void setDisabledSources(Set<String> ids) {
    _disabledSourceIds = ids;
  }

  /// Unlock or lock adult (18+) sources
  void setAdultUnlocked(bool value) {
    _adultUnlocked = value;
  }

  /// Get a source by ID
  MangaSource? get(String id) => _sources[id];

  /// Get all registered sources
  List<MangaSource> get all => _sources.values.toList();

  /// Get all enabled (non-disabled) sources
  List<MangaSource> get enabled =>
      _sources.values
          .where((s) =>
              !s.disabled &&
              !_disabledSourceIds.contains(s.id) &&
              (!s.isAdult || _adultUnlocked))
          .toList();

  /// Get the default source
  MangaSource? get defaultSource =>
      _defaultSourceId != null ? _sources[_defaultSourceId!] : null;

  /// Set the default source
  set defaultSourceId(String id) {
    if (_sources.containsKey(id)) {
      _defaultSourceId = id;
    }
  }
}
