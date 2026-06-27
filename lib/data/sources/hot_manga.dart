import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/utils/crypto_utils.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// 热辣漫画 (manga2026.com) data source.
///
/// Uses the same backend system as CopyManga with different domains and CDN.
/// Supports dual domains: manga2026.com (international) and manga2026.xyz (mainland).
class HotManga extends MangaSource {
  static const String sourceId = 'hot_manga';

  // Domain options
  static const String _domainInternational = 'www.manga2026.com';
  static const String _domainMainland = 'www.manga2026.xyz';

  String _activeDomain = _domainInternational;

  // APP API config (same signing scheme as CopyManga)
  static const String _appVersion = '3.0.6';
  static const String _appSignatureSecret =
      'M2FmMDg1OTAzMTEwMzJlZmUwNjYwNTUwYTA1NjNhNTM=';
  static const String _appUmString = 'b4c89ca4104ea9a97750314d791520ac';

  String _mangaKey = _defaultKey;
  final Random _random = Random();
  late final String _deviceInfo = _generateDeviceInfo();
  late final String _device = _generateDevice();
  late final String _pseudoId = _generatePseudoId();

  static const _defaultKey = 'op0zzpvv.nmn.00p';

  static final _mangaKeyPattern =
      RegExp(r'class="disposablePass"[^>]+disposable="([^"]+)"');
  static final _chapterContentKeyPattern =
      RegExp(r'class="disData"[^>]+contentKey="([^"]+)"');
  static final _chapterContentKeyScriptPattern =
      RegExp(r"var contentKey = '(.*?)'");
  static final _chapterPassPattern =
      RegExp(r'class="disPass"[^>]+contentKey="([^"]+)"');
  static final _imageUrlPattern = RegExp(r'\.c[0-9]+x\.');

  String get _baseUrl => 'https://$_activeDomain';
  String get _apiUrl => 'https://$_activeDomain/api/v3';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36';

  static const Map<String, String> _apiHeaders = {
    'webp': '1',
    'region': '1',
    'platform': '3',
    'version': '3.0.0',
    'accept': 'application/json',
    'User-Agent': 'COPY/3.0.0',
  };

  Map<String, String> get _imageHeaders => {
        'Accept':
            'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        'Referer': _baseUrl,
      };

  Map<String, String> get _defaultWebHeaders => {
        'User-Agent': _userAgent,
        'Referer': _baseUrl,
        'Cookie': 'age=18; webp=1',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };

  /// Switch to mainland domain
  void useMasilandDomain() {
    _activeDomain = _domainMainland;
  }

  /// Switch to international domain
  void useInternationalDomain() {
    _activeDomain = _domainInternational;
  }

  /// Get current active domain
  String get activeDomain => _activeDomain;

  /// Set active domain directly
  set activeDomain(String domain) {
    if (domain == _domainInternational || domain == _domainMainland) {
      _activeDomain = domain;
    }
  }

  @override
  String get id => sourceId;

  @override
  String get name => '热辣漫画';

  @override
  String get shortName => 'HOT';

  @override
  String? get description => 'manga2026.com';

  @override
  double get score => 4.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get needsProxy => true;

  @override
  bool get needsCloudflare => true;

  @override
  String? get userAgent => _userAgent;

  @override
  Map<String, String>? get defaultHeaders => _defaultWebHeaders;

  @override
  List<FilterOption> get discoveryFilters => [
        const FilterOption(
          name: 'type',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '無修正', value: 'Uncensored'),
            FilterChoice(label: "Teen's Love", value: 'teenslove'),
            FilterChoice(label: '愛情', value: 'aiqing'),
            FilterChoice(label: '歡樂向', value: 'huanlexiang'),
            FilterChoice(label: '冒险', value: 'maoxian'),
            FilterChoice(label: '奇幻', value: 'qihuan'),
            FilterChoice(label: '百合', value: 'baihe'),
            FilterChoice(label: '校园', value: 'xiaoyuan'),
            FilterChoice(label: '科幻', value: 'kehuan'),
            FilterChoice(label: '東方', value: 'dongfang'),
            FilterChoice(label: '耽美', value: 'danmei'),
            FilterChoice(label: '生活', value: 'shenghuo'),
            FilterChoice(label: '格鬥', value: 'gedou'),
            FilterChoice(label: '悬疑', value: 'xuanyi'),
            FilterChoice(label: '其他', value: 'qita'),
            FilterChoice(label: '热血', value: 'rexue'),
            FilterChoice(label: '後宮', value: 'hougong'),
            FilterChoice(label: '都市', value: 'dushi'),
            FilterChoice(label: '武侠', value: 'wuxia'),
            FilterChoice(label: '仙侠', value: 'xianxia'),
            FilterChoice(label: '搞笑', value: 'gaoxiao'),
            FilterChoice(label: '恐怖', value: 'kongbu'),
            FilterChoice(label: '竞技', value: 'jingji'),
            FilterChoice(label: '职场', value: 'zhichang'),
            FilterChoice(label: '萌系', value: 'mengxi'),
            FilterChoice(label: '治愈', value: 'zhiyu'),
            FilterChoice(label: '長條', value: 'changtiao'),
            FilterChoice(label: '四格', value: 'sige'),
            FilterChoice(label: '舰娘', value: 'jianniang'),
            FilterChoice(label: '節操', value: 'jiecao'),
            FilterChoice(label: '偽娘', value: 'weiniang'),
            FilterChoice(label: '性轉換', value: 'xingzhuanhuan'),
            FilterChoice(label: '重生', value: 'chongsheng'),
            FilterChoice(label: '穿越', value: 'chuanyue'),
            FilterChoice(label: '異世界', value: 'yishijie'),
            FilterChoice(label: '轉生', value: 'zhuansheng'),
            FilterChoice(label: '戰爭', value: 'zhanzheng'),
            FilterChoice(label: '歷史', value: 'lishi'),
            FilterChoice(label: '偵探', value: 'zhentan'),
            FilterChoice(label: '美食', value: 'meishi'),
            FilterChoice(label: '勵志', value: 'lizhi'),
            FilterChoice(label: '生存', value: 'shengcun'),
            FilterChoice(label: '驚悚', value: 'jingsong'),
            FilterChoice(label: '神鬼', value: 'shengui'),
            FilterChoice(label: '機戰', value: 'jizhan'),
            FilterChoice(label: '音樂舞蹈', value: 'yinyuewudao'),
            FilterChoice(label: '宅系', value: 'zhaixi'),
            FilterChoice(label: '輕小說', value: 'qingxiaoshuo'),
            FilterChoice(label: 'COLOR', value: 'COLOR'),
          ],
        ),
        const FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: '-datetime_updated',
          choices: [
            FilterChoice(label: '更新时间⬇️', value: '-datetime_updated'),
            FilterChoice(label: '更新时间⬆️', value: 'datetime_updated'),
            FilterChoice(label: '热度⬇️', value: '-popular'),
            FilterChoice(label: '热度⬆️', value: 'popular'),
          ],
        ),
      ];

  // ─── Discovery ───────────────────────────────────────────────

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final type = filters['type'] ?? '';
    final sort = filters['sort'] ?? '-datetime_updated';

    final queryParams = <String, dynamic>{
      'limit': '21',
      'offset': '${(page - 1) * 21}',
      'ordering': sort,
      '_update': 'true',
    };
    if (type.isNotEmpty) queryParams['theme'] = type;

    return FetchConfig(
      url: '$_apiUrl/comics',
      headers: {
        ..._apiHeaders,
        'Cookie': 'age=18; webp=1',
      },
      queryParameters: queryParams,
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final data = response as Map<String, dynamic>;
    if (data['code'] != 200) return [];

    final results = data['results'] as Map<String, dynamic>;
    final list = results['list'] as List;

    return list.map((item) {
      final authors = (item['author'] as List?)
              ?.map((a) => a['name'] as String)
              .join(', ') ??
          '';
      return MangaSummary(
        id: item['path_word'] as String,
        sourceId: sourceId,
        title: item['name'] as String,
        coverUrl: item['cover'] as String,
        author: authors,
        updateTime: item['datetime_updated'] as String?,
      );
    }).toList();
  }

  // ─── Search ──────────────────────────────────────────────────

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_apiUrl/search/comic',
      headers: {
        ..._apiHeaders,
        'platform': '2',
        'Cookie': 'age=18; webp=1',
      },
      queryParameters: {
        'platform': '2',
        'q': keyword,
        'limit': '12',
        'offset': '${(page - 1) * 12}',
        'q_type': '',
        '_update': 'true',
      },
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final data = response as Map<String, dynamic>;
    if (data['code'] != 200) return [];

    final results = data['results'] as Map<String, dynamic>;
    final list = results['list'] as List;

    return list.map((item) {
      final authors = (item['author'] as List?)
              ?.map((a) => a['name'] as String)
              .join(', ') ??
          '';
      return MangaSummary(
        id: item['path_word'] as String,
        sourceId: sourceId,
        title: item['name'] as String,
        coverUrl: item['cover'] as String,
        author: authors,
      );
    }).toList();
  }

  // ─── Manga Info ──────────────────────────────────────────────

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/comic/$mangaId',
      headers: _defaultWebHeaders,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final html = response as String;

    // Extract encryption key for chapter list
    final keyMatch = _mangaKeyPattern.firstMatch(html);
    if (keyMatch != null) {
      _mangaKey = keyMatch.group(1) ?? _defaultKey;
    }

    // Parse cover image
    final coverMatch = RegExp(
            r'comicParticulars-left-img[^>]*>.*?<img[^>]+(?:data-src|src)="([^"]+)"',
            dotAll: true)
        .firstMatch(html);
    final cover = coverMatch?.group(1) ?? '';

    // Parse title
    final titleMatch = RegExp(
            r'comicParticulars-title-right[^>]*>\s*<h6[^>]*>(.*?)</h6',
            dotAll: true)
        .firstMatch(html);
    final title = titleMatch?.group(1)?.trim() ?? '';

    // Extract authors
    final authorSection =
        RegExp(r'作者：.*?</li>', dotAll: true).firstMatch(html);
    final authors = <String>[];
    if (authorSection != null) {
      final authorMatches = RegExp(
              r'comicParticulars-right-txt[^>]*>\s*<a[^>]*>(.*?)</a>',
              dotAll: true)
          .allMatches(authorSection.group(0)!);
      for (final m in authorMatches) {
        final author = m.group(1)?.trim();
        if (author != null && author.isNotEmpty) authors.add(author);
      }
    }

    // Extract status
    var status = MangaStatus.unknown;
    final statusMatch = RegExp(
            r'狀態：.*?comicParticulars-right-txt[^>]*>(.*?)<', dotAll: true)
        .firstMatch(html);
    if (statusMatch != null) {
      final statusText = statusMatch.group(1) ?? '';
      if (statusText.contains('連載中')) {
        status = MangaStatus.ongoing;
      } else if (statusText.contains('已完結')) {
        status = MangaStatus.completed;
      }
    }

    // Extract tags
    final tags = <String>[];
    final tagSection =
        RegExp(r'題材：.*?</li>', dotAll: true).firstMatch(html);
    if (tagSection != null) {
      final tagMatches = RegExp(
              r'comicParticulars-tag[^>]*>\s*<a[^>]*>(.*?)</a>', dotAll: true)
          .allMatches(tagSection.group(0)!);
      for (final m in tagMatches) {
        final tag = m.group(1)?.trim();
        if (tag != null && tag.isNotEmpty) tags.add(tag);
      }
    }

    // Extract update time
    final updateMatch = RegExp(
            r'最後更新：.*?comicParticulars-right-txt[^>]*>(.*?)<', dotAll: true)
        .firstMatch(html);
    final updateTime = updateMatch?.group(1)?.trim();

    // Extract description
    final descMatch =
        RegExp(r'class="intro"[^>]*>(.*?)</\w+>', dotAll: true)
            .firstMatch(html);
    final desc = descMatch?.group(1)?.trim();

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: cover,
      author: authors.join(', '),
      description: desc,
      tags: tags,
      status: status,
      updateTime: updateTime,
      headers: _imageHeaders,
    );
  }

  // ─── Chapter List ────────────────────────────────────────────

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    return FetchConfig(
      url: '$_baseUrl/comicdetail/$mangaId/chapters',
      headers: {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/comic/$mangaId',
        'Cookie': 'age=18; webp=1',
      },
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final data = response as Map<String, dynamic>;
    if (data['code'] != 200) {
      return const ChapterListResult(chapters: []);
    }

    final encrypted = data['results'] as String;
    final decrypted = aesDecrypt(encrypted, _mangaKey);
    final chapterData = _parseJson(decrypted) as Map<String, dynamic>;

    final build = chapterData['build'] as Map<String, dynamic>?;
    final pathWord = build?['path_word'] as String? ?? mangaId;
    final groups = chapterData['groups'] as Map<String, dynamic>? ?? {};

    final allChapters = <ChapterItem>[];

    for (final entry in groups.entries) {
      final group = entry.value as Map<String, dynamic>;
      final chapters = group['chapters'] as List? ?? [];
      for (final ch in chapters) {
        allChapters.add(ChapterItem(
          id: ch['id'] as String,
          mangaId: pathWord,
          title: ch['name'] as String,
          href: '$_baseUrl/comic/$pathWord/chapter/${ch['id']}',
        ));
      }
    }

    return ChapterListResult(
      chapters: allChapters.reversed.toList(),
      canLoadMore: false,
    );
  }

  // ─── Chapter Content ─────────────────────────────────────────

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // Try APP API first for cleaner data
    return FetchConfig(
      url: '$_apiUrl/comic/$mangaId/chapter/$chapterId',
      headers: _buildAppHeaders(),
      queryParameters: {
        'in_mainland': 'true',
        'request_id': '',
      },
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_baseUrl/comic/$mangaId/chapter/$chapterId';
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    if (response is Map<String, dynamic>) {
      return _parseChapterFromApi(response, mangaId, chapterId);
    }

    // HTML fallback
    final html = response as String;
    return _parseChapterFromHtml(html, mangaId, chapterId);
  }

  ChapterResult _parseChapterFromApi(
    Map<String, dynamic> response,
    String mangaId,
    String chapterId,
  ) {
    if (response['code'] != 200) {
      throw Exception('HotManga chapter API failed: ${response['message']}');
    }

    final results = response['results'] as Map<String, dynamic>?;
    final chapterData = results?['chapter'] as Map<String, dynamic>?;
    if (chapterData == null) {
      throw Exception('HotManga chapter API returned empty chapter data');
    }

    final title = chapterData['name'] as String? ?? '';
    final contents = chapterData['contents'] as List? ?? const [];
    final rawImages = contents.map((item) {
      final url = (item as Map<String, dynamic>)['url'] as String;
      return ChapterImage(
        url: url.replaceAll(_imageUrlPattern, '.c1500x.'),
        headers: _imageHeaders,
      );
    }).toList();

    final words = chapterData['words'] as List?;
    final images = (words != null && words.length == rawImages.length)
        ? _reorderImages(rawImages, words)
        : rawImages;

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: _imageHeaders,
      ),
    );
  }

  ChapterResult _parseChapterFromHtml(
    String html,
    String mangaId,
    String chapterId,
  ) {
    // Extract title
    final headerMatch =
        RegExp(r'<h4[^>]*class="header"[^>]*>(.*?)</h4>', dotAll: true)
            .firstMatch(html);
    final headerText = headerMatch?.group(1)?.trim() ?? '';
    final parts = headerText.split('/');
    final title = parts.length > 1 ? parts[1].trim() : headerText;

    // Extract decryption key from disPass element
    final passMatch = _chapterPassPattern.firstMatch(html);
    final key = passMatch?.group(1) ?? _mangaKey;

    // Extract encrypted image data
    final dataMatch = _chapterContentKeyPattern.firstMatch(html);
    final scriptDataMatch = _chapterContentKeyScriptPattern.firstMatch(html);
    if (dataMatch == null && scriptDataMatch == null) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: title,
          images: const [],
          headers: _imageHeaders,
        ),
      );
    }

    final encryptedData = dataMatch?.group(1) ?? scriptDataMatch!.group(1)!;
    if (encryptedData.length < 16) {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: title,
          images: const [],
          headers: _imageHeaders,
        ),
      );
    }

    final decrypted = aesDecrypt(encryptedData, key);
    final imageList = _parseJson(decrypted) as List;

    final images = imageList.map((item) {
      final url =
          (item['url'] as String).replaceAll(_imageUrlPattern, '.c1500x.');
      return ChapterImage(url: url, headers: _imageHeaders);
    }).toList();

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: _imageHeaders,
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────

  List<ChapterImage> _reorderImages(List<ChapterImage> images, List words) {
    final reordered = List<ChapterImage?>.filled(images.length, null);

    for (var i = 0; i < images.length; i++) {
      final order = int.tryParse('${words[i]}');
      if (order == null || order < 0 || order >= images.length) {
        return images;
      }
      reordered[order] = images[i];
    }

    if (reordered.any((image) => image == null)) {
      return images;
    }

    return reordered.cast<ChapterImage>();
  }

  Map<String, String> _buildAppHeaders() {
    final now = DateTime.now();
    final timestamp = (now.millisecondsSinceEpoch ~/ 1000).toString();
    final date =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final signature = Hmac(
      sha256,
      base64Decode(_appSignatureSecret),
    ).convert(utf8.encode(timestamp)).toString();

    return {
      'User-Agent': 'COPY/$_appVersion',
      'source': 'copyApp',
      'deviceinfo': _deviceInfo,
      'dt': date,
      'platform': '3',
      'referer': 'com.copymanga.app-$_appVersion',
      'version': _appVersion,
      'device': _device,
      'pseudoid': _pseudoId,
      'Accept': 'application/json',
      'region': '0',
      'authorization': 'Token',
      'umstring': _appUmString,
      'x-auth-timestamp': timestamp,
      'x-auth-signature': signature,
      'Cookie': 'age=18; webp=1',
    };
  }

  String _generateDeviceInfo() {
    final first = 1000000 + _random.nextInt(9000000);
    final second = 1000 + _random.nextInt(9000);
    return '${first}V-$second';
  }

  String _generateDevice() {
    String randomUpper() => String.fromCharCode(65 + _random.nextInt(26));
    String randomDigit() => _random.nextInt(10).toString();

    return '${randomUpper()}${randomUpper()}${randomDigit()}${randomUpper()}.${randomDigit()}${randomDigit()}${randomDigit()}${randomDigit()}${randomDigit()}${randomDigit()}.${randomDigit()}${randomDigit()}${randomDigit()}';
  }

  String _generatePseudoId() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  dynamic _parseJson(String text) {
    try {
      return const JsonDecoder().convert(text);
    } catch (_) {
      return {};
    }
  }
}
