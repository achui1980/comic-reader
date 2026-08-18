import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/bazuo.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() {
  final source = Bazuo();

  group('metadata', () {
    test('exposes stable identity', () {
      expect(source.id, 'bazuo');
      expect(source.isAdult, isTrue);
      expect(source.href, contains('manga.bazuo.link'));
    });

    test('exposes a category filter and a ranking filter', () {
      final names = source.discoveryFilters.map((f) => f.name).toList();
      expect(names, containsAll(<String>['sort', 'category']));

      final sort = source.discoveryFilters.firstWhere((f) => f.name == 'sort');
      expect(sort.defaultValue, 'latest');
      expect(
        sort.choices.map((c) => c.value),
        containsAll(<String>['latest', 'day', 'week', 'month', 'year']),
      );

      final category =
          source.discoveryFilters.firstWhere((f) => f.name == 'category');
      expect(category.defaultValue, '');
      expect(category.choices.length, 8); // 全部 + 7 real categories
    });
  });

  group('prepareDiscoveryFetch', () {
    test('defaults to the latest static feed', () {
      final config = source.prepareDiscoveryFetch(1, {});
      expect(config.url, contains('/mini-data/latest.json'));
      expect(config.method, HttpMethod.get);
    });

    test('appends -<page> for later pages of the latest feed', () {
      final config = source.prepareDiscoveryFetch(3, {'sort': 'latest'});
      expect(config.url, contains('/mini-data/latest-3.json'));
    });

    test('maps a display category to its slug file', () {
      final config =
          source.prepareDiscoveryFetch(1, {'category': '同人志'});
      expect(config.url, contains('/mini-data/categories/doujin.json'));
    });

    test('paginates category listings by filename suffix', () {
      final config = source.prepareDiscoveryFetch(2, {'category': '韩漫'});
      expect(config.url, contains('/mini-data/categories/hanman-2.json'));
    });

    test('falls back to the latest feed for an unmapped category', () {
      final config = source.prepareDiscoveryFetch(1, {'category': '国漫'});
      expect(config.url, contains('/mini-data/latest.json'));
      expect(config.url, isNot(contains('/categories/')));
    });

    test('uses the ranking endpoint with offset paging when sorted by period',
        () {
      final config = source.prepareDiscoveryFetch(2, {'sort': 'week'});
      expect(config.url, contains('/api/search.js'));
      expect(config.url, contains('mode=rankings'));
      expect(config.url, contains('period=week'));
      expect(config.url, contains('offset=180'));
      expect(config.url, contains('limit=180'));
    });

    test('combines a ranking period with a category filter', () {
      final config = source.prepareDiscoveryFetch(
        1,
        {'sort': 'month', 'category': '韩漫'},
      );
      expect(config.url, contains('period=month'));
      // The ranking endpoint filters on the display name, not the slug.
      expect(config.url, contains(Uri.encodeQueryComponent('韩漫')));
      expect(config.url, contains('offset=0'));
    });
  });

  group('prepareSearchFetch', () {
    test('percent-encodes the keyword and targets the .js endpoint', () {
      final config = source.prepareSearchFetch('学校', 1, {});
      expect(config.url, contains('/api/search.js'));
      expect(config.url, contains('q=${Uri.encodeQueryComponent('学校')}'));
    });
  });

  group('prepareMangaInfoFetch', () {
    test('requests the resolved .json.js detail URL', () {
      final config = source.prepareMangaInfoFetch('wnacg-377305-remote');
      expect(config.url,
          contains('/data/comics/wnacg-377305-remote.json.js'));
    });

    test('percent-encodes ids containing CJK characters', () {
      final config = source.prepareMangaInfoFetch('hanman-测试-414a40f0');
      expect(config.url, contains(Uri.encodeComponent('hanman-测试-414a40f0')));
      expect(config.url, isNot(contains('测试')));
    });
  });

  group('parseDiscovery', () {
    test('reads the shared items envelope', () {
      final result = source.parseDiscovery({
        'category': '同人志',
        'totalCount': 97775,
        'items': [
          {
            'id': 'wnacg-377305-remote',
            'title': 'Example Title',
            'category': '同人志',
            'cover': 'https://img5.qy0.ru/data/3773/05/001.jpg',
            'firstPageSrc': 'https://img5.qy0.ru/data/3773/05/001.jpg',
            'chapterCount': 1,
          },
        ],
      });

      expect(result, hasLength(1));
      expect(result.first.id, 'wnacg-377305-remote');
      expect(result.first.sourceId, 'bazuo');
      expect(result.first.coverUrl,
          'https://img5.qy0.ru/data/3773/05/001.jpg');
      expect(result.first.chapterCount, 1);
      expect(result.first.headers?['Referer'], isNotNull);
    });

    test('falls back to firstPageSrc when cover is missing', () {
      final result = source.parseDiscovery({
        'items': [
          {
            'id': 'x-1',
            'title': 'T',
            'cover': '',
            'firstPageSrc': 'https://cdn.example/1.jpg',
          },
        ],
      });
      expect(result.single.coverUrl, 'https://cdn.example/1.jpg');
    });

    test('decodes a raw JSON string body', () {
      final result = source.parseDiscovery(
        '{"items":[{"id":"a","title":"A","cover":"https://c/1.jpg"}]}',
      );
      expect(result.single.id, 'a');
    });

    test('returns empty for malformed or empty payloads', () {
      expect(source.parseDiscovery('not json'), isEmpty);
      expect(source.parseDiscovery({'items': null}), isEmpty);
      expect(source.parseDiscovery(null), isEmpty);
    });

    test('skips entries without an id', () {
      final result = source.parseDiscovery({
        'items': [
          {'title': 'no id'},
          {'id': 'ok', 'title': 'yes'},
        ],
      });
      expect(result.single.id, 'ok');
    });
  });

  group('parseSearch', () {
    test('maps titleAliases to altTitles', () {
      final result = source.parseSearch({
        'ok': true,
        'query': '学校',
        'items': [
          {
            'id': 'hanman-abc-1',
            'title': '学校母汤黑白来！',
            'cover': 'https://img5.qy0.ru/data/2795/07/cover.jpg',
            'titleAliases': ['alias one', 'alias two'],
          },
        ],
      });
      expect(result.single.altTitles, ['alias one', 'alias two']);
    });
  });

  group('parseMangaInfo', () {
    test('parses a single-chapter doujin entry as completed', () {
      final detail = source.parseMangaInfo({
        'id': 'wnacg-377305-remote',
        'title': 'Doujin Title',
        'author': 'wnacg',
        'category': '同人志',
        'description': 'remote source',
        'cover': 'https://img5.qy0.ru/data/3773/05/001.jpg',
        'tags': ['同人志', '远程'],
        'pageCount': 108,
        'chapters': [
          {
            'id': '正文',
            'title': '正文',
            'pages': [
              {'src': 'https://img5.qy0.ru/data/3773/05/001.jpg'},
            ],
          },
        ],
      }, 'wnacg-377305-remote');

      expect(detail.title, 'Doujin Title');
      expect(detail.author, 'wnacg');
      expect(detail.tags, ['同人志', '远程']);
      expect(detail.status, MangaStatus.completed);
      expect(detail.chapters, hasLength(1));
      expect(detail.chapters.single.id, '正文');
      expect(detail.chapters.single.mangaId, 'wnacg-377305-remote');
    });

    test('parses a grouped multi-chapter series as ongoing', () {
      final detail = source.parseMangaInfo({
        'id': 'hanman-x-414a40f0',
        'title': 'Series',
        'category': '韩漫',
        'cover': 'https://img5.qy0.ru/data/3771/30/cover.jpg',
        'tags': ['韩漫', '远程', '目录汇总'],
        'chapterCount': 2,
        'latestChapterTitle': 'Series 72-73话',
        'workGrouping': {'mode': 'hanman-series', 'baseTitle': 'Series'},
        'chapters': [
          {'id': 'aid-301084', 'title': 'Series 1-7话', 'pages': []},
          {'id': 'aid-302860', 'title': 'Series 8-9话', 'pages': []},
        ],
      }, 'hanman-x-414a40f0');

      expect(detail.status, MangaStatus.ongoing);
      expect(detail.latestChapter, 'Series 72-73话');
      expect(detail.chapters.map((c) => c.id),
          ['aid-301084', 'aid-302860']);
    });

    test('degrades gracefully on an unparseable body', () {
      final detail = source.parseMangaInfo('<html>nope</html>', 'fallback-id');
      expect(detail.id, 'fallback-id');
      expect(detail.title, 'fallback-id');
      expect(detail.chapters, isEmpty);
    });
  });

  group('chapter list', () {
    test('is embedded in the detail response', () {
      expect(source.prepareChapterListFetch('any', 1), isNull);
      expect(source.parseChapterList(null, 'any').chapters, isEmpty);
    });
  });

  group('parseChapter', () {
    final detailJson = {
      'id': 'hanman-x-414a40f0',
      'chapters': [
        {
          'id': 'aid-301084',
          'title': 'Chapter One',
          'pages': [
            {'src': 'https://img5.qy0.ru/data/3010/84/01_01.jpg'},
            {'src': 'https://img5.qy0.ru/data/3010/84/01_02.jpg'},
          ],
        },
        {
          'id': 'aid-302860',
          'title': 'Chapter Two',
          'pages': [
            {'src': 'https://img5.qy0.ru/data/3028/60/08_01.jpg'},
          ],
        },
      ],
    };

    test('re-fetches the detail JSON for chapter images', () {
      final config = source.prepareChapterFetch('m-1', 'aid-301084', 1);
      expect(config.url, contains('/data/comics/m-1.json.js'));
    });

    test('selects the matching chapter and maps page srcs', () {
      final result = source.parseChapter(
          detailJson, 'hanman-x-414a40f0', 'aid-301084', 1);

      expect(result.chapter.title, 'Chapter One');
      expect(result.chapter.images, hasLength(2));
      expect(result.chapter.images.first.url,
          'https://img5.qy0.ru/data/3010/84/01_01.jpg');
      expect(result.chapter.images.first.scrambleType, ScrambleType.none);
      expect(result.chapter.images.first.headers?['Referer'], isNotNull);
      expect(result.canLoadMore, isFalse);
    });

    test('selects the second chapter independently', () {
      final result = source.parseChapter(
          detailJson, 'hanman-x-414a40f0', 'aid-302860', 1);
      expect(result.chapter.images.single.url,
          'https://img5.qy0.ru/data/3028/60/08_01.jpg');
    });

    test('falls back to the only chapter when the id does not match', () {
      final single = {
        'chapters': [
          {
            'id': '正文',
            'title': '正文',
            'pages': [
              {'src': 'https://img5.qy0.ru/data/1/001.jpg'},
            ],
          },
        ],
      };
      final result = source.parseChapter(single, 'm', 'unexpected-id', 1);
      expect(result.chapter.images, hasLength(1));
    });

    test('returns no images when the chapter is absent from a multi-chapter set',
        () {
      final result = source.parseChapter(detailJson, 'm', 'missing', 1);
      expect(result.chapter.images, isEmpty);
    });

    test('tolerates a malformed body', () {
      final result = source.parseChapter('garbage', 'm', 'c', 1);
      expect(result.chapter.images, isEmpty);
    });
  });

  group('getChapterWebUrl', () {
    test('builds an encoded reader deep link', () {
      final url = source.getChapterWebUrl('hanman-测试-1', 'aid-1')!;
      expect(url, contains('manga.bazuo.link/manga-app/'));
      expect(url, contains('chapter=aid-1'));
      expect(url, isNot(contains('测试')));
    });
  });
}
