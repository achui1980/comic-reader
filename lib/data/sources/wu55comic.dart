import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Wu55Comic (污污漫画) source plugin.
/// Uses HTML scraping for all data extraction.
/// Images are encrypted and require the Wu55ComicDecoder for decryption.
class Wu55Comic extends MangaSource {
  static const String sourceId = 'wu55comic';
  static const String _domainDiscoveryUrl =
      'https://bitbucket.org/h365g/55comic/raw/main/README.md';

  String _baseUrl = 'https://www.wu55comic.store';

  @override
  String get id => sourceId;

  @override
  String get name => '污污漫画';

  @override
  String get shortName => 'WU55';

  @override
  String? get description => '韩漫/日漫';

  @override
  double get score => 4.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => false;

  @override
  int get firstPage => 1;

  @override
  Map<String, String>? get defaultHeaders => {
        'Referer': '$_baseUrl/',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8',
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'area',
          label: '地区',
          defaultValue: '-1',
          choices: [
            FilterChoice(label: '全部', value: '-1'),
            FilterChoice(label: '韩漫', value: '2'),
            FilterChoice(label: '日漫', value: '1'),
          ],
        ),
        FilterOption(
          name: 'tag',
          label: '标签',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '巨乳', value: '巨乳'),
            FilterChoice(label: '人妻', value: '人妻'),
            FilterChoice(label: 'NTR', value: 'NTR'),
            FilterChoice(label: '長篇', value: '長篇'),
            FilterChoice(label: '劇情向', value: '劇情向'),
            FilterChoice(label: '御姐・女王', value: '御姐・女王'),
            FilterChoice(label: '教師', value: '教師'),
            FilterChoice(label: '同人', value: '同人'),
            FilterChoice(label: '連褲襪', value: '連褲襪'),
            FilterChoice(label: '不倫', value: '不倫'),
            FilterChoice(label: '姉・妹', value: '姉・妹'),
          ],
        ),
        FilterOption(
          name: 'end',
          label: '状态',
          defaultValue: '-1',
          choices: [
            FilterChoice(label: '全部', value: '-1'),
            FilterChoice(label: '完结', value: '1'),
            FilterChoice(label: '连载', value: '0'),
          ],
        ),
      ];

  // --- Base URL management ---

  /// Get current base URL
  String get baseUrl => _baseUrl;

  /// Set base URL (for domain update)
  set baseUrl(String url) {
    if (url.isNotEmpty) _baseUrl = url;
  }

  // --- Domain Discovery ---

  /// Prepare fetch for domain discovery from bitbucket README
  FetchConfig prepareDomainDiscoveryFetch() {
    return const FetchConfig(url: _domainDiscoveryUrl);
  }

  /// Parse domain discovery response, extract new domain.
  /// Returns true if domain was changed.
  bool parseDomainDiscovery(dynamic response) {
    final text = response as String;
    // Look for URL pattern in README content
    final urlPattern = RegExp(r'https?://[^\s<>"]+wu55[^\s<>"]*');
    final match = urlPattern.firstMatch(text);
    if (match != null) {
      final newUrl = match.group(0)!.trimRight();
      // Remove trailing punctuation
      final cleaned = newUrl.replaceAll(RegExp(r'[.,;:!?\)]+$'), '');
      if (cleaned != _baseUrl && cleaned.startsWith('http')) {
        _baseUrl = cleaned;
        return true;
      }
    }
    return false;
  }

  // ====== Discovery ======

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    // The /booklist page renders content via JavaScript (empty grid in SSR).
    // Use /index (homepage) which has SSR-rendered book links for page 1.
    // For page > 1, there's no SSR pagination available.
    if (page > 1) {
      // Return search with empty keyword as a fallback for "more" content
      // Actually, just use /index for all - it only has one page of content
      return FetchConfig(
        url: '$_baseUrl/index',
        headers: defaultHeaders,
      );
    }

    return FetchConfig(
      url: '$_baseUrl/index',
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);
    return _parseBookList(document);
  }

  // ====== Search ======

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search',
      queryParameters: {'keyword': keyword},
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);
    return _parseBookList(document);
  }

  // ====== Manga Info ======

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/book/$mangaId');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Title
    final title =
        document.querySelector('h1.sp-book-title')?.text.trim() ?? '';

    // Author (format "作者：xxx")
    final authorRaw =
        document.querySelector('p.sp-book-author')?.text.trim() ?? '';
    final author = authorRaw.replaceFirst(RegExp(r'^作者[：:]'), '').trim();

    // Tags
    final tagEls = document.querySelectorAll('a.sp-book-tag');
    final tags = tagEls.map((e) => e.text.trim()).where((t) => t.isNotEmpty).toList();

    // Summary/description
    final description =
        document.querySelector('p.sp-book-summary')?.text.trim();

    // Status
    MangaStatus status = MangaStatus.unknown;
    final metaItems = document.querySelectorAll('.sp-book-meta-item');
    for (final item in metaItems) {
      final text = item.text.trim();
      if (text.contains('完結')) {
        status = MangaStatus.completed;
        break;
      } else if (text.contains('連載')) {
        status = MangaStatus.ongoing;
        break;
      }
    }

    // Cover - first element with data-src attribute
    // Cover image - encrypted CDN URL, will be decrypted lazily in the UI
    String coverUrl = '';
    final dataSrcEls = document.querySelectorAll('[data-src]');
    for (final el in dataSrcEls) {
      final src = el.attributes['data-src'] ?? '';
      if (src.isNotEmpty && src.contains('/static/upload/book/')) {
        coverUrl = src;
        break;
      }
    }

    // Chapters - a.sp-chapter-item with href /free-chapter/{id}?t=...
    final chapterEls = document.querySelectorAll('a.sp-chapter-item');
    final chapters = <ChapterItem>[];
    final chapterIdPattern = RegExp(r'/free-chapter/(\d+)');

    for (final el in chapterEls) {
      final href = el.attributes['href'] ?? '';
      final idMatch = chapterIdPattern.firstMatch(href);
      if (idMatch == null) continue;

      final chId = idMatch.group(1)!;
      final chTitle = el.attributes['title']?.trim() ?? el.text.trim();

      chapters.add(ChapterItem(
        id: chId,
        mangaId: mangaId,
        title: chTitle,
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
      headers: defaultHeaders,
      chapters: chapters,
    );
  }

  // ====== Chapter List (not used - chapters embedded in manga info) ======

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // ====== Chapter Content ======

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // Build date parameter in YYYYMMDD format
    final now = DateTime.now();
    final dateParam =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    return FetchConfig(
      url: '$_baseUrl/free-chapter/$chapterId?t=$dateParam',
      headers: defaultHeaders,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Extract images from div.cropped[data-src]
    final imageEls = document.querySelectorAll('div.cropped[data-src]');
    final images = <ChapterImage>[];
    final bookId = int.tryParse(mangaId) ?? 0;

    for (int i = 0; i < imageEls.length; i++) {
      final el = imageEls[i];
      final src = el.attributes['data-src'] ?? '';
      if (src.isEmpty) continue;

      // pageNumber is the image ID (from div id or URL filename)
      // JS uses div.id which equals the filename number (e.g. "299297")
      final divId = el.attributes['id'] ?? '';
      int pageNumber = int.tryParse(divId) ?? 0;
      if (pageNumber == 0) {
        // Fallback: extract from URL filename (e.g. ".../299297.jpg" → 299297)
        final fname = src.split('/').last.split('.').first;
        pageNumber = int.tryParse(fname) ?? (i + 1);
      }

      images.add(ChapterImage(
        url: src,
        scrambleType: ScrambleType.wu55,
        wu55BookId: bookId,
        wu55PageNumber: pageNumber,
        headers: defaultHeaders,
      ));
    }

    // Chapter title from page
    final title = document.querySelector('h1')?.text.trim() ??
        document.querySelector('.chapter-title')?.text.trim() ??
        '';

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: defaultHeaders,
      ),
      canLoadMore: false,
    );
  }

  // --- Private Helpers ---

  /// Shared parser for book list pages (discovery and search)
  List<MangaSummary> _parseBookList(Document document) {
    final results = <MangaSummary>[];
    final bookIdPattern = RegExp(r'/book/(\d+)');

    // Find all links to /book/{id}
    final links = document.querySelectorAll('a[href*="/book/"]');

    // Track seen IDs to avoid duplicates
    final seenIds = <String>{};

    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      final idMatch = bookIdPattern.firstMatch(href);
      if (idMatch == null) continue;

      final mangaId = idMatch.group(1)!;
      if (seenIds.contains(mangaId)) continue;
      seenIds.add(mangaId);

      // Cover image - encrypted CDN URL, will be decrypted lazily in the UI
      String coverUrl = '';
      final imgEl = link.querySelector('[data-src]') ??
          link.querySelector('img');
      if (imgEl != null) {
        final src = imgEl.attributes['data-src'] ??
            imgEl.attributes['src'] ?? '';
        if (src.contains('/static/upload/book/')) {
          coverUrl = src;
        }
      }

      // Title - extract from text content or title attribute
      String title = link.attributes['title']?.trim() ?? '';
      if (title.isEmpty) {
        // Try to find a title element within the link
        final titleEl = link.querySelector('.book-title') ??
            link.querySelector('.title') ??
            link.querySelector('h2') ??
            link.querySelector('h3');
        title = titleEl?.text.trim() ?? link.text.trim();
      }

      // Skip if no meaningful title
      if (title.isEmpty) continue;

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        headers: defaultHeaders,
      ));
    }

    return results;
  }
}
