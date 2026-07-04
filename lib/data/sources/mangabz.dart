import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/utils/js_unpacker.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Mangabz (漫畫bz) - traditional-Chinese Japanese-manga reader.
///
/// - Detail page: `/{urlKey}/` (e.g. `/242bz/`). mangaId == urlKey.
/// - List/category: `/manga-list-{tagid}-{status}-{sort}/`.
/// - Search: `/search/?title={keyword}`.
/// - Chapter reader: `/m{cid}/` (e.g. `/m16752/`). chapterId == `m{cid}`.
///
/// Chapter images live inside a Dean-Edwards packed `eval(function(p,a,c,k,e,d){...})`
/// block. After unpacking, the full image list for the whole chapter is present
/// (no pagination). Image URLs already carry signature params (key/uk) so they
/// are usable directly, but require a `Referer` header pointing at the reader URL.
class Mangabz extends MangaSource {
  static const String sourceId = 'mangabz';
  static const String _baseUrl = 'https://mangabz.com';

  static const String _mobileUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 '
      'Mobile/15E148 Safari/604.1';

  String _resolveUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$_baseUrl$url';
  }

  @override
  String get id => sourceId;

  @override
  String get name => '漫畫bz';

  @override
  String get shortName => 'MBZ';

  @override
  String? get description => '繁体中文日漫';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => false;

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;

  @override
  String? get userAgent => _mobileUA;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _mobileUA,
        'Referer': '$_baseUrl/',
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'tagid',
          label: '分類',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '熱血', value: '31'),
            FilterChoice(label: '戀愛', value: '26'),
            FilterChoice(label: '校園', value: '1'),
            FilterChoice(label: '冒險', value: '2'),
            FilterChoice(label: '科幻', value: '25'),
            FilterChoice(label: '生活', value: '11'),
            FilterChoice(label: '懸疑', value: '17'),
            FilterChoice(label: '魔法', value: '15'),
            FilterChoice(label: '運動', value: '34'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '狀態',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '連載中', value: '1'),
            FilterChoice(label: '已完結', value: '2'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: '10',
          choices: [
            FilterChoice(label: '人氣', value: '10'),
            FilterChoice(label: '更新時間', value: '2'),
            FilterChoice(label: '上架時間', value: '18'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final tagid = filters['tagid'] ?? '0';
    final status = filters['status'] ?? '0';
    final sort = filters['sort'] ?? '10';
    // Pagination is path-based (`-p{page}/`), NOT a `?page=` query param.
    // `?page=` is silently ignored by the server and always returns page 1.
    final suffix = page > 1 ? '-p$page' : '';
    return FetchConfig(
      url: '$_baseUrl/manga-list-$tagid-$status-$sort$suffix/',
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final document = html_parser.parse(response as String);
    return _parseListCards(document.querySelectorAll('.manga-i-list-item'));
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search/',
      headers: defaultHeaders,
      queryParameters: {'title': keyword, 'page': '$page'},
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final document = html_parser.parse(response as String);
    // Search results use `.manga-item`; fall back to list-card layout.
    final items = document.querySelectorAll('.manga-item');
    if (items.isNotEmpty) {
      return _parseSearchCards(items);
    }
    return _parseListCards(document.querySelectorAll('.manga-i-list-item'));
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/$mangaId/',
      headers: defaultHeaders,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final document = html_parser.parse(response as String);

    final title =
        document.querySelector('.detail-main-title')?.text.trim() ?? '';

    final coverEl = document.querySelector('img.detail-bar-img');
    final cover = _resolveUrl(
        coverEl?.attributes['src'] ?? coverEl?.attributes['data-src'] ?? '');

    // Author + tags live in .detail-main-subtitle spans.
    String author = '';
    final tags = <String>[];
    final subtitle = document.querySelector('.detail-main-subtitle');
    if (subtitle != null) {
      for (final span in subtitle.querySelectorAll('span.block')) {
        final label = span.text.trim();
        if (label.startsWith('作者')) {
          author = span
              .querySelectorAll('a span')
              .map((e) => e.text.trim())
              .where((e) => e.isNotEmpty)
              .join(', ');
          if (author.isEmpty) {
            author = label.replaceFirst(RegExp(r'^作者[：:]\s*'), '').trim();
          }
        } else if (label.startsWith('題材') || label.startsWith('题材')) {
          for (final s in span.querySelectorAll('span')) {
            final t = s.text.trim();
            if (t.isNotEmpty) tags.add(t);
          }
        }
      }
    }

    final description =
        document.querySelector('.detail-main-content')?.text.trim();

    // Status from the left label of the chapter section.
    var status = MangaStatus.unknown;
    final statusEl = document.querySelector('.detail-list-left');
    final statusText = statusEl?.text.trim() ?? '';
    if (statusText.contains('連載') || statusText.contains('连载')) {
      status = MangaStatus.ongoing;
    } else if (statusText.contains('完結') || statusText.contains('完结')) {
      status = MangaStatus.completed;
    }

    // Chapters are embedded in the detail page as `<a href="/m{cid}/">`.
    final chapters = _parseChapterAnchors(
        document.querySelectorAll('a[href^="/m"]'), mangaId);

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: cover,
      description: description,
      author: author,
      tags: tags,
      status: status,
      chapters: chapters,
      headers: defaultHeaders,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are parsed from the detail page.
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/$chapterId/',
      headers: defaultHeaders,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;

    final title = _extractReaderTitle(htmlStr);
    final referer = '$_baseUrl/$chapterId/';
    final imageHeaders = {
      'User-Agent': _mobileUA,
      'Referer': referer,
    };

    final images = <ChapterImage>[];

    final packed = JsUnpacker.findPackedScript(htmlStr) ??
        _findPackedFallback(htmlStr);
    if (packed != null) {
      final unpacked = JsUnpacker.unpack(packed);
      if (unpacked != null) {
        final urlPattern =
            RegExp(r'https://image\.mangabz\.com/[^' "'" r'"\s\\]+');
        final seen = <String>{};
        for (final m in urlPattern.allMatches(unpacked)) {
          final url = m.group(0)!;
          if (seen.add(url)) {
            images.add(ChapterImage(url: url, headers: imageHeaders));
          }
        }
      }
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: imageHeaders,
      ),
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/$chapterId/';
  }

  // --- Private helpers ---

  /// Parse home/list card layout: `.manga-i-list-item` containers.
  List<MangaSummary> _parseListCards(List<Element> items) {
    final results = <MangaSummary>[];
    final seen = <String>{};
    for (final item in items) {
      final link = item.querySelector('a[href^="/"]');
      final mangaId = _extractUrlKey(link?.attributes['href'] ?? '');
      if (mangaId == null || !seen.add(mangaId)) continue;

      final imgEl = item.querySelector('img.manga-i-cover') ??
          item.querySelector('img');
      final cover = _resolveUrl(imgEl?.attributes['src'] ??
          imgEl?.attributes['data-src'] ??
          '');

      final title = item.querySelector('.manga-i-list-title')?.text.trim() ??
          imgEl?.attributes['alt']?.trim() ??
          '';
      if (title.isEmpty) continue;

      final subtitle =
          item.querySelector('.manga-i-list-subtitle')?.text.trim();

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: cover,
        latestChapter: subtitle,
        headers: defaultHeaders,
      ));
    }
    return results;
  }

  /// Parse search result layout: `.manga-item` anchors.
  List<MangaSummary> _parseSearchCards(List<Element> items) {
    final results = <MangaSummary>[];
    final seen = <String>{};
    for (final item in items) {
      final href = item.localName == 'a'
          ? item.attributes['href'] ?? ''
          : item.querySelector('a[href^="/"]')?.attributes['href'] ?? '';
      final mangaId = _extractUrlKey(href);
      if (mangaId == null || !seen.add(mangaId)) continue;

      final imgEl = item.querySelector('img.manga-item-cover') ??
          item.querySelector('img');
      final cover = _resolveUrl(imgEl?.attributes['src'] ??
          imgEl?.attributes['data-src'] ??
          '');

      final title = item.querySelector('.manga-item-title')?.text.trim() ??
          imgEl?.attributes['alt']?.trim() ??
          '';
      if (title.isEmpty) continue;

      final author =
          item.querySelector('.manga-item-subtitle')?.text.trim() ?? '';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: cover,
        author: author,
        headers: defaultHeaders,
      ));
    }
    return results;
  }

  /// Extract the manga urlKey from an href like `/242bz/`.
  /// Excludes chapter links (`/m123/`).
  String? _extractUrlKey(String href) {
    final match = RegExp(r'^/([0-9a-zA-Z]+)/?$').firstMatch(href.trim());
    if (match == null) return null;
    final key = match.group(1)!;
    // Chapter links look like `m16752`; skip them here.
    if (RegExp(r'^m\d+$').hasMatch(key)) return null;
    return key;
  }

  /// Parse embedded chapter anchors `<a href="/m{cid}/">`.
  List<ChapterItem> _parseChapterAnchors(List<Element> anchors, String mangaId) {
    final chapters = <ChapterItem>[];
    final seen = <String>{};
    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      final match = RegExp(r'^/(m\d+)/?$').firstMatch(href.trim());
      if (match == null) continue;
      final chapterId = match.group(1)!;
      if (!seen.add(chapterId)) continue;
      final title = a.text.trim();
      if (title.isEmpty) continue;
      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        href: '$_baseUrl/$chapterId/',
      ));
    }
    return chapters;
  }

  /// Reader page title, e.g. `籃球少年王漫畫_第1卷_...` -> `第1卷`.
  String _extractReaderTitle(String html) {
    final titleMatch = RegExp(r'<title>([^<]*)</title>').firstMatch(html);
    if (titleMatch != null) {
      final parts = titleMatch.group(1)!.split('_');
      if (parts.length >= 2) return parts[1].trim();
    }
    return '';
  }

  /// Fallback: capture the raw packed function call if [JsUnpacker.findPackedScript]
  /// misses due to trailing-argument variations.
  String? _findPackedFallback(String html) {
    final match = RegExp(
      r"eval\(function\(p,a,c,k,e,d\)\{.*?\.split\('\|'\)\s*,\s*\d+\s*,\s*\{?\}?\s*\)\)",
      dotAll: true,
    ).firstMatch(html);
    return match?.group(0);
  }
}
