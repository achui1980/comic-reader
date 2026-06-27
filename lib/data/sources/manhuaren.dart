import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:uuid/uuid.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Manhuaren (漫画人) source plugin using internal mobile API.
///
/// API base: http://mangaapi.manhuaren.com
/// Auth: RSA-encrypted device info → anonymous user creation → GSN-signed requests
class ManhuarenSource extends MangaSource {
  static const String sourceId = 'manhuaren';
  static const String _apiBase = 'http://mangaapi.manhuaren.com';
  static const String _salt = '4e0a48e1c0b54041bce9c8f0e036124d';
  static const int _pageSize = 20;

  // RSA public key for device info encryption
  static const String _rsaPublicKeyBase64 =
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmFCg289dTws27v8GtqIf'
      'fkP4zgFR+MYIuUIeVO5AGiBV0rfpRh5gg7i8RrT12E9j6XwKoe3xJz1khDnPc65P'
      '5f7CJcNJ9A8bj7Al5K4jYGxz+4Q+n0YzSllXPit/Vz/iW5jFdlP6CTIgUVwvIoG'
      'EL2sS4cqqqSpCDKHSeiXh9CtMsktc6YyrSN+8mQbBvoSSew18r/vC07iQiaYkClc'
      's7jIPq9tuilL//2uR9kWn5jsp8zHKVjmXuLtHDhM9lObZGCVJwdlN2KDKTh276u/'
      'pzQ1s5u8z/ARtK26N8e5w8mNlGcHcHfwyhjfEQurvrnkqYH37+12U3jGk5YNHGyO'
      'PcwIDAQAB';

  // Cached auth state (memory-only)
  String? _userId;
  String? _authScheme;
  String? _authParameter;
  String? _imei;
  int? _lastUsedTime;

  final _uuid = const Uuid();

  @override
  String get id => sourceId;

  @override
  String get name => '漫画人';

  @override
  String get shortName => 'MHR';

  @override
  String? get description => 'Manhuaren.com mobile API (漫画人)';

  @override
  double get score => 4.0;

  @override
  String? get href => 'https://www.manhuaren.com';

  @override
  bool get needsProxy => false;

  @override
  int get firstPage => 1;

  @override
  Map<String, String> get defaultHeaders => {
        'User-Agent':
            'Dalvik/2.1.0 (Linux; U; Android 13; Pixel 7 Build/TP1A.220624.021)',
        'X-Yq-Yqci': '{"le":"zh","os":"1","ov":"33_13","av":"7.0.1"}',
      };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'genre',
          label: '题材',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '热血', value: '1'),
            FilterChoice(label: '恋爱', value: '2'),
            FilterChoice(label: '校园', value: '3'),
            FilterChoice(label: '搞笑', value: '4'),
            FilterChoice(label: '格斗', value: '5'),
            FilterChoice(label: '冒险', value: '6'),
            FilterChoice(label: '科幻', value: '7'),
            FilterChoice(label: '魔幻', value: '8'),
            FilterChoice(label: '神鬼', value: '9'),
            FilterChoice(label: '悬疑', value: '10'),
            FilterChoice(label: '唯美', value: '11'),
            FilterChoice(label: '惊悚', value: '12'),
            FilterChoice(label: '职场', value: '13'),
            FilterChoice(label: '萌系', value: '14'),
            FilterChoice(label: '治愈', value: '15'),
            FilterChoice(label: '历史', value: '16'),
            FilterChoice(label: '美食', value: '17'),
            FilterChoice(label: '同人', value: '18'),
            FilterChoice(label: '运动', value: '19'),
            FilterChoice(label: '励志', value: '20'),
            FilterChoice(label: '生活', value: '21'),
            FilterChoice(label: '战争', value: '22'),
            FilterChoice(label: '长条', value: '23'),
          ],
        ),
        FilterOption(
          name: 'region',
          label: '地区',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '日漫', value: '1'),
            FilterChoice(label: '韩漫', value: '2'),
            FilterChoice(label: '国漫', value: '3'),
          ],
        ),
        FilterOption(
          name: 'status',
          label: '进度',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '全部', value: '0'),
            FilterChoice(label: '连载中', value: '1'),
            FilterChoice(label: '已完结', value: '2'),
          ],
        ),
        FilterOption(
          name: 'sort',
          label: '排序',
          defaultValue: '0',
          choices: [
            FilterChoice(label: '热门', value: '0'),
            FilterChoice(label: '更新', value: '1'),
            FilterChoice(label: '新作', value: '2'),
          ],
        ),
      ];

  @override
  List<FilterOption> get searchFilters => const [];

  /// Whether this source needs authentication before making requests.
  bool get needsAuth => _userId == null || _authParameter == null;

  // ---------------------------------------------------------------------------
  // Utility methods
  // ---------------------------------------------------------------------------

  /// Generate a valid 15-digit IMEI with Luhn checksum.
  String _generateImei() {
    final random = Random();
    final digits = List.generate(14, (_) => random.nextInt(10));

    // Luhn checksum calculation
    int sum = 0;
    for (int i = 0; i < 14; i++) {
      int d = digits[i];
      if (i % 2 == 1) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    digits.add(checkDigit);

    return digits.join();
  }

  /// Custom URL encoding matching manhuaren's expected format.
  /// Standard percent-encoding but: + → %20, %7E → ~, * → %2A
  String _customUrlEncode(String value) {
    final encoded = Uri.encodeComponent(value);
    return encoded
        .replaceAll('+', '%20')
        .replaceAll('%7E', '~')
        .replaceAll('*', '%2A');
  }

  /// Build the common query parameters included in every API request.
  Map<String, String> _buildCommonParams() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _lastUsedTime ??= now;
    final userId = _userId ?? '';

    return {
      'gsm': 'md5',
      'gft': 'json',
      'gak': 'android_manhuaren2',
      'gat': '',
      'gui': userId,
      'gts': now.toString(),
      'gut': '0',
      'gem': '1',
      'gaui': userId,
      'gln': '',
      'gcy': 'US',
      'gle': 'zh',
      'gcl': 'dm5',
      'gos': '1',
      'gov': '33_13',
      'gav': '7.0.1',
      'gdi': _imei ?? '',
      'gfcl': 'dm5',
      'gfut': _lastUsedTime.toString(),
      'glut': _lastUsedTime.toString(),
      'gpt': 'com.mhr.mangamini',
      'gciso': 'us',
      'glot': '',
      'glat': '',
      'gflot': '',
      'gflat': '',
      'glbsaut': '0',
      'gac': '',
      'gcut': 'GMT+8',
      'gfcc': '',
      'gflg': '',
      'glcn': '',
      'glcc': '',
      'gflcc': '',
    };
  }

  /// Compute GSN signature for a request.
  ///
  /// gsn = MD5(salt + METHOD + sorted(params.keys).map(k => k + encode(params[k])).join('') + salt)
  String _computeGsn(String method, Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    final buffer = StringBuffer(_salt);
    buffer.write(method.toUpperCase());
    for (final key in sortedKeys) {
      buffer.write(key);
      buffer.write(_customUrlEncode(params[key] ?? ''));
    }
    buffer.write(_salt);
    final bytes = utf8.encode(buffer.toString());
    return md5.convert(bytes).toString();
  }

  /// RSA-encrypt plaintext using the server's public key (OAEP/SHA-1).
  String _rsaEncrypt(String plaintext) {
    // Wrap raw base64 key in PEM format for RSAKeyParser
    const pem = '-----BEGIN PUBLIC KEY-----\n$_rsaPublicKeyBase64\n-----END PUBLIC KEY-----';
    final parser = encrypt_lib.RSAKeyParser();
    final publicKey = parser.parse(pem) as RSAPublicKey;

    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.RSA(publicKey: publicKey, encoding: encrypt_lib.RSAEncoding.OAEP),
    );

    final inputBytes = utf8.encode(plaintext);
    // RSA-OAEP with 2048-bit key + SHA-1: max block = 256 - 42 = 214 bytes
    final keyBytes = (publicKey.modulus!.bitLength + 7) ~/ 8;
    final maxBlockSize = keyBytes - 42;
    final output = <int>[];

    for (int offset = 0; offset < inputBytes.length; offset += maxBlockSize) {
      final end = (offset + maxBlockSize > inputBytes.length)
          ? inputBytes.length
          : offset + maxBlockSize;
      final block = Uint8List.fromList(inputBytes.sublist(offset, end));
      final encrypted = encrypter.encryptBytes(block.toList());
      output.addAll(encrypted.bytes);
    }

    return base64Encode(output);
  }

  /// Build per-request headers (Authorization, X-Yq-Key, etc.)
  Map<String, String> _buildRequestHeaders() {
    final headers = <String, String>{
      'x-request-id': _uuid.v4(),
      'yq_is_anonymous': '1',
    };
    if (_userId != null) {
      headers['X-Yq-Key'] = _userId!;
    }
    if (_authScheme != null && _authParameter != null) {
      headers['Authorization'] = '$_authScheme $_authParameter';
    }
    return headers;
  }

  /// Build a signed GET FetchConfig with common params + endpoint params + GSN.
  FetchConfig _buildSignedGet(String path, Map<String, String> endpointParams) {
    final params = _buildCommonParams()..addAll(endpointParams);
    final gsn = _computeGsn('GET', params);
    params['gsn'] = gsn;

    return FetchConfig(
      url: '$_apiBase$path',
      method: HttpMethod.get,
      headers: _buildRequestHeaders(),
      queryParameters: params,
    );
  }

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Prepare the anonymous user creation request.
  FetchConfig prepareAuthFetch() {
    _imei ??= _generateImei();
    _lastUsedTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final deviceInfo = jsonEncode({
      'osType': '1',
      'osVersion': '33',
      'imei': _imei,
      'deviceName': 'Pixel 7',
      'deviceModel': 'Pixel 7',
    });
    final encryptedBody = _rsaEncrypt(deviceInfo);

    // For POST, the gsn includes "body" key
    final params = _buildCommonParams();
    params['body'] = encryptedBody;
    final gsn = _computeGsn('POST', params);
    params.remove('body'); // body goes in request body, not query params
    params['gsn'] = gsn;

    return FetchConfig(
      url: '$_apiBase/v1/user/createAnonyUser2',
      method: HttpMethod.post,
      headers: {
        ..._buildRequestHeaders(),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      queryParameters: params,
      body: 'body=${Uri.encodeComponent(encryptedBody)}',
    );
  }

  /// Parse the auth response and cache credentials.
  void parseAuthResponse(dynamic responseData) {
    final Map<String, dynamic> json;
    if (responseData is String) {
      json = jsonDecode(responseData) as Map<String, dynamic>;
    } else if (responseData is Map) {
      json = responseData as Map<String, dynamic>;
    } else {
      throw Exception(
          'Unexpected auth response type: ${responseData.runtimeType}');
    }

    final response = json['response'] as Map<String, dynamic>?;
    if (response == null) {
      throw Exception('Auth response missing "response" field: $json');
    }

    _userId = response['userId']?.toString();
    final tokenResult = response['tokenResult'] as Map<String, dynamic>?;
    if (tokenResult != null) {
      _authScheme = tokenResult['scheme'] as String? ?? 'Bearer';
      _authParameter = tokenResult['parameter'] as String?;
    }

    if (_userId == null || _authParameter == null) {
      throw Exception('Auth response missing userId or token: $response');
    }
  }

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final genre = filters['genre'] ?? '0';
    final region = filters['region'] ?? '0';
    final status = filters['status'] ?? '0';
    final sort = filters['sort'] ?? '0';
    final start = ((page - 1) * _pageSize).toString();

    return _buildSignedGet('/v2/manga/getCategoryMangas', {
      'subCategoryId': genre,
      'subCategoryType': region,
      'status': status,
      'start': start,
      'limit': _pageSize.toString(),
      'sort': sort,
    });
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseMangaList(response);
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    final start = ((page - 1) * _pageSize).toString();

    return _buildSignedGet('/v1/search/getSearchManga', {
      'keywords': keyword,
      'start': start,
      'limit': _pageSize.toString(),
    });
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseMangaList(response);
  }

  // ---------------------------------------------------------------------------
  // Manga Info
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return _buildSignedGet('/v1/manga/getDetail', {
      'mangaId': mangaId,
    });
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final Map<String, dynamic> json;
    if (response is String) {
      json = jsonDecode(response) as Map<String, dynamic>;
    } else if (response is Map) {
      json = response as Map<String, dynamic>;
    } else {
      return MangaDetail(
        id: mangaId,
        sourceId: sourceId,
        title: '',
        coverUrl: '',
      );
    }

    final data = json['response'] as Map<String, dynamic>? ?? json;

    final title = data['mangaName'] as String? ?? '';
    final coverUrl = data['mangaCoverimageUrl'] as String? ?? '';
    final description = data['mangaDescription'] as String?;
    final author = data['mangaAuthor'] as String? ?? '';
    final themeStr = data['mangaTheme'] as String? ?? '';
    final tags = themeStr.isNotEmpty
        ? themeStr.split(' ').where((t) => t.isNotEmpty).toList()
        : <String>[];
    final isOver = data['mangaIsOver'] as int? ?? 0;
    final status = isOver == 1 ? MangaStatus.completed : MangaStatus.ongoing;

    // Parse chapters from mangaSections
    final sections = data['mangaSections'] as List? ?? [];
    final chapters = <ChapterItem>[];
    for (final section in sections) {
      final s = section as Map<String, dynamic>;
      final sectionId = s['sectionId']?.toString() ?? '';
      final sectionTitle =
          s['sectionTitle'] as String? ?? s['sectionName'] as String? ?? '';
      if (sectionId.isNotEmpty) {
        chapters.add(ChapterItem(
          id: sectionId,
          mangaId: mangaId,
          title: sectionTitle,
        ));
      }
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
      chapters: chapters,
    );
  }

  // ---------------------------------------------------------------------------
  // Chapter List (embedded in manga info, returns null)
  // ---------------------------------------------------------------------------

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are embedded in the detail response
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // ---------------------------------------------------------------------------
  // Chapter Content
  // ---------------------------------------------------------------------------

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    return _buildSignedGet('/v1/manga/getRead', {
      'mangaSectionId': chapterId,
    });
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final Map<String, dynamic> json;
    if (response is String) {
      json = jsonDecode(response) as Map<String, dynamic>;
    } else if (response is Map) {
      json = response as Map<String, dynamic>;
    } else {
      return ChapterResult(
        chapter: Chapter(
          id: chapterId,
          mangaId: mangaId,
          title: '',
          images: const [],
        ),
      );
    }

    final data = json['response'] as Map<String, dynamic>? ?? json;
    final imageList = data['mangaSectionImages'] as List? ?? [];
    final title =
        data['sectionTitle'] as String? ?? data['sectionName'] as String? ?? '';

    final images = imageList.map((img) {
      final imageMap = img as Map<String, dynamic>;
      final url =
          imageMap['imageUrl'] as String? ?? imageMap['url'] as String? ?? '';
      return ChapterImage(url: url);
    }).where((img) => img.url.isNotEmpty).toList();

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared parsers
  // ---------------------------------------------------------------------------

  /// Parse a manga list response (used by both discovery and search).
  List<MangaSummary> _parseMangaList(dynamic responseData) {
    final Map<String, dynamic> json;
    if (responseData is String) {
      json = jsonDecode(responseData) as Map<String, dynamic>;
    } else if (responseData is Map) {
      json = responseData as Map<String, dynamic>;
    } else {
      return [];
    }

    final response = json['response'] as Map<String, dynamic>?;
    if (response == null) return [];

    // Try 'mangas' first, then 'result' for search
    final mangas =
        (response['mangas'] as List?) ?? (response['result'] as List?) ?? [];

    return mangas.map((item) {
      final manga = item as Map<String, dynamic>;
      return MangaSummary(
        id: manga['mangaId']?.toString() ?? '',
        sourceId: sourceId,
        title: manga['mangaName'] as String? ?? '',
        coverUrl: manga['mangaCoverimageUrl'] as String? ?? '',
        author: manga['mangaAuthor'] as String? ?? '',
        latestChapter: manga['mangaNewestContent'] as String?,
      );
    }).where((m) => m.id.isNotEmpty).toList();
  }
}
