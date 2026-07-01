import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/utils/js_unpacker.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Manhuaren (漫画人) source backed by the dm5/动漫屋 SSR website
/// at https://www.manhuaren.com.
///
/// The previous implementation used the mobile APP API
/// (mangaapi.manhuaren.com) with RSA + GSN signing and anonymous user
/// registration via /v1/user/createAnonyUser2. That endpoint returns
/// `code:41000 初始化失败` for unknown devices/IPs (server-side rejection,
/// not a signing bug — see keiyoushi/extensions-source issue #789), so we
/// scrape the public SSR website instead, which needs no authentication.
class ManhuarenSource extends MangaSource {
  static const String sourceId = 'manhuaren';
  static const String _baseUrl = 'https://www.manhuaren.com';

  static const String _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 '
      'Mobile/15E148 Safari/604.1';

  @override
  String get id => sourceId;

  @override
  String get name => '漫画人';

  @override
  String get shortName => 'MHR';

  @override
  String? get description => '动漫屋(dm5)网页源，无需登录';

  @override
  double get score => 6.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => true;

  @override
  String? get userAgent => _ua;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _ua,
        'Referer': '$_baseUrl/',
      };

  /// Resolve a potentially protocol-relative or relative URL to absolute.
  String _resolveUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$_baseUrl$url';
    return '$_baseUrl/$url';
  }

  /// Extract the manga slug from a href like "/manhua-{slug}/".
  String? _extractSlug(String href) {
    final match = RegExp(r'/manhua-([^/]+)/?').firstMatch(href);
    return match?.group(1);
  }

  /// Extract the numeric chapter id from a href like "/m{id}/".
  String? _extractChapterId(String href) {
    final match = RegExp(r'/m(\d+)/?').firstMatch(href);
    return match?.group(1);
  }

  // --- Discovery (uses the category/list page) ---

  @override
  List<FilterOption> get discoveryFilters => const [
        // dm5 sort segments embedded in the /manhua-list[-sN]/ path.
        // Empty value = default (综合/人气) page.
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: '',
          choices: [
            FilterChoice(label: '人气', value: ''),
            FilterChoice(label: '订阅榜', value: 's2'),
            FilterChoice(label: '更新', value: 's1'),
            FilterChoice(label: '新书', value: 's19'),
          ],
        ),
      ];

  @override
  List<FilterOption> get searchFilters => const [];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final sort = filters['sort'] ?? '';
    // dm5 category/list page uses path segments, not query params:
    //   page 1: /manhua-list/            or /manhua-list-{sort}/
    //   page N: /manhua-list-p{N}/       or /manhua-list-{sort}-p{N}/
    final sortSeg = sort.isNotEmpty ? '-$sort' : '';
    final pageSeg = page > 1 ? '-p$page' : '';
    return FetchConfig(
      url: '$_baseUrl/manhua-list$sortSeg$pageSeg/',
      headers: {'User-Agent': _ua, 'Referer': '$_baseUrl/'},
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseMangaList(response as String);
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search',
      headers: {'User-Agent': _ua, 'Referer': '$_baseUrl/'},
      queryParameters: {
        'title': keyword,
        'language': '1',
        'page': '$page',
      },
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseMangaList(response as String);
  }

  /// Shared parser for search/discovery result lists.
  ///
  /// Handles two distinct page layouts:
  ///  - Search page (`/search`): `.book-list` containers with
  ///    `.book-list-info-title` / `img.book-list-cover-img`.
  ///  - Category page (`/manhua-list*`): `ul.manga-list-2 > li` with
  ///    `.manga-list-2-title` / `img.manga-list-2-cover-img` /
  ///    `.manga-list-2-tip` (latest chapter).
  List<MangaSummary> _parseMangaList(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];
    final seen = <String>{};

    // Prefer the category-page layout when present.
    final mangaListItems = document.querySelectorAll('ul.manga-list-2 > li');
    if (mangaListItems.isNotEmpty) {
      for (final li in mangaListItems) {
        final link = li.querySelector('a[href*="/manhua-"]');
        if (link == null) continue;
        final href = link.attributes['href'] ?? '';
        final slug = _extractSlug(href);
        if (slug == null || seen.contains(slug)) continue;

        final titleEl = li.querySelector('.manga-list-2-title');
        var title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) title = link.attributes['title']?.trim() ?? '';
        if (title.isEmpty) continue;

        final imgEl = li.querySelector('img.manga-list-2-cover-img') ??
            li.querySelector('img');
        final cover = imgEl?.attributes['data-src'] ??
            imgEl?.attributes['src'] ??
            '';

        final tipEl = li.querySelector('.manga-list-2-tip');
        final latest = tipEl?.text.trim();

        seen.add(slug);
        results.add(MangaSummary(
          id: slug,
          sourceId: sourceId,
          title: title,
          coverUrl: _resolveUrl(cover),
          latestChapter: (latest != null && latest.isNotEmpty) ? latest : null,
          headers: const {'Referer': '$_baseUrl/'},
        ));
      }
      return results;
    }

    // Search-page layout: `.book-list` containers (fall back to `li`).
    final containers = document.querySelectorAll('.book-list');
    final blocks =
        containers.isNotEmpty ? containers : document.querySelectorAll('li');

    for (final block in blocks) {
      final link = block.querySelector('a[href*="/manhua-"]');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      final slug = _extractSlug(href);
      if (slug == null || seen.contains(slug)) continue;

      final titleEl = block.querySelector('.book-list-info-title') ??
          block.querySelector('p.book-list-info-title');
      var title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) {
        title = link.attributes['title']?.trim() ?? '';
      }
      if (title.isEmpty) continue;

      final imgEl = block.querySelector('img.book-list-cover-img') ??
          block.querySelector('img');
      final cover = imgEl?.attributes['data-src'] ??
          imgEl?.attributes['src'] ??
          '';

      final statusEl = block.querySelector('.book-list-info-bottom-right-font');
      final latest = statusEl?.text.trim();

      seen.add(slug);
      results.add(MangaSummary(
        id: slug,
        sourceId: sourceId,
        title: title,
        coverUrl: _resolveUrl(cover),
        latestChapter: (latest != null && latest.isNotEmpty) ? latest : null,
        headers: const {'Referer': '$_baseUrl/'},
      ));
    }

    return results;
  }

  // --- Manga info (detail page, chapters embedded) ---

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/manhua-$mangaId/',
      headers: {'User-Agent': _ua, 'Referer': '$_baseUrl/'},
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final titleEl = document.querySelector('.detail-main-info-title');
    final title = titleEl?.text.trim() ?? '';

    final coverEl = document.querySelector('.detail-main-cover img');
    final cover = coverEl?.attributes['data-src'] ??
        coverEl?.attributes['src'] ??
        '';

    // Author: text like "作者：尾田荣一郎"
    final authorEl = document.querySelector('.detail-main-info-author');
    var author = authorEl?.text.trim() ?? '';
    author = author.replaceFirst(RegExp(r'^作者[:：]\s*'), '').trim();

    // Tags from the class/genre links.
    final tags = <String>[];
    for (final a in document.querySelectorAll('.detail-main-info-class a')) {
      final t = a.text.trim();
      if (t.isNotEmpty) tags.add(t);
    }

    // Description (hidden full copy first, then visible).
    final descEl = document.querySelector('#detail-desc') ??
        document.querySelector('.detail-desc');
    final description = descEl?.text.trim();

    // Status from page text.
    var status = MangaStatus.unknown;
    final bodyText = document.body?.text ?? '';
    if (bodyText.contains('已完结') || bodyText.contains('完结')) {
      status = MangaStatus.completed;
    } else if (bodyText.contains('连载中') || bodyText.contains('连载')) {
      status = MangaStatus.ongoing;
    }

    // Chapters: a.chapteritem with href "/m{id}/". A manga may have several
    // `ul.detail-list-1` sections (正篇 + 番外 etc). We dedupe by chapter id.
    final chapters = <ChapterItem>[];
    final seen = <String>{};
    for (final a in document.querySelectorAll('a.chapteritem')) {
      final href = a.attributes['href'] ?? '';
      final chId = _extractChapterId(href);
      if (chId == null || seen.contains(chId)) continue;

      // Prefer the visible text (e.g. "第1186话"), which is the chapter
      // number users expect. The title attribute is usually a subtitle
      // (e.g. "再一次"). Text may carry a trailing page count like "（17P）".
      var chTitle = a.text.trim();
      if (chTitle.isEmpty) {
        chTitle = a.attributes['title']?.trim() ?? '';
      }
      chTitle = chTitle.replaceAll(RegExp(r'\s*[（(]\s*\d+\s*P\s*[）)]\s*$'), '').trim();
      if (chTitle.isEmpty) continue;

      seen.add(chId);
      chapters.add(ChapterItem(
        id: chId,
        mangaId: mangaId,
        title: chTitle,
        href: '$_baseUrl/m$chId/',
      ));
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: _resolveUrl(cover),
      description: description,
      author: author,
      tags: tags,
      status: status,
      chapters: chapters,
      headers: const {'Referer': '$_baseUrl/'},
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are embedded in the detail page.
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter (reader page) ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return FetchConfig(
      url: '$_baseUrl/m$chapterId/',
      headers: {'User-Agent': _ua, 'Referer': '$_baseUrl/'},
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;

    final emptyResult = ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: const [],
      ),
    );

    // The image list is delivered inside a Dean Edwards packed eval block.
    final packed = JsUnpacker.findPackedScript(htmlStr);
    if (packed == null) return emptyResult;

    final unpacked = JsUnpacker.unpack(packed);
    if (unpacked == null) return emptyResult;

    // Unpacked content contains: var newImgs=['url1','url2',...]
    // Some chapters escape the quotes as \' so a naive split(',') + quote
    // strip leaves stray backslashes/quotes. Match each quoted string
    // literal (URLs starting with http(s):// or //) directly instead.
    final imgsMatch =
        RegExp(r'var\s+newImgs\s*=\s*\[([^\]]*)\]').firstMatch(unpacked);
    if (imgsMatch == null) return emptyResult;

    final raw = imgsMatch.group(1) ?? '';
    final urls = <String>[];
    // Capture the URL inside optional (escaped) single/double quotes.
    final urlPattern = RegExp(r'''\\?['"]((?:https?:)?//[^'"\\]+)''');
    for (final m in urlPattern.allMatches(raw)) {
      final u = m.group(1)?.trim() ?? '';
      if (u.isEmpty) continue;
      urls.add(_resolveUrl(u));
    }

    if (urls.isEmpty) return emptyResult;

    // dm5 intentionally shuffles newImgs order. The real page number is the
    // leading number of the filename in the URL path (".../{cid}/{n}_{rand}.jpg").
    int pageNum(String url) {
      final m = RegExp(r'/(\d+)_\d+\.\w+(?:\?|$)').firstMatch(url);
      if (m != null) return int.tryParse(m.group(1)!) ?? 1 << 30;
      return 1 << 30;
    }

    urls.sort((a, b) => pageNum(a).compareTo(pageNum(b)));

    final imageHeaders = {'Referer': '$_baseUrl/'};
    final images = urls
        .map((u) => ChapterImage(url: u, headers: imageHeaders))
        .toList();

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: images,
      ),
    );
  }
}
