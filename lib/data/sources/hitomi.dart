import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show ResponseType;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Hitomi.la source plugin (Chinese content).
///
/// Uses the nozomi binary index for discovery/search, galleries/{id}.js for
/// manga info, and dynamic gg.js for image URL construction.
///
/// API endpoints (via gold-usergeneratedcontent.net CDN):
///   - Discovery:  https://ltn.gold-usergeneratedcontent.net/index-chinese.nozomi
///   - Search:     https://ltn.gold-usergeneratedcontent.net/tag/{tag}-chinese.nozomi
///   - Gallery:    https://ltn.gold-usergeneratedcontent.net/galleries/{id}.js
///   - gg.js:      https://ltn.gold-usergeneratedcontent.net/gg.js
///   - Images:     https://{sub}.gold-usergeneratedcontent.net/{dir}/{path}.{ext}
///   - Thumbnails: https://tn.gold-usergeneratedcontent.net/...
class Hitomi extends MangaSource {
  static const String sourceId = 'hitomi';

  /// CDN domain used for API and static resources.
  static const String _domain2 = 'gold-usergeneratedcontent.net';
  static const String _ltnBase = 'https://ltn.$_domain2';

  /// Number of galleries per page in discovery/search.
  static const int _pageSize = 25;

  // Cached gg.js parameters (mirrors gg object from gg.js)
  Set<int>? _ggCaseSet; // Values that map to the non-default result
  int? _ggDefaultValue; // Default value of `o` variable
  String? _ggB; // gg.b - path prefix
  // gg.s is always: /(..)(.)$/ → parseInt(m[2]+m[1], 16).toString(10)
  DateTime? _ggFetchedAt;

  @override
  String get id => sourceId;

  @override
  bool get isAdult => true;

  @override
  String get name => 'Hitomi';

  @override
  String get shortName => 'HT';

  @override
  String? get description => 'Hitomi.la Chinese doujinshi/manga';

  @override
  double get score => 4.0;

  @override
  String? get href => 'https://hitomi.la';

  @override
  bool get needsProxy => true;

  @override
  bool get needsCloudflare => false;

  @override
  int get firstPage => 1;

  @override
  Map<String, String> get defaultHeaders => {
        'Referer': 'https://hitomi.la/',
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'type',
          label: 'Type',
          defaultValue: '',
          choices: [
            FilterChoice(label: 'All', value: ''),
            FilterChoice(label: 'Doujinshi', value: 'doujinshi'),
            FilterChoice(label: 'Manga', value: 'manga'),
            FilterChoice(label: 'Artist CG', value: 'artistcg'),
            FilterChoice(label: 'Game CG', value: 'gamecg'),
            FilterChoice(label: 'Anime', value: 'anime'),
          ],
        ),
      ];

  @override
  List<FilterOption> get searchFilters => const [];

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final type = filters['type'] ?? '';
    String url;
    if (type.isNotEmpty) {
      url = '$_ltnBase/type/$type-chinese.nozomi';
    } else {
      url = '$_ltnBase/index-chinese.nozomi';
    }

    // Range-based pagination: each entry is 4 bytes (big-endian int32)
    final start = (page - 1) * _pageSize * 4;
    final end = start + _pageSize * 4 - 1;

    return FetchConfig(
      url: url,
      headers: {
        'Range': 'bytes=$start-$end',
      },
      responseType: ResponseType.bytes,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseNozomiResponse(response);
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // Hitomi search uses tag-based nozomi files.
    // Format: tag/{keyword}-chinese.nozomi
    // Tags use spaces (not underscores) and are lowercase.
    // Example: "female:big breasts" → tag/female:big breasts-chinese.nozomi
    final tag = keyword.trim().toLowerCase();
    final url = '$_ltnBase/tag/$tag-chinese.nozomi';

    final start = (page - 1) * _pageSize * 4;
    final end = start + _pageSize * 4 - 1;

    return FetchConfig(
      url: url,
      headers: {
        'Range': 'bytes=$start-$end',
      },
      responseType: ResponseType.bytes,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseNozomiResponse(response);
  }

  // ---------------------------------------------------------------------------
  // Manga Info
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_ltnBase/galleries/$mangaId.js',
      responseType: ResponseType.plain,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final json = _parseGalleryJs(response as String);

    final title = json['title'] as String? ?? '';
    final type = json['type'] as String? ?? '';

    // Artists
    final artistsList = json['artists'] as List? ?? [];
    final artists =
        artistsList.map((a) => (a['artist'] ?? '') as String).toList();

    // Tags
    final tagsList = json['tags'] as List? ?? [];
    final tags = tagsList.map((t) => (t['tag'] ?? '') as String).toList();

    // Cover/thumbnail - use first file's thumbnail via tn CDN
    final files = json['files'] as List? ?? [];
    String coverUrl = '';
    if (files.isNotEmpty) {
      final firstFile = files[0] as Map<String, dynamic>;
      final hash = firstFile['hash'] as String? ?? '';
      if (hash.isNotEmpty) {
        // Thumbnail uses real_full_path_from_hash and 'tn' base routing
        // Use webp instead of avif for browser compatibility
        final tnUrl =
            'https://a.$_domain2/webpbigtn/${_realFullPathFromHash(hash)}.webp';
        coverUrl = _applySubdomainRouting(tnUrl, 'tn');
      }
    }

    // Page count
    final pageCount = files.length;

    // Single chapter for the gallery
    final chapters = [
      ChapterItem(
        id: '1',
        mangaId: mangaId,
        title: '$pageCount pages${type.isNotEmpty ? " ($type)" : ""}',
      ),
    ];

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: artists.join(', '),
      tags: tags,
      status: MangaStatus.completed,
      chapters: chapters,
      headers: const {'Referer': 'https://hitomi.la/'},
    );
  }

  // ---------------------------------------------------------------------------
  // Chapter List
  // ---------------------------------------------------------------------------

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Single-chapter per gallery
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // ---------------------------------------------------------------------------
  // Chapter (image fetch)
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // Fetch gallery info to get image file list
    return FetchConfig(
      url: '$_ltnBase/galleries/$mangaId.js',
      responseType: ResponseType.plain,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final json = _parseGalleryJs(response as String);
    final files = json['files'] as List? ?? [];
    final title = json['title'] as String? ?? '';
    final galleryId = json['id'] ?? mangaId;

    final images = <ChapterImage>[];
    for (final file in files) {
      final fileMap = file as Map<String, dynamic>;
      final hash = fileMap['hash'] as String? ?? '';
      final name = fileMap['name'] as String? ?? '';
      final haswebp = fileMap['haswebp'] as int? ?? 0;
      final hasavif = fileMap['hasavif'] as int? ?? 0;

      if (hash.isEmpty) continue;

      // Build image URL using gg.js logic (mirrors url_from_url_from_hash)
      final imageUrl =
          _buildImageUrl(galleryId.toString(), hash, name, haswebp, hasavif);
      images.add(ChapterImage(
        url: imageUrl,
        headers: const {'Referer': 'https://hitomi.la/'},
      ));
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: const {'Referer': 'https://hitomi.la/'},
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // gg.js handling (called externally by repository before chapter fetch)
  // ---------------------------------------------------------------------------

  /// Prepares a fetch for gg.js (called by repository before chapter fetch).
  FetchConfig prepareGgFetch() {
    return const FetchConfig(
      url: 'https://ltn.gold-usergeneratedcontent.net/gg.js',
      responseType: ResponseType.plain,
    );
  }

  /// Parses gg.js response and caches the routing parameters.
  ///
  /// gg.js format:
  /// ```
  /// gg = { m: function(g) {
  ///   var o = 0;
  ///   switch (g) {
  ///   case 123:
  ///   case 456:
  ///   ...
  ///   o = 1; break;
  ///   }
  ///   return o;
  /// },
  /// s: function(h) { var m = /(..)(.)$/.exec(h); return parseInt(m[2]+m[1], 16).toString(10); },
  /// b: '1782457201/'
  /// };
  /// ```
  void parseGgResponse(String ggJs) {
    // Extract gg.b: the path prefix (e.g. '1782457201/')
    final bMatch =
        RegExp(r'''b:\s*['"]([^'"]+)['"]''').firstMatch(ggJs);
    final ggB = bMatch?.group(1) ?? '';

    // Extract default value of o: `var o = N`
    final defaultMatch = RegExp(r'var\s+o\s*=\s*(\d+)').firstMatch(ggJs);
    final defaultValue = int.tryParse(defaultMatch?.group(1) ?? '0') ?? 0;

    // Extract all case values from switch statement
    final caseSet = <int>{};
    final caseMatches = RegExp(r'case\s+(\d+):').allMatches(ggJs);
    for (final match in caseMatches) {
      final v = int.tryParse(match.group(1)!);
      if (v != null) caseSet.add(v);
    }

    _ggCaseSet = caseSet;
    _ggDefaultValue = defaultValue;
    _ggB = ggB;
    _ggFetchedAt = DateTime.now();
  }

  /// Whether gg.js data needs to be refreshed (stale after 10 minutes).
  bool get needsGgRefresh {
    if (_ggFetchedAt == null || _ggCaseSet == null || _ggB == null) {
      return true;
    }
    return DateTime.now().difference(_ggFetchedAt!).inMinutes > 10;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Mirrors `gg.m(g)` from gg.js.
  /// Cases in the switch produce the opposite of the default `o` value.
  int _ggM(int g) {
    if (_ggCaseSet == null || _ggDefaultValue == null) return 0;
    if (_ggCaseSet!.contains(g)) {
      // Cases produce opposite of default
      return _ggDefaultValue == 0 ? 1 : 0;
    }
    return _ggDefaultValue!;
  }

  /// Mirrors `gg.s(hash)` from gg.js:
  /// `var m = /(..)(.)$/.exec(h); return parseInt(m[2]+m[1], 16).toString(10);`
  String _ggS(String hash) {
    if (hash.length < 3) return '0';
    // m[1] = hash[-3:-1] (2 chars), m[2] = hash[-1] (1 char)
    final m1 = hash.substring(hash.length - 3, hash.length - 1);
    final m2 = hash.substring(hash.length - 1);
    // parseInt(m[2]+m[1], 16) → hex to decimal string
    final value = int.tryParse('$m2$m1', radix: 16) ?? 0;
    return value.toString();
  }

  /// Mirrors `full_path_from_hash(hash)` from common.js:
  /// `return gg.b + gg.s(hash) + '/' + hash;`
  String _fullPathFromHash(String hash) {
    final b = _ggB ?? '';
    return '$b${_ggS(hash)}/$hash';
  }

  /// Mirrors `real_full_path_from_hash(hash)` from common.js:
  /// `return hash.replace(/^.*(..)(.)$/, '$2/$1/'+hash);`
  String _realFullPathFromHash(String hash) {
    if (hash.length < 3) return hash;
    final m1 = hash.substring(hash.length - 3, hash.length - 1);
    final m2 = hash.substring(hash.length - 1);
    return '$m2/$m1/$hash';
  }

  /// Mirrors `subdomain_from_url(url, base, dir)` from common.js.
  ///
  /// Extracts the routing number from the URL path (64-char hash in path),
  /// then builds the subdomain based on base and dir.
  String _subdomainFromUrl(String url, String? base, String? dir) {
    var retval = '';
    if (base == null || base.isEmpty) {
      if (dir == 'webp') {
        retval = 'w';
      } else if (dir == 'avif') {
        retval = 'a';
      }
    }

    // Regex from common.js: /\/[0-9a-f]{61}([0-9a-f]{2})([0-9a-f])/
    // This matches the 64-char hash in the URL path
    final r = RegExp(r'/[0-9a-f]{61}([0-9a-f]{2})([0-9a-f])');
    final m = r.firstMatch(url);
    if (m == null) return retval;

    // g = parseInt(m[2]+m[1], 16)
    final g = int.tryParse('${m.group(2)}${m.group(1)}', radix: 16);
    if (g == null) return retval;

    if (base != null && base.isNotEmpty) {
      // retval = String.fromCharCode(97 + gg.m(g)) + base
      retval = String.fromCharCode(97 + _ggM(g)) + base;
    } else {
      // retval = retval + (1 + gg.m(g))  (e.g. 'a2' or 'w1')
      retval = '$retval${1 + _ggM(g)}';
    }

    return retval;
  }

  /// Mirrors `url_from_url(url, base, dir)` from common.js.
  /// Replaces the subdomain in the URL using routing logic.
  String _applySubdomainRouting(String url, [String? base, String? dir]) {
    final subdomain = _subdomainFromUrl(url, base, dir);
    if (subdomain.isEmpty) return url;
    // Replace: //..?.(?:gold-usergeneratedcontent\.net|hitomi\.la)/
    return url.replaceFirst(
      RegExp(r'//..?\.(?:gold-usergeneratedcontent\.net|hitomi\.la)/'),
      '//$subdomain.$_domain2/',
    );
  }

  /// Mirrors `url_from_hash(galleryid, image, dir, ext)` from common.js.
  String _urlFromHash(String hash, String dir, String ext) {
    if (dir == 'webp' || dir == 'avif') {
      // dir becomes empty string in path, ext keeps the format
      return 'https://a.$_domain2/${_fullPathFromHash(hash)}.$ext';
    }
    return 'https://a.$_domain2/$dir/${_fullPathFromHash(hash)}.$ext';
  }

  /// Build the final image URL (mirrors `url_from_url_from_hash` from common.js).
  String _buildImageUrl(
      String galleryId, String hash, String name, int haswebp, int hasavif) {
    // Always use WebP format regardless of haswebp flag.
    // Reason 1: Flutter Web cannot decode hitomi's AVIF files.
    // Reason 2: The CDN serves WebP for ALL images (even when haswebp=0 in gallery info).
    // Reason 3: The 'images/' directory (original format) is not accessible on
    //           gold-usergeneratedcontent.net CDN — it produces invalid subdomains
    //           (e.g. '1.gold-usergeneratedcontent.net' which gets 502).
    const ext = 'webp';
    const dir = 'webp';

    final baseUrl = _urlFromHash(hash, dir, ext);
    return _applySubdomainRouting(baseUrl, null, dir);
  }

  /// Parse nozomi binary response into gallery ID list.
  List<String> parseNozomiIds(dynamic response) {
    final List<int> bytes;
    if (response is Uint8List) {
      bytes = response;
    } else if (response is List<int>) {
      bytes = response;
    } else {
      return [];
    }

    final ids = <String>[];
    // Each gallery ID is 4 bytes, big-endian
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      final galleryId = (bytes[i] << 24) |
          (bytes[i + 1] << 16) |
          (bytes[i + 2] << 8) |
          bytes[i + 3];
      if (galleryId > 0) {
        ids.add(galleryId.toString());
      }
    }
    return ids;
  }

  /// Build FetchConfig for a galleryblock HTML page.
  FetchConfig prepareGalleryBlockFetch(String galleryId) {
    return FetchConfig(
      url: '$_ltnBase/galleryblock/$galleryId.html',
      responseType: ResponseType.plain,
    );
  }

  /// Parse galleryblock HTML into a MangaSummary.
  /// Returns null if parsing fails.
  MangaSummary? parseGalleryBlock(String html, String galleryId) {
    // Extract title from: <h1 class="lillie"><a href="...">TITLE</a></h1>
    final titleMatch =
        RegExp(r'<h1[^>]*class="lillie"[^>]*><a[^>]*>([^<]+)</a>')
            .firstMatch(html);
    final title = titleMatch?.group(1) ?? 'Gallery #$galleryId';

    // Extract cover from: <img class="lazyload" ... data-src="//tn.gold-.../webpbigtn/...">
    // This is the webp thumbnail (no AVIF decode issues)
    String coverUrl = '';
    final coverMatch =
        RegExp(r'data-src="(//[^"]*webpbigtn/[^"]+)"').firstMatch(html);
    if (coverMatch != null) {
      coverUrl = 'https:${coverMatch.group(1)}';
    }

    // Extract artist from: <div class="artist-list">...<a>ARTIST</a>...</div>
    // or "N/A" if no artist
    String? author;
    final artistMatch =
        RegExp(r'<div class="artist-list"[^>]*>(.*?)</div>', dotAll: true)
            .firstMatch(html);
    if (artistMatch != null) {
      final artistContent = artistMatch.group(1) ?? '';
      final artistLinkMatch =
          RegExp(r'<a[^>]*>([^<]+)</a>').firstMatch(artistContent);
      if (artistLinkMatch != null) {
        author = artistLinkMatch.group(1);
      }
    }

    return MangaSummary(
      id: galleryId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author ?? '',
      headers: const {'Referer': 'https://hitomi.la/'},
    );
  }

  /// Parse nozomi binary response into MangaSummary list (legacy fallback).
  List<MangaSummary> _parseNozomiResponse(dynamic response) {
    final ids = parseNozomiIds(response);
    return ids
        .map((id) => MangaSummary(
              id: id,
              sourceId: sourceId,
              title: 'Gallery #$id',
              coverUrl: '',
            ))
        .toList();
  }

  /// Parse `var galleryinfo = {...}` JS response into a Map.
  Map<String, dynamic> _parseGalleryJs(String jsResponse) {
    // Remove "var galleryinfo = " prefix and trailing semicolons
    var jsonStr = jsResponse.trim();
    if (jsonStr.startsWith('var galleryinfo')) {
      final eqIndex = jsonStr.indexOf('=');
      if (eqIndex != -1) {
        jsonStr = jsonStr.substring(eqIndex + 1).trim();
      }
    }
    // Remove trailing semicolons/whitespace
    while (jsonStr.endsWith(';') || jsonStr.endsWith('\n')) {
      jsonStr = jsonStr.substring(0, jsonStr.length - 1).trim();
    }

    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
