import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/copy_manga.dart';
import 'package:comic_reader/core/utils/hash_utils.dart';
import 'package:comic_reader/core/utils/crypto_utils.dart';

void main() {
  late CopyManga source;

  setUp(() {
    source = CopyManga();
  });

  group('CopyManga metadata', () {
    test('has correct id', () {
      expect(source.id, 'copy');
    });
    test('has correct name', () {
      expect(source.name, '拷贝漫画');
    });
    test('has correct score', () {
      expect(source.score, 5.0);
    });
    test('is not disabled', () {
      expect(source.disabled, false);
    });
    test('has discovery filters', () {
      expect(source.discoveryFilters.length, 3);
      expect(source.discoveryFilters[0].name, 'type');
      expect(source.discoveryFilters[1].name, 'region');
      expect(source.discoveryFilters[2].name, 'sort');
    });
  });

  group('CopyManga request builders', () {
    test('prepareDiscoveryFetch builds correct URL', () {
      final config = source.prepareDiscoveryFetch(
          1, {'type': '', 'region': '', 'sort': '-datetime_updated'});
      expect(config.url, contains('api.mangacopy.com/api/v3/comics'));
      expect(config.queryParameters?['offset'], '0');
      expect(config.queryParameters?['limit'], '21');
    });

    test('prepareDiscoveryFetch page 2 has offset 21', () {
      final config = source.prepareDiscoveryFetch(
          2, {'type': '', 'region': '', 'sort': '-datetime_updated'});
      expect(config.queryParameters?['offset'], '21');
    });

    test('prepareSearchFetch builds correct URL', () {
      final config = source.prepareSearchFetch('test', 1, {});
      expect(config.url, contains('api.mangacopy.com/api/v3/search/comic'));
      expect(config.queryParameters?['q'], 'test');
      expect(config.queryParameters?['offset'], '0');
    });

    test('prepareMangaInfoFetch builds correct URL', () {
      final config = source.prepareMangaInfoFetch('one-piece');
      expect(config.url, 'https://www.mangacopy.com/comic/one-piece');
    });

    test('prepareChapterListFetch builds correct URL', () {
      final config = source.prepareChapterListFetch('one-piece', 1);
      expect(config?.url,
          'https://www.mangacopy.com/comicdetail/one-piece/chapters');
    });

    test('prepareChapterFetch builds correct URL', () {
      final config = source.prepareChapterFetch('one-piece', 'ch-001', 1);
      expect(
        config.url,
        'https://api.copy-manga.com/api/v3/comic/one-piece/chapter2/ch-001',
      );
      expect(config.queryParameters?['in_mainland'], 'true');
      expect(config.queryParameters?['request_id'], '');
      expect(config.headers?['source'], 'copyApp');
    });
  });

  group('hash utilities', () {
    test('combineHash produces correct format', () {
      expect(combineHash('copy', 'manga1'), 'copy&manga1');
      expect(combineHash('copy', 'manga1', 'ch1'), 'copy&manga1&ch1');
    });

    test('splitHash parses correctly', () {
      final result = splitHash('copy&manga1&ch1');
      expect(result.sourceId, 'copy');
      expect(result.mangaId, 'manga1');
      expect(result.chapterId, 'ch1');
    });

    test('splitHash without chapter', () {
      final result = splitHash('copy&manga1');
      expect(result.sourceId, 'copy');
      expect(result.mangaId, 'manga1');
      expect(result.chapterId, null);
    });
  });

  group('CopyManga response parsing', () {
    test('parseDiscovery handles valid response', () {
      final response = {
        'code': 200,
        'results': {
          'total': 1,
          'list': [
            {
              'name': 'Test Manga',
              'cover': 'https://example.com/cover.jpg',
              'path_word': 'test-manga',
              'datetime_updated': '2024-01-01',
              'author': [
                {'name': 'Author1', 'path_word': 'author1'}
              ],
              'theme': [
                {'name': 'Action', 'path_word': 'action'}
              ],
            }
          ],
        },
      };

      final result = source.parseDiscovery(response);
      expect(result.length, 1);
      expect(result[0].title, 'Test Manga');
      expect(result[0].id, 'test-manga');
      expect(result[0].coverUrl, 'https://example.com/cover.jpg');
      expect(result[0].author, 'Author1');
    });

    test('parseDiscovery returns empty on error code', () {
      final response = {'code': 500, 'message': 'error'};
      final result = source.parseDiscovery(response);
      expect(result, isEmpty);
    });

    test('parseSearch handles valid response', () {
      final response = {
        'code': 200,
        'results': {
          'limit': 20,
          'list': [
            {
              'name': 'Found Manga',
              'cover': 'https://example.com/cover2.jpg',
              'path_word': 'found-manga',
              'author': [
                {'name': 'Author2', 'path_word': 'author2'}
              ],
              'theme': [
                {'name': 'Comedy', 'path_word': 'comedy'}
              ],
            }
          ],
        },
      };

      final result = source.parseSearch(response);
      expect(result.length, 1);
      expect(result[0].title, 'Found Manga');
      expect(result[0].id, 'found-manga');
    });

    test('parseChapterList supports manga key from ccz variable', () {
      const mangaKey = 'op0zzpvv.nmn.00p';
      source.parseMangaInfo('''
        <script>
          var ccz = '$mangaKey';
        </script>
      ''', 'haizeiwang');

      final encryptedChapters = _encryptCopyPayload('''
        {"build":{"path_word":"haizeiwang"},"groups":{"default":{"chapters":[{"id":"ch-001","name":"第1话"}]}}}
      ''', mangaKey);

      final result = source.parseChapterList({
        'code': 200,
        'results': encryptedChapters,
      }, 'haizeiwang');

      expect(result.chapters, hasLength(1));
      expect(result.chapters.first.id, 'ch-001');
      expect(result.chapters.first.mangaId, 'haizeiwang');
      expect(result.chapters.first.title, '第1话');
    });

    test('parseChapter supports cct and contentKey variables', () {
      const chapterKey = 'op0zzpvv.nmn.00p';
      final encryptedImages = _encryptCopyPayload('''
        [{"url":"https://img.example.com/page1.c800x.jpg"}]
      ''', chapterKey);

      final result = source.parseChapter('''
        <h4 class="header">海贼王/1卷</h4>
        <script>
          var cct = '$chapterKey';
          var contentKey = '$encryptedImages';
        </script>
      ''', 'haizeiwang', 'ch-001', 1);

      expect(result.chapter.title, '1卷');
      expect(result.chapter.images, hasLength(1));
      expect(
        result.chapter.images.first.url,
        'https://img.example.com/page1.c1500x.jpg',
      );
    });

    test('parseChapter supports app chapter2 response', () {
      final result = source.parseChapter({
        'code': 200,
        'results': {
          'chapter': {
            'name': '1卷',
            'contents': [
              {'url': 'https://img.example.com/page2.c800x.jpg'},
              {'url': 'https://img.example.com/page1.c800x.jpg'},
            ],
            'words': [1, 0],
          },
        },
      }, 'haizeiwang', 'ch-001', 1);

      expect(result.chapter.title, '1卷');
      expect(result.chapter.images, hasLength(2));
      expect(result.chapter.images[0].url, 'https://img.example.com/page1.c1500x.jpg');
      expect(result.chapter.images[1].url, 'https://img.example.com/page2.c1500x.jpg');
    });
  });

  group('crypto', () {
    test('aesDecrypt roundtrip works correctly', () {
      // Encrypt a known plaintext, then decrypt with aesDecrypt
      const plaintext = '{"test": "hello world"}';
      const keyStr = 'xxxxyyyy11112222'; // 16 bytes
      const ivStr = 'abcdefghijklmnop'; // 16 bytes

      final key = encrypt.Key.fromUtf8(keyStr);
      final iv = encrypt.IV.fromUtf8(ivStr);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );
      final encrypted = encrypter.encrypt(plaintext, iv: iv);

      // Build contentKey: IV (16 chars) + hex-encoded ciphertext
      final hexCiphertext = encrypted.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final contentKey = '$ivStr$hexCiphertext';

      // Decrypt using our utility
      final result = aesDecrypt(contentKey, keyStr);
      expect(result, plaintext);
    });
  });
}

String _encryptCopyPayload(String plaintext, String keyStr) {
  const ivStr = 'abcdefghijklmnop';
  final key = encrypt.Key.fromUtf8(keyStr);
  final iv = encrypt.IV.fromUtf8(ivStr);
  final encrypter = encrypt.Encrypter(
    encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
  );
  final encrypted = encrypter.encrypt(plaintext, iv: iv);
  final hexCiphertext =
      encrypted.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$ivStr$hexCiphertext';
}
