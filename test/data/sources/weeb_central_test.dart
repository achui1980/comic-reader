import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/weeb_central.dart';

void main() {
  late WeebCentral source;

  setUp(() {
    source = WeebCentral();
  });

  group('WeebCentral metadata', () {
    test('has correct id', () {
      expect(source.id, 'weebcentral');
    });
    test('has correct name', () {
      expect(source.name, 'Weeb Central');
    });
    test('has href', () {
      expect(source.href, 'https://weebcentral.com');
    });
    test('is not disabled', () {
      expect(source.disabled, false);
    });
    test('requires Cloudflare / WebView fetch', () {
      expect(source.needsCloudflare, true);
      expect(source.usesWebViewFetch, true);
      expect(source.needsProxy, true);
      expect(source.cloudflareUrl, 'https://weebcentral.com/');
    });
    test('does not require login', () {
      expect(source.requiresLogin, false);
    });
  });

  group('WeebCentral request builders', () {
    test('prepareDiscoveryFetch hits search/data with empty text', () {
      final config = source.prepareDiscoveryFetch(1, const {});
      expect(config.url, 'https://weebcentral.com/search/data');
      expect(config.method, HttpMethod.get);
      expect(config.queryParameters?['limit'], '32');
      expect(config.queryParameters?['offset'], '0');
      expect(config.queryParameters?['text'], '');
    });

    test('prepareDiscoveryFetch page 2 has offset 32', () {
      final config = source.prepareDiscoveryFetch(2, const {});
      expect(config.queryParameters?['offset'], '32');
    });

    test('prepareSearchFetch builds correct URL and params', () {
      final config = source.prepareSearchFetch('iruma', 1, const {});
      expect(config.url, 'https://weebcentral.com/search/data');
      expect(config.queryParameters?['text'], 'iruma');
      expect(config.queryParameters?['offset'], '0');
      expect(config.queryParameters?['sort'], 'Best Match');
      expect(config.queryParameters?['order'], 'Descending');
      expect(config.queryParameters?['display_mode'], 'Full Display');
    });

    test('prepareMangaInfoFetch builds series URL', () {
      final config = source.prepareMangaInfoFetch('01J76XYC5SVSG0YGGA1EN740VW');
      expect(config.url,
          'https://weebcentral.com/series/01J76XYC5SVSG0YGGA1EN740VW');
    });

    test('prepareChapterListFetch hits full-chapter-list on page 1', () {
      final config =
          source.prepareChapterListFetch('01J76XYC5SVSG0YGGA1EN740VW', 1);
      expect(config?.url,
          'https://weebcentral.com/series/01J76XYC5SVSG0YGGA1EN740VW/full-chapter-list');
    });

    test('prepareChapterListFetch returns null beyond first page', () {
      final config =
          source.prepareChapterListFetch('01J76XYC5SVSG0YGGA1EN740VW', 2);
      expect(config, isNull);
    });

    test('prepareChapterFetch hits images endpoint with params', () {
      final config = source.prepareChapterFetch(
          '01J76XYC5SVSG0YGGA1EN740VW', '01KX2A1AVZ88TCA4Q7ARG4WJN0', 1);
      expect(config.url,
          'https://weebcentral.com/chapters/01KX2A1AVZ88TCA4Q7ARG4WJN0/images');
      expect(config.queryParameters?['is_prev'], 'False');
      expect(config.queryParameters?['current_page'], '1');
      expect(config.queryParameters?['reading_style'], 'long_strip');
    });

    test('getChapterWebUrl returns reader page URL', () {
      final url = source.getChapterWebUrl(
          '01J76XYC5SVSG0YGGA1EN740VW', '01KX2A1AVZ88TCA4Q7ARG4WJN0');
      expect(url,
          'https://weebcentral.com/chapters/01KX2A1AVZ88TCA4Q7ARG4WJN0');
    });
  });

  group('WeebCentral filters', () {
    test('exposes the same filter set for discovery and search', () {
      expect(source.discoveryFilters, isNotEmpty);
      expect(source.searchFilters, source.discoveryFilters);
      final names = source.discoveryFilters.map((f) => f.name).toList();
      expect(
        names,
        containsAll(<String>[
          'sort',
          'order',
          'included_type',
          'included_status',
          'official',
          'adult',
        ]),
      );
    });

    test('exposes an adult (18+) filter with True/False/Any choices', () {
      final adult =
          source.discoveryFilters.firstWhere((f) => f.name == 'adult');
      expect(adult.defaultValue, 'Any');
      final values = adult.choices.map((c) => c.value).toList();
      expect(values, containsAll(<String>['Any', 'True', 'False']));
    });

    test('applies selected filters to the query', () {
      final config = source.prepareDiscoveryFetch(1, const {
        'sort': 'Latest Updates',
        'order': 'Ascending',
        'official': 'True',
        'adult': 'True',
        'included_type': 'Manhwa',
        'included_status': 'Ongoing',
      });
      expect(config.queryParameters?['sort'], 'Latest Updates');
      expect(config.queryParameters?['order'], 'Ascending');
      expect(config.queryParameters?['official'], 'True');
      expect(config.queryParameters?['adult'], 'True');
      expect(config.queryParameters?['included_type'], 'Manhwa');
      expect(config.queryParameters?['included_status'], 'Ongoing');
    });

    test('omits type/status when set to the "All" (empty) choice', () {
      final config = source.prepareSearchFetch('x', 1, const {
        'included_type': '',
        'included_status': '',
      });
      expect(config.queryParameters?.containsKey('included_type'), false);
      expect(config.queryParameters?.containsKey('included_status'), false);
    });

    test('defaults adult to Any when no filter is provided', () {
      final config = source.prepareDiscoveryFetch(1, const {});
      expect(config.queryParameters?['adult'], 'Any');
    });
  });

  group('WeebCentral response parsing', () {
    test('parseSearch extracts series from article fragments', () {
      const html = '''
        <article class="bg-base-300">
          <section>
            <a href="https://weebcentral.com/series/01ABC/Test-Series">
              <picture>
                <source srcset="https://temp.compsci88.com/cover/normal/01ABC.webp" type="image/webp">
                <img src="https://temp.compsci88.com/cover/fallback/01ABC.jpg" alt="Test Series cover">
              </picture>
            </a>
          </section>
          <section class="hidden lg:block">
            <a class="line-clamp-1 link" href="https://weebcentral.com/series/01ABC/Test-Series">Test Series</a>
            <div><strong>Author(s):</strong> <span><a>Some Author</a></span></div>
          </section>
        </article>
      ''';
      final result = source.parseSearch(html);
      expect(result.length, 1);
      expect(result[0].id, '01ABC');
      expect(result[0].title, 'Test Series');
      expect(result[0].coverUrl, contains('01ABC'));
    });

    test('parseChapterList extracts chapters and reverses to oldest-first', () {
      const html = '''
        <div class="flex items-center">
          <a href="https://weebcentral.com/chapters/01CH2">
            <span class="grow"><span>Chapter 2</span></span>
            <time datetime="2024-02-01T00:00:00Z"></time>
          </a>
        </div>
        <div class="flex items-center">
          <a href="https://weebcentral.com/chapters/01CH1">
            <span class="grow"><span>Chapter 1</span></span>
            <time datetime="2024-01-01T00:00:00Z"></time>
          </a>
        </div>
      ''';
      final result = source.parseChapterList(html, '01ABC');
      expect(result.chapters.length, 2);
      // HTML is newest-first; parseChapterList reverses to oldest-first.
      expect(result.chapters.first.id, '01CH1');
      expect(result.chapters.first.title, 'Chapter 1');
      expect(result.chapters.last.id, '01CH2');
      expect(result.chapters.first.mangaId, '01ABC');
    });

    test('parseChapter extracts image URLs', () {
      const html = '''
        <section>
          <img src="https://scans.lastation.us/manga/Test/0001-001.png" width="836" height="1200">
          <img src="https://scans.lastation.us/manga/Test/0001-002.png" width="836" height="1200">
        </section>
      ''';
      final result = source.parseChapter(html, '01ABC', '01CH1', 1);
      expect(result.chapter.images.length, 2);
      expect(result.chapter.images[0].url,
          'https://scans.lastation.us/manga/Test/0001-001.png');
      expect(result.canLoadMore, false);
    });
  });
}
