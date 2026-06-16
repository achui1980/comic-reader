import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class JmComic extends MangaSource {
  static const String sourceId = 'jmc';
  static const String _baseUrl = 'https://18comic.vip';

  static const String _mobileUA =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const Map<String, String> _imageHeaders = {
    'Referer': '$_baseUrl/',
  };

  @override
  String get id => sourceId;

  @override
  String get name => '禁漫天堂';

  @override
  String get shortName => 'JMC';

  @override
  String? get description => '需要代理，屏蔽日本ip';

  @override
  double get score => 5.0;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsCloudflare => true;

  @override
  List<String> get cloudflarePageTitles => const ['Just a moment...', '403 Forbidden'];

  @override
  String? get userAgent => _mobileUA;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _mobileUA,
        'Referer': _baseUrl,
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'type',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '选择分类', value: ''),
            FilterChoice(label: '其他类', value: 'another'),
            FilterChoice(label: '同人', value: 'doujin'),
            FilterChoice(label: '韩漫', value: 'hanman'),
            FilterChoice(label: '美漫', value: 'meiman'),
            FilterChoice(label: '短篇', value: 'short'),
            FilterChoice(label: '单本', value: 'single'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'mr',
          choices: [
            FilterChoice(label: '选择排序', value: 'mr'),
            FilterChoice(label: '最新', value: 'mr'),
            FilterChoice(label: '最多订阅', value: 'mv'),
            FilterChoice(label: '最多图片', value: 'mp'),
            FilterChoice(label: '最高评分', value: 'tr'),
            FilterChoice(label: '最多评论', value: 'md'),
            FilterChoice(label: '最多爱心', value: 'tf'),
          ],
        ),
      ];

  @override
  List<FilterOption> get searchFilters => const [
        FilterOption(
          name: 'time',
          label: '时间',
          defaultValue: 'a',
          choices: [
            FilterChoice(label: '选择时间', value: 'a'),
            FilterChoice(label: '一天内', value: 't'),
            FilterChoice(label: '一周内', value: 'w'),
            FilterChoice(label: '一个月内', value: 'm'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'mr',
          choices: [
            FilterChoice(label: '选择排序', value: 'mr'),
            FilterChoice(label: '最新的', value: 'mr'),
            FilterChoice(label: '最多点阅', value: 'mv'),
            FilterChoice(label: '最多图片', value: 'mp'),
            FilterChoice(label: '最多爱心', value: 'tf'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final type = filters['type'] ?? '';
    final sort = filters['sort'] ?? 'mr';

    final path = type.isNotEmpty ? '/albums/$type' : '/albums';
    return FetchConfig(
      url: '$_baseUrl$path',
      headers: {'User-Agent': _mobileUA},
      queryParameters: {
        'o': sort,
        'page': '$page',
      },
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final items = document.querySelectorAll('div.row div.list-col');
    final results = <MangaSummary>[];

    for (final item in items) {
      // Must have thumb-overlay-albums for discovery
      final overlay = item.querySelector('div.thumb-overlay-albums');
      if (overlay == null) continue;

      final linkEl = item.querySelector('a');
      if (linkEl == null) continue;

      final href = linkEl.attributes['href'] ?? '';
      final mangaId = _extractAlbumId(href);
      if (mangaId == null) continue;

      final imgEl = item.querySelector('img');
      final title = imgEl?.attributes['title'] ?? '';
      final cover = imgEl?.attributes['data-original'] ??
          imgEl?.attributes['src'] ??
          imgEl?.attributes['data-cfsrc'] ??
          '';
      final fullCover = _ensureAbsoluteUrl(cover);

      // Author
      final authorEl = item.querySelector(
          'div.title-truncate:not(.video-title):not(.tags) a');
      final author = authorEl?.text.trim() ?? '';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: fullCover,
        author: author,
        headers: _imageHeaders,
      ));
    }

    return results;
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final time = filters['time'] ?? 'a';
    final sort = filters['sort'] ?? 'mr';

    return FetchConfig(
      url: '$_baseUrl/search/photos',
      headers: {'User-Agent': _mobileUA},
      queryParameters: {
        'main_tag': '0',
        'search_query': keyword,
        't': time,
        'o': sort,
        'page': '$page',
      },
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Search uses div.thumb-overlay (without -albums)
    final items = document.querySelectorAll('div.row div.list-col');
    final results = <MangaSummary>[];

    for (final item in items) {
      final overlay = item.querySelector('div.thumb-overlay') ??
          item.querySelector('div.thumb-overlay-albums');
      if (overlay == null) continue;

      final linkEl = item.querySelector('a');
      if (linkEl == null) continue;

      final href = linkEl.attributes['href'] ?? '';
      final mangaId = _extractAlbumId(href);
      if (mangaId == null) continue;

      final imgEl = item.querySelector('img');
      final title = imgEl?.attributes['title'] ?? '';
      final cover = imgEl?.attributes['data-original'] ??
          imgEl?.attributes['src'] ??
          imgEl?.attributes['data-cfsrc'] ??
          '';
      final fullCover = _ensureAbsoluteUrl(cover);

      final authorEl = item.querySelector(
          'div.title-truncate:not(.video-title):not(.tags) a');
      final author = authorEl?.text.trim() ?? '';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: fullCover,
        author: author,
        headers: _imageHeaders,
      ));
    }

    return results;
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/album/$mangaId',
      headers: {'User-Agent': _mobileUA},
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Cover
    final coverEl =
        document.querySelector('div#album_photo_cover div.thumb-overlay img');
    final cover = coverEl?.attributes['data-original'] ??
        coverEl?.attributes['src'] ??
        '';
    final fullCover = _ensureAbsoluteUrl(cover);

    // Title
    final title = coverEl?.attributes['title'] ?? '';

    // Update time from span[itemprop=datePublished]
    final dateEls = document.querySelectorAll('span[itemprop=datePublished]');
    String? updateTime;
    if (dateEls.isNotEmpty) {
      updateTime = dateEls.last.attributes['content'] ??
          dateEls.last.text.trim();
    }

    // Tags
    final tags = <String>[];
    final tagEls = document.querySelectorAll(
        'div#intro-block div.tag-block span[data-type=tags] a');
    for (final el in tagEls) {
      final tag = el.text.trim();
      if (tag.isNotEmpty) tags.add(tag);
    }

    // Author
    final authorEls = document.querySelectorAll(
        'div#intro-block div.tag-block span[data-type=author] a');
    final authors = <String>[];
    for (final el in authorEls) {
      final a = el.text.trim();
      if (a.isNotEmpty) authors.add(a);
    }

    // Chapters - look for base64-encoded chapter HTML in script
    var chapters = <ChapterItem>[];
    final scripts = document.querySelectorAll('script');
    for (final script in scripts) {
      final content = script.text;
      final b64Match =
          RegExp(r'base64DecodeUtf8\("([^"]+)"\)').firstMatch(content);
      if (b64Match != null) {
        final b64 = b64Match.group(1)!;
        try {
          final decoded = utf8.decode(base64.decode(b64));
          final chapterDoc = html_parser.parseFragment(decoded);
          final chapterLinks =
              chapterDoc.querySelectorAll('.episode ul.btn-toolbar a');
          for (final link in chapterLinks) {
            final chHref = link.attributes['href'] ?? '';
            final chId = _extractPhotoId(chHref);
            if (chId == null) continue;
            final chTitle = link.text.trim();
            chapters.add(ChapterItem(
              id: chId,
              mangaId: mangaId,
              title: chTitle,
              href: '$_baseUrl$chHref',
            ));
          }
        } catch (_) {
          // Base64 decode failed, skip
        }
        break;
      }
    }

    // If no chapters found from script, try the read button as single chapter
    if (chapters.isEmpty) {
      final readBtn = document.querySelector('a.reading') ??
          document.querySelector('a[href*="/photo/"]');
      if (readBtn != null) {
        final readHref = readBtn.attributes['href'] ?? '';
        final readId = _extractPhotoId(readHref);
        if (readId != null) {
          chapters.add(ChapterItem(
            id: readId,
            mangaId: mangaId,
            title: '开始阅读',
            href: '$_baseUrl$readHref',
          ));
        }
      }
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: fullCover,
      author: authors.join(', '),
      tags: tags,
      status: MangaStatus.unknown,
      updateTime: updateTime,
      headers: _imageHeaders,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are parsed from manga info page
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
      url: '$_baseUrl/photo/$chapterId',
      headers: {
        'User-Agent': _mobileUA,
        'Referer': '$_baseUrl/album/$mangaId',
      },
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Extract scramble info from script
    String? scrambleId;
    String? seriesId;
    String? aid;

    final scripts = document.querySelectorAll('script');
    for (final script in scripts) {
      final content = script.text;
      if (content.contains('var series_id') || content.contains('var aid')) {
        final seriesMatch =
            RegExp(r'var\s+series_id\s*=\s*(\d+)').firstMatch(content);
        final aidMatch =
            RegExp(r'var\s+aid\s*=\s*(\d+)').firstMatch(content);
        final scrambleMatch =
            RegExp(r'var\s+scramble_id\s*=\s*(\d+)').firstMatch(content);

        seriesId = seriesMatch?.group(1);
        aid = aidMatch?.group(1);
        scrambleId = scrambleMatch?.group(1);
        break;
      }
    }

    // Use seriesId as mangaId if available
    final effectiveMangaId = seriesId ?? mangaId;
    final effectiveChapterId = aid ?? chapterId;

    // Extract images
    final imageEls = document.querySelectorAll(
        'div.panel-body div.thumb-overlay-albums div.scramble-page img.lazy_img');
    // Fallback selector if above doesn't match
    final imgElements = imageEls.isNotEmpty
        ? imageEls
        : document.querySelectorAll('div.scramble-page img[id^=album_photo]');

    final images = <ChapterImage>[];
    for (final img in imgElements) {
      final src = img.attributes['data-original'] ??
          img.attributes['src'] ??
          '';
      if (src.isEmpty) continue;

      final fullUrl = _ensureAbsoluteUrl(src.trim());

      // Determine if image needs unscrambling
      var scrambleType = ScrambleType.none;
      if (!fullUrl.endsWith('.gif') && scrambleId != null) {
        final chIdNum = int.tryParse(effectiveChapterId);
        final scrIdNum = int.tryParse(scrambleId);
        if (chIdNum != null && scrIdNum != null && chIdNum >= scrIdNum) {
          scrambleType = ScrambleType.jmc;
        }
      }

      images.add(ChapterImage(
        url: fullUrl,
        scrambleType: scrambleType,
        headers: _imageHeaders,
      ));
    }

    // Title
    final titleEl = document.querySelector('div.container div.panel-heading') ??
        document.querySelector('title');
    final chapterTitle = titleEl?.text.trim() ?? '';

    return ChapterResult(
      chapter: Chapter(
        id: effectiveChapterId,
        mangaId: effectiveMangaId,
        title: chapterTitle,
        images: images,
        headers: _imageHeaders,
      ),
    );
  }

  // --- Private helpers ---

  /// Extract album ID from href like "/album/12345/" or "/album/12345"
  String? _extractAlbumId(String href) {
    final match = RegExp(r'/album/(\d+)').firstMatch(href);
    return match?.group(1);
  }

  /// Extract photo ID from href like "/photo/12345/" or "/photo/12345"
  String? _extractPhotoId(String href) {
    final match = RegExp(r'/photo/(\d+)').firstMatch(href);
    return match?.group(1);
  }

  /// Ensure a URL is absolute
  String _ensureAbsoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$_baseUrl$url';
  }
}
