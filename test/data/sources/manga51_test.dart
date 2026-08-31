import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/utils/crypto_utils.dart';
import 'package:comic_reader/data/sources/manga51.dart';

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
}
