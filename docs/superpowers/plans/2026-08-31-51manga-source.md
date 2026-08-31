# 51manga Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `51漫画` (51manga.com) as a `MangaSource` plugin, including AES-decryption of its obfuscated chapter image payload.

**Architecture:** A single new `MangaSource` subclass (`lib/data/sources/manga51.dart`) that talks exclusively to the mobile host `m.51manga.com` and follows the repo's prepare/parse purity rule — `prepare*Fetch` builds URLs, `parse*` turns HTML into entities and never touches the network. The only cross-cutting change is one new pure helper in `lib/core/utils/crypto_utils.dart` for the site's "base64 payload with a 16-byte IV prefix" AES-CBC scheme, which the existing `aesDecrypt` (hex ciphertext + UTF-8 character IV, CopyManga) cannot express. Chapter images are decrypted inside `parseChapter` as pure computation, so no framework change is needed.

**Tech Stack:** Dart / Flutter, `package:html` (DOM parsing), `package:encrypt` (AES-CBC), `flutter_test`. All dependencies already in `pubspec.yaml`.

**Spec:** `docs/superpowers/specs/2026-08-31-51manga-source-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/core/utils/crypto_utils.dart` | Modify (append) | Add `aesDecryptBase64PrefixedIv` — generic base64/prefixed-IV AES-CBC decryption. No 51manga-specific knowledge (no key, no JSON). |
| `lib/data/sources/manga51.dart` | Create | The whole source: metadata, filters, 5 prepare/parse pairs, private DOM/URL helpers. Owns the site key and CDN constants. |
| `test/data/sources/manga51_test.dart` | Create | Zero-network unit tests for the helper, the URL builders, and every parser. |
| `lib/app/di/injection.dart` | Modify (2 lines) | Register the source in the active set. |

Rationale for keeping the source in one file: every existing source in `lib/data/sources/` is a single self-contained file (`haokan_manhua.dart` 327 lines, `hot_manga.dart` 669 lines). Splitting would break the established convention for no benefit — the projected size is ~350 lines.

---

### Task 1: `aesDecryptBase64PrefixedIv` crypto helper

**Files:**
- Modify: `lib/core/utils/crypto_utils.dart` (append after line 31, before `_hexDecode`)
- Test: `test/data/sources/manga51_test.dart` (create)

Context: the existing `aesDecrypt` in this file treats the first 16 **characters** of its input as a UTF-8 IV and the rest as **hex** ciphertext. 51manga base64-encodes `IV_bytes || ciphertext_bytes`. These are incompatible, so a second helper is required rather than a modification.

- [ ] **Step 1: Write the failing test**

Create `test/data/sources/manga51_test.dart` with exactly this content:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/utils/crypto_utils.dart';

/// Base64 of `IV || AES-128-CBC(PKCS7)` produced offline with the real 51manga
/// key `9S8$vJnU2ANeSRoF` and the fixed IV `0123456789abcdef`.
/// Plaintext: `{"ok":true,"msg":"51manga"}`
///
/// Re-verify this vector independently of Dart (`tail -c +17` drops the
/// 16-byte IV prefix so only the ciphertext reaches openssl):
///
/// ```sh
/// echo -n 'MDEyMzQ1Njc4OWFiY2RlZg3jWjN/qoD6bo2MJ85/CU9d6d1jHc/1vHQsEOQqB99M' \
///   | base64 -d | tail -c +17 \
///   | openssl enc -d -aes-128-cbc \
///       -K 39533824764a6e5532414e6553526f46 \
///       -iv 30313233343536373839616263646566
/// # -> {"ok":true,"msg":"51manga"}
/// ```
///
/// `-K`/`-iv` are the hex forms of the UTF-8 key and IV above.
const String kSimplePayload =
    'MDEyMzQ1Njc4OWFiY2RlZg3jWjN/qoD6bo2MJ85/CU9d6d1jHc/1vHQsEOQqB99M';

const String kPicKey = r'9S8$vJnU2ANeSRoF';

void main() {
  group('aesDecryptBase64PrefixedIv', () {
    test('decrypts a known payload to its known plaintext', () {
      expect(
        aesDecryptBase64PrefixedIv(kSimplePayload, kPicKey),
        '{"ok":true,"msg":"51manga"}',
      );
    });

    test('throws when the payload is 16 bytes or shorter (no ciphertext)', () {
      // 16 bytes: IV only, nothing left to decrypt.
      //
      // The message predicate is essential, not decoration: RangeError and
      // IndexError both EXTEND ArgumentError, so a bare isA<ArgumentError>()
      // would also be satisfied by an accidental out-of-range crash and would
      // still pass if the length guard were deleted outright.
      expect(
        () => aesDecryptBase64PrefixedIv('MDEyMzQ1Njc4OWFiY2RlZg==', kPicKey),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(
              contains('decoded payload is 16 bytes'),
              contains('need more than 16'),
            ),
          ),
        ),
      );
    });

    test('throws a PKCS7 pad-check failure on a wrong key of the correct '
        'length', () {
      // The pad check is the ONLY thing that makes a wrong key throw here.
      // Encrypter.decrypt utf8-decodes with allowMalformed: true, so garbage
      // plaintext would otherwise come back as U+FFFD mojibake, not an error.
      expect(
        () => aesDecryptBase64PrefixedIv(kSimplePayload, 'wrongkey12345678'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('Invalid or corrupted pad block'),
          ),
        ),
      );
    });

    test('throws FormatException when the payload is not valid base64', () {
      // base64.decode (not our guard) rejects this, so the type is
      // FormatException rather than ArgumentError. Matters because Task 5
      // scrapes this payload out of HTML. Note base64.decode IS tolerant of
      // missing '=' padding and of the base64url alphabet, so this fixture
      // uses a character outside both alphabets.
      expect(
        () => aesDecryptBase64PrefixedIv('not!valid!base64', kPicKey),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid character'),
          ),
        ),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/sources/manga51_test.dart
```

Expected: compile failure — `The function 'aesDecryptBase64PrefixedIv' isn't defined`.

- [ ] **Step 3: Write the minimal implementation**

In `lib/core/utils/crypto_utils.dart`, change the import block at the top from:

```dart
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
```

to:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
```

Then insert this function after the closing brace of `aesDecrypt` (i.e. after line 31) and before `Uint8List _hexDecode(...)`:

```dart
/// AES-CBC decryption where [payload] is base64-encoded and, once decoded,
/// its first 16 BYTES are the IV and the remainder is the ciphertext.
///
/// [key] is the AES key as a UTF-8 string; its length selects the variant
/// (16 bytes = AES-128, 24 = AES-192, 32 = AES-256). 51manga uses a 16-byte
/// key, but nothing here is 128-specific. Padding is PKCS7.
///
/// This is the scheme used by 51manga's `pic-v3.js`. It is deliberately
/// separate from [aesDecrypt], which uses 16 leading *characters* as the IV
/// plus *hex* ciphertext (the CopyManga scheme).
///
/// The plaintext is UTF-8 decoded *leniently* (`allowMalformed: true`, inside
/// `Encrypter.decrypt`), so a wrong-but-plausible key yields U+FFFD mojibake
/// rather than an error. Do not treat "returned a String" as "decrypted
/// correctly" — callers should validate the decoded content.
///
/// Throws:
/// - [FormatException] if [payload] is not valid base64. Relevant because
///   callers scrape this blob out of HTML, so a markup change surfaces here
///   and not as an [ArgumentError].
/// - [ArgumentError] if the decoded payload has no ciphertext (the explicit
///   guard below), and also from the PKCS7 pad check ("Invalid or corrupted
///   pad block") when the key is wrong or the ciphertext is not block-aligned.
String aesDecryptBase64PrefixedIv(String payload, String key) {
  final raw = base64.decode(payload);
  if (raw.length <= 16) {
    throw ArgumentError.value(
      payload,
      'payload',
      'decoded payload is ${raw.length} bytes; need more than 16 '
          '(16-byte IV prefix plus ciphertext)',
    );
  }

  final iv = encrypt.IV(Uint8List.sublistView(raw, 0, 16));
  final ciphertext = encrypt.Encrypted(Uint8List.sublistView(raw, 16));

  final encrypter = encrypt.Encrypter(
    encrypt.AES(
      encrypt.Key.fromUtf8(key),
      mode: encrypt.AESMode.cbc,
      padding: 'PKCS7',
    ),
  );

  return encrypter.decrypt(ciphertext, iv: iv);
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/data/sources/manga51_test.dart
```

Expected: `All tests passed!` (4 tests).

- [ ] **Step 5: Static check**

```bash
flutter analyze lib/core/utils/crypto_utils.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/utils/crypto_utils.dart test/data/sources/manga51_test.dart
git commit -m "feat: add aesDecryptBase64PrefixedIv crypto helper for 51manga"
```

---

### Task 2: `Manga51` skeleton — metadata, filters, and URL builders

**Files:**
- Create: `lib/data/sources/manga51.dart`
- Test: `test/data/sources/manga51_test.dart` (append)

All five `parse*` methods are stubbed with `UnimplementedError` in this task so the class compiles; Tasks 3–5 fill them in. Do not delete the stubs' signatures — they are the exact contract from `lib/data/sources/manga_source.dart`.

**Two easy-to-get-wrong details, both covered by tests below:**
1. `/category` path segments have a **fixed order**: `list` → `tags` → `finish` → `order` → `page`. Emitting them in filter-map order breaks the site.
2. Search pagination uses a **bare numeric segment**: `/search/<enc>/2`. Writing `/search/<enc>/page/2` silently returns page 1 — a bug that looks like "search only ever has one page".

- [ ] **Step 1: Write the failing test**

Append this to `test/data/sources/manga51_test.dart`, inside `void main() { ... }`, after the existing `group('aesDecryptBase64PrefixedIv', ...)` block:

```dart
  group('Manga51 metadata', () {
    final source = Manga51();

    test('identity getters', () {
      expect(source.id, 'manga51');
      expect(source.name, '51漫画');
      expect(source.shortName, '51漫');
      expect(source.score, 4.0);
      expect(source.href, 'https://www.51manga.com');
    });

    test('flags', () {
      expect(source.isAdult, isTrue);
      expect(source.needsProxy, isFalse);
      expect(source.needsCloudflare, isFalse);
      expect(source.disabled, isFalse);
      expect(source.firstPage, 1);
    });

    test('sends a mobile UA and a PC-host Referer', () {
      expect(source.userAgent, contains('iPhone'));
      expect(source.defaultHeaders?['Referer'], 'https://www.51manga.com/');
    });

    test('exposes the four discovery filters in order', () {
      expect(
        source.discoveryFilters.map((f) => f.name).toList(),
        ['list', 'tags', 'finish', 'order'],
      );
      expect(source.searchFilters, isEmpty);
    });

    test('tag filter labels are unique (site duplicates id 872/873 as 恋爱)', () {
      final tags = source.discoveryFilters.firstWhere((f) => f.name == 'tags');
      final labels = tags.choices.map((c) => c.label).toList();
      expect(labels.toSet().length, labels.length,
          reason: 'duplicate labels would render two identical dropdown rows');
      expect(tags.choices.map((c) => c.value), isNot(contains('873')));
    });
  });

  group('Manga51 request builders', () {
    final source = Manga51();

    test('prepareDiscoveryFetch with no filters', () {
      expect(
        source.prepareDiscoveryFetch(1, {}).url,
        'https://m.51manga.com/category/page/1',
      );
    });

    test('prepareDiscoveryFetch emits segments in the site order', () {
      // Deliberately insert the map keys out of order to prove the builder
      // does not depend on map iteration order.
      final config = source.prepareDiscoveryFetch(3, {
        'order': 'hits',
        'finish': '2',
        'list': '1',
        'tags': '889',
      });
      expect(
        config.url,
        'https://m.51manga.com/category/list/1/tags/889/finish/2/order/hits/page/3',
      );
    });

    test('prepareDiscoveryFetch skips empty filter values', () {
      expect(
        source.prepareDiscoveryFetch(2, {'list': '', 'tags': '870', 'order': ''}).url,
        'https://m.51manga.com/category/tags/870/page/2',
      );
    });

    test('prepareSearchFetch page 1 has no trailing page segment', () {
      final url = source.prepareSearchFetch('妹妹', 1, {}).url;
      expect(url, 'https://m.51manga.com/search/%E5%A6%B9%E5%A6%B9');
    });

    test('prepareSearchFetch page 2 uses a bare number, never /page/', () {
      final url = source.prepareSearchFetch('妹妹', 2, {}).url;
      expect(url, 'https://m.51manga.com/search/%E5%A6%B9%E5%A6%B9/2');
      expect(url, isNot(contains('/page/')),
          reason: '/page/N silently returns page 1 on this site');
    });

    test('prepareMangaInfoFetch', () {
      expect(
        source.prepareMangaInfoFetch('4aNek4246W').url,
        'https://m.51manga.com/mh/4aNek4246W',
      );
    });

    test('prepareChapterListFetch is null (chapters ship with the info page)', () {
      expect(source.prepareChapterListFetch('4aNek4246W', 1), isNull);
    });

    test('prepareChapterFetch uses the mobile host', () {
      expect(
        source.prepareChapterFetch('4aNek4246W', 'Vd3Q3uKzVB', 1).url,
        'https://m.51manga.com/show/Vd3Q3uKzVB.html',
      );
    });

    test('getChapterWebUrl uses the PC host for in-browser reading', () {
      expect(
        source.getChapterWebUrl('4aNek4246W', 'Vd3Q3uKzVB'),
        'https://www.51manga.com/show/Vd3Q3uKzVB.html',
      );
    });
  });
```

And add this import to the top of the test file, below the existing imports:

```dart
import 'package:comic_reader/data/sources/manga51.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/sources/manga51_test.dart
```

Expected: compile failure — `Target of URI doesn't exist: 'package:comic_reader/data/sources/manga51.dart'`.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/data/sources/manga51.dart`:

```dart
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// 51漫画 (51manga.com) — an MCCMS-based site, same engine family as
/// [HaokanManhua] but with a different template and, crucially, AES-encrypted
/// chapter image lists.
///
/// All requests go to the MOBILE host `m.51manga.com`:
///  * the PC search template is broken (always 0 results),
///  * mobile manga/chapter ids and paths are identical to PC,
///  * the mobile detail page ships the ENTIRE chapter list in one response.
class Manga51 extends MangaSource {
  static const String sourceId = 'manga51';

  /// Host used for every request.
  static const String _baseUrl = 'https://m.51manga.com';

  /// Host used for the anti-hotlink Referer and for opening pages in a browser.
  static const String _pcBaseUrl = 'https://www.51manga.com';

  /// Image CDN. Only used as a prefix for relative paths; the decrypted
  /// payload normally contains absolute URLs.
  static const String _imageCdn = 'https://img1.baipiaoguai.org';

  /// AES-128 key from `/template/pc/51manga/js/pic-v3.js`.
  /// Raw string literal because it contains a `$`.
  static const String _picKey = r'9S8$vJnU2ANeSRoF';

  static const String _mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  @override
  String get id => sourceId;

  @override
  String get name => '51漫画';

  @override
  String get shortName => '51漫';

  @override
  String? get description => 'MCCMS 漫画站，章节图片 AES 加密';

  @override
  double get score => 4.0;

  @override
  String? get href => _pcBaseUrl;

  @override
  bool get isAdult => true;

  @override
  bool get needsProxy => false;

  @override
  String? get userAgent => _mobileUa;

  @override
  Map<String, String>? get defaultHeaders => const {'Referer': '$_pcBaseUrl/'};

  /// Headers required by `img1.baipiaoguai.org`, which returns 403 without a
  /// Referer. Attached to covers AND chapter images.
  static const Map<String, String> _imageHeaders = {
    'Referer': '$_pcBaseUrl/',
    'User-Agent': _mobileUa,
  };

  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'list',
          label: '类型',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '国产漫画', value: '1'),
            FilterChoice(label: '日本漫画', value: '2'),
            FilterChoice(label: '韩国漫画', value: '3'),
            FilterChoice(label: '欧美漫画', value: '4'),
          ],
        ),
        FilterOption(
          name: 'tags',
          label: '题材',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '科幻', value: '867'),
            FilterChoice(label: '后宫', value: '868'),
            FilterChoice(label: '机甲', value: '869'),
            FilterChoice(label: '都市', value: '870'),
            FilterChoice(label: '恋爱生活', value: '871'),
            // Site has both 872 and 873 labelled 恋爱; 873 is dropped so the
            // dropdown does not show two identical rows.
            FilterChoice(label: '恋爱', value: '872'),
            FilterChoice(label: '其他', value: '874'),
            FilterChoice(label: '推理悬疑', value: '875'),
            FilterChoice(label: '魔法', value: '876'),
            FilterChoice(label: '奇幻', value: '877'),
            FilterChoice(label: '异世界', value: '878'),
            FilterChoice(label: '滑稽搞笑', value: '879'),
            FilterChoice(label: '重生', value: '880'),
            FilterChoice(label: '励志', value: '881'),
            FilterChoice(label: '浪漫', value: '882'),
            FilterChoice(label: '逆袭', value: '883'),
            FilterChoice(label: '脑洞', value: '884'),
            FilterChoice(label: '日常', value: '885'),
            FilterChoice(label: '热血机战', value: '886'),
            FilterChoice(label: '魔法/奇幻', value: '887'),
            FilterChoice(label: '武侠经典', value: '888'),
            FilterChoice(label: '韩漫', value: '889'),
            FilterChoice(label: '小说改编', value: '890'),
            FilterChoice(label: '穿越', value: '891'),
            FilterChoice(label: '非现代', value: '892'),
            FilterChoice(label: '大女主', value: '893'),
            FilterChoice(label: '腹黑', value: '894'),
            FilterChoice(label: '校园', value: '895'),
            FilterChoice(label: '剧情', value: '896'),
          ],
        ),
        FilterOption(
          name: 'finish',
          label: '状态',
          defaultValue: '',
          choices: [
            FilterChoice(label: '全部', value: ''),
            FilterChoice(label: '连载中', value: '1'),
            FilterChoice(label: '已完结', value: '2'),
          ],
        ),
        FilterOption(
          name: 'order',
          label: '排序',
          defaultValue: 'hits',
          choices: [
            FilterChoice(label: '热门', value: 'hits'),
            FilterChoice(label: '最新', value: 'addtime'),
          ],
        ),
      ];

  // --- Discovery ---
  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    // Segment order is fixed by the site: list -> tags -> finish -> order -> page.
    final buffer = StringBuffer('$_baseUrl/category');
    for (final key in const ['list', 'tags', 'finish', 'order']) {
      final value = filters[key] ?? '';
      if (value.isNotEmpty) buffer.write('/$key/$value');
    }
    buffer.write('/page/$page');
    return FetchConfig(url: buffer.toString());
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    throw UnimplementedError();
  }

  // --- Search ---
  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    // Pagination is a BARE numeric segment. `/page/$page` silently returns
    // page 1 on this site.
    final base = '$_baseUrl/search/${Uri.encodeComponent(keyword)}';
    return FetchConfig(url: page <= 1 ? base : '$base/$page');
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    throw UnimplementedError();
  }

  // --- Manga Info ---
  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    return FetchConfig(url: '$_baseUrl/mh/$mangaId');
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    throw UnimplementedError();
  }

  // --- Chapter List (embedded in the info page) ---
  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) => null;

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    return const ChapterListResult(chapters: []);
  }

  // --- Chapter Content ---
  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    // chapterId is globally unique; mangaId is intentionally unused.
    return FetchConfig(url: '$_baseUrl/show/$chapterId.html');
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    throw UnimplementedError();
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    // PC layout reads better in a real browser.
    return '$_pcBaseUrl/show/$chapterId.html';
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/data/sources/manga51_test.dart
```

Expected: `All tests passed!` (15 tests). If `_imageHeaders` is reported as unused, that is expected until Task 3 — but it is referenced by `const` so analyze will not flag it; if analyze does complain, proceed to Task 3 rather than deleting it.

- [ ] **Step 5: Static check**

```bash
flutter analyze lib/data/sources/manga51.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/sources/manga51.dart test/data/sources/manga51_test.dart
git commit -m "feat: add Manga51 source skeleton with metadata, filters and URL builders"
```

---

### Task 3: Listing card parsing (`parseDiscovery` / `parseSearch`)

**Files:**
- Modify: `lib/data/sources/manga51.dart`
- Test: `test/data/sources/manga51_test.dart` (append)

`/category` and `/search` render the same card markup, so one private `_parseCards` serves both. Real markup (verified live):

```html
<div class="comic-item">
  <a href="/mh/5p6pyYRwZr">
    <div class="pic">
      <img src="https://www.51manga.com/packs/mccms/empty.png" alt="标题">
      <div class="mask">完结</div>
    </div>
    <div class="field-info">
      <h3 class="title">标题</h3>
      <div class="txt">待浏览</div>
    </div>
  </a>
</div>
```

`div.mask` (完结 / 连载) is deliberately **not** used: `MangaSummary` has no status field.

- [ ] **Step 1: Write the failing test**

Append inside `void main()`:

```dart
  group('Manga51 card parsing', () {
    final source = Manga51();

    const listHtml = '''
<div id="comic-list">
  <div class="comic-item">
    <a href="/mh/4aNek4246W">
      <div class="pic">
        <img src="https://img1.baipiaoguai.org/static/upload3/book/id/520879/cover_1.jpg?v=1" alt="溯古之黄鹤楼">
        <div class="mask">已完结</div>
      </div>
      <div class="field-info">
        <h3 class="title">溯古之黄鹤楼</h3>
        <div class="txt">最终章 释然</div>
      </div>
    </a>
  </div>
  <div class="comic-item">
    <a href="/mh/r368n70WNX">
      <div class="pic">
        <img data-src="https://img1.baipiaoguai.org/lazy.jpg" src="/packs/mccms/empty.png" alt="魔皇大管家">
        <div class="mask">连载</div>
      </div>
      <div class="field-info">
        <h3 class="title">魔皇大管家</h3>
        <div class="txt">第916话</div>
      </div>
    </a>
  </div>
  <div class="comic-item">
    <a href="/redirect/code/toP0LT"><div class="pic"><img src="x.jpg"></div></a>
  </div>
</div>
''';

    test('parseDiscovery extracts id, title, cover and latest chapter', () {
      final results = source.parseDiscovery(listHtml);
      expect(results, hasLength(2), reason: 'the non-/mh/ card must be skipped');

      expect(results[0].id, '4aNek4246W');
      expect(results[0].sourceId, 'manga51');
      expect(results[0].title, '溯古之黄鹤楼');
      expect(
        results[0].coverUrl,
        'https://img1.baipiaoguai.org/static/upload3/book/id/520879/cover_1.jpg?v=1',
      );
      expect(results[0].latestChapter, '最终章 释然');
    });

    test('parseDiscovery prefers data-src over the src placeholder', () {
      final results = source.parseDiscovery(listHtml);
      expect(results[1].coverUrl, 'https://img1.baipiaoguai.org/lazy.jpg');
    });

    test('every summary carries the anti-hotlink headers', () {
      for (final s in source.parseDiscovery(listHtml)) {
        expect(s.headers?['Referer'], 'https://www.51manga.com/');
        expect(s.headers?['User-Agent'], contains('iPhone'));
      }
    });

    test('parseSearch uses the same card parser', () {
      final results = source.parseSearch(listHtml);
      expect(results.map((s) => s.id).toList(), ['4aNek4246W', 'r368n70WNX']);
    });

    test('parseDiscovery returns empty on unrelated HTML', () {
      expect(source.parseDiscovery('<html><body>nope</body></html>'), isEmpty);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/sources/manga51_test.dart --plain-name 'Manga51 card parsing'
```

Expected: 5 failures, each `UnimplementedError`.

- [ ] **Step 3: Write the minimal implementation**

In `lib/data/sources/manga51.dart`, add these imports at the very top, above the existing `package:comic_reader/...` imports:

```dart
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
```

Replace the `parseDiscovery` stub:

```dart
  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    throw UnimplementedError();
  }
```

with:

```dart
  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseCards(response as String);
  }
```

Replace the `parseSearch` stub:

```dart
  @override
  List<MangaSummary> parseSearch(dynamic response) {
    throw UnimplementedError();
  }
```

with:

```dart
  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseCards(response as String);
  }
```

Then add these private helpers just before the final closing brace of the class:

```dart
  // --- Private helpers ---

  static final RegExp _mangaIdPattern = RegExp(r'/mh/([A-Za-z0-9]+)');
  static final RegExp _chapterIdPattern = RegExp(r'/show/([A-Za-z0-9]+)\.html');
  static final RegExp _whitespacePattern = RegExp(r'\s+');

  /// Parse `.comic-item` cards, shared by /category and /search.
  ///
  /// `div.mask` (已完结 / 连载) is intentionally ignored: MangaSummary has no
  /// status field, so status is surfaced only on the detail page.
  List<MangaSummary> _parseCards(String htmlStr) {
    final document = html_parser.parse(htmlStr);
    final results = <MangaSummary>[];

    for (final item in document.querySelectorAll('div.comic-item')) {
      final href = item.querySelector('a')?.attributes['href'] ?? '';
      final mangaId = _mangaIdPattern.firstMatch(href)?.group(1);
      // Cards without a /mh/ target are ads or app-download promos.
      if (mangaId == null) continue;

      final img = item.querySelector('div.pic img');
      final cover =
          img?.attributes['data-src'] ?? img?.attributes['src'] ?? '';

      final title = _cleanText(item.querySelector('h3.title')?.text) ??
          _cleanText(img?.attributes['alt']) ??
          '';

      results.add(MangaSummary(
        id: mangaId,
        sourceId: sourceId,
        title: title,
        coverUrl: cover,
        latestChapter: _cleanText(item.querySelector('div.field-info .txt')?.text),
        headers: _imageHeaders,
      ));
    }

    return results;
  }

  /// Trim, collapse internal whitespace, drop nbsp. Returns null when empty.
  String? _cleanText(String? raw) {
    if (raw == null) return null;
    final cleaned =
        raw.replaceAll('\u00a0', ' ').replaceAll(_whitespacePattern, ' ').trim();
    return cleaned.isEmpty ? null : cleaned;
  }
```

Note: `Document` from `package:html/dom.dart` is needed by Task 4; the import is added now and will be used there. If `flutter analyze` flags `dom.dart` as an unused import at this step, leave the import out for now and add it in Task 4 instead.

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/data/sources/manga51_test.dart
```

Expected: `All tests passed!` (20 tests).

- [ ] **Step 5: Static check**

```bash
flutter analyze lib/data/sources/manga51.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/sources/manga51.dart test/data/sources/manga51_test.dart
git commit -m "feat: parse 51manga discovery and search listing cards"
```

---

### Task 4: Detail page parsing (`parseMangaInfo`)

**Files:**
- Modify: `lib/data/sources/manga51.dart`
- Test: `test/data/sources/manga51_test.dart` (append)

Verified selectors on `m.51manga.com/mh/<ID>`:

| Field | Selector |
|---|---|
| title | `h1.name`, fallback `header .title h2` |
| cover | `div.comic_cover` attribute `style="background-image: url('URL');"` |
| author | `div.comic_hot` text (strip the inner `<i>` icon) |
| tags | `span.tags_last.diy_tags a[href^="/category/tags/"]` |
| latest chapter | `div.zuixin p`, strip the `最新话：` prefix |
| update time | `div.zuixin time` |
| description | the **last** `<p>` inside `div.metas-desc` |
| chapters | `ul.chapter-list > li > a[href^="/show/"]` |

Two traps:
1. `div.metas-desc` contains a decoy `div.download-app > p` whose text is `下载APP，免费看更多精彩漫画`. Taking the first `<p>` yields the ad. The implementation removes `.download-app` before reading, and a test asserts the ad text never becomes the description.
2. There is no status field on the mobile detail page. Status is inferred from tag text (`已完结`/`完结` → completed, `连载` → ongoing, else unknown).

Chapters are complete on this single page (verified 916 chapters for `r368n70WNX`) and are in **ascending** order.

- [ ] **Step 1: Write the failing test**

Append inside `void main()`:

```dart
  group('Manga51 detail parsing', () {
    final source = Manga51();

    const detailHtml = '''
<html><body>
<header><div class="title"><h2>头部标题</h2></div></header>
<div class="comic_cover" style="background-image: url('https://img1.baipiaoguai.org/static/upload3/book/id/520879/cover_1.jpg?v=1786032820'); display: block;"></div>
<div class="mask"></div>
<h1 class="name">溯古之黄鹤楼</h1>
<span class="tags_last diy_tags" style="color: #fff;">
  <a target="_blank" href="/category/tags/1025">已完结</a>
  <a target="_blank" href="/category/tags/2843">国漫</a>
  <a target="_blank" href="/category/tags/2593">古风</a>
</span>
<div class="comic_hot"><i class="iconfont icon-myfill"></i>剧象漫画</div>
<div class="zuixin">
  <p>最新话：最终章 释然</p>
  <time>2026-08-08 01:26</time>
</div>
<div class="metas-desc">
  <div class="download-app">
    <p>下载APP，免费看更多精彩漫画</p>
    <a href="/redirect/code/toP0LT" target="_blank">立即下载</a>
  </div>
  <p>北宋年间，吕洞宾于黄鹤楼修行之时，点化费祎用橘皮化作的黄鹤。</p>
</div>
<ul class="chapter-list" style="max-height: 100%;">
  <li data-chapter_id="1"><i></i><a href="/show/ARkjkt1m3D.html">预告：2月16日上线</a><span>08-08</span></li>
  <li data-chapter_id="2"><i></i><a href="/show/Vd3Q3uKzVB.html">第1-2话 初遇</a><span>08-08</span></li>
  <li data-chapter_id="3"><i></i><a href="javascript:void(0);">占位</a></li>
</ul>
</body></html>
''';

    test('extracts the scalar fields', () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.id, '4aNek4246W');
      expect(detail.sourceId, 'manga51');
      expect(detail.title, '溯古之黄鹤楼');
      expect(
        detail.coverUrl,
        'https://img1.baipiaoguai.org/static/upload3/book/id/520879/cover_1.jpg?v=1786032820',
      );
      expect(detail.author, '剧象漫画');
      expect(detail.latestChapter, '最终章 释然');
      expect(detail.updateTime, '2026-08-08 01:26');
      expect(detail.headers?['Referer'], 'https://www.51manga.com/');
    });

    test('description skips the download-app decoy paragraph', () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.description, startsWith('北宋年间'));
      expect(detail.description, isNot(contains('下载APP')));
    });

    test('extracts tags and infers completed status from them', () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.tags, ['已完结', '国漫', '古风']);
      expect(detail.status, MangaStatus.completed);
    });

    test('infers ongoing status from a 连载 tag', () {
      final html = detailHtml.replaceFirst(
        '<a target="_blank" href="/category/tags/1025">已完结</a>',
        '<a target="_blank" href="/category/tags/1024">连载中</a>',
      );
      expect(source.parseMangaInfo(html, 'x').status, MangaStatus.ongoing);
    });

    test('status is unknown when no tag mentions it', () {
      const html = '<h1 class="name">T</h1>'
          '<span class="tags_last diy_tags"><a href="/category/tags/1">古风</a></span>';
      expect(source.parseMangaInfo(html, 'x').status, MangaStatus.unknown);
    });

    test('extracts the full ascending chapter list, skipping non-/show/ rows', () {
      final detail = source.parseMangaInfo(detailHtml, '4aNek4246W');
      expect(detail.chapters, hasLength(2));

      expect(detail.chapters.first.id, 'ARkjkt1m3D');
      expect(detail.chapters.first.mangaId, '4aNek4246W');
      expect(detail.chapters.first.title, '预告：2月16日上线');
      expect(detail.chapters.first.href,
          'https://www.51manga.com/show/ARkjkt1m3D.html');

      expect(detail.chapters.last.id, 'Vd3Q3uKzVB');
      expect(detail.chapters.last.title, '第1-2话 初遇');
    });

    test('falls back to the header title when h1.name is absent', () {
      const html = '<header><div class="title"><h2>兜底标题</h2></div></header>';
      expect(source.parseMangaInfo(html, 'x').title, '兜底标题');
    });

    test('throws on the deleted-manga page instead of returning an empty shell', () {
      const html =
          '<html><body>很遗憾，该漫画不存在或章节已被删除。</body></html>';
      expect(
        () => source.parseMangaInfo(html, 'deadid'),
        throwsA(isA<Exception>()),
      );
    });

    test('description is null when metas-desc has no real paragraph', () {
      const html = '<h1 class="name">T</h1>'
          '<div class="metas-desc"><div class="download-app"><p>下载APP，免费看更多精彩漫画</p></div></div>';
      expect(source.parseMangaInfo(html, 'x').description, isNull);
    });

    test('parseChapterList always returns an empty result', () {
      expect(source.parseChapterList(detailHtml, '4aNek4246W').chapters, isEmpty);
      expect(source.parseChapterList(detailHtml, '4aNek4246W').canLoadMore, isFalse);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/sources/manga51_test.dart --plain-name 'Manga51 detail parsing'
```

Expected: 9 failures with `UnimplementedError` (the `parseChapterList` test already passes).

- [ ] **Step 3: Write the minimal implementation**

Replace the `parseMangaInfo` stub:

```dart
  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    throw UnimplementedError();
  }
```

with:

```dart
  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final htmlStr = response as String;
    final document = html_parser.parse(htmlStr);

    final title = _cleanText(document.querySelector('h1.name')?.text) ??
        _cleanText(document.querySelector('header .title h2')?.text) ??
        '';
    if (title.isEmpty) {
      // Deleted/missing manga serves a ~259 byte stub page.
      throw Exception('51manga: 该漫画不存在或已被删除 (mangaId=$mangaId)');
    }

    final tags = <String>[];
    for (final a in document
        .querySelectorAll('span.tags_last a[href^="/category/tags/"]')) {
      final text = _cleanText(a.text);
      if (text != null) tags.add(text);
    }

    final zuixin = document.querySelector('div.zuixin');
    final latestChapter = _cleanText(zuixin?.querySelector('p')?.text)
        ?.replaceFirst(RegExp(r'^最新话[:：]\s*'), '');

    final chapters = <ChapterItem>[];
    for (final a in document.querySelectorAll('ul.chapter-list li a')) {
      final chapterId =
          _chapterIdPattern.firstMatch(a.attributes['href'] ?? '')?.group(1);
      if (chapterId == null) continue;
      chapters.add(ChapterItem(
        id: chapterId,
        mangaId: mangaId,
        title: _cleanText(a.text) ?? chapterId,
        href: '$_pcBaseUrl/show/$chapterId.html',
      ));
    }

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: _extractCoverUrl(document) ?? '',
      description: _extractDescription(document),
      author: _cleanText(document.querySelector('div.comic_hot')?.text) ?? '',
      tags: tags,
      status: _statusFromTags(tags),
      latestChapter:
          (latestChapter != null && latestChapter.isEmpty) ? null : latestChapter,
      updateTime: _cleanText(zuixin?.querySelector('time')?.text),
      chapters: chapters,
      headers: _imageHeaders,
    );
  }
```

Then add these helpers next to `_parseCards` (before the class's closing brace):

```dart
  static final RegExp _coverUrlPattern =
      RegExp(r'''background-image:\s*url\(\s*['"]?(.*?)['"]?\s*\)''');

  /// Cover lives in an inline style: `background-image: url('...')`.
  String? _extractCoverUrl(Document document) {
    final style =
        document.querySelector('div.comic_cover')?.attributes['style'] ?? '';
    final url = _coverUrlPattern.firstMatch(style)?.group(1);
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// `div.metas-desc` also contains a `div.download-app > p` advert. Drop that
  /// subtree first, then take the last remaining paragraph.
  String? _extractDescription(Document document) {
    final container = document.querySelector('div.metas-desc');
    if (container == null) return null;
    for (final ad in container.querySelectorAll('.download-app')) {
      ad.remove();
    }
    final paragraphs = container.querySelectorAll('p');
    if (paragraphs.isEmpty) return null;
    return _cleanText(paragraphs.last.text);
  }

  /// The mobile detail page has no status field; infer it from the tag texts.
  MangaStatus _statusFromTags(List<String> tags) {
    for (final tag in tags) {
      if (tag.contains('完结')) return MangaStatus.completed;
      if (tag.contains('连载')) return MangaStatus.ongoing;
    }
    return MangaStatus.unknown;
  }
```

If Task 3 skipped the `package:html/dom.dart` import, add it now — `Document` is used above.

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/data/sources/manga51_test.dart
```

Expected: `All tests passed!` (30 tests).

- [ ] **Step 5: Static check**

```bash
flutter analyze lib/data/sources/manga51.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/sources/manga51.dart test/data/sources/manga51_test.dart
git commit -m "feat: parse 51manga detail page including embedded chapter list"
```

---

### Task 5: Chapter image decryption (`parseChapter`)

**Files:**
- Modify: `lib/data/sources/manga51.dart`
- Test: `test/data/sources/manga51_test.dart` (append)

The chapter page's `<div id="pic-list">` is an empty container. The real image array is in an inline script:

```html
<script>var tpl_path = '/template/wap/51manga/', params = '<BASE64>';</script>
```

Decrypting `params` with `aesDecryptBase64PrefixedIv(params, _picKey)` yields JSON:

```json
{"host":"www.51manga.com","source_id":"12","comic_id":"618431","comic_down":0,
 "chapter_id":"223165","images":["https://img1.baipiaoguai.org/..."],"lazy":false}
```

`pic-v3.js` prefixes non-`http` image paths with `https://img1.baipiaoguai.org`; replicate that as a fallback.

The test payload below was generated offline with the **real** key `9S8$vJnU2ANeSRoF` and IV `0123456789abcdef`, so a wrong key or wrong IV handling fails the test. Its `images` array intentionally mixes an absolute URL, a leading-slash relative path, and a bare relative path.

- [ ] **Step 1: Write the failing test**

Append inside `void main()`:

```dart
  group('Manga51 chapter parsing', () {
    final source = Manga51();

    /// Base64 of `IV || AES-128-CBC(PKCS7)` built offline with the real key
    /// `9S8$vJnU2ANeSRoF` and IV `0123456789abcdef`. Plaintext:
    /// {"host":"www.51manga.com","source_id":"12","comic_id":"618431",
    ///  "comic_down":0,"chapter_id":"223165","images":[
    ///    "https://img1.baipiaoguai.org/static/upload3/book/id/1/a.webp",
    ///    "/static/upload3/book/id/1/b.webp",
    ///    "static/upload3/book/id/1/c.webp"],"lazy":false}
    const params =
        'MDEyMzQ1Njc4OWFiY2RlZoJEmtpzKW14ZWHmM1m0alUjXyRvoUP2OgS3xi55GP0dDMqJ'
        'D56Gixfv9pBhogV9slaJqVOKl+lzwk0IIzeYFccF5vpjRO1EbofHrMSy0iCcQ0e2WH6W'
        'eRDxbJjZ80tD/sQjfXc0jXZMBU+O9J0AYlJind9LaCFo3f1yPkrUTNX/N02+m7dOxgJU'
        'GEM0VqOLpXAGdQMO4yZiIYek67LhZJZYPTeAtVqB6+zNnRsQz9w4/DtLZ9/w1ek7mUSp'
        'TsilECJi2yRy7mXvhLQhSWqmP8hDu2gxSuAtQw2OPsuDRPEqqpnM9u7Ax2XNB1kzpAt5'
        'mM/sTnwPTigPfJ/dvi4I8IgWc3trypbEwQpvYk5ogZvj';

    const chapterHtml = '''
<html><body>
<header class="x"><div class="title"><h2>第1-2话 初遇</h2></div></header>
<div class="back"><a href="/mh/4aNek4246W">返回</a></div>
<div class="img-box" id="pic-list"></div>
<div class="diy_btn"><a href="/show/ARkjkt1m3D.html">下一话</a></div>
<script>var tpl_path = '/template/wap/51manga/', params = '$params';</script>
</body></html>
''';

    test('decrypts params into the image list', () {
      final result = source.parseChapter(
          chapterHtml, '4aNek4246W', 'Vd3Q3uKzVB', 1);

      expect(result.chapter.id, 'Vd3Q3uKzVB');
      expect(result.chapter.mangaId, '4aNek4246W');
      expect(result.chapter.title, '第1-2话 初遇');
      expect(result.canLoadMore, isFalse);
      expect(result.chapter.images, hasLength(3));
    });

    test('absolute URLs pass through and relative paths get the CDN prefix', () {
      final result = source.parseChapter(
          chapterHtml, '4aNek4246W', 'Vd3Q3uKzVB', 1);

      expect(result.chapter.images.map((i) => i.url).toList(), [
        'https://img1.baipiaoguai.org/static/upload3/book/id/1/a.webp',
        'https://img1.baipiaoguai.org/static/upload3/book/id/1/b.webp',
        'https://img1.baipiaoguai.org/static/upload3/book/id/1/c.webp',
      ]);
    });

    test('every image carries the anti-hotlink headers', () {
      final result = source.parseChapter(
          chapterHtml, '4aNek4246W', 'Vd3Q3uKzVB', 1);
      for (final image in result.chapter.images) {
        expect(image.headers?['Referer'], 'https://www.51manga.com/');
        expect(image.headers?['User-Agent'], contains('iPhone'));
        expect(image.scrambleType, ScrambleType.none);
      }
    });

    test('falls back to chapterId when the title element is missing', () {
      final html = chapterHtml.replaceFirst(
          '<h2>第1-2话 初遇</h2>', '<h2></h2>');
      final result = source.parseChapter(html, '4aNek4246W', 'Vd3Q3uKzVB', 1);
      expect(result.chapter.title, 'Vd3Q3uKzVB');
    });

    test('throws when params is absent instead of returning zero images', () {
      const html = '<html><body><div id="pic-list"></div></body></html>';
      expect(
        () => source.parseChapter(html, '4aNek4246W', 'Vd3Q3uKzVB', 1),
        throwsA(isA<Exception>()),
      );
    });

    test('throws with the chapterId in the message when decryption fails', () {
      const html =
          "<script>var params = 'bm90LWEtdmFsaWQtcGF5bG9hZC1hdC1hbGwtcmVhbGx5';</script>";
      expect(
        () => source.parseChapter(html, '4aNek4246W', 'BADCHAP', 1),
        throwsA(predicate((e) => e.toString().contains('BADCHAP'))),
      );
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/data/sources/manga51_test.dart --plain-name 'Manga51 chapter parsing'
```

Expected: 6 failures with `UnimplementedError`.

- [ ] **Step 3: Write the minimal implementation**

Add `dart:convert` as the first import of `lib/data/sources/manga51.dart`:

```dart
import 'dart:convert';
```

Add the crypto helper import alongside the other `package:comic_reader/...` imports:

```dart
import 'package:comic_reader/core/utils/crypto_utils.dart';
```

Replace the `parseChapter` stub:

```dart
  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    throw UnimplementedError();
  }
```

with:

```dart
  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final htmlStr = response as String;

    final payload = _paramsPattern.firstMatch(htmlStr)?.group(1);
    if (payload == null || payload.isEmpty) {
      throw Exception('51manga: 未找到章节图片数据 (chapterId=$chapterId)');
    }

    final List<dynamic> rawImages;
    try {
      final decoded = json.decode(aesDecryptBase64PrefixedIv(payload, _picKey));
      rawImages = (decoded is Map && decoded['images'] is List)
          ? decoded['images'] as List
          : const [];
    } catch (e) {
      // Surface a key rotation / template change loudly rather than showing
      // an empty chapter.
      throw Exception('51manga: 章节图片解密失败 (chapterId=$chapterId): $e');
    }

    final images = <ChapterImage>[];
    for (final raw in rawImages) {
      if (raw is! String || raw.isEmpty) continue;
      images.add(ChapterImage(
        url: _absoluteImageUrl(raw),
        headers: _imageHeaders,
      ));
    }

    final document = html_parser.parse(htmlStr);
    final title =
        _cleanText(document.querySelector('header .title h2')?.text) ?? chapterId;

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
```

Then add these next to the other private helpers:

```dart
  static final RegExp _paramsPattern = RegExp(r"""params\s*=\s*'([^']+)'""");

  /// Mirrors pic-v3.js: non-`http` paths are relative to the image CDN.
  String _absoluteImageUrl(String raw) {
    if (raw.startsWith('http')) return raw;
    return raw.startsWith('/') ? '$_imageCdn$raw' : '$_imageCdn/$raw';
  }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/data/sources/manga51_test.dart
```

Expected: `All tests passed!` (36 tests).

- [ ] **Step 5: Static check**

```bash
flutter analyze lib/data/sources/manga51.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/sources/manga51.dart test/data/sources/manga51_test.dart
git commit -m "feat: decrypt 51manga chapter image payload"
```

---

### Task 6: Register the source and verify end to end

**Files:**
- Modify: `lib/app/di/injection.dart` (import near line 42, register near line 201)

- [ ] **Step 1: Add the import**

In `lib/app/di/injection.dart`, find this line (line 42):

```dart
import 'package:comic_reader/data/sources/bazuo.dart';
```

Add immediately after it:

```dart
import 'package:comic_reader/data/sources/manga51.dart';
```

- [ ] **Step 2: Add the registration**

In the same file, find the last line of the register block (line 201):

```dart
  registry.register(Bazuo());
```

Add immediately after it:

```dart
  registry.register(Manga51());
```

- [ ] **Step 3: Full static check**

```bash
flutter analyze lib/data/sources/manga51.dart lib/core/utils/crypto_utils.dart lib/app/di/injection.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Run the unit tests**

```bash
flutter test test/data/sources/manga51_test.dart
```

Expected: `All tests passed!` (36 tests).

Do NOT run `flutter test` over the whole repo: this repo contains live-network scripts under `test/` and a `test/widget_test.dart` that is already failing for unrelated reasons.

- [ ] **Step 5: Live end-to-end verification (throwaway, not committed)**

Write this to `/tmp/verify_manga51.dart` (outside the repo so it is never committed):

```dart
// Throwaway live-network check. Run: dart run /tmp/verify_manga51.dart
import 'dart:io';

import 'package:comic_reader/data/sources/manga51.dart';

const ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
    'Mobile/15E148 Safari/604.1';

Future<String> get(String url, {Map<String, String> headers = const {}}) async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('User-Agent', ua);
  request.headers.set('Referer', 'https://www.51manga.com/');
  headers.forEach(request.headers.set);
  final response = await request.close();
  final body = await response.transform(SystemEncoding().decoder).join();
  client.close();
  if (response.statusCode != 200) {
    throw 'HTTP ${response.statusCode} for $url';
  }
  return body;
}

Future<void> main() async {
  final source = Manga51();

  final discovery = source
      .parseDiscovery(await get(source.prepareDiscoveryFetch(1, {}).url));
  print('discovery: ${discovery.length} items, first=${discovery.first.title}');
  if (discovery.isEmpty) throw 'discovery empty';

  final search = source
      .parseSearch(await get(source.prepareSearchFetch('妹妹', 2, {}).url));
  print('search p2: ${search.length} items, first=${search.first.title}');
  if (search.isEmpty) throw 'search empty';

  final mangaId = discovery.first.id;
  final detail = source.parseMangaInfo(
      await get(source.prepareMangaInfoFetch(mangaId).url), mangaId);
  print('detail: ${detail.title} / ${detail.chapters.length} chapters '
      '/ status=${detail.status} / desc=${detail.description?.substring(0, 20)}');
  if (detail.chapters.isEmpty) throw 'no chapters';

  final chapterId = detail.chapters.last.id;
  final chapter = source.parseChapter(
      await get(source.prepareChapterFetch(mangaId, chapterId, 1).url),
      mangaId,
      chapterId,
      1);
  print('chapter: ${chapter.chapter.title} / '
      '${chapter.chapter.images.length} images');
  if (chapter.chapter.images.isEmpty) throw 'no images';

  final first = chapter.chapter.images.first;
  print('first image: ${first.url}');
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(first.url));
  first.headers?.forEach(request.headers.set);
  final response = await request.close();
  final bytes = await response.fold<int>(0, (n, c) => n + c.length);
  client.close();
  print('image HTTP ${response.statusCode} '
      '${response.headers.contentType} $bytes bytes');
  if (response.statusCode != 200) throw 'image fetch failed';
  if (!'${response.headers.contentType}'.startsWith('image/')) {
    throw 'not an image';
  }
  print('OK');
}
```

Run it from the repo root:

```bash
cd /Users/achui/project/comic-reader && dart run /tmp/verify_manga51.dart
```

Expected final line: `OK`, with a nonzero image byte count and `content-type` starting with `image/`.

If the image step returns 403, the anti-hotlink headers are not reaching the request — recheck `_imageHeaders` is passed to every `ChapterImage`.

- [ ] **Step 6: Commit**

```bash
git add lib/app/di/injection.dart
git commit -m "feat: register 51manga source"
```

- [ ] **Step 7: Refresh the knowledge graph**

```bash
graphify update .
```

(AST-only, no API cost. Skip if `graphify` is not on PATH.)

---

## Self-Review Notes

Spec coverage check against `docs/superpowers/specs/2026-08-31-51manga-source-design.md`:

| Spec section | Covered by |
|---|---|
| Host choice (`m.` everywhere, mobile UA, PC Referer) | Task 2 constants + metadata tests |
| URL scheme (all 5 endpoints, fixed segment order, bare-number search paging) | Task 2 request-builder tests |
| Filter values (list/tags/finish/order, 873 dropped) | Task 2 filter tests |
| Listing card selectors, `data-src` fallback, mask ignored | Task 3 |
| Detail selectors, download-app decoy, status inference, full chapter list | Task 4 |
| `prepareChapterListFetch` → null, `parseChapterList` → empty | Task 2 (builder) + Task 4 (parser) |
| AES scheme, key, IV prefix, relative-path fallback | Task 1 + Task 5 |
| Anti-hotlink headers on Summary/Detail/ChapterImage | Tasks 3, 4, 5 (one assertion each) |
| Edge cases: missing title throws, missing params throws, decrypt failure throws with chapterId, empty description → null | Tasks 4, 5 |
| Registration | Task 6 |
| Verification commands + manual live E2E | Task 6 |
