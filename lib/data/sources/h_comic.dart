import 'dart:convert';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// H-Comic source plugin.
/// Scrapes h-comic.com which is a nhentai mirror/aggregator focused on
/// Chinese-translated content, with its own image CDN proxy.
/// Data is extracted from SvelteKit SSR-embedded JSON in HTML pages.
class HComic extends MangaSource {
  static const String sourceId = 'h_comic';
  static const String _baseUrl = 'https://h-comic.com';

  /// Image CDN base mapped by comic_source field
  static const Map<String, String> _imageCdnPaths = {
    'nh': 'https://h-comic.link/api/nh',
    'mms': 'https://h-comic.link/api/mms',
    'mml': 'https://h-comic.link/api/mml',
  };

  @override
  String get id => sourceId;

  @override
  bool get isAdult => true;

  @override
  String get name => 'H-Comic';

  @override
  String get shortName => 'HC';

  @override
  String? get description => '中文同人誌聚合 (h-comic.com)';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => true;

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'tag',
          label: '標籤',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '全彩', value: 'full color'),
            FilterChoice(label: '巨乳', value: 'big breasts'),
            FilterChoice(label: 'NTR', value: 'netorare'),
            FilterChoice(label: '黑絲/白襪', value: 'stockings'),
            FilterChoice(label: '足交', value: 'footjob'),
            FilterChoice(label: '女學生', value: 'schoolgirl uniform'),
            FilterChoice(label: '眼鏡', value: 'glasses'),
            FilterChoice(label: '口交', value: 'blowjob'),
            FilterChoice(label: '正太', value: 'shotacon'),
            FilterChoice(label: '亂倫', value: 'incest'),
            FilterChoice(label: '熟女/人妻', value: 'milf'),
            FilterChoice(label: '同志BL', value: 'males only'),
            FilterChoice(label: '泳裝', value: 'swimsuit'),
            FilterChoice(label: '姐姐/妹妹', value: 'sister'),
            FilterChoice(label: '催眠', value: 'mind control'),
            FilterChoice(label: '群交', value: 'group'),
            FilterChoice(label: '肛交', value: 'anal'),
          ],
        ),
      ];

  // --- Discovery ---

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final tag = filters['tag'] ?? '';
    final params = <String, dynamic>{'page': '$page'};
    if (tag.isNotEmpty) {
      params['tag'] = tag;
    }
    return FetchConfig(url: _baseUrl, queryParameters: params);
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseComicList(response as String);
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final params = <String, dynamic>{
      'q': keyword,
      'page': '$page',
    };
    return FetchConfig(url: _baseUrl, queryParameters: params);
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseComicList(response as String);
  }

  // --- Manga Info ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    // Use the reader page which has full SSR data
    return FetchConfig(url: '$_baseUrl/comics/$mangaId/reader');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final data = _extractSsrData(htmlStr);
    if (data == null) {
      return MangaDetail(
        id: mangaId,
        sourceId: sourceId,
        title: 'Unknown',
        coverUrl: '',
        status: MangaStatus.completed,
      );
    }

    final comic = _extractComic(data);
    if (comic == null) {
      return MangaDetail(
        id: mangaId,
        sourceId: sourceId,
        title: 'Unknown',
        coverUrl: '',
        status: MangaStatus.completed,
      );
    }

    final title = _getTitle(comic);
    final coverUrl = _getCoverUrl(comic);
    final tags = _getTags(comic);
    final author = _getArtist(comic);
    final numPages = (comic['num_pages'] as num?)?.toInt() ?? 0;

    // Single chapter for the entire gallery
    final chapters = [
      ChapterItem(
        id: '1',
        mangaId: mangaId,
        title: '$numPages pages',
      ),
    ];

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: author,
      tags: tags,
      status: MangaStatus.completed,
      chapters: chapters,
    );
  }

  // --- Chapter List ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Single-chapter per gallery, no separate fetch needed
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(url: '$_baseUrl/comics/$mangaId/reader');
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final data = _extractSsrData(htmlStr);
    final comic = data != null ? _extractComic(data) : null;

    if (comic == null) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    final title = _getTitle(comic);
    final images = _buildImageUrls(comic);

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
      ),
    );
  }

  // --- Private Helpers ---

  /// Extract SSR data from SvelteKit HTML page.
  /// Data is embedded in a script block like:
  /// `__sveltekit_17t8wkb = {..., nodes: [..., () => {...data: [null,{"type":"data","data":{comics:[...]}}]}]}`
  /// The outer wrapper uses JSON (quoted keys) but the inner data payload
  /// uses JavaScript object literal syntax (unquoted keys).
  Map<String, dynamic>? _extractSsrData(String html) {
    // Find the data payload marker: `data: [null,{"type":"data","data":{`
    // or `"data":[null,{"type":"data","data":{`
    final marker = RegExp(r'(?:"data"|data)\s*:\s*\[null,\{"type":"data","data":\{');
    final markerMatch = marker.firstMatch(html);
    if (markerMatch == null) return null;

    // Start extracting from after `"data":{`
    final dataStart = markerMatch.end; // position right after the opening {

    // Find the matching closing by tracking brace depth
    // We need to find where the inner data object ends: `},"uses":{...}}]`
    // Strategy: find `},"uses":` or end of the wrapping `}]`
    final scriptEnd = html.indexOf('</script>', dataStart);
    if (scriptEnd == -1) return null;
    final segment = html.substring(dataStart, scriptEnd);

    // Find the end of the data object. The structure is:
    // {"type":"data","data":{...DATA...},"uses":{...}}]
    // We need to extract ...DATA... which is JS object literal.
    // Find `},"uses":` pattern to locate the end of data content.
    const usesMarker = ',"uses":';
    final usesIdx = segment.lastIndexOf(usesMarker);

    String jsContent;
    if (usesIdx != -1) {
      // Extract everything before `,"uses":`
      // The segment looks like: `comics:[...],pages:{...},tagTranslate:[]},"uses":...`
      // The trailing `}` before `,"uses":` is the closing brace of the outer "data" object.
      // We want just the inner content without that trailing `}`.
      jsContent = segment.substring(0, usesIdx);
      // Remove trailing `}` which belongs to the outer wrapper
      if (jsContent.endsWith('}')) {
        jsContent = jsContent.substring(0, jsContent.length - 1);
      }
    } else {
      // Fallback: try to find closing `}]` at end
      final closeIdx = segment.lastIndexOf('}]');
      if (closeIdx == -1) return null;
      jsContent = segment.substring(0, closeIdx);
    }

    // Wrap in braces to make it a complete object: `{comics:[...], pages:{...}}`
    final jsObj = '{$jsContent}';

    // Convert JS object literal to valid JSON:
    // Add quotes around unquoted keys (word characters before a colon)
    final jsonStr = _jsToJson(jsObj);

    try {
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  /// Convert JavaScript object literal to valid JSON string.
  /// Handles unquoted keys like `{comics:[{_id:"abc"}]}` → `{"comics":[{"_id":"abc"}]}`
  String _jsToJson(String js) {
    final buf = StringBuffer();
    var i = 0;
    while (i < js.length) {
      final ch = js[i];

      if (ch == '"') {
        // Skip over quoted strings
        buf.write(ch);
        i++;
        while (i < js.length) {
          final c = js[i];
          buf.write(c);
          i++;
          if (c == '\\' && i < js.length) {
            buf.write(js[i]);
            i++;
          } else if (c == '"') {
            break;
          }
        }
      } else if (_isIdentStart(ch) && _isKeyPosition(js, i)) {
        // Unquoted key: read identifier and wrap in quotes
        final start = i;
        while (i < js.length && _isIdentChar(js[i])) {
          i++;
        }
        final key = js.substring(start, i);
        buf.write('"$key"');
      } else {
        buf.write(ch);
        i++;
      }
    }
    return buf.toString();
  }

  /// Check if position i is the start of an object key (after { or ,)
  bool _isKeyPosition(String js, int i) {
    // Look backwards to find the preceding non-whitespace character
    var j = i - 1;
    while (j >= 0 && (js[j] == ' ' || js[j] == '\t' || js[j] == '\n' || js[j] == '\r')) {
      j--;
    }
    if (j < 0) return false;
    final prev = js[j];
    // A key follows { or , in object context
    if (prev != '{' && prev != ',') return false;
    // Verify this identifier is followed by a colon
    var k = i;
    while (k < js.length && _isIdentChar(js[k])) {
      k++;
    }
    // Skip whitespace after identifier
    while (k < js.length && (js[k] == ' ' || js[k] == '\t')) {
      k++;
    }
    return k < js.length && js[k] == ':';
  }

  bool _isIdentStart(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || // A-Z
        (c >= 97 && c <= 122) || // a-z
        c == 95; // _
  }

  bool _isIdentChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || // A-Z
        (c >= 97 && c <= 122) || // a-z
        (c >= 48 && c <= 57) || // 0-9
        c == 95; // _
  }

  /// Extract comic object from SSR data.
  /// For list pages: data contains 'comics' array
  /// For reader page: data contains a single 'comic' object
  Map<String, dynamic>? _extractComic(Map<String, dynamic> data) {
    if (data.containsKey('comic')) {
      return data['comic'] as Map<String, dynamic>?;
    }
    return null;
  }

  /// Parse comic list from SSR data (discovery/search pages).
  List<MangaSummary> _parseComicList(String html) {
    final data = _extractSsrData(html);
    if (data == null) return [];

    final comicsList = data['comics'] as List<dynamic>?;
    if (comicsList == null) return [];

    final results = <MangaSummary>[];
    for (final item in comicsList) {
      if (item is! Map<String, dynamic>) continue;

      final comicId = item['id']?.toString() ?? '';
      if (comicId.isEmpty) continue;

      final title = _getTitle(item);
      final coverUrl = _getCoverUrl(item);
      final author = _getArtist(item);

      results.add(MangaSummary(
        id: comicId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        author: author,
      ));
    }

    return results;
  }

  /// Get display title from comic object.
  String _getTitle(Map<String, dynamic> comic) {
    final titleObj = comic['title'];
    if (titleObj is Map<String, dynamic>) {
      return (titleObj['display'] as String?) ??
          (titleObj['pretty'] as String?) ??
          (titleObj['japanese'] as String?) ??
          (titleObj['english'] as String?) ??
          '';
    }
    return titleObj?.toString() ?? '';
  }

  /// Get cover image URL from comic object.
  String _getCoverUrl(Map<String, dynamic> comic) {
    // Use the thumbnail field directly if available
    final thumbnail = comic['thumbnail'] as String?;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return thumbnail;
    }

    // Fallback: construct from media_id and comic_source
    final mediaId = comic['media_id']?.toString();
    final comicSource = comic['comic_source']?.toString() ?? 'nh';
    if (mediaId != null && mediaId.isNotEmpty) {
      final cdnBase = _imageCdnPaths[comicSource] ?? _imageCdnPaths['nh']!;
      return '$cdnBase/$mediaId';
    }

    return '';
  }

  /// Get artist name from tags.
  String _getArtist(Map<String, dynamic> comic) {
    final tags = comic['tags'] as List<dynamic>?;
    if (tags == null) return '';

    final artists = tags
        .where((t) => t is Map<String, dynamic> && t['type'] == 'artist')
        .map((t) => (t as Map<String, dynamic>)['name_zh'] ??
            (t)['name'] ??
            '')
        .where((name) => name.toString().isNotEmpty)
        .toList();

    return artists.join(', ');
  }

  /// Get tag names from comic object.
  List<String> _getTags(Map<String, dynamic> comic) {
    final tags = comic['tags'] as List<dynamic>?;
    if (tags == null) return [];

    return tags
        .where((t) => t is Map<String, dynamic> && t['type'] == 'tag')
        .map((t) => ((t as Map<String, dynamic>)['name_zh'] ??
                (t)['name'] ??
                '')
            .toString())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  /// Build image URLs for all pages of a comic.
  List<ChapterImage> _buildImageUrls(Map<String, dynamic> comic) {
    final mediaId = comic['media_id']?.toString();
    final comicSource = comic['comic_source']?.toString() ?? 'nh';
    final numPages = (comic['num_pages'] as num?)?.toInt() ?? 0;

    if (mediaId == null || mediaId.isEmpty || numPages == 0) return [];

    final cdnBase = _imageCdnPaths[comicSource] ?? _imageCdnPaths['nh']!;
    final images = <ChapterImage>[];

    for (var i = 1; i <= numPages; i++) {
      images.add(ChapterImage(
        url: '$cdnBase/$mediaId/pages/$i',
      ));
    }

    return images;
  }
}
