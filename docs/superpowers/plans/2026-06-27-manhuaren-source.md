# Manhuaren (漫画人) Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a manga data source for manhuaren.com using their internal mobile API with RSA+GSN authentication.

**Architecture:** Single source file `lib/data/sources/manhuaren.dart` implementing MangaSource with a pre-request auth check in the repository layer. Authentication uses RSA-encrypted device info to create an anonymous user, then GSN-signed requests for all subsequent API calls.

**Tech Stack:** Flutter/Dart, pointycastle (RSA), crypto (MD5), uuid (request IDs), dio (HTTP)

---

### Task 1: Create ManhuarenSource scaffold with metadata and filters

**Files:**
- Create: `lib/data/sources/manhuaren.dart`

- [ ] **Step 1: Create the source file with class scaffold, metadata, and filter definitions**

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:pointycastle/export.dart';
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
}
```

- [ ] **Step 2: Verify the file compiles**

Run: `flutter analyze lib/data/sources/manhuaren.dart`
Expected: No errors (warnings about unimplemented methods are fine at this stage — we'll add them next)

---

### Task 2: Implement utility methods (IMEI, GSN, URL encoding, RSA, common params)

**Files:**
- Modify: `lib/data/sources/manhuaren.dart`

- [ ] **Step 1: Add IMEI generation helper**

Add after the `needsAuth` getter:

```dart
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
```

- [ ] **Step 2: Add custom URL encoding**

```dart
  /// Custom URL encoding matching manhuaren's expected format.
  /// Standard percent-encoding but: + → %20, %7E → ~, * → %2A
  String _customUrlEncode(String value) {
    final encoded = Uri.encodeComponent(value);
    return encoded
        .replaceAll('+', '%20')
        .replaceAll('%7E', '~')
        .replaceAll('*', '%2A');
  }
```

- [ ] **Step 3: Add common query parameters builder**

```dart
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
```

- [ ] **Step 4: Add GSN signature computation**

```dart
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
```

- [ ] **Step 5: Add RSA encryption helper**

```dart
  /// RSA-encrypt plaintext using the server's public key.
  String _rsaEncrypt(String plaintext) {
    final publicKeyBytes = base64Decode(_rsaPublicKeyBase64);
    final asn1Parser = ASN1Parser(Uint8List.fromList(publicKeyBytes));
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final bitString = topLevelSeq.elements![1] as ASN1BitString;
    final publicKeyDer = bitString.contentBytes()!;

    final keyParser = ASN1Parser(publicKeyDer);
    final keySeq = keyParser.nextObject() as ASN1Sequence;
    final modulus = (keySeq.elements![0] as ASN1Integer).integer!;
    final exponent = (keySeq.elements![1] as ASN1Integer).integer!;

    final rsaPublicKey = RSAPublicKey(modulus, exponent);
    final encryptor = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));

    final inputBytes = utf8.encode(plaintext);
    // RSA-OAEP can only encrypt up to keySize - 2*hashSize - 2 bytes at once
    // For 2048-bit key with SHA-1: max = 256 - 42 = 214 bytes
    final maxBlockSize = (modulus.bitLength + 7) ~/ 8 - 42;
    final output = <int>[];

    for (int offset = 0; offset < inputBytes.length; offset += maxBlockSize) {
      final end =
          (offset + maxBlockSize > inputBytes.length) ? inputBytes.length : offset + maxBlockSize;
      final block = Uint8List.fromList(inputBytes.sublist(offset, end));
      output.addAll(encryptor.process(block));
    }

    return base64Encode(output);
  }
```

- [ ] **Step 6: Add request headers builder**

```dart
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
```

- [ ] **Step 7: Add signed FetchConfig builder**

```dart
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
```

- [ ] **Step 8: Verify compilation**

Run: `flutter analyze lib/data/sources/manhuaren.dart`
Expected: No errors (only warnings about unimplemented abstract methods)

---

### Task 3: Implement authentication (prepareAuthFetch / parseAuthResponse)

**Files:**
- Modify: `lib/data/sources/manhuaren.dart`

- [ ] **Step 1: Add prepareAuthFetch method**

```dart
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
      throw Exception('Unexpected auth response type: ${responseData.runtimeType}');
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
```

- [ ] **Step 2: Verify compilation**

Run: `flutter analyze lib/data/sources/manhuaren.dart`
Expected: No errors (only warnings about unimplemented abstract methods)

---

### Task 4: Implement Discovery and Search

**Files:**
- Modify: `lib/data/sources/manhuaren.dart`

- [ ] **Step 1: Implement prepareDiscoveryFetch and parseDiscovery**

```dart
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
```

- [ ] **Step 2: Implement prepareSearchFetch and parseSearch**

```dart
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
```

- [ ] **Step 3: Add shared manga list parser**

```dart
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
    final mangas = (response['mangas'] as List?) ?? (response['result'] as List?) ?? [];

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
```

- [ ] **Step 4: Verify compilation**

Run: `flutter analyze lib/data/sources/manhuaren.dart`
Expected: No errors (only warnings about remaining unimplemented methods)

---

### Task 5: Implement MangaInfo and ChapterList

**Files:**
- Modify: `lib/data/sources/manhuaren.dart`

- [ ] **Step 1: Implement prepareMangaInfoFetch and parseMangaInfo**

```dart
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
    final tags =
        themeStr.isNotEmpty ? themeStr.split(' ').where((t) => t.isNotEmpty).toList() : <String>[];
    final isOver = data['mangaIsOver'] as int? ?? 0;
    final status = isOver == 1 ? MangaStatus.completed : MangaStatus.ongoing;

    // Parse chapters from mangaSections
    final sections = data['mangaSections'] as List? ?? [];
    final chapters = <ChapterItem>[];
    for (final section in sections) {
      final s = section as Map<String, dynamic>;
      final sectionId = s['sectionId']?.toString() ?? '';
      final sectionTitle = s['sectionTitle'] as String? ?? s['sectionName'] as String? ?? '';
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
```

- [ ] **Step 2: Implement prepareChapterListFetch and parseChapterList**

```dart
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
```

- [ ] **Step 3: Verify compilation**

Run: `flutter analyze lib/data/sources/manhuaren.dart`
Expected: No errors (only warnings about unimplemented prepareChapterFetch/parseChapter)

---

### Task 6: Implement Chapter content fetch

**Files:**
- Modify: `lib/data/sources/manhuaren.dart`

- [ ] **Step 1: Implement prepareChapterFetch and parseChapter**

```dart
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
    final title = data['sectionTitle'] as String? ?? data['sectionName'] as String? ?? '';

    final images = imageList.map((img) {
      final imageMap = img as Map<String, dynamic>;
      final url = imageMap['imageUrl'] as String? ?? imageMap['url'] as String? ?? '';
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
```

- [ ] **Step 2: Verify full compilation with no errors**

Run: `flutter analyze lib/data/sources/manhuaren.dart`
Expected: No errors, no warnings

---

### Task 7: Register source and add repository auth integration

**Files:**
- Modify: `lib/app/di/injection.dart`
- Modify: `lib/data/repositories/manga_repository_impl.dart`

- [ ] **Step 1: Register ManhuarenSource in DI**

In `lib/app/di/injection.dart`, add import at top:

```dart
import 'package:comic_reader/data/sources/manhuaren.dart';
```

Add registration after the existing sources (e.g., after `registry.register(HComic());`):

```dart
  registry.register(ManhuarenSource());
```

- [ ] **Step 2: Add ManhuarenSource import to repository**

In `lib/data/repositories/manga_repository_impl.dart`, add import:

```dart
import 'package:comic_reader/data/sources/manhuaren.dart';
```

- [ ] **Step 3: Add pre-request auth helper in repository**

Add this private method in `MangaRepositoryImpl`:

```dart
  /// Ensure ManhuarenSource is authenticated before making API requests.
  Future<void> _ensureManhuarenAuth(ManhuarenSource source) async {
    if (!source.needsAuth) return;
    try {
      final authConfig = _mergeHeaders(source.prepareAuthFetch(), source);
      final authResponse = await _httpClient.execute(authConfig);
      source.parseAuthResponse(authResponse.data);
      debugPrint('[Manhuaren] Auth successful, userId=${source.id}');
    } catch (e) {
      debugPrint('[Manhuaren] Auth failed: $e');
      rethrow;
    }
  }
```

- [ ] **Step 4: Add auth check in getDiscovery**

In `getDiscovery`, after the source null check and before `prepareDiscoveryFetch`:

```dart
    // Manhuaren: ensure authenticated before API calls
    if (source is ManhuarenSource && source.needsAuth) {
      await _ensureManhuarenAuth(source);
    }
```

- [ ] **Step 5: Add auth check in searchManga**

In `searchManga`, after the source null check and before `prepareSearchFetch`:

```dart
    // Manhuaren: ensure authenticated before API calls
    if (source is ManhuarenSource && source.needsAuth) {
      await _ensureManhuarenAuth(source);
    }
```

- [ ] **Step 6: Add auth check in getMangaInfo**

In `getMangaInfo`, after the source null check and before the Hitomi gg.js block:

```dart
    // Manhuaren: ensure authenticated before API calls
    if (source is ManhuarenSource && source.needsAuth) {
      await _ensureManhuarenAuth(source);
    }
```

- [ ] **Step 7: Add auth check in getChapter**

In `getChapter`, after the source null check and before the effectivePage line:

```dart
    // Manhuaren: ensure authenticated before API calls
    if (source is ManhuarenSource && source.needsAuth) {
      await _ensureManhuarenAuth(source);
    }
```

- [ ] **Step 8: Verify full project compilation**

Run: `flutter analyze lib/data/sources/manhuaren.dart lib/app/di/injection.dart lib/data/repositories/manga_repository_impl.dart`
Expected: No errors

---

### Task 8: Final verification

**Files:**
- All modified files

- [ ] **Step 1: Run full project analysis**

Run: `flutter analyze`
Expected: No errors related to our changes

- [ ] **Step 2: Commit**

```bash
git add lib/data/sources/manhuaren.dart lib/app/di/injection.dart lib/data/repositories/manga_repository_impl.dart
git commit -m "feat: add Manhuaren (漫画人) data source with mobile API integration

- Implement ManhuarenSource with RSA auth + GSN-signed requests
- Full discovery filters (genre, region, status, sort)
- Search, manga detail, and chapter reading support
- Add pre-request auth check in repository layer"
```
