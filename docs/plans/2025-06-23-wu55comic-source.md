# Wu55Comic 数据源实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 comic-reader 中实现 wu55comic（污污漫画）作为新的漫画源插件，包含图片分片下载、AES解密、切片重组全链路。

**Architecture:** 新增两个文件：`wu55comic.dart`（MangaSource子类，HTML解析）和 `wu55comic_decoder.dart`（图片解密器）。扩展 `ScrambleType` 枚举和 `ChapterImage` 模型。在 `MangaImage` widget 中添加 wu55 类型的切片重组渲染。

**Tech Stack:** Flutter/Dart, html package (HTML解析), encrypt package (AES-CBC), crypto package (MD5), dio (HTTP)

---

## Task 1: 扩展 ScrambleType 枚举和 ChapterImage 模型

**Files:**
- Modify: `lib/domain/entities/chapter.dart`

**Step 1: 添加 wu55 枚举值**

在 `lib/domain/entities/chapter.dart` 第3行修改枚举：

```dart
enum ScrambleType { none, jmc, rm5, wu55 }
```

**Step 2: 扩展 ChapterImage 添加 wu55 字段**

在 `ChapterImage` 类中新增两个可选字段用于 wu55 切片数计算：

```dart
class ChapterImage extends Equatable {
  final String url;
  final ScrambleType scrambleType;
  final Map<String, String>? headers;
  /// The scramble_id threshold used for JMC unscrambling.
  /// Only relevant when scrambleType == ScrambleType.jmc.
  final int? scrambleId;
  /// wu55comic book ID, used for slice count calculation.
  /// Only relevant when scrambleType == ScrambleType.wu55.
  final int? wu55BookId;
  /// wu55comic page number (1-based index), used for slice count calculation.
  /// Only relevant when scrambleType == ScrambleType.wu55.
  final int? wu55PageNumber;

  const ChapterImage({
    required this.url,
    this.scrambleType = ScrambleType.none,
    this.headers,
    this.scrambleId,
    this.wu55BookId,
    this.wu55PageNumber,
  });

  @override
  List<Object?> get props => [url, scrambleType, scrambleId, wu55BookId, wu55PageNumber];
}
```

**Step 3: 验证静态分析通过**

Run: `flutter analyze lib/domain/entities/chapter.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/domain/entities/chapter.dart
git commit -m "feat(wu55comic): extend ScrambleType enum and ChapterImage model for wu55"
```

---

## Task 2: 实现 Wu55ComicDecoder 图片解密器

**Files:**
- Create: `lib/data/sources/wu55comic_decoder.dart`

**Step 1: 创建解密器文件**

```dart
import 'dart:typed_data';
import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart' show md5;
import 'package:encrypt/encrypt.dart' as encrypt;

/// Result of decoding a wu55comic encrypted image.
class Wu55ImageDecodeResult {
  /// The restored image bytes (valid JPEG/GIF/AVIF with correct file header).
  final Uint8List imageBytes;

  /// Whether this image needs slice unscrambling (type == "monga").
  final bool needsUnscramble;

  /// The book ID extracted from magic number (for slice count calculation).
  final int bookId;

  /// The page number extracted from magic number (for slice count calculation).
  final int pageNumber;

  /// The detected MIME type of the image.
  final String mimeType;

  const Wu55ImageDecodeResult({
    required this.imageBytes,
    required this.needsUnscramble,
    required this.bookId,
    required this.pageNumber,
    required this.mimeType,
  });
}

/// Handles wu55comic image decryption pipeline:
/// 1. URL transformation (original → shard URLs)
/// 2. AES-CBC decryption
/// 3. Magic number parsing & file header restoration
/// 4. Slice count calculation for UI unscrambling
class Wu55ComicDecoder {
  // AES-CBC parameters (hardcoded in site JS)
  static const String _aesKeyStr = 'aaaaaaaaaaaaaaaa'; // 16 bytes of 'a'
  static const String _aesIvStr = 'bbbbbbbbaaaaaaaa'; // 8 bytes 'b' + 8 bytes 'a'

  // CDN hosts for split file shards
  static const List<String> _defaultCdnHosts = [
    'https://bmigmij-wuwu.sqxxov.com',
    'https://bmigmih-wuwu.sqxxov.com',
  ];

  // Magic number bytes for restoring file headers
  static const List<int> _jpegMagic = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01];
  static const List<int> _gifMagic = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
  static const List<int> _avifMagic = [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66];

  /// Generate the cache key (YYYYMMDD format).
  static String get _cacheKey {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// Convert an original image URL to 2 shard URLs on different CDN hosts.
  ///
  /// Input: `https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/3751/13411/299297.jpg`
  /// Output: [
  ///   `https://bmigmij-wuwu.sqxxov.com/static/upload/book/3751/13411/299297.b_0?v=20250623`,
  ///   `https://bmigmih-wuwu.sqxxov.com/static/upload/book/3751/13411/299297.b_1?v=20250623`,
  /// ]
  static List<String> buildShardUrls(String originalUrl, {List<String>? cdnHosts}) {
    final hosts = cdnHosts ?? _defaultCdnHosts;
    final cacheKey = _cacheKey;

    // Remove /break_xxx/ path segment
    String cleanUrl = originalUrl.replaceAll(RegExp(r'/break[^/]*/'), '/');

    // Extract domain from cleaned URL
    final domainMatch = RegExp(r'^https?://[^/]+').firstMatch(cleanUrl);
    final originalDomain = domainMatch?.group(0) ?? '';

    // Find file extension
    final lastDot = cleanUrl.lastIndexOf('.');
    final extension = cleanUrl.substring(lastDot + 1);

    final results = <String>[];
    for (int i = 0; i < 2; i++) {
      String shardUrl = cleanUrl.replaceAll('.$extension', '.b_$i');
      shardUrl = shardUrl.replaceFirst(originalDomain, hosts[i]);
      shardUrl += '?v=$cacheKey';
      results.add(shardUrl);
    }
    return results;
  }

  /// Decrypt the concatenated shard data using AES-CBC.
  static Uint8List decryptAES(Uint8List combinedData) {
    final key = encrypt.Key.fromUtf8(_aesKeyStr);
    final iv = encrypt.IV.fromUtf8(_aesIvStr);

    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );

    final decrypted = encrypter.decryptBytes(
      encrypt.Encrypted(combinedData),
      iv: iv,
    );

    return Uint8List.fromList(decrypted);
  }

  /// Parse magic number from decrypted data and restore the real file header.
  ///
  /// Decrypted data layout:
  /// - byte[0]: file type code (0=JPEG, 3=GIF, 4=AVIF)
  /// - byte[1]: sub-type (0="monga" needs unscramble, 1="other" no unscramble)
  /// - byte[2..]: additional metadata (bookId, pageNumber) for monga type
  static Wu55ImageDecodeResult restoreImage(Uint8List decrypted) {
    final fileTypeCode = decrypted[0];
    final subType = decrypted[1];

    // Determine file type and magic bytes
    List<int> magicBytes;
    String mimeType;
    switch (fileTypeCode) {
      case 0:
        magicBytes = _jpegMagic;
        mimeType = 'image/jpeg';
        break;
      case 3:
        magicBytes = _gifMagic;
        mimeType = 'image/gif';
        break;
      case 4:
        magicBytes = _avifMagic;
        mimeType = 'image/avif';
        break;
      default:
        // Unknown type, assume JPEG
        magicBytes = _jpegMagic;
        mimeType = 'image/jpeg';
    }

    // Parse metadata based on sub-type
    bool needsUnscramble = false;
    int bookId = 0;
    int pageNumber = 0;

    if (subType == 0) {
      // type = "monga" — needs slice unscrambling
      needsUnscramble = true;
      // bookId = byte[2]*256 + byte[3]
      bookId = decrypted[2] * 256 + decrypted[3];
      // pageNumber = byte[4]*16777216 + byte[5]*65536 + byte[6]*256 + byte[7]
      pageNumber = decrypted[4] * 16777216 +
          decrypted[5] * 65536 +
          decrypted[6] * 256 +
          decrypted[7];
    }

    // Restore the real image file header by overwriting magic number region
    final result = Uint8List.fromList(decrypted);
    for (int i = 0; i < magicBytes.length && i < result.length; i++) {
      result[i] = magicBytes[i];
    }

    return Wu55ImageDecodeResult(
      imageBytes: result,
      needsUnscramble: needsUnscramble,
      bookId: bookId,
      pageNumber: pageNumber,
      mimeType: mimeType,
    );
  }

  /// Calculate the slice count for image unscrambling.
  ///
  /// Algorithm: `44 + (md5(bookId + pageNumber).lastChar.ascii % 10) * 4`
  /// Result range: 44, 48, 52, 56, 60, 64, 68, 72, 76, 80
  static int getSliceCount(int bookId, int pageNumber) {
    final combined = '$bookId$pageNumber';
    final hash = md5.convert(utf8.encode(combined)).toString();
    final lastChar = hash.codeUnitAt(hash.length - 1);
    final mod = lastChar % 10;
    return 44 + mod * 4;
  }
}
```

**Step 2: 验证静态分析通过**

Run: `flutter analyze lib/data/sources/wu55comic_decoder.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/data/sources/wu55comic_decoder.dart
git commit -m "feat(wu55comic): implement image decoder with AES decryption and magic number restoration"
```

---

## Task 3: 编写 Wu55ComicDecoder 单元测试

**Files:**
- Create: `test/data/sources/wu55comic_decoder_test.dart`

**Step 1: 编写纯逻辑单元测试（不需要网络）**

```dart
import 'dart:typed_data';
import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' show md5;
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';

void main() {
  group('Wu55ComicDecoder', () {
    group('buildShardUrls', () {
      test('converts original URL to 2 shard URLs with correct hosts', () {
        const originalUrl =
            'https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/3751/13411/299297.jpg';
        final urls = Wu55ComicDecoder.buildShardUrls(originalUrl);

        expect(urls.length, 2);
        expect(urls[0], contains('bmigmij-wuwu.sqxxov.com'));
        expect(urls[1], contains('bmigmih-wuwu.sqxxov.com'));
        expect(urls[0], contains('.b_0'));
        expect(urls[1], contains('.b_1'));
        expect(urls[0], contains('?v='));
        // Should NOT contain /break_2/
        expect(urls[0], isNot(contains('/break_2/')));
        expect(urls[0], isNot(contains('/break_avif/')));
      });

      test('removes any /break_xxx/ path segment', () {
        const url =
            'https://bmigmij-wuwu.sqxxov.com/break_avif/static/upload/book/100/200/300.jpg';
        final urls = Wu55ComicDecoder.buildShardUrls(url);

        expect(urls[0], isNot(contains('/break_avif/')));
        expect(urls[0], contains('/static/upload/book/100/200/300.b_0'));
      });

      test('uses custom CDN hosts when provided', () {
        const url =
            'https://cdn1.example.com/break_2/path/image.jpg';
        final urls = Wu55ComicDecoder.buildShardUrls(
          url,
          cdnHosts: ['https://host-a.com', 'https://host-b.com'],
        );

        expect(urls[0], startsWith('https://host-a.com'));
        expect(urls[1], startsWith('https://host-b.com'));
      });

      test('cache key is YYYYMMDD format', () {
        const url =
            'https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/1/2/3.jpg';
        final urls = Wu55ComicDecoder.buildShardUrls(url);

        // Extract ?v= parameter
        final vParam = RegExp(r'\?v=(\d+)').firstMatch(urls[0])?.group(1);
        expect(vParam, isNotNull);
        expect(vParam!.length, 8); // YYYYMMDD
        expect(int.tryParse(vParam), isNotNull);
      });
    });

    group('getSliceCount', () {
      test('returns value in range 44-80 with step 4', () {
        // Test multiple combinations
        for (int bookId = 1; bookId <= 100; bookId++) {
          for (int page = 1; page <= 10; page++) {
            final count = Wu55ComicDecoder.getSliceCount(bookId, page);
            expect(count, greaterThanOrEqualTo(44));
            expect(count, lessThanOrEqualTo(80));
            expect((count - 44) % 4, 0);
          }
        }
      });

      test('is deterministic for same inputs', () {
        final count1 = Wu55ComicDecoder.getSliceCount(3751, 5);
        final count2 = Wu55ComicDecoder.getSliceCount(3751, 5);
        expect(count1, count2);
      });

      test('different inputs produce different slice counts', () {
        // With enough variation, we should see different values
        final counts = <int>{};
        for (int i = 1; i <= 100; i++) {
          counts.add(Wu55ComicDecoder.getSliceCount(i, 1));
        }
        // Should have multiple distinct values
        expect(counts.length, greaterThan(1));
      });

      test('matches known md5 calculation', () {
        // Manual verification: md5("37511") → check last char
        final hash = md5.convert(utf8.encode('37511')).toString();
        final lastChar = hash.codeUnitAt(hash.length - 1);
        final expected = 44 + (lastChar % 10) * 4;
        expect(Wu55ComicDecoder.getSliceCount(3751, 1), expected);
      });
    });

    group('restoreImage', () {
      test('restores JPEG header for fileType 0', () {
        // Simulate decrypted data: byte[0]=0 (JPEG), byte[1]=0 (monga),
        // byte[2..3]=bookId=3751 (0x0E, 0xA7), byte[4..7]=pageNumber=5
        final data = Uint8List.fromList([
          0, 0, // fileType=JPEG, subType=monga
          0x0E, 0xA7, // bookId = 14*256 + 167 = 3751
          0, 0, 0, 5, // pageNumber = 5
          // padding to be longer than magic bytes
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ]);

        final result = Wu55ComicDecoder.restoreImage(data);

        expect(result.needsUnscramble, true);
        expect(result.bookId, 3751);
        expect(result.pageNumber, 5);
        expect(result.mimeType, 'image/jpeg');
        // First bytes should be JPEG magic
        expect(result.imageBytes[0], 0xFF);
        expect(result.imageBytes[1], 0xD8);
        expect(result.imageBytes[2], 0xFF);
        expect(result.imageBytes[3], 0xE0);
      });

      test('handles GIF type (fileType=3)', () {
        final data = Uint8List.fromList([
          3, 1, // fileType=GIF, subType=other (no unscramble)
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ]);

        final result = Wu55ComicDecoder.restoreImage(data);

        expect(result.needsUnscramble, false);
        expect(result.mimeType, 'image/gif');
        // First bytes should be GIF89a magic
        expect(result.imageBytes[0], 0x47); // 'G'
        expect(result.imageBytes[1], 0x49); // 'I'
        expect(result.imageBytes[2], 0x46); // 'F'
      });

      test('handles AVIF type (fileType=4)', () {
        final data = Uint8List.fromList([
          4, 0, // fileType=AVIF, subType=monga
          0x01, 0x00, // bookId = 256
          0, 0, 0, 1, // pageNumber = 1
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ]);

        final result = Wu55ComicDecoder.restoreImage(data);

        expect(result.needsUnscramble, true);
        expect(result.bookId, 256);
        expect(result.pageNumber, 1);
        expect(result.mimeType, 'image/avif');
        // ftyp box header
        expect(result.imageBytes[4], 0x66); // 'f'
        expect(result.imageBytes[5], 0x74); // 't'
        expect(result.imageBytes[6], 0x79); // 'y'
        expect(result.imageBytes[7], 0x70); // 'p'
      });
    });

    group('decryptAES', () {
      test('decrypts data encrypted with known key/iv', () {
        // Create a test by encrypting known plaintext
        // We'll use the same key/iv to encrypt, then verify decrypt gives back original
        final plaintext = Uint8List.fromList(
          List.generate(32, (i) => i), // 32 bytes of 0,1,2,...,31
        );

        // Encrypt using same parameters
        final key = encrypt.Key.fromUtf8('aaaaaaaaaaaaaaaa');
        final iv = encrypt.IV.fromUtf8('bbbbbbbbaaaaaaaa');
        final encrypter = encrypt.Encrypter(
          encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
        );
        final encrypted = encrypter.encryptBytes(plaintext, iv: iv);

        // Now decrypt using our decoder
        final decrypted = Wu55ComicDecoder.decryptAES(encrypted.bytes);

        expect(decrypted, plaintext);
      });
    });
  });
}
```

**Step 2: 运行测试确认通过**

Run: `flutter test test/data/sources/wu55comic_decoder_test.dart`
Expected: All tests passing

**Step 3: Commit**

```bash
git add test/data/sources/wu55comic_decoder_test.dart
git commit -m "test(wu55comic): add unit tests for Wu55ComicDecoder"
```

---

## Task 4: 实现 Wu55Comic 主源类（元数据 + Discovery）

**Files:**
- Create: `lib/data/sources/wu55comic.dart`

**Step 1: 创建源文件，实现元数据和 Discovery 解析**

```dart
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Wu55Comic (污污漫画) source plugin.
/// Uses HTML scraping for all data extraction.
/// Images are encrypted (split file + AES-CBC + slice scramble).
class Wu55Comic extends MangaSource {
  static const String sourceId = 'wu55comic';
  String _baseUrl = 'https://www.wu55comic.store';

  static const String _domainDiscoveryUrl =
      'https://bitbucket.org/h365g/55comic/raw/main/README.md';

  @override
  String get id => sourceId;

  @override
  String get name => '污污漫画';

  @override
  String get shortName => '污漫';

  @override
  String? get description => '韩漫日漫在线阅读';

  @override
  double get score => 3.5;

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
            FilterChoice(label: '长篇', value: '長篇'),
            FilterChoice(label: '剧情向', value: '劇情向'),
            FilterChoice(label: '御姐', value: '御姐・女王'),
            FilterChoice(label: '教师', value: '教師'),
            FilterChoice(label: '同人', value: '同人'),
            FilterChoice(label: '连裤袜', value: '連褲襪'),
            FilterChoice(label: '不伦', value: '不倫'),
            FilterChoice(label: '姐妹', value: '姉・妹'),
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

  /// Get the current base URL. Allows domain refresh logic.
  String get baseUrl => _baseUrl;

  /// Update base URL (called after domain discovery).
  set baseUrl(String url) => _baseUrl = url;

  // ─── Discovery ─────────────────────────────────────────────────────────────

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final tag = filters['tag'] ?? '';
    final area = filters['area'] ?? '-1';
    final end = filters['end'] ?? '-1';

    return FetchConfig(
      url: '$_baseUrl/booklist',
      method: HttpMethod.get,
      queryParameters: {
        'tag': tag,
        'area': area,
        'end': end,
        'page': '$page',
      },
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    final html = response.toString();
    final document = html_parser.parse(html);
    return _parseBookList(document);
  }

  // ─── Search ────────────────────────────────────────────────────────────────

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search',
      method: HttpMethod.get,
      queryParameters: {'keyword': keyword},
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final html = response.toString();
    final document = html_parser.parse(html);
    return _parseBookList(document);
  }

  // ─── Manga Info ────────────────────────────────────────────────────────────

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(
      url: '$_baseUrl/book/$mangaId',
      method: HttpMethod.get,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final html = response.toString();
    final document = html_parser.parse(html);

    // Title
    final title = document.querySelector('h1.sp-book-title')?.text.trim() ?? '';

    // Author - format: "作者：xxx"
    final authorRaw =
        document.querySelector('p.sp-book-author')?.text.trim() ?? '';
    final author = authorRaw.replaceFirst(RegExp(r'^作者[：:]'), '').trim();

    // Summary
    final summary =
        document.querySelector('p.sp-book-summary')?.text.trim() ?? '';

    // Tags
    final tagElements = document.querySelectorAll('a.sp-book-tag');
    final tags = tagElements.map((e) => e.text.trim()).toList();

    // Status - check for "完結" or "連載" text in meta
    var status = MangaStatus.unknown;
    final metaItems = document.querySelectorAll('.sp-book-meta-item');
    for (final item in metaItems) {
      final text = item.text;
      if (text.contains('完結')) {
        status = MangaStatus.completed;
        break;
      } else if (text.contains('連載')) {
        status = MangaStatus.ongoing;
        break;
      }
    }

    // Cover URL (encrypted)
    final coverEl = document.querySelector('[data-src]');
    final coverUrl = coverEl?.attributes['data-src'] ?? '';

    // Chapters
    final chapterElements = document.querySelectorAll('a.sp-chapter-item');
    final chapters = <ChapterItem>[];
    for (final el in chapterElements) {
      final href = el.attributes['href'] ?? '';
      // href format: /free-chapter/13411?t=20260415
      final chapterIdMatch = RegExp(r'/free-chapter/(\d+)').firstMatch(href);
      if (chapterIdMatch != null) {
        final chapterId = chapterIdMatch.group(1)!;
        final chapterTitle =
            el.attributes['title'] ?? el.text.trim();
        chapters.add(ChapterItem(
          id: chapterId,
          mangaId: mangaId,
          title: chapterTitle,
        ));
      }
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: summary.isNotEmpty ? summary : null,
      author: author,
      tags: tags,
      status: status,
      chapters: chapters,
    );
  }

  // ─── Chapter List ──────────────────────────────────────────────────────────

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // Chapters are embedded in the manga info page
    return null;
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    // Not used since chapters are in manga info
    return const ChapterListResult(chapters: []);
  }

  // ─── Chapter Content ───────────────────────────────────────────────────────

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // Generate a timestamp parameter similar to the site's ?t=YYYYMMDD
    final now = DateTime.now();
    final t =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    return FetchConfig(
      url: '$_baseUrl/free-chapter/$chapterId',
      method: HttpMethod.get,
      queryParameters: {'t': t},
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final html = response.toString();
    final document = html_parser.parse(html);

    // Extract all image divs: <div class="cropped" data-src="...">
    final imageElements = document.querySelectorAll('div.cropped[data-src]');
    final images = <ChapterImage>[];

    for (int i = 0; i < imageElements.length; i++) {
      final dataSrc = imageElements[i].attributes['data-src'] ?? '';
      if (dataSrc.isEmpty) continue;

      // The data-src contains the original encrypted image URL
      // We store it as-is; the decoder will handle transformation
      images.add(ChapterImage(
        url: dataSrc,
        scrambleType: ScrambleType.wu55,
        wu55BookId: int.tryParse(mangaId) ?? 0,
        wu55PageNumber: i + 1,
      ));
    }

    // Chapter title - try to extract from page
    final title = document.querySelector('title')?.text.trim() ?? '第${chapterId}话';

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

  // ─── Domain Discovery ──────────────────────────────────────────────────────

  /// Prepare a fetch to discover the current active domain from Bitbucket.
  FetchConfig prepareDomainDiscoveryFetch() {
    return FetchConfig(
      url: _domainDiscoveryUrl,
      method: HttpMethod.get,
    );
  }

  /// Parse domain discovery response and update base URL.
  /// Returns true if a new domain was found.
  bool parseDomainDiscovery(dynamic response) {
    final text = response.toString();
    // Look for wu55comic domain pattern
    final match =
        RegExp(r'https?://www\.wu55comic\.\w+').firstMatch(text);
    if (match != null) {
      final newUrl = match.group(0)!;
      if (newUrl != _baseUrl) {
        _baseUrl = newUrl;
        return true;
      }
    }
    return false;
  }

  // ─── Private Helpers ───────────────────────────────────────────────────────

  /// Parse a book list page (used for both discovery and search).
  List<MangaSummary> _parseBookList(Document document) {
    final results = <MangaSummary>[];

    // Find all book links in the list - they contain /book/{id}
    final bookLinks = document.querySelectorAll('a[href*="/book/"]');
    final seenIds = <String>{};

    for (final link in bookLinks) {
      final href = link.attributes['href'] ?? '';
      final idMatch = RegExp(r'/book/(\d+)').firstMatch(href);
      if (idMatch == null) continue;

      final bookId = idMatch.group(1)!;
      if (seenIds.contains(bookId)) continue;
      seenIds.add(bookId);

      // Try to find title and cover within or near this link
      final titleText = link.attributes['title'] ??
          link.querySelector('h2,h3,.title')?.text.trim() ??
          link.text.trim();
      if (titleText.isEmpty) continue;

      // Cover: look for data-src attribute
      final coverEl = link.querySelector('[data-src]');
      final coverUrl = coverEl?.attributes['data-src'] ?? '';

      results.add(MangaSummary(
        id: bookId,
        sourceId: sourceId,
        title: titleText,
        coverUrl: coverUrl,
      ));
    }

    return results;
  }
}
```

**Step 2: 验证静态分析通过**

Run: `flutter analyze lib/data/sources/wu55comic.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/data/sources/wu55comic.dart
git commit -m "feat(wu55comic): implement Wu55Comic MangaSource with HTML parsing"
```

---

## Task 5: 注册 Wu55Comic 到 DI 容器

**Files:**
- Modify: `lib/app/di/injection.dart`

**Step 1: 添加 import 和注册**

在 `injection.dart` 的 import 区域（约第15行之后）添加：

```dart
import 'package:comic_reader/data/sources/wu55comic.dart';
```

在 source registry 注册区域（约第74行，`registry.register(BaoziManga())` 之后）添加：

```dart
registry.register(Wu55Comic());
```

**Step 2: 验证静态分析通过**

Run: `flutter analyze lib/app/di/injection.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/app/di/injection.dart
git commit -m "feat(wu55comic): register Wu55Comic source in DI container"
```

---

## Task 6: 在 MangaImage widget 中支持 wu55 切片重组

**Files:**
- Modify: `lib/presentation/reader/widgets/manga_image.dart`

**Step 1: 添加 wu55comic_decoder import**

在文件顶部 import 区域添加：

```dart
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';
```

**Step 2: 添加 wu55 切片数计算方法**

在 `_MangaImageState` 类中（`_calculateSegments` 方法之后）添加新方法：

```dart
/// Calculate segment count for wu55comic unscrambling.
int _calculateWu55Segments(int width, int height) {
  final bookId = widget.image.wu55BookId ?? 0;
  final pageNumber = widget.image.wu55PageNumber ?? 0;
  if (bookId == 0 || pageNumber == 0) return 0;
  return Wu55ComicDecoder.getSliceCount(bookId, pageNumber);
}
```

**Step 3: 在图片加载完成的 loadStateChanged handler 中处理 wu55 类型**

在 `case LoadState.completed:` 中，紧接现有的 JMC unscramble 代码块后面添加 wu55 处理：

```dart
// If image needs wu55 unscrambling
if (widget.image.scrambleType == ScrambleType.wu55) {
  final imageInfo = state.extendedImageInfo;
  if (imageInfo != null) {
    return _UnscrambledImage(
      image: imageInfo.image,
      fit: widget.fit,
      alignment: widget.jmcAlignment,
      calculateSegments: _calculateWu55Segments,
    );
  }
}
```

**Step 4: 对 local file path 加载也处理 wu55 类型**

在 `_buildImageContent()` 方法中处理本地文件的 `onCompleted` callback 部分，扩展条件：

将 `widget.image.scrambleType == ScrambleType.jmc` 改为：
```dart
widget.image.scrambleType == ScrambleType.jmc ||
    widget.image.scrambleType == ScrambleType.wu55
```

并在对应的 onCompleted handler 中根据类型选择不同的 calculateSegments 函数：

```dart
onCompleted: (widget.image.scrambleType == ScrambleType.jmc ||
        widget.image.scrambleType == ScrambleType.wu55)
    ? (state) {
        final imageInfo = state.extendedImageInfo;
        if (imageInfo != null) {
          return _UnscrambledImage(
            image: imageInfo.image,
            fit: widget.fit,
            alignment: widget.jmcAlignment,
            calculateSegments: widget.image.scrambleType == ScrambleType.wu55
                ? _calculateWu55Segments
                : _calculateSegments,
          );
        }
        return state.completedWidget;
      }
    : null,
```

**Step 5: 在网络加载的 gesture 逻辑中也加入 wu55**

将 `final isJmcScrambled = widget.image.scrambleType == ScrambleType.jmc;` 改为：
```dart
final isScrambled = widget.image.scrambleType == ScrambleType.jmc ||
    widget.image.scrambleType == ScrambleType.wu55;
```
并将后续使用 `isJmcScrambled` 的地方改为 `isScrambled`。

**Step 6: 验证静态分析通过**

Run: `flutter analyze lib/presentation/reader/widgets/manga_image.dart`
Expected: No issues found

**Step 7: Commit**

```bash
git add lib/presentation/reader/widgets/manga_image.dart
git commit -m "feat(wu55comic): add wu55 scramble type rendering in MangaImage widget"
```

---

## Task 7: 在 Repository 中处理 wu55 图片解密流程

**Files:**
- Modify: `lib/data/repositories/manga_repository_impl.dart`

**Step 1: 添加 import**

```dart
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';
```

**Step 2: 在 getChapter 方法中添加 wu55 图片解密逻辑**

在获取到 `result` 之后，且在返回之前（多页扩展逻辑之后），如果源是 Wu55Comic，对每张图片执行解密：

```dart
// Wu55Comic: decrypt images after parsing chapter HTML
if (source is Wu55Comic) {
  final decryptedImages = <ChapterImage>[];
  for (final image in result.chapter.images) {
    if (image.scrambleType != ScrambleType.wu55) {
      decryptedImages.add(image);
      continue;
    }
    try {
      // 1. Build shard URLs from original data-src
      final shardUrls = Wu55ComicDecoder.buildShardUrls(image.url);

      // 2. Download both shards in parallel
      final shardConfigs = shardUrls.map((url) => FetchConfig(
        url: url,
        method: HttpMethod.get,
        responseType: ResponseType.bytes,
        headers: {
          'Referer': '${source.baseUrl}/',
          'Origin': source.baseUrl,
        },
      )).toList();

      final shardResponses = await Future.wait(
        shardConfigs.map((config) => _httpClient.execute(_mergeHeaders(config, source))),
      );

      // 3. Concatenate shards
      final shard0 = shardResponses[0].data as List<int>;
      final shard1 = shardResponses[1].data as List<int>;
      final combined = Uint8List.fromList([...shard0, ...shard1]);

      // 4. AES decrypt
      final decrypted = Wu55ComicDecoder.decryptAES(combined);

      // 5. Restore image file header & parse metadata
      final decoded = Wu55ComicDecoder.restoreImage(decrypted);

      // 6. Create a data: URI or save to temp file for display
      // Using a memory-based approach: store bytes as base64 data URI
      final base64Data = base64Encode(decoded.imageBytes);
      final dataUri = 'data:${decoded.mimeType};base64,$base64Data';

      decryptedImages.add(ChapterImage(
        url: dataUri,
        scrambleType: decoded.needsUnscramble ? ScrambleType.wu55 : ScrambleType.none,
        wu55BookId: decoded.bookId,
        wu55PageNumber: decoded.pageNumber,
      ));
    } catch (e) {
      debugPrint('[wu55comic] Failed to decrypt image: ${image.url} - $e');
      // Add a placeholder for failed images
      decryptedImages.add(ChapterImage(
        url: '', // empty URL triggers placeholder in UI
        scrambleType: ScrambleType.none,
      ));
    }
  }

  result = ChapterResult(
    chapter: Chapter(
      id: result.chapter.id,
      mangaId: result.chapter.mangaId,
      title: result.chapter.title,
      images: decryptedImages,
    ),
    canLoadMore: false,
  );
}
```

**Step 3: 添加必要的 import 在文件顶部**

```dart
import 'dart:convert' show base64Encode;
import 'dart:typed_data';
```

**Step 4: 验证静态分析通过**

Run: `flutter analyze lib/data/repositories/manga_repository_impl.dart`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/data/repositories/manga_repository_impl.dart
git commit -m "feat(wu55comic): integrate image decryption pipeline in repository"
```

---

## Task 8: 处理 data: URI 在 MangaImage 中的加载

**Files:**
- Modify: `lib/presentation/reader/widgets/manga_image.dart`

**Step 1: 支持 data: URI 图片加载**

在 `_buildImageContent()` 方法中，network loading 部分之前，添加 data URI 处理：

```dart
// Handle data: URI images (e.g., wu55comic decrypted images)
if (widget.image.url.startsWith('data:')) {
  return _buildDataUriImage();
}
```

**Step 2: 实现 _buildDataUriImage 方法**

在 `_MangaImageState` 类中添加：

```dart
Widget _buildDataUriImage() {
  // Parse base64 data from data: URI
  final dataUri = widget.image.url;
  final commaIndex = dataUri.indexOf(',');
  if (commaIndex < 0) {
    return const Center(child: Icon(Icons.broken_image_outlined));
  }
  final base64Str = dataUri.substring(commaIndex + 1);
  final bytes = base64Decode(base64Str);

  final isScrambled = widget.image.scrambleType == ScrambleType.wu55;

  if (!isScrambled) {
    return Image.memory(
      Uint8List.fromList(bytes),
      fit: widget.fit,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
      ),
    );
  }

  // For scrambled images, we need ui.Image for CustomPainter
  return FutureBuilder<ui.Image>(
    future: _decodeImageFromBytes(bytes),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return const Center(
          child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
        );
      }
      return _UnscrambledImage(
        image: snapshot.data!,
        fit: widget.fit,
        alignment: widget.jmcAlignment,
        calculateSegments: _calculateWu55Segments,
      );
    },
  );
}

Future<ui.Image> _decodeImageFromBytes(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  return frame.image;
}
```

**Step 3: 添加必要的 import**

在文件顶部添加：

```dart
import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;
```

**Step 4: 验证静态分析通过**

Run: `flutter analyze lib/presentation/reader/widgets/manga_image.dart`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/presentation/reader/widgets/manga_image.dart
git commit -m "feat(wu55comic): support data: URI image loading with wu55 unscramble"
```

---

## Task 9: 域名动态发现集成

**Files:**
- Modify: `lib/data/repositories/manga_repository_impl.dart`

**Step 1: 在 Repository 中添加 wu55 域名刷新逻辑**

在请求失败时触发域名刷新。在 `_executeWithFallback` 方法中或在 wu55 源的请求逻辑中添加域名发现回退机制。

实际上，更简洁的做法是在 `getChapter`/`getMangaInfo`/`getDiscovery` 等方法调用失败时，如果源是 Wu55Comic，尝试刷新域名并重试。

在 `manga_repository_impl.dart` 中添加一个辅助方法：

```dart
/// Attempt to refresh wu55comic domain if request fails.
Future<void> _refreshWu55Domain(Wu55Comic source) async {
  try {
    final config = source.prepareDomainDiscoveryFetch();
    final response = await _httpClient.execute(config);
    source.parseDomainDiscovery(response.data);
    debugPrint('[wu55comic] Domain refreshed to: ${source.baseUrl}');
  } catch (e) {
    debugPrint('[wu55comic] Domain refresh failed: $e');
  }
}
```

这个方法可以在现有的 `_executeWithFallback` 机制中被调用，或者在第一次请求此源失败时触发。

**Step 2: 验证静态分析通过**

Run: `flutter analyze lib/data/repositories/manga_repository_impl.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/data/repositories/manga_repository_impl.dart
git commit -m "feat(wu55comic): add domain refresh fallback mechanism"
```

---

## Task 10: 编写集成验证脚本

**Files:**
- Create: `test/verify_wu55comic.dart`

**Step 1: 创建网络实测脚本**

```dart
/// Manual verification script for wu55comic source.
/// Run with: dart run test/verify_wu55comic.dart
///
/// This is NOT a unit test - it makes real network requests.
/// Do not include in CI.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert' show base64Encode;

import 'package:dio/dio.dart';
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';

void main() async {
  final source = Wu55Comic();
  final dio = Dio();

  print('=== Wu55Comic Verification ===');
  print('Base URL: ${source.baseUrl}');
  print('');

  // 1. Test Discovery
  print('--- Discovery ---');
  try {
    final config = source.prepareDiscoveryFetch(1, {});
    print('URL: ${config.url}?${config.queryParameters}');
    final response = await dio.get(
      config.url,
      queryParameters: config.queryParameters,
      options: Options(headers: source.defaultHeaders),
    );
    final results = source.parseDiscovery(response.data);
    print('Found ${results.length} manga');
    if (results.isNotEmpty) {
      print('First: ${results[0].title} (id=${results[0].id})');
    }
  } catch (e) {
    print('ERROR: $e');
  }
  print('');

  // 2. Test Search
  print('--- Search ---');
  try {
    final config = source.prepareSearchFetch('秘密', 1, {});
    final response = await dio.get(
      config.url,
      queryParameters: config.queryParameters,
      options: Options(headers: source.defaultHeaders),
    );
    final results = source.parseSearch(response.data);
    print('Search "秘密": ${results.length} results');
    if (results.isNotEmpty) {
      print('First: ${results[0].title} (id=${results[0].id})');
    }
  } catch (e) {
    print('ERROR: $e');
  }
  print('');

  // 3. Test Manga Info
  print('--- Manga Info ---');
  final testMangaId = '3751';
  try {
    final config = source.prepareMangaInfoFetch(testMangaId);
    final response = await dio.get(
      config.url,
      options: Options(headers: source.defaultHeaders),
    );
    final detail = source.parseMangaInfo(response.data, testMangaId);
    print('Title: ${detail.title}');
    print('Author: ${detail.author}');
    print('Tags: ${detail.tags}');
    print('Chapters: ${detail.chapters.length}');
    if (detail.chapters.isNotEmpty) {
      print('First chapter: ${detail.chapters[0].title} (id=${detail.chapters[0].id})');
    }
  } catch (e) {
    print('ERROR: $e');
  }
  print('');

  // 4. Test Chapter + Image Decrypt
  print('--- Chapter & Image Decrypt ---');
  try {
    // First get manga info to find a chapter
    final infoConfig = source.prepareMangaInfoFetch(testMangaId);
    final infoResponse = await dio.get(
      infoConfig.url,
      options: Options(headers: source.defaultHeaders),
    );
    final detail = source.parseMangaInfo(infoResponse.data, testMangaId);

    if (detail.chapters.isEmpty) {
      print('No chapters found');
      exit(1);
    }

    final chapterId = detail.chapters[0].id;
    print('Testing chapter: $chapterId');

    final chapterConfig =
        source.prepareChapterFetch(testMangaId, chapterId, 1);
    final chapterResponse = await dio.get(
      chapterConfig.url,
      queryParameters: chapterConfig.queryParameters,
      options: Options(headers: source.defaultHeaders),
    );
    final chapterResult =
        source.parseChapter(chapterResponse.data, testMangaId, chapterId, 1);
    print('Images found: ${chapterResult.chapter.images.length}');

    if (chapterResult.chapter.images.isNotEmpty) {
      final firstImage = chapterResult.chapter.images[0];
      print('First image URL: ${firstImage.url}');

      // Decrypt first image
      final shardUrls = Wu55ComicDecoder.buildShardUrls(firstImage.url);
      print('Shard URLs:');
      for (final url in shardUrls) {
        print('  $url');
      }

      // Download shards
      print('Downloading shards...');
      final shard0Response = await dio.get<List<int>>(
        shardUrls[0],
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': '${source.baseUrl}/'},
        ),
      );
      final shard1Response = await dio.get<List<int>>(
        shardUrls[1],
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': '${source.baseUrl}/'},
        ),
      );

      print('Shard 0: ${shard0Response.data!.length} bytes');
      print('Shard 1: ${shard1Response.data!.length} bytes');

      // Combine and decrypt
      final combined = Uint8List.fromList([
        ...shard0Response.data!,
        ...shard1Response.data!,
      ]);
      print('Combined: ${combined.length} bytes');

      final decrypted = Wu55ComicDecoder.decryptAES(combined);
      print('Decrypted: ${decrypted.length} bytes');
      print('First 8 bytes (before restore): ${decrypted.sublist(0, 8)}');

      // Restore image
      final decoded = Wu55ComicDecoder.restoreImage(decrypted);
      print('MIME: ${decoded.mimeType}');
      print('Needs unscramble: ${decoded.needsUnscramble}');
      print('Book ID: ${decoded.bookId}');
      print('Page Number: ${decoded.pageNumber}');

      if (decoded.needsUnscramble) {
        final sliceCount =
            Wu55ComicDecoder.getSliceCount(decoded.bookId, decoded.pageNumber);
        print('Slice count: $sliceCount');
      }

      // Save to file for visual inspection
      final outputFile = File('/tmp/wu55_test_image.jpg');
      await outputFile.writeAsBytes(decoded.imageBytes);
      print('Saved decoded image to: ${outputFile.path}');
      print('(Note: image will appear scrambled if needsUnscramble=true)');
    }
  } catch (e, stack) {
    print('ERROR: $e');
    print(stack);
  }

  print('\n=== Done ===');
  exit(0);
}
```

**Step 2: Commit**

```bash
git add test/verify_wu55comic.dart
git commit -m "test(wu55comic): add manual network verification script"
```

---

## Task 11: 最终集成验证

**Step 1: 运行全局静态分析**

Run: `flutter analyze`
Expected: No issues found (或仅有预存的未修改文件的warning)

**Step 2: 运行 decoder 单元测试**

Run: `flutter test test/data/sources/wu55comic_decoder_test.dart`
Expected: All tests passing

**Step 3: 运行验证脚本（手动，需网络）**

Run: `dart run test/verify_wu55comic.dart`
Expected: 能成功获取漫画列表、详情、章节，并解密至少一张图片

**Step 4: Final commit (if any remaining fixes)**

```bash
git add -A
git commit -m "feat(wu55comic): complete wu55comic source integration"
```
