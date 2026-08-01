import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// hmjd9.com (韓漫基地) source plugin.
///
/// A maccms-based adult Korean-manhua site (Traditional Chinese). No
/// Cloudflare, no JS encryption. All chapter images are embedded directly in
/// the reader page HTML via `data-original` lazy-load attributes. Chapters are
/// embedded in the manga info page, so [prepareChapterListFetch] returns null.
///
/// Images/covers are served from a `*pic.xyz` CDN (subdomain observed to
/// rotate over time, e.g. jmpic.xyz -> nnpic.xyz) which may hotlink-protect,
/// so a Referer header is attached to both cover summaries and chapter images.
class Hmjd9 extends MangaSource {
  static const String sourceId = 'hmjd9';
  static const String _baseUrl = 'https://hmjd9.com';

  @override
  String get id => sourceId;

  @override
  bool get isAdult => true;

  @override
  String get name => '韓漫基地';

  @override
  String get shortName => 'HM';

  @override
  String? get description => '成人韓漫（繁體中文）';

  @override
  double get score => 3.5;

  @override
  String? get href => _baseUrl;

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'category',
          label: '分類',
          defaultValue: 'all',
          choices: [
            FilterChoice(label: '全部', value: 'all'),
            FilterChoice(label: '正妹', value: '正妹'),
            FilterChoice(label: '恋爱', value: '恋爱'),
            FilterChoice(label: '出版漫画', value: '出版漫画'),
            FilterChoice(label: '肉慾', value: '肉慾'),
            FilterChoice(label: '浪漫', value: '浪漫'),
            FilterChoice(label: '大尺度', value: '大尺度'),
            FilterChoice(label: '巨乳', value: '巨乳'),
            FilterChoice(label: '有夫之婦', value: '有夫之婦'),
            FilterChoice(label: '女大生', value: '女大生'),
            FilterChoice(label: '狗血劇', value: '狗血劇'),
            FilterChoice(label: '同居', value: '同居'),
            FilterChoice(label: '好友', value: '好友'),
            FilterChoice(label: '調教', value: '調教'),
            FilterChoice(label: '动作', value: '动作'),
            FilterChoice(label: '後宮', value: '後宮'),
            FilterChoice(label: '不倫', value: '不倫'),
            FilterChoice(label: '3D', value: '3D'),
            FilterChoice(label: '校園', value: '校園'),
            FilterChoice(label: '耽美', value: '耽美'),
            FilterChoice(label: '日漫', value: '日漫'),
          ],
        ),
        FilterOption(
          name: 'order',
          label: '排序',
          defaultValue: 'time',
          choices: [
            FilterChoice(label: '按時間', value: 'time'),
            FilterChoice(label: '按熱度', value: 'hits'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '狀態',
          defaultValue: 'all',
          choices: [
            FilterChoice(label: '全部', value: 'all'),
            FilterChoice(label: '已完結', value: 'completed'),
            FilterChoice(label: '連載中', value: 'serialized'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final category = filters['category'] ?? 'all';
    final order = filters['order'] ?? 'time';
    final status = filters['status'] ?? 'all';
    final categorySeg =
        category == 'all' ? 'all' : Uri.encodeComponent(category);
    return FetchConfig(
      url: '$_baseUrl/manhua/$categorySeg/ob/$order/st/$status/page/$page',
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseList(response as String);
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // The site's search form submits to `/catalog.php?key=<keyword>` (GET).
    // The pretty `/search/<keyword>.html` route always renders an empty
    // "共 0 部" page, so it must NOT be used for keyword search.
    return FetchConfig(
      url: '$_baseUrl/catalog.php',
      queryParameters: {'key': keyword},
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseList(response as String);
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/manhua-$mangaId.html');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Title
    final title = document.querySelector('h1.hl-dc-title')?.text.trim() ??
        document.querySelector('h1')?.text.trim() ??
        '';

    // Cover image (lazy-loaded via data-original)
    final coverEl = document.querySelector('.hl-dc-pic img') ??
        document.querySelector('.hl-item-thumb');
    final cover = coverEl?.attributes['data-original'] ??
        coverEl?.attributes['data-src'] ??
        coverEl?.attributes['src'] ??
        '';

    // Metadata lives in `.hl-full-box ul li` rows, each prefixed by an <em>
    // label ('作者：', 'TAG：', '進度：', '简介：'). Dispatch by that label.
    var author = '';
    var description = '';
    var status = MangaStatus.unknown;
    final tags = <String>[];
    for (final li in document.querySelectorAll('.hl-full-box ul li')) {
      final label = li.querySelector('em')?.text.trim() ?? '';
      final anchors = li.querySelectorAll('a');
      // Text content of the row with the <em> label stripped off.
      final emText = li.querySelector('em')?.text ?? '';
      final bodyText = li.text.replaceFirst(emText, '').trim();

      if (label.contains('作者')) {
        author = anchors.isNotEmpty
            ? anchors.map((a) => a.text.trim()).where((t) => t.isNotEmpty).join(' & ')
            : bodyText;
      } else if (label.contains('TAG') || label.contains('标签') || label.contains('標籤')) {
        for (final a in anchors) {
          final t = a.text.trim();
          if (t.isNotEmpty) tags.add(t);
        }
      } else if (label.contains('進度') || label.contains('进度')) {
        if (bodyText.contains('完結') ||
            bodyText.contains('完结') ||
            bodyText.contains('完成')) {
          status = MangaStatus.completed;
        } else if (bodyText.contains('连载') || bodyText.contains('連載')) {
          status = MangaStatus.ongoing;
        }
      } else if (label.contains('简介') || label.contains('簡介')) {
        description = bodyText;
      }
    }

    // Chapters — embedded in the info page, listed newest-first.
    final chapters = <ChapterItem>[];
    final chapterAnchors =
        document.querySelectorAll('#hl-plays-list li a');
    for (final a in chapterAnchors) {
      final href = a.attributes['href'] ?? '';
      final hash = _extractChapterHash(href);
      if (hash == null) continue;
      final chTitle = (a.attributes['title'] ?? a.text).trim();
      chapters.add(ChapterItem(
        id: hash,
        mangaId: mangaId,
        title: chTitle,
        href: _ensureAbsoluteUrl(href),
      ));
    }
    // Site lists chapters newest-first; the first anchor is the latest chapter.
    final latestChapter = chapters.isNotEmpty ? chapters.first.title : null;
    // Reverse to ascending order for display.
    final orderedChapters = chapters.reversed.toList();

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: _ensureAbsoluteUrl(cover),
      description: description.isEmpty ? null : description,
      author: author,
      tags: tags,
      status: status,
      latestChapter: latestChapter,
      chapters: orderedChapters,
      headers: const {'Referer': _baseUrl},
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are embedded in the manga info page.
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
      url: '$_baseUrl/manhua-$mangaId/$chapterId.html',
      headers: {'Referer': '$_baseUrl/manhua-$mangaId.html'},
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final images = <ChapterImage>[];
    // Reader images are lazy-loaded. The lazy-load attribute has rotated over
    // time (`data-original` -> `data-src` observed), and the image CDN
    // subdomain also rotates (jmpic.xyz -> nnpic.xyz observed), so scan every
    // <img> and pick the first lazy-load/real URL that points at a *pic.xyz
    // host rather than keying off a single attribute or hardcoded domain.
    for (final img in document.querySelectorAll('img')) {
      final url = img.attributes['data-original'] ??
          img.attributes['data-src'] ??
          img.attributes['src'] ??
          '';
      if (url.isEmpty) continue;
      // Only keep CDN image URLs, skip icons/placeholders.
      if (!_isCdnImageUrl(url)) continue;
      images.add(ChapterImage(
        url: _ensureAbsoluteUrl(url),
        headers: const {'Referer': _baseUrl},
      ));
    }

    // The chapter reading page has no `h1.hl-dc-title` (that's the info-page
    // selector). The chapter title lives in the document <title>, formatted as
    // `第01話 - 《漫畫名》無遮擋版免費在線閱讀 - 韓漫基地`; take the part before
    // the first ` - ` separator. Fall back to a generic label if unavailable.
    final pageTitle = document.querySelector('title')?.text.trim() ?? '';
    var title = pageTitle.split(' - ').first.trim();
    if (title.isEmpty) title = '第$page话';

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
      ),
      canLoadMore: false,
    );
  }

  // --- Private Helpers ---

  List<MangaSummary> _parseList(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final items = document.querySelectorAll('.hl-list-item');
    final results = <MangaSummary>[];

    for (final item in items) {
      final thumb = item.querySelector('a.hl-item-thumb') ??
          item.querySelector('a');
      if (thumb == null) continue;

      final href = thumb.attributes['href'] ?? '';
      final mangaId = _extractMangaId(href);
      if (mangaId == null) continue;

      // Title: prefer the text-title anchor, fall back to thumb title attr.
      final title = item
              .querySelector('.hl-item-title a')
              ?.text
              .trim() ??
          thumb.attributes['title'] ??
          '';

      final cover = thumb.attributes['data-original'] ??
          thumb.attributes['data-src'] ??
          thumb.attributes['src'] ??
          '';
      final coverUrl = cover.startsWith('data:') ? '' : cover;

      // `.hl-item-sub` is order-dependent on the list URL: the "hits" ordering
      // yields a view count ('阅读：5,404,000') and the "time" ordering yields an
      // update date ('2026-08-01'). It is NOT a chapter name. Route it to the
      // matching field so the discovery grid shows popularity, not a bogus
      // "latest chapter".
      final sub = item.querySelector('.hl-item-sub')?.text.trim() ?? '';
      String? popularityText;
      String? updateTime;
      String? latestChapter;
      if (sub.isNotEmpty) {
        if (sub.contains('阅读') || sub.contains('閱讀')) {
          popularityText = sub;
        } else if (RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(sub)) {
          updateTime = sub;
          // The discovery grid only renders chapterCount/popularityText, so
          // surface the update date there too (prefixed for clarity) — the
          // default discovery ordering is "time", making this the common case.
          popularityText = '更新 $sub';
        } else {
          latestChapter = sub;
        }
      }

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: _ensureAbsoluteUrl(coverUrl),
        latestChapter: latestChapter,
        updateTime: updateTime,
        popularityText: popularityText,
        headers: const {'Referer': _baseUrl},
      ));
    }

    return results;
  }

  /// Extract numeric manga id from `/manhua-{id}.html`.
  String? _extractMangaId(String href) {
    final match = RegExp(r'/manhua-(\d+)\.html').firstMatch(href);
    return match?.group(1);
  }

  /// Extract chapter hash from `/manhua-{id}/{hash}.html`.
  String? _extractChapterHash(String href) {
    final match =
        RegExp(r'/manhua-\d+/([A-Za-z0-9]+)\.html').firstMatch(href);
    return match?.group(1);
  }

  /// Whether [url] points at the site's image CDN. The CDN base domain has
  /// rotated over time (`jmpic.xyz`, `nnpic.xyz`, ... all observed), but they
  /// all share the `pic.xyz` apex, so match that suffix rather than a single
  /// hardcoded host. Note there is NO dot between the site prefix (`jm`/`nn`)
  /// and `pic.xyz` — it's one apex domain, e.g. `p8.jmpic.xyz`.
  bool _isCdnImageUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.endsWith('pic.xyz');
  }

  String _ensureAbsoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$_baseUrl$url';
  }
}
