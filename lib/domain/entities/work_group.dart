import 'package:equatable/equatable.dart';
import 'package:comic_reader/core/utils/title_normalizer.dart';
import 'manga.dart';

/// One member (a specific source's copy) of a [WorkGroup].
class WorkGroupMember extends Equatable {
  final String sourceId;
  final String mangaId;
  final String title;
  final String coverUrl;

  const WorkGroupMember({
    required this.sourceId,
    required this.mangaId,
    required this.title,
    this.coverUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'mangaId': mangaId,
        'title': title,
        'coverUrl': coverUrl,
      };

  factory WorkGroupMember.fromJson(Map<String, dynamic> json) =>
      WorkGroupMember(
        sourceId: json['sourceId'] as String? ?? '',
        mangaId: json['mangaId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        coverUrl: json['coverUrl'] as String? ?? '',
      );

  @override
  List<Object?> get props => [sourceId, mangaId, title, coverUrl];
}

/// A canonical work grouping the same manga surfaced by multiple sources.
///
/// [canonicalKey] is a normalized title(+author) string used both as a stable
/// identity and as the primary matching key. [members] holds one entry per
/// (sourceId, mangaId).
class WorkGroup extends Equatable {
  final String canonicalKey;
  final String displayTitle;
  final String author;
  final List<WorkGroupMember> members;

  const WorkGroup({
    required this.canonicalKey,
    required this.displayTitle,
    this.author = '',
    this.members = const [],
  });

  bool containsSource(String sourceId) =>
      members.any((m) => m.sourceId == sourceId);

  WorkGroup copyWith({
    String? displayTitle,
    String? author,
    List<WorkGroupMember>? members,
  }) =>
      WorkGroup(
        canonicalKey: canonicalKey,
        displayTitle: displayTitle ?? this.displayTitle,
        author: author ?? this.author,
        members: members ?? this.members,
      );

  Map<String, dynamic> toJson() => {
        'canonicalKey': canonicalKey,
        'displayTitle': displayTitle,
        'author': author,
        'members': members.map((m) => m.toJson()).toList(),
      };

  factory WorkGroup.fromJson(Map<String, dynamic> json) => WorkGroup(
        canonicalKey: json['canonicalKey'] as String? ?? '',
        displayTitle: json['displayTitle'] as String? ?? '',
        author: json['author'] as String? ?? '',
        members: (json['members'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((m) => WorkGroupMember.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );

  @override
  List<Object?> get props => [canonicalKey, displayTitle, author, members];
}

/// Groups [MangaSummary] results from multiple sources into [WorkGroup]s using
/// normalized title/author/altTitles matching.
///
/// Matching heuristic (pure, deterministic, no network):
/// - Primary key = normalized title (+ author when present).
/// - Each summary is also indexed by the normalized form of every altTitle, so
///   a source that only exposes an original-language title can still join a
///   group keyed by a localized title (and vice-versa).
/// - First-seen order (i.e. source order of the input list) wins for the
///   canonical key and display title.
class WorkGroupMatcher {
  /// Build work groups from a flat list of summaries (already collected from
  /// one or more sources, in the desired priority order).
  static List<WorkGroup> group(List<MangaSummary> summaries) {
    // Map every normalized alias → the canonical key of the group it belongs to.
    final aliasToKey = <String, String>{};
    final groups = <String, _MutableGroup>{};

    for (final m in summaries) {
      final aliases = _aliasesFor(m);
      if (aliases.isEmpty) continue;

      // Find an existing group any alias already points to.
      String? matchedKey;
      for (final a in aliases) {
        final k = aliasToKey[a];
        if (k != null) {
          matchedKey = k;
          break;
        }
      }

      final key = matchedKey ?? aliases.first;
      final group = groups.putIfAbsent(
        key,
        () => _MutableGroup(
          canonicalKey: key,
          displayTitle: m.title,
          author: m.author,
        ),
      );

      // Register all aliases for this summary onto the group key.
      for (final a in aliases) {
        aliasToKey.putIfAbsent(a, () => key);
      }

      // Avoid duplicate members for the exact same (source, manga).
      final alreadyMember = group.members
          .any((mm) => mm.sourceId == m.sourceId && mm.mangaId == m.id);
      if (!alreadyMember) {
        group.members.add(WorkGroupMember(
          sourceId: m.sourceId,
          mangaId: m.id,
          title: m.title,
          coverUrl: m.coverUrl,
        ));
      }
    }

    return groups.values
        .map((g) => WorkGroup(
              canonicalKey: g.canonicalKey,
              displayTitle: g.displayTitle,
              author: g.author,
              members: List.unmodifiable(g.members),
            ))
        .toList();
  }

  /// All normalized match aliases for a summary: the title (+author) key plus
  /// each altTitle (both bare and author-qualified).
  static Set<String> _aliasesFor(MangaSummary m) {
    final author = normalizeTitle(m.author);
    final aliases = <String>{};

    void addTitle(String raw) {
      final t = normalizeTitle(raw);
      if (t.isEmpty) return;
      aliases.add(author.isEmpty ? t : '$t\u0000$author');
      // Also index the bare title so a member without author info can join.
      aliases.add(t);
    }

    addTitle(m.title);
    for (final alt in m.altTitles) {
      addTitle(alt);
    }
    return aliases;
  }
}

class _MutableGroup {
  final String canonicalKey;
  final String displayTitle;
  final String author;
  final List<WorkGroupMember> members = [];

  _MutableGroup({
    required this.canonicalKey,
    required this.displayTitle,
    required this.author,
  });
}
