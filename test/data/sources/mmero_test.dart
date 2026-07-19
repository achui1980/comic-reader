import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/mmero.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() {
  late MmeroSource source;

  setUp(() {
    source = MmeroSource();
  });

  group('MmeroSource metadata and request builders', () {
    test('declares an adult Mmero source with catalog filters', () {
      expect(source.id, 'mmero');
      expect(source.name, '摸摸漫画');
      expect(source.shortName, 'MM');
      expect(source.description, '成人漫画');
      expect(source.score, 3.5);
      expect(source.href, 'https://mmero.com');
      expect(source.isAdult, isTrue);
      expect(source.discoveryFilters.map((filter) => filter.name), [
        'channel',
        'status',
      ]);
      final channel = source.discoveryFilters[0];
      expect(channel.label, '频道');
      expect(channel.defaultValue, 'all');
      expect(channel.choices.map((choice) => [choice.label, choice.value]), [
        ['全部', 'all'],
        ['韩漫', '1'],
        ['同人志', '2'],
        ['杂志', '4'],
        ['单行本', '5'],
      ]);
      final status = source.discoveryFilters[1];
      expect(status.label, '状态');
      expect(status.defaultValue, 'all');
      expect(status.choices.map((choice) => [choice.label, choice.value]), [
        ['全部', 'all'],
        ['连载中', 'ongoing'],
        ['已完结', 'completed'],
      ]);
    });

    test('builds a filtered catalog request', () {
      final config = source.prepareDiscoveryFetch(2, {
        'channel': '2',
        'status': 'completed',
      });
      expect(config.url, 'https://mmero.com/api/comic/items');
      expect(config.method, HttpMethod.get);
      expect(config.queryParameters, {
        'pageNo': 2,
        'pageSize': 30,
        'channel': 2,
        'isEnded': true,
      });
      final ongoing = source.prepareDiscoveryFetch(1, {'status': 'ongoing'});
      expect(ongoing.queryParameters, {
        'pageNo': 1,
        'pageSize': 30,
        'isEnded': false,
      });
    });

    test('builds an unfiltered catalog request without optional values', () {
      final config = source.prepareDiscoveryFetch(1, const {});
      expect(config.queryParameters, {'pageNo': 1, 'pageSize': 30});
    });

    test('builds a comic search request', () {
      final config = source.prepareSearchFetch('谷口大介', 3, const {});
      expect(config.url, 'https://mmero.com/api/comic/search');
      expect(config.method, HttpMethod.get);
      expect(config.queryParameters, {
        'keyword': '谷口大介',
        'pageNo': 3,
        'pageSize': 30,
        'type': 1,
      });
    });

    test('builds JSON POST requests for detail and chapter content', () {
      final detail = source.prepareMangaInfoFetch('51118');
      final chapter = source.prepareChapterFetch('51118', '1', 1);
      expect(detail.url, 'https://mmero.com/api/comic/content');
      expect(detail.method, HttpMethod.post);
      expect(detail.body, {'id': 51118});
      expect(chapter.url, 'https://mmero.com/api/comic/chapter');
      expect(chapter.method, HttpMethod.post);
      expect(chapter.body, {'id': 51118, 'chapter': 1});
      expect(
        source.getChapterWebUrl('51118', '1'),
        'https://mmero.com/comics/51118/1',
      );
    });

    test('does not request a separate chapter list', () {
      expect(source.prepareChapterListFetch('51118', 1), isNull);
    });
  });

  group('MmeroSource response parsing', () {
    test('maps catalog items and derives the cover URL', () {
      final results = source.parseDiscovery({
        'items': [
          {'id': 51118, 'title': '测试漫画', 'chapter': 3},
        ],
        'page': 1,
        'size': 30,
        'total': 1,
      });
      expect(results, hasLength(1));
      expect(results.single.id, '51118');
      expect(results.single.sourceId, 'mmero');
      expect(results.single.title, '测试漫画');
      expect(
        results.single.coverUrl,
        'https://cover.2thewash.com/comic/51118/cover.jpg',
      );
      expect(results.single.latestChapter, '第3话');
    });

    test('maps detail metadata, tags, status, and embedded chapters', () {
      final detail = source.parseMangaInfo({
        'id': 51118,
        'title': '测试漫画',
        'author': '测试作者',
        'desc': '测试简介',
        'isEnded': true,
        'tags': [
          {'id': 12, 'name': '后宫'},
          {'id': 25, 'name': '巨乳'},
        ],
        'chapters': [
          {'number': 1, 'title': '第1话', 'pages': 63},
          {'number': 2, 'title': '第2话', 'pages': 40},
        ],
      }, '51118');
      expect(detail.id, '51118');
      expect(detail.sourceId, 'mmero');
      expect(detail.title, '测试漫画');
      expect(detail.author, '测试作者');
      expect(detail.description, '测试简介');
      expect(detail.status, MangaStatus.completed);
      expect(detail.tags, ['后宫', '巨乳']);
      expect(
        detail.coverUrl,
        'https://cover.2thewash.com/comic/51118/cover.jpg',
      );
      expect(detail.chapters.map((chapter) => chapter.id), ['1', '2']);
      expect(
        detail.chapters.map((chapter) => chapter.mangaId),
        ['51118', '51118'],
      );
    });

    test('maps search items and derives the cover URL', () {
      final results = source.parseSearch({
        'items': [
          {'id': 51118, 'title': '测试漫画'},
        ],
        'page': 1,
        'size': 30,
        'total': 1,
      });
      expect(results, hasLength(1));
      expect(results.single.id, '51118');
      expect(results.single.sourceId, 'mmero');
      expect(results.single.title, '测试漫画');
      expect(
        results.single.coverUrl,
        'https://cover.2thewash.com/comic/51118/cover.jpg',
      );
    });

    test('generates one ordered direct image URL for every chapter page', () {
      final result = source.parseChapter({
        'number': 1,
        'title': '第1话',
        'pages': 3,
        'hadPrevious': false,
        'hadNext': false,
      }, '51118', '1', 1);
      expect(result.canLoadMore, isFalse);
      expect(result.chapter.id, '1');
      expect(result.chapter.mangaId, '51118');
      expect(result.chapter.title, '第1话');
       expect(result.chapter.images.map((image) => image.url), [
         'https://c2.2thewash.com/comic/51118/1/1.jpg',
         'https://c2.2thewash.com/comic/51118/1/2.jpg',
         'https://c2.2thewash.com/comic/51118/1/3.jpg',
       ]);
       expect(
         result.chapter.images.map((image) => image.responseEncoding),
         everyElement(ImageResponseEncoding.base64OrBinary),
       );
    });

    test('does not invent image URLs when the chapter page count is absent', () {
      final result = source.parseChapter({'title': '第1话'}, '51118', '1', 1);
      expect(result.chapter.images, isEmpty);
    });

    test('does not throw or generate images for a malformed page count', () {
      final result = source.parseChapter(
        {'title': '第1话', 'pages': 'invalid'},
        '51118',
        '1',
        1,
      );

      expect(result.chapter.images, isEmpty);
    });
  });
}
