import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// JMComic APP API client.
///
/// Uses the mobile APP API which doesn't require Cloudflare bypass.
/// Implements token-based auth and AES-ECB response decryption.
class JmComic extends MangaSource {
  static const String sourceId = 'jmc';

  // APP API secrets (from jmcomic-crawler-python)
  static const String _appTokenSecret = '18comicAPP';
  static const String _appTokenSecret2 = '18comicAPPContent';
  static const String _appDataSecret = '185Hcomic3PAPP7R';
  static const String _appVersion = '2.0.21';

  // API domains (ordered by reliability)
  static const List<String> _apiDomains = [
    'www.cdngwc.cc',
    'www.cdngwc.net',
    'www.cdngwc.club',
    'www.cdnhjk.net',
  ];

  // Image CDN domains
  static const List<String> _imageDomains = [
    'cdn-msp.jmapiproxy1.cc',
    'cdn-msp.jmapiproxy2.cc',
    'cdn-msp2.jmapiproxy2.cc',
    'cdn-msp3.jmapiproxy2.cc',
    'cdn-msp.jmapinodeudzn.net',
    'cdn-msp3.jmapinodeudzn.net',
  ];

  static const String _mobileUA =
      'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Safari/537.36';

  // Scramble thresholds
  static const int _scramble220980 = 220980;
  static const int _scramble268850 = 268850;
  static const int _scramble421926 = 421926;

  String? _currentDomain;
  int _currentDomainIndex = 0;
  int _scrambleId = _scramble220980;
  // Cache timestamp for consistent token in request/response pair
  String? _lastTs;

  String get _apiDomain {
    _currentDomain ??= _apiDomains[_currentDomainIndex];
    return _currentDomain!;
  }

  /// Switch to the next available API domain (fallback on failure).
  /// Returns true if a new domain is available, false if all exhausted.
  bool switchToNextDomain() {
    _currentDomainIndex = (_currentDomainIndex + 1) % _apiDomains.length;
    _currentDomain = _apiDomains[_currentDomainIndex];
    return true;
  }

  /// Number of fallback retries available (total domains - 1).
  int get maxDomainRetries => _apiDomains.length - 1;

  String get _apiBaseUrl => 'https://$_apiDomain';

  String get _imageDomain =>
      _imageDomains[Random().nextInt(_imageDomains.length)];

  @override
  String get id => sourceId;

  @override
  String get name => '禁漫天堂';

  @override
  String get shortName => 'JMC';

  @override
  String? get description => 'APP API模式，无需CF验证';

  @override
  double get score => 5.0;

  @override
  String? get href => 'https://18comic.vip';

  @override
  bool get needsProxy => true;

  @override
  bool get needsCloudflare => false; // APP API doesn't need CF

  @override
  List<String> get cloudflarePageTitles => const [];

  @override
  String? get userAgent => _mobileUA;

  @override
  Map<String, String>? get defaultHeaders => null;

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'category',
          label: '分类',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '同人', value: 'doujin'),
            FilterChoice(label: '单本', value: 'single'),
            FilterChoice(label: '短篇', value: 'short'),
            FilterChoice(label: '其他', value: 'another'),
            FilterChoice(label: '韩漫', value: 'hanman'),
            FilterChoice(label: '美漫', value: 'meiman'),
            FilterChoice(label: 'Cosplay', value: 'doujin_cosplay'),
            FilterChoice(label: '3D', value: '3D'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'mr',
          choices: [
            FilterChoice(label: '最新', value: 'mr'),
            FilterChoice(label: '最多观看', value: 'mv'),
            FilterChoice(label: '最多图片', value: 'mp'),
            FilterChoice(label: '最多爱心', value: 'tf'),
          ],
        ),
        FilterOption(
          name: 'time',
          label: '时间',
          defaultValue: 'a',
          choices: [
            FilterChoice(label: '全部', value: 'a'),
            FilterChoice(label: '今天', value: 't'),
            FilterChoice(label: '本周', value: 'w'),
            FilterChoice(label: '本月', value: 'm'),
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
            FilterChoice(label: '全部', value: 'a'),
            FilterChoice(label: '今天', value: 't'),
            FilterChoice(label: '本周', value: 'w'),
            FilterChoice(label: '本月', value: 'm'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: 'mr',
          choices: [
            FilterChoice(label: '最新', value: 'mr'),
            FilterChoice(label: '最多观看', value: 'mv'),
            FilterChoice(label: '最多图片', value: 'mp'),
            FilterChoice(label: '最多爱心', value: 'tf'),
          ],
        ),
      ];

  // --- API Request Building ---

  /// Generate token and tokenparam for API authentication.
  Map<String, String> _buildApiHeaders({String? secret}) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    _lastTs = ts;

    final effectiveSecret = secret ?? _appTokenSecret;
    final token = _md5Hex('$ts$effectiveSecret');
    final tokenparam = '$ts,$_appVersion';

    return {
      'token': token,
      'tokenparam': tokenparam,
      'User-Agent': _mobileUA,
      'Accept-Encoding': 'gzip, deflate',
    };
  }

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final category = filters['category'] ?? '0';
    final sort = filters['sort'] ?? 'mr';
    final time = filters['time'] ?? 'a';

    // Build order param: "mv_m" for monthly most viewed, etc.
    final o = time != 'a' ? '${sort}_$time' : sort;

    return FetchConfig(
      url: '$_apiBaseUrl/categories/filter',
      headers: _buildApiHeaders(),
      queryParameters: {
        'page': '$page',
        'order': '',
        'c': category,
        'o': o,
      },
      extra: {'ts': _lastTs, 'isJmApi': true},
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final data = _decodeApiResponse(response);
    if (data == null) return [];

    final content = data['content'] as List? ?? [];
    return _parseAlbumList(content);
  }

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final time = filters['time'] ?? 'a';
    final sort = filters['sort'] ?? 'mr';

    return FetchConfig(
      url: '$_apiBaseUrl/search',
      headers: _buildApiHeaders(),
      queryParameters: {
        'search_query': keyword,
        'page': '$page',
        'main_tag': '0',
        'o': sort,
        't': time,
      },
      extra: {'ts': _lastTs, 'isJmApi': true},
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final data = _decodeApiResponse(response);
    if (data == null) return [];

    // Check for redirect_aid (direct album ID search)
    if (data['redirect_aid'] != null) {
      // Single result redirect — we'll return a minimal summary
      final aid = data['redirect_aid'].toString();
      return [
        MangaSummary(
          id: aid,
          sourceId: sourceId,
          title: 'JM$aid',
          coverUrl: _buildCoverUrl(aid),
          author: '',
        ),
      ];
    }

    final content = data['content'] as List? ?? [];
    return _parseAlbumList(content);
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_apiBaseUrl/album',
      headers: _buildApiHeaders(),
      queryParameters: {'id': mangaId},
      extra: {'ts': _lastTs, 'isJmApi': true},
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final data = _decodeApiResponse(response);
    if (data == null) {
      return MangaDetail(
        id: mangaId,
        sourceId: sourceId,
        title: 'Error',
        coverUrl: '',
        author: '',
        tags: const [],
        status: MangaStatus.unknown,
      );
    }

    final title = data['name']?.toString() ?? '';
    final authors = (data['author'] as List?)?.cast<String>() ?? [];
    final tags = (data['tags'] as List?)?.cast<String>() ?? [];
    final description = data['description']?.toString();

    // Build chapter list from series
    final series = data['series'] as List? ?? [];
    final chapters = <ChapterItem>[];

    if (series.isEmpty) {
      // Single-chapter manga: album_id IS the photo_id (chapter_id)
      chapters.add(ChapterItem(
        id: mangaId,
        mangaId: mangaId,
        title: '开始阅读',
        href: '',
      ));
    } else {
      for (final ch in series) {
        if (ch is Map) {
          final chName = ch['name']?.toString() ?? '';
          final sort = ch['sort']?.toString() ?? '';
          // Use name if available, otherwise fall back to "第N话"
          final displayTitle = chName.isNotEmpty ? chName : '第$sort话';
          chapters.add(ChapterItem(
            id: ch['id']?.toString() ?? '',
            mangaId: mangaId,
            title: displayTitle,
            href: '',
          ));
        }
      }
    }

    // Cover URL
    final coverUrl = _buildCoverUrl(mangaId);

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      author: authors.join(', '),
      tags: tags,
      status: MangaStatus.unknown,
      description: description,
      chapters: chapters,
      headers: _imageHeaders,
    );
  }

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are embedded in manga info response
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
      url: '$_apiBaseUrl/chapter',
      headers: _buildApiHeaders(),
      queryParameters: {'id': chapterId},
      extra: {'ts': _lastTs, 'isJmApi': true},
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final data = _decodeApiResponse(response);
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

    final chTitle = data['name']?.toString() ?? '';
    final imageNames = (data['images'] as List?)?.cast<String>() ?? [];
    final seriesId = data['series_id']?.toString() ?? mangaId;

    // Build image URLs
    final images = <ChapterImage>[];
    for (int i = 0; i < imageNames.length; i++) {
      final imgName = imageNames[i];
      // Use the original image name from API (not re-indexed) for correct CDN URL
      // The filename is needed both for URL construction and scramble hash calculation
      final imgUrl =
          'https://$_imageDomain/media/photos/$chapterId/$imgName';

      // Determine scramble
      final scrambleType = _getScrambleType(chapterId, imgName);

      images.add(ChapterImage(
        url: imgUrl,
        scrambleType: scrambleType,
        headers: _imageHeaders,
        scrambleId: scrambleType == ScrambleType.jmc ? _scrambleId : null,
      ));
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: seriesId,
        title: chTitle,
        images: images,
        headers: _imageHeaders,
      ),
    );
  }

  // --- Crypto ---

  /// MD5 hex digest of a string.
  String _md5Hex(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// Decrypt API response data.
  ///
  /// 1. Base64 decode
  /// 2. AES-ECB decrypt with key = md5(ts + secret)
  /// 3. Remove PKCS7 padding
  /// 4. UTF-8 decode → JSON
  Map<String, dynamic>? _decodeApiResponse(dynamic response) {
    try {
      // Dio may auto-parse JSON into a Map, or leave it as String
      if (response is Map<String, dynamic>) {
        // Already parsed JSON — check for encrypted 'data' field
        if (response.containsKey('data') && response['data'] is String) {
          final encrypted = response['data'] as String;
          if (encrypted.isNotEmpty) {
            return _decryptData(encrypted);
          }
        }
        // Plain unencrypted response
        return response;
      }

      // Response is a raw string
      final respStr = response as String;

      // Try to parse as JSON first
      try {
        final parsed = jsonDecode(respStr);
        if (parsed is Map<String, dynamic>) {
          if (parsed.containsKey('data') && parsed['data'] is String) {
            final encrypted = parsed['data'] as String;
            if (encrypted.isNotEmpty) {
              return _decryptData(encrypted);
            }
          }
          return parsed;
        }
      } catch (_) {
        // Not valid JSON
      }

      // Try treating entire response as encrypted data
      return _decryptData(respStr);
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _decryptData(String encryptedData) {
    final ts = _lastTs ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // Key = md5(ts + secret) → 32-char hex → use first 16 bytes as AES key
    final keyHex = _md5Hex('$ts$_appDataSecret');
    final keyBytes = utf8.encode(keyHex);

    // Base64 decode the data
    final dataBytes = base64.decode(encryptedData);

    // AES-ECB decrypt
    final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.ecb, padding: 'PKCS7'),
    );
    final decrypted = encrypter.decrypt(encrypt_pkg.Encrypted(dataBytes));

    // Parse JSON
    return jsonDecode(decrypted) as Map<String, dynamic>;
  }

  // --- Image Helpers ---

  /// Image headers for native platforms.
  /// On web, Referer/X-Requested-With are ignored by the browser
  /// but the CORS proxy handles them automatically.
  Map<String, String> get _imageHeaders => const {
        'Referer': 'https://www.cdngwc.cc',
        'X-Requested-With': 'com.JMComic3.app',
      };

  String _buildCoverUrl(String albumId) {
    return 'https://$_imageDomain/media/albums/${albumId}_3x4.jpg';
  }

  String _padIndex(int index) {
    return index.toString().padLeft(5, '0');
  }

  String _getImageSuffix(String imageName) {
    // imageName like "00001.webp" or "00002.jpg"
    final dotIndex = imageName.lastIndexOf('.');
    if (dotIndex >= 0) {
      return imageName.substring(dotIndex);
    }
    return '.webp';
  }

  ScrambleType _getScrambleType(String chapterId, String imageName) {
    final chIdNum = int.tryParse(chapterId) ?? 0;

    // GIF images are never scrambled
    if (imageName.endsWith('.gif')) return ScrambleType.none;

    if (chIdNum < _scrambleId) return ScrambleType.none;

    return ScrambleType.jmc;
  }

  /// Calculate the number of segments for image unscrambling.
  ///
  /// This implements the same algorithm as the Python library.
  static int calculateSegmentCount(int scrambleId, int albumId, String filename) {
    if (albumId < scrambleId) return 0;
    if (albumId < _scramble268850) return 10;

    final x = albumId < _scramble421926 ? 10 : 8;
    final s = '$albumId$filename';
    final hash = md5.convert(utf8.encode(s)).toString();
    final lastChar = hash.codeUnitAt(hash.length - 1);
    final num = lastChar % x;
    return num * 2 + 2;
  }

  // --- List Parsing ---

  List<MangaSummary> _parseAlbumList(List<dynamic> content) {
    final results = <MangaSummary>[];
    for (final item in content) {
      if (item is! Map) continue;
      final albumId = item['id']?.toString() ?? '';
      if (albumId.isEmpty) continue;

      final title = item['name']?.toString() ?? '';
      final author = item['author']?.toString() ?? '';

      results.add(MangaSummary(
        id: albumId,
        sourceId: sourceId,
        title: title,
        coverUrl: _buildCoverUrl(albumId),
        author: author,
        headers: _imageHeaders,
      ));
    }
    return results;
  }

  // --- Scramble ID fetching ---

  /// Fetch scramble_id from the chapter_view_template endpoint.
  /// Call this before reading a chapter to get the correct scramble threshold.
  FetchConfig prepareScrambleFetch(String chapterId) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final token = _md5Hex('$ts$_appTokenSecret2');
    final tokenparam = '$ts,$_appVersion';

    return FetchConfig(
      url: '$_apiBaseUrl/chapter_view_template',
      headers: {
        'token': token,
        'tokenparam': tokenparam,
        'User-Agent': _mobileUA,
        'Accept-Encoding': 'gzip, deflate',
      },
      queryParameters: {
        'id': chapterId,
        'mode': 'vertical',
        'page': '0',
        'app_img_shunt': '1',
        'express': 'off',
        'v': ts,
      },
      extra: {'ts': ts, 'isJmApi': true},
    );
  }

  /// Parse scramble_id from the chapter_view_template response.
  void parseScrambleResponse(String responseText) {
    final match =
        RegExp(r'var\s+scramble_id\s*=\s*(\d+)').firstMatch(responseText);
    if (match != null) {
      _scrambleId = int.tryParse(match.group(1)!) ?? _scramble220980;
    }
  }
}
