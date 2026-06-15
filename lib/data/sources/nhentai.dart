import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// NHentai source plugin.
/// Parses HTML gallery covers for discovery/search, and uses
/// embedded JSON (`window._gallery`) for manga info and chapter images.
class NHentai extends MangaSource {
  static const String sourceId = 'nhentai';
  static const String _baseUrl = 'https://nhentai.net';

  @override
  String get id => sourceId;

  @override
  String get name => 'NHentai';

  @override
  String get shortName => 'NH';

  @override
  String? get description => 'English doujinshi gallery (requires CF bypass)';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsCloudflare => true;

  @override
  List<String> get cloudflarePageTitles => const ['Just a moment...'];

  @override
  List<FilterOption> get searchFilters => const [
        FilterOption(
          name: 'sort',
          label: 'Sort',
          defaultValue: '',
          choices: [
            FilterChoice(label: 'Recent', value: ''),
            FilterChoice(label: 'Popular Today', value: 'popular-today'),
            FilterChoice(label: 'Popular This Week', value: 'popular-week'),
            FilterChoice(label: 'Popular All Time', value: 'popular'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    return FetchConfig(
      url: _baseUrl,
      queryParameters: {'page': '$page'},
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseGalleryList(response as String);
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final sort = filters['sort'] ?? '';
    final params = <String, dynamic>{
      'q': keyword,
      'page': '$page',
    };
    if (sort.isNotEmpty) {
      params['sort'] = sort;
    }
    return FetchConfig(
      url: '$_baseUrl/search/',
      queryParameters: params,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final htmlStr = response as String;

    // Check if this is a direct gallery page (has window._gallery)
    if (htmlStr.contains('window._gallery')) {
      final data = _extractGalleryJson(htmlStr);
      if (data != null) {
        final mangaId = data['id'].toString();
        final title = (data['title'] as Map?)?['english'] ??
            (data['title'] as Map?)?['japanese'] ??
            '';
        final cover = _buildCoverUrl(data);
        final tags = data['tags'] as List? ?? [];
        final artists = tags
            .where((t) => t['type'] == 'artist')
            .map<String>((t) => t['name'] as String)
            .toList();

        return [
          MangaSummary(
            id: mangaId,
            sourceId: sourceId,
            title: title.toString(),
            coverUrl: cover,
            author: artists.join(', '),
          ),
        ];
      }
    }

    return _parseGalleryList(htmlStr);
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/g/$mangaId/');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final data = _extractGalleryJson(htmlStr);

    if (data == null) {
      // Fallback: parse HTML directly
      return _parseMangaInfoFromHtml(htmlStr, mangaId);
    }

    final titleMap = data['title'] as Map? ?? {};
    final title =
        (titleMap['english'] ?? titleMap['japanese'] ?? '').toString();
    final cover = _buildCoverUrl(data);

    final tags = data['tags'] as List? ?? [];
    final tagNames = <String>[];
    final artists = <String>[];
    final groups = <String>[];

    for (final tag in tags) {
      final type = tag['type'] as String? ?? '';
      final tagName = tag['name'] as String? ?? '';
      if (type == 'tag') {
        tagNames.add(tagName);
      } else if (type == 'artist') {
        artists.add(tagName);
      } else if (type == 'group') {
        groups.add(tagName);
      }
    }

    final numPages = data['num_pages'] as int? ?? 0;
    final uploadDate = data['upload_date'] as int?;
    String? updateTime;
    if (uploadDate != null) {
      updateTime = DateTime.fromMillisecondsSinceEpoch(uploadDate * 1000)
          .toIso8601String()
          .split('T')
          .first;
    }

    // Single chapter for the gallery
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
      coverUrl: cover,
      author: artists.isNotEmpty ? artists.join(', ') : groups.join(', '),
      tags: tagNames,
      status: MangaStatus.completed,
      updateTime: updateTime,
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // NHentai is single-chapter per gallery
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(url: '$_baseUrl/g/$mangaId/1');
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final data = _extractGalleryJson(htmlStr);

    if (data == null) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    // Extract picture base from the page's first image
    String pictureBase = '';
    final document = html_parser.parse(htmlStr);
    final imgEl = document.querySelector('section#image-container img');
    if (imgEl != null) {
      final src = imgEl.attributes['src'] ?? '';
      if (src.isNotEmpty) {
        final lastSlash = src.lastIndexOf('/');
        if (lastSlash > 0) {
          pictureBase = src.substring(0, lastSlash);
        }
      }
    }

    // Fallback: construct from media_id
    if (pictureBase.isEmpty) {
      final mediaId = data['media_id']?.toString() ?? '';
      if (mediaId.isNotEmpty) {
        pictureBase = 'https://i.nhentai.net/galleries/$mediaId';
      }
    }

    final pagesData = (data['images'] as Map?)?['pages'] as List? ?? [];
    final images = <ChapterImage>[];

    for (var i = 0; i < pagesData.length; i++) {
      final pageInfo = pagesData[i] as Map;
      final ext = _getExtension(pageInfo['t'] as String? ?? 'j');
      images.add(ChapterImage(
        url: '$pictureBase/${i + 1}.$ext',
      ));
    }

    final titleMap = data['title'] as Map? ?? {};
    final title =
        (titleMap['english'] ?? titleMap['japanese'] ?? '').toString();

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

  List<MangaSummary> _parseGalleryList(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final items = document.querySelectorAll('div.gallery a.cover');
    final results = <MangaSummary>[];

    for (final item in items) {
      final href = item.attributes['href'] ?? '';
      final mangaId = _extractGalleryId(href);
      if (mangaId == null) continue;

      final imgEl = item.querySelector('img');
      final title =
          item.querySelector('div.caption')?.text.trim() ?? '';
      final cover = imgEl?.attributes['data-src'] ??
          imgEl?.attributes['src'] ??
          '';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: _ensureAbsoluteUrl(cover),
      ));
    }

    return results;
  }

  Map<String, dynamic>? _extractGalleryJson(String htmlStr) {
    // Look for window._gallery = JSON.parse("...")
    final match =
        RegExp(r'window\._gallery\s*=\s*JSON\.parse\("(.+?)"\)')
            .firstMatch(htmlStr);
    if (match == null) return null;

    try {
      // The JSON string is escaped in the HTML
      final escaped = match.group(1)!;
      final unescaped = escaped
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\')
          .replaceAll(r'\/', '/');
      return jsonDecode(unescaped) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _buildCoverUrl(Map<String, dynamic> data) {
    final mediaId = data['media_id']?.toString() ?? '';
    final images = data['images'] as Map? ?? {};
    final coverInfo = images['cover'] as Map? ?? {};
    final ext = _getExtension(coverInfo['t'] as String? ?? 'j');
    return 'https://t.nhentai.net/galleries/$mediaId/cover.$ext';
  }

  String _getExtension(String t) {
    switch (t) {
      case 'j':
        return 'jpg';
      case 'p':
        return 'png';
      case 'g':
        return 'gif';
      case 'w':
        return 'webp';
      default:
        return 'jpg';
    }
  }

  String? _extractGalleryId(String href) {
    final match = RegExp(r'/g/(\d+)').firstMatch(href);
    return match?.group(1);
  }

  String _ensureAbsoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$_baseUrl$url';
  }

  MangaDetail _parseMangaInfoFromHtml(String htmlStr, String mangaId) {
    final document = html_parser.parse(htmlStr);

    final title =
        document.querySelector('h1.title span.pretty')?.text.trim() ??
            document.querySelector('h1')?.text.trim() ??
            '';
    final coverEl = document.querySelector('#cover img');
    final cover = coverEl?.attributes['data-src'] ??
        coverEl?.attributes['src'] ??
        '';

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: _ensureAbsoluteUrl(cover),
      status: MangaStatus.completed,
      chapters: [
        ChapterItem(id: '1', mangaId: mangaId, title: 'Read'),
      ],
    );
  }
}
