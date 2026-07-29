import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/domain/entities/work_group.dart';

/// Persists user-confirmed [WorkGroup] groupings.
///
/// Key: `'work_groups'` in [LocalStorage].
/// Format: `{ "<canonicalKey>": { ...WorkGroup.toJson() }, ... }`
class WorkGroupStore {
  final LocalStorage _storage;
  static const _key = 'work_groups';
  Map<String, WorkGroup>? _cache;

  WorkGroupStore({required LocalStorage storage}) : _storage = storage;

  Future<void> init() async {
    await _loadAll();
  }

  Future<Map<String, WorkGroup>> _loadAll() async {
    if (_cache != null) return _cache!;
    final raw = await _storage.read(_key);
    if (raw == null) {
      _cache = {};
      return _cache!;
    }
    final map = <String, WorkGroup>{};
    for (final entry in raw.entries) {
      if (entry.value is Map) {
        try {
          final group = WorkGroup.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          map[entry.key] = group;
        } catch (_) {
          // Ignore corrupted entries.
        }
      }
    }
    _cache = map;
    return _cache!;
  }

  /// All stored [WorkGroup]s.
  Future<List<WorkGroup>> getAll() async {
    final all = await _loadAll();
    return all.values.toList();
  }

  /// Get a single [WorkGroup] by [canonicalKey].
  Future<WorkGroup?> get(String canonicalKey) async {
    final all = await _loadAll();
    return all[canonicalKey];
  }

  /// Persist a [WorkGroup].
  Future<void> save(WorkGroup group) async {
    final all = await _loadAll();
    all[group.canonicalKey] = group;
    await _persist(all);
  }

  /// Remove a [WorkGroup] by [canonicalKey].
  Future<void> remove(String canonicalKey) async {
    final all = await _loadAll();
    if (all.remove(canonicalKey) != null) {
      await _persist(all);
    }
  }

  /// Replace all stored groups (used when auto-grouping a search result batch).
  Future<void> saveAll(List<WorkGroup> groups) async {
    final map = <String, WorkGroup>{
      for (final g in groups) g.canonicalKey: g,
    };
    _cache = map;
    await _persist(map);
  }

  /// Clear all stored groups.
  Future<void> clearAll() async {
    _cache = {};
    await _storage.delete(_key);
  }

  Future<void> _persist(Map<String, WorkGroup> data) async {
    final encoded = {
      for (final e in data.entries) e.key: e.value.toJson(),
    };
    await _storage.write(_key, encoded);
    _cache = data;
  }

  /// Find the [WorkGroup] that contains a specific (sourceId, mangaId) pair.
  ///
  /// Scans all stored groups; O(N·members). Acceptable for typical datasets.
  Future<WorkGroup?> findByMember(String sourceId, String mangaId) async {
    final all = await _loadAll();
    for (final group in all.values) {
      if (group.members.any(
          (m) => m.sourceId == sourceId && m.mangaId == mangaId)) {
        return group;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Convenience: build + save groups from a flat list of summaries.
  // ---------------------------------------------------------------------------

  /// Group [summaries] using [WorkGroupMatcher] and save the result.
  Future<List<WorkGroup>> buildAndSave(
    List<dynamic> summaries, {
    bool merge = false,
  }) async {
    // summaries is List<MangaSummary> but typed dynamic to avoid a circular
    // dependency; WorkGroupMatcher accepts List<MangaSummary>.
    final groups = WorkGroupMatcher.group(List.from(summaries));
    if (merge) {
      final existing = await _loadAll();
      for (final g in groups) {
        final prev = existing[g.canonicalKey];
        if (prev != null) {
          // Merge members: add any new (sourceId, mangaId) pairs.
          final merged = List<WorkGroupMember>.from(prev.members);
          for (final m in g.members) {
            if (!merged.any(
                (e) => e.sourceId == m.sourceId && e.mangaId == m.mangaId)) {
              merged.add(m);
            }
          }
          existing[g.canonicalKey] = prev.copyWith(members: merged);
        } else {
          existing[g.canonicalKey] = g;
        }
      }
      await _persist(existing);
      return existing.values.toList();
    } else {
      await saveAll(groups);
      return groups;
    }
  }
}
