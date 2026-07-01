import 'package:html/parser.dart' as html_parser;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Wnacg (绅士漫画) source plugin.
/// HTML-based, no auth required. Single-chapter per gallery.
class Wnacg extends MangaSource {
  static const String sourceId = 'wnacg';
  static const String _baseUrl = 'https://www.wnacg.com';

  @override
  String get id => sourceId;

  @override
  bool get isAdult => true;

  @override
  String get name => '绅士漫画';

  @override
  String get shortName => 'WN';

  @override
  String? get description => '绅士漫画/紳士漫畫';

  @override
  double get score => 3.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => true;

  @override
  bool get needsCloudflare => true;

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'category',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '同人誌-漫畫', value: '1'),
            FilterChoice(label: '同人誌-CG画集', value: '2'),
            FilterChoice(label: '同人誌-Cosplay', value: '3'),
            FilterChoice(label: '單行本', value: '5'),
            FilterChoice(label: '雜誌', value: '6'),
            FilterChoice(label: '韓漫', value: '7'),
            FilterChoice(label: '美漫', value: '8'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final category = filters['category'] ?? '';
    String url;
    if (category.isNotEmpty) {
      url = '$_baseUrl/albums-index-cate-$category-page-$page.html';
    } else {
      url = '$_baseUrl/albums-index-page-$page.html';
    }
    return FetchConfig(url: url);
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseGalleryList(response as String);
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search/',
      queryParameters: {
        'q': keyword,
        'p': '$page',
      },
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseGalleryList(response as String);
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/photos-index-aid-$mangaId.html');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    // Title
    final title = document.querySelector('.userwrap h2')?.text.trim() ?? '';

    // Cover
    final coverEl = document.querySelector('#bodywrap .uwconn img') ??
        document.querySelector('.pic_box img');
    final cover = coverEl?.attributes['src'] ?? '';

    // Tags
    final tags = <String>[];
    final tagEls = document.querySelectorAll('.uwconn .tagshow a');
    for (final el in tagEls) {
      final tag = el.text.trim();
      if (tag.isNotEmpty) tags.add(tag);
    }

    // Upload date
    String? updateTime;
    final infoEls = document.querySelectorAll('.uwconn .asTBcell p');
    for (final el in infoEls) {
      final text = el.text;
      if (text.contains('上傳時間') || text.contains('上传时间')) {
        // Extract date from text like "上傳時間：2024-01-15"
        final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(text);
        if (dateMatch != null) {
          updateTime = dateMatch.group(1);
        }
        break;
      }
    }

    // Single chapter
    final chapters = [
      ChapterItem(
        id: '1',
        mangaId: mangaId,
        title: '全部图片',
      ),
    ];

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: _ensureAbsoluteUrl(cover),
      tags: tags,
      status: MangaStatus.completed,
      updateTime: updateTime,
      chapters: chapters,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Single chapter per gallery
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // Gallery view showing all images
    return FetchConfig(url: '$_baseUrl/photos-gallery-aid-$mangaId.html');
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final images = <ChapterImage>[];

    // Try to parse images from gallery view
    final imgEls = document.querySelectorAll('.pic_box img');
    for (final img in imgEls) {
      final src = img.attributes['data-original'] ??
          img.attributes['src'] ??
          '';
      if (src.isEmpty) continue;
      images.add(ChapterImage(url: _ensureAbsoluteUrl(src)));
    }

    // Fallback: try extracting from script (some pages use JS to build list)
    if (images.isEmpty) {
      final scripts = document.querySelectorAll('script');
      for (final script in scripts) {
        final content = script.text;
        // Look for image URL patterns in scripts
        final urlMatches =
            RegExp(r'(//[^\s"]+\.(jpg|png|gif|webp))', caseSensitive: false)
                .allMatches(content);
        for (final m in urlMatches) {
          final url = m.group(1) ?? '';
          if (url.contains('wnacg') || url.contains('img')) {
            images.add(ChapterImage(url: _ensureAbsoluteUrl(url)));
          }
        }
        if (images.isNotEmpty) break;
      }
    }

    // Another fallback: check all images on the page
    if (images.isEmpty) {
      final allImgs = document.querySelectorAll('img');
      for (final img in allImgs) {
        final src = img.attributes['data-original'] ??
            img.attributes['src'] ??
            '';
        if (src.isEmpty) continue;
        if (src.contains('/data/') || src.contains('img.wnacg')) {
          images.add(ChapterImage(url: _ensureAbsoluteUrl(src)));
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
    );
  }

  // --- Private Helpers ---

  List<MangaSummary> _parseGalleryList(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final items = document.querySelectorAll('.gallary_item');
    final results = <MangaSummary>[];

    for (final item in items) {
      // Link with manga ID
      final linkEl = item.querySelector('.pic_box a');
      final href = linkEl?.attributes['href'] ?? '';
      final mangaId = _extractMangaId(href);
      if (mangaId == null) continue;

      // Cover image
      final imgEl = item.querySelector('.pic_box img');
      final cover = imgEl?.attributes['data-original'] ??
          imgEl?.attributes['src'] ??
          '';

      // Title
      final titleEl = item.querySelector('.info .title a') ??
          item.querySelector('.title a');
      final title = titleEl?.text.trim() ?? '';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: _ensureAbsoluteUrl(cover),
      ));
    }

    return results;
  }

  String? _extractMangaId(String href) {
    // Format: /photos-index-aid-XXXXX.html
    final match = RegExp(r'aid-(\d+)').firstMatch(href);
    return match?.group(1);
  }

  String _ensureAbsoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$_baseUrl$url';
  }
}
