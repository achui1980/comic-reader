import 'dart:convert';
import 'dart:io';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/hanabi_manga.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildHanabiSessionCookie', () {
    test('keeps short payloads as a single cookie', () {
      final cookie = buildHanabiSessionCookie(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresIn: 3600,
        expiresAt: 1234567890,
        user: {'id': 'u1'},
      );
      expect(
        cookie.startsWith('sb-uhkvqrxmcapgtpspglrp-auth-token=base64-'),
        isTrue,
      );
      expect(cookie.contains('.0='), isFalse);
    });

    test('splits long payloads across suffixed cookies', () {
      final longRefreshToken = 'r' * 4000;
      final cookie = buildHanabiSessionCookie(
        accessToken: 'access',
        refreshToken: longRefreshToken,
        expiresIn: 3600,
        expiresAt: 1234567890,
        user: {'id': 'u1', 'email': 'x@example.com'},
      );
      expect(
        cookie.contains('sb-uhkvqrxmcapgtpspglrp-auth-token.0='),
        isTrue,
      );
      expect(
        cookie.contains('sb-uhkvqrxmcapgtpspglrp-auth-token.1='),
        isTrue,
      );
      expect(cookie.contains('; '), isTrue);
    });
  });

  group('extractHanabiBookLdJson', () {
    test('parses the Book ld+json block from the real detail page', () async {
      final html = await File(
        'test/fixtures/hanabi/detail_page.html',
      ).readAsString();
      final book = extractHanabiBookLdJson(html);
      expect(book, isNotNull);
      expect(book!['name'], '尼古喵喵');
      expect(book['alternateName'], ['雅尼猫']);
      expect(
        (book['author'] as List).first['name'],
        'にゃんにゃんファクトリー',
      );
      expect(
        book['image'],
        'https://img2.cycimg.me/r/400/pic/cover/l/90/31/445083_BXuSi.jpg',
      );
      expect(book['genre'], ['搞笑']);
    });
  });

  group('extractHanabiChapters', () {
    test('parses all 73 chapters from the real detail page', () async {
      final html = await File(
        'test/fixtures/hanabi/detail_page.html',
      ).readAsString();
      final chapters = extractHanabiChapters(html);
      expect(chapters.length, 73);
      expect(chapters.first['id'], 164145);
      expect(chapters.first['title'], '第01话');
      expect(chapters.first['idx'], 1);
      expect(chapters.first['category'], 'normal');
      expect(chapters.first['image_count'], 15);
      expect(chapters[29]['id'], 164174);
      expect(chapters[29]['title'], '第29话');
      expect(chapters[29]['idx'], 30);
      expect(chapters[35]['title'], '动画化');
      expect(chapters[35]['idx'], 36);
      expect(chapters.last['id'], 201340);
      expect(chapters.last['title'], '第69话');
      expect(chapters.last['idx'], 73);
    });
  });

  group('HanabiManga.parseMangaInfo', () {
    test('extracts full metadata and chapter list from the real detail page', () async {
      final html = await File(
        'test/fixtures/hanabi/detail_page.html',
      ).readAsString();
      final source = HanabiManga();
      final detail = source.parseMangaInfo(html, '3361');

      expect(detail.title, '尼古喵喵');
      expect(detail.author, 'にゃんにゃんファクトリー');
      expect(detail.altTitles, ['雅尼猫']);
      expect(
        detail.coverUrl,
        'https://img2.cycimg.me/r/400/pic/cover/l/90/31/445083_BXuSi.jpg',
      );
      expect(detail.tags, ['搞笑']);
      expect(detail.status, MangaStatus.ongoing);
      expect(detail.chapters.length, 73);
      expect(detail.chapters.first.id, 'chapter-1');
      expect(detail.chapters.first.title, '第01话');
      expect(detail.chapters[29].id, 'chapter-30');
      expect(detail.chapters[29].title, '第29话');
      expect(detail.chapters.last.id, 'chapter-73');
    });
  });

  group('HanabiManga chapter list', () {
    test('prepareChapterListFetch returns null; parseChapterList returns empty', () {
      final source = HanabiManga();
      expect(source.prepareChapterListFetch('3361', 1), isNull);
      expect(
        source.parseChapterList(null, '3361'),
        const ChapterListResult(chapters: []),
      );
    });
  });

  group('HanabiManga.prepareChapterFetch/parseChapter', () {
    test('prepareChapterFetch builds the reader API URL', () {
      final source = HanabiManga();
      final config = source.prepareChapterFetch('3361', 'chapter-30', 1);
      expect(
        config.url,
        'https://web.hanabimanga.com/api/reader/comic/3361/chapter-30',
      );
    });

    test('parseChapter extracts pages with hanabi scramble metadata', () {
      final source = HanabiManga();
      const response = {
        'chapter': {
          'comicId': 3361,
          'chapterSlug': 'chapter-1',
          'chapterId': 164145,
          'title': '第01话',
          'idx': 1,
          'totalPages': 2,
        },
        'pages': [
          {
            'index': 0,
            'page': '001',
            'url': 'https://cdn.hanabimanga.top/a/001.webp',
          },
          {
            'index': 1,
            'page': '002',
            'url': 'https://cdn.hanabimanga.top/a/002.webp',
          },
        ],
        'metadata': {
          'expiresIn': 7200,
          'scrambleInfo': {
            'ticket': 'Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=',
            'nonce': 'ZkfsVQTteF2Ab4Ha',
            'cols': 4,
            'rows': 4,
          },
        },
      };

      final result = source.parseChapter(response, '3361', 'chapter-1', 1);

      expect(result.chapter.title, '第01话');
      expect(result.chapter.images.length, 2);
      final first = result.chapter.images.first;
      expect(first.url, 'https://cdn.hanabimanga.top/a/001.webp');
      expect(first.scrambleType, ScrambleType.hanabi);
      expect(
        first.hanabiTicket,
        'Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=',
      );
      expect(first.hanabiNonce, 'ZkfsVQTteF2Ab4Ha');
      expect(first.hanabiCols, 4);
      expect(first.hanabiRows, 4);
    });
  });

  group('HanabiManga discovery', () {
    test('prepareDiscoveryFetch builds the browse URL with only non-default filters', () {
      final source = HanabiManga();
      final config = source.prepareDiscoveryFetch(2, {
        'category': 'yuri',
        'sort': 'rating',
        'region': 'jp',
        'status': 'serializing',
      });
      expect(
        config.url,
        'https://web.hanabimanga.com/zh-CN/browse?page=2&category=yuri&sort=rating&region=jp&status=serializing',
      );
    });

    test('prepareDiscoveryFetch omits default/all filter values', () {
      final source = HanabiManga();
      final config = source.prepareDiscoveryFetch(1, {
        'category': 'all',
        'sort': '',
        'region': 'all',
        'status': 'all',
      });
      expect(config.url, 'https://web.hanabimanga.com/zh-CN/browse?page=1');
    });

    test('parseDiscovery extracts manga cards via structural selectors', () {
      final source = HanabiManga();
      const html = '''
        <div>
          <a href="/zh-CN/comic/123">
            <img src="https://img2.xfmanga.top/cover1.jpg" alt="漫画A" />
            <h3>漫画A</h3>
          </a>
          <a href="/zh-CN/comic/456">
            <img src="https://img2.xfmanga.top/cover2.jpg" />
            <h3>漫画B</h3>
          </a>
          <a href="/zh-CN/comic/123">
            <img src="https://img2.xfmanga.top/cover1-dup.jpg" />
            <h3>漫画A重复</h3>
          </a>
        </div>
      ''';
      final results = source.parseDiscovery(html);
      expect(results.length, 2);
      expect(results[0].id, '123');
      expect(results[0].title, '漫画A');
      expect(results[0].coverUrl, 'https://img2.xfmanga.top/cover1.jpg');
      expect(results[1].id, '456');
      expect(results[1].title, '漫画B');
    });
  });

  group('HanabiManga search', () {
    test('prepareSearchFetch builds the Supabase RPC request', () {
      final source = HanabiManga();
      final config = source.prepareSearchFetch('尼古', 1, const {});
      expect(
        config.url,
        'https://uhkvqrxmcapgtpspglrp.supabase.co/rest/v1/rpc/search_comics_pgroonga',
      );
      expect(config.method, HttpMethod.post);
      expect(config.headers?['apikey'], isNotEmpty);
      expect(
        config.body,
        jsonEncode({
          'search_term': '尼古',
          'page_number': 1,
          'items_per_page': 24,
        }),
      );
    });

    test(
      'prepareSearchFetch sends Bearer anon key when not logged in',
      () {
        final source = HanabiManga();
        final config = source.prepareSearchFetch('尼古', 1, const {});
        expect(
          config.headers?['authorization'],
          'Bearer ${config.headers?['apikey']}',
        );
      },
    );

    test(
      'prepareSearchFetch sends Bearer access token when logged in',
      () {
        final source = HanabiManga();
        final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        source.syncExtraData({
          'cookie': 'sb-uhkvqrxmcapgtpspglrp-auth-token=base64-x',
          'accessToken': 'user-access-tok',
          'refreshToken': 'r',
          'expiresAt': nowSeconds + 3600,
        });
        final config = source.prepareSearchFetch('尼古', 1, const {});
        expect(config.headers?['authorization'], 'Bearer user-access-tok');
      },
    );

    test('parseSearch extracts MangaSummary from the Supabase RPC response', () {
      final source = HanabiManga();
      const response = [
        {
          'id': 3361,
          'title': '尼古喵喵',
          'aliases': ['雅尼猫'],
          'cover_url':
              'https://img2.cycimg.me/r/400/pic/cover/l/90/31/445083_BXuSi.jpg',
          'lock_status': 'free',
          'chapters_count': 73,
        },
      ];
      final results = source.parseSearch(response);
      expect(results.length, 1);
      expect(results.first.id, '3361');
      expect(results.first.title, '尼古喵喵');
      expect(results.first.altTitles, ['雅尼猫']);
      expect(results.first.chapterCount, 73);
    });
  });

  group('HanabiManga login/session', () {
    test('buildSignInRequest posts to the Supabase password grant endpoint', () {
      final source = HanabiManga();
      final config = source.buildSignInRequest('user@example.com', 'secret');
      expect(
        config.url,
        'https://uhkvqrxmcapgtpspglrp.supabase.co/auth/v1/token?grant_type=password',
      );
      expect(config.method, HttpMethod.post);
      expect(
        config.body,
        jsonEncode({'email': 'user@example.com', 'password': 'secret'}),
      );
    });

    test('parseSignIn builds a session cookie and marks the source authenticated', () {
      final source = HanabiManga();
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final data = source.parseSignIn({
        'access_token': 'access-tok',
        'refresh_token': 'refresh-tok',
        'expires_in': 3600,
        'expires_at': nowSeconds + 3600,
        'user': {'id': 'u1', 'email': 'user@example.com'},
      });

      expect(data, isNotNull);
      expect(
        data!['cookie'],
        startsWith('sb-uhkvqrxmcapgtpspglrp-auth-token=base64-'),
      );
      expect(data['accessToken'], 'access-tok');
      expect(data['refreshToken'], 'refresh-tok');
      expect(data['expiresAt'], nowSeconds + 3600);

      source.syncExtraData(data);
      expect(source.isAuthenticated, isTrue);
      expect(source.extraHeaders['Cookie'], data['cookie']);
    });

    test('needsSessionRefresh becomes true within 5 minutes of expiry', () {
      final source = HanabiManga();
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      source.syncExtraData({
        'cookie': 'sb-uhkvqrxmcapgtpspglrp-auth-token=base64-x',
        'accessToken': 'a',
        'refreshToken': 'r',
        'expiresAt': nowSeconds + 60,
      });
      expect(source.needsSessionRefresh, isTrue);
    });

    test('buildRefreshRequest posts to the Supabase refresh_token grant endpoint', () {
      final source = HanabiManga();
      source.syncExtraData({
        'cookie': 'sb-uhkvqrxmcapgtpspglrp-auth-token=base64-x',
        'accessToken': 'a',
        'refreshToken': 'r-123',
        'expiresAt':
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
      });
      final config = source.buildRefreshRequest();
      expect(
        config.url,
        'https://uhkvqrxmcapgtpspglrp.supabase.co/auth/v1/token?grant_type=refresh_token',
      );
      expect(config.body, jsonEncode({'refresh_token': 'r-123'}));
    });
  });
}
