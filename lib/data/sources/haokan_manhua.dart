import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class HaokanManhua extends MangaSource {
  static const String sourceId = 'haokan';
  static const String _baseUrl = 'https://www.haokantxt.com';

  @override
  String get id => sourceId;

  @override
  String get name => '好看漫画';

  @override
  String get shortName => 'HK';

  @override
  String? get description => '国内免费漫画站，MCCMS 系统';

  @override
  double get score => 3.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => false;

  @override
  bool get needsProxy => false;

  @override
  Map<String, String>? get defaultHeaders => {'Referer': _baseUrl};

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'tags',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '热血', value: '6'),
            FilterChoice(label: '冒险', value: '7'),
            FilterChoice(label: '科幻', value: '8'),
            FilterChoice(label: '霸总', value: '9'),
            FilterChoice(label: '玄幻', value: '10'),
            FilterChoice(label: '校园', value: '11'),
            FilterChoice(label: '修真', value: '12'),
            FilterChoice(label: '搞笑', value: '13'),
          ],
        ),
        FilterOption(
          name: 'finish',
          label: '状态',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '连载', value: '1'),
            FilterChoice(label: '完结', value: '2'),
          ],
        ),
        FilterOption(
          name: 'order',
          label: '排序',
          defaultValue: 'addtime',
          choices: [
            FilterChoice(label: '最新', value: 'addtime'),
            FilterChoice(label: '人气', value: 'hits'),
          ],
        ),
      ];

  // --- Discovery ---
  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final buffer = StringBuffer('$_baseUrl/category');
    final tags = filters['tags'] ?? '';
    final finish = filters['finish'] ?? '';
    final order = filters['order'] ?? '';
    if (tags.isNotEmpty) buffer.write('/tags/$tags');
    if (finish.isNotEmpty) buffer.write('/finish/$finish');
    if (order.isNotEmpty) buffer.write('/order/$order');
    buffer.write('/page/$page');
    return FetchConfig(url: buffer.toString());
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseCards(response as String);
  }

  // --- Search ---
  @override
  FetchConfig prepareSearchFetch(String keyword, int page, Map<String, String> filters) {
    // Path form is required: query form (?key=) does not support pagination.
    return FetchConfig(url: '$_baseUrl/search/${Uri.encodeComponent(keyword)}/$page');
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseCards(response as String);
  }

  // --- Manga Info ---
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/comic_$mangaId.html');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Numeric comic id: needed to build chapter URLs. Fall back to slug.
    final numericId = _extractNumericId(htmlStr) ?? mangaId;

    // Prefer ld+json for metadata; fall back to DOM.
    final ld = _parseLdJson(document);

    String title = _stripBrackets((ld?['name'] as String?) ??
        document.querySelector('.comic-meta-info h1')?.text.trim() ??
        '');

    final authorLd = (ld?['author'] is Map && ld!['author']['name'] is String)
        ? ld['author']['name'] as String
        : null;
    final author = authorLd ?? '';

    final description = (ld?['description'] as String?) ??
        document.querySelector('.comic-description p')?.text.trim();

    String coverUrl = (ld?['image'] as String?) ??
        document.querySelector('.comic-cover-large img')?.attributes['src'] ??
        '';

    String? latestChapter;
    if (ld?['workExample'] is Map) {
      final be = ld!['workExample']['bookEdition'];
      if (be is String) latestChapter = be;
    }

    // Status from the second .comic-tags .tag (连载 / 完结).
    final statusTags = document.querySelectorAll('.comic-tags .tag');
    MangaStatus status = MangaStatus.unknown;
    if (statusTags.length >= 2) {
      final text = statusTags[1].text.trim();
      if (text.contains('连载')) {
        status = MangaStatus.ongoing;
      } else if (text.contains('完结')) {
        status = MangaStatus.completed;
      }
    }

    final tags = <String>[];
    final genre = ld?['genre'];
    if (genre is String && genre.isNotEmpty) tags.add(genre);

    // Chapters embedded in the info page.
    final chapters = <ChapterItem>[];
    for (final a in document.querySelectorAll('#chapter-list .chapter-item > a')) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'chapter_(\d+)_(\d+)\.html').firstMatch(href);
      if (m == null) continue;
      // Composite chapterId: "{numericComicId}_{cid}" so prepareChapterFetch
      // can build the chapter URL without depending on the mangaId param
      // (the framework passes the slug, not the numeric id, at runtime).
      final chapterId = '${m.group(1)!}_${m.group(2)!}';
      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: numericId,
        title: a.text.trim(),
        href: '$_baseUrl$href',
      ));
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: tags,
      status: status,
      latestChapter: latestChapter,
      chapters: chapters,
      // Cover CDN (comic.5um.net) requires a Referer header, else it
      // returns an HTML captcha page that fails to decode as an image.
      headers: const {'Referer': _baseUrl},
    );
  }

  // --- Chapter List (embedded in info page) ---
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page, {dynamic extra}) {
    // chapterId is the composite "{numericComicId}_{cid}"; the chapter URL is
    // /chapter_{numericComicId}_{cid}.html, i.e. /chapter_{chapterId}.html.
    // mangaId (the slug) is intentionally unused here.
    return FetchConfig(url: '$_baseUrl/chapter_$chapterId.html');
  }

  @override
  ChapterResult parseChapter(dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final imgEls = document.querySelectorAll('.comic-content img.comic-image');
    final images = <ChapterImage>[];
    for (final el in imgEls) {
      final url = el.attributes['src'] ?? el.attributes['data-src'] ?? '';
      if (url.isEmpty) continue;
      images.add(ChapterImage(
        url: url,
        headers: const {'Referer': _baseUrl},
      ));
    }

    // Paywall guard: zero images + a paywall box that is NOT hidden.
    if (images.isEmpty) {
      final buyBox = document.querySelector('.buy-box');
      if (buyBox != null) {
        final style = buyBox.attributes['style'] ?? '';
        if (!style.contains('display:none') && !style.contains('display: none')) {
          throw Exception('该章节需要付费');
        }
      }
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: images,
      ),
      canLoadMore: false,
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/chapter_$chapterId.html';
  }

  String? _extractNumericId(String htmlStr) {
    final byData = RegExp(r'data-id="(\d+)"').firstMatch(htmlStr);
    if (byData != null) return byData.group(1);
    final byChapter = RegExp(r'chapter_(\d+)_').firstMatch(htmlStr);
    return byChapter?.group(1);
  }

  Map<String, dynamic>? _parseLdJson(Document document) {
    final el = document.querySelector('script[type="application/ld+json"]');
    if (el == null) return null;
    try {
      final decoded = json.decode(el.text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _stripBrackets(String s) => s.replaceAll('《', '').replaceAll('》', '').trim();

  /// Resolve the manga URL slug from a detail-page href like /comic_yirenzhixia.html
  String? _extractSlug(String href) {
    final match = RegExp(r'comic_(.+?)\.html').firstMatch(href);
    return match?.group(1);
  }

  /// Parse `.comic-item` cards (handles the three DOM variants observed on the
  /// site: div-wrapper with inner a.comic-cover, outer <a class="comic-item">,
  /// and the search/category variant).
  List<MangaSummary> _parseCards(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final items = document.querySelectorAll('.comic-item');
    final results = <MangaSummary>[];
    for (final item in items) {
      final href = item.localName == 'a'
          ? (item.attributes['href'] ?? '')
          : (item.querySelector('a')?.attributes['href'] ?? '');
      final slug = _extractSlug(href);
      if (slug == null) continue;

      final titleEl = item.querySelector('.comic-title') ??
          item.querySelector('h3 a') ??
          item.querySelector('h3');
      final title = titleEl?.text.trim() ?? '';

      final imgEl = item.querySelector('img');
      final cover = imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '';

      final author = item.querySelector('p.comic-author')?.text.trim() ?? '';
      final badge = item.querySelector('span.update-badge')?.text.trim();

      results.add(MangaSummary(
        id: slug,
        sourceId: sourceId,
        title: title,
        coverUrl: cover,
        author: author,
        latestChapter: badge,
        // Cover CDN (comic.5um.net) requires a Referer header, else it
        // returns an HTML captcha page that fails to decode as an image.
        headers: const {'Referer': _baseUrl},
      ));
    }
    return results;
  }
}
