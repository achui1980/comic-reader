import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/data/sources/mangago.dart';

void main() {
  late Mangago source;

  setUp(() {
    source = Mangago();
  });

  group('Mangago metadata', () {
    test('has correct id', () {
      expect(source.id, 'mangago');
    });
    test('has correct name', () {
      expect(source.name, 'Mangago');
    });
    test('has href', () {
      expect(source.href, 'https://www.mangago.me');
    });
    test('is not disabled', () {
      expect(source.disabled, false);
    });
    test('requires Cloudflare / WebView fetch', () {
      expect(source.needsCloudflare, true);
      expect(source.usesWebViewFetch, true);
      expect(source.needsProxy, true);
      expect(source.cloudflareUrl, 'https://www.mangago.me/');
    });
    test('does not require login', () {
      expect(source.requiresLogin, false);
    });
    test('exposes Chinese discovery filters incl. an 18+ filter', () {
      final filters = source.discoveryFilters;
      expect(filters, isNotEmpty);
      final names = filters.map((f) => f.name).toList();
      expect(names, containsAll(<String>['genre', 'sortby', 'status', 'adult']));
      final adult = filters.firstWhere((f) => f.name == 'adult');
      expect(adult.label, '18+内容');
      expect(adult.defaultValue, 'hide');
      expect(adult.choices.map((c) => c.value),
          containsAll(<String>['hide', 'show', 'only']));
    });
  });

  group('Mangago request builders', () {
    test('prepareDiscoveryFetch hits latest listing for the page', () {
      final config = source.prepareDiscoveryFetch(1, const {});
      expect(config.url, 'https://www.mangago.me/list/latest/all/1/');
      expect(config.method, HttpMethod.get);
      expect(config.extra?['renderMode'], true);
    });

    test('prepareDiscoveryFetch page 3 uses the page number', () {
      final config = source.prepareDiscoveryFetch(3, const {});
      expect(config.url, 'https://www.mangago.me/list/latest/all/3/');
    });

    test('prepareDiscoveryFetch with filters hits the genre endpoint', () {
      final config = source.prepareDiscoveryFetch(1, const {
        'genre': 'Yaoi',
        'sortby': 'view',
        'status': 'finished',
        'adult': 'hide',
      });
      expect(config.url, 'https://www.mangago.me/genre/Yaoi/1/');
      expect(config.queryParameters?['f'], '1');
      expect(config.queryParameters?['o'], '0');
      expect(config.queryParameters?['sortby'], 'view');
      expect(config.queryParameters?['e'], contains('Adult'));
    });

    test('prepareDiscoveryFetch ongoing status maps to f=0&o=1', () {
      final config = source.prepareDiscoveryFetch(1, const {
        'genre': 'Comedy',
        'status': 'ongoing',
        'adult': 'show',
      });
      expect(config.url, 'https://www.mangago.me/genre/Comedy/1/');
      expect(config.queryParameters?['f'], '0');
      expect(config.queryParameters?['o'], '1');
      expect(config.queryParameters?['e'], '');
    });

    test('prepareDiscoveryFetch adult=only defaults genre to Adult', () {
      final config = source.prepareDiscoveryFetch(2, const {'adult': 'only'});
      expect(config.url, 'https://www.mangago.me/genre/Adult/2/');
    });

    test('prepareDiscoveryFetch adult=show with no filters stays on latest',
        () {
      final config = source.prepareDiscoveryFetch(1, const {'adult': 'show'});
      expect(config.url, 'https://www.mangago.me/list/latest/all/1/');
    });

    test('prepareSearchFetch builds l_search URL and params', () {
      final config = source.prepareSearchFetch('jinx', 1, const {});
      expect(config.url, 'https://www.mangago.me/r/l_search/');
      expect(config.queryParameters?['name'], 'jinx');
      expect(config.queryParameters?['page'], '1');
    });

    test('prepareMangaInfoFetch builds read-manga URL', () {
      final config = source.prepareMangaInfoFetch('jinx');
      expect(config.url, 'https://www.mangago.me/read-manga/jinx/');
      expect(config.extra?['renderMode'], true);
    });

    test('prepareChapterListFetch returns detail URL on page 1', () {
      final config = source.prepareChapterListFetch('jinx', 1);
      expect(config?.url, 'https://www.mangago.me/read-manga/jinx/');
    });

    test('prepareChapterListFetch returns null beyond first page', () {
      final config = source.prepareChapterListFetch('jinx', 2);
      expect(config, isNull);
    });

    test('prepareChapterFetch builds bare reader page URL', () {
      final config =
          source.prepareChapterFetch('jinx', 'uu/br_chapter-128596', 1);
      expect(config.url,
          'https://www.mangago.me/read-manga/jinx/uu/br_chapter-128596/');
      // Chapter images are decrypted from imgsrcs via Dart AES, so the plain
      // Dio path is used — no navigation render mode.
      expect(config.extra?['renderMode'], isNot(true));
    });

    test('prepareChapterFetch always targets bare URL (whole chapter at once)',
        () {
      final config =
          source.prepareChapterFetch('jinx', 'uu/br_chapter-128596', 2);
      expect(config.url,
          'https://www.mangago.me/read-manga/jinx/uu/br_chapter-128596/');
    });

    test('getChapterWebUrl returns reader page URL', () {
      final url = source.getChapterWebUrl('jinx', 'uu/br_chapter-128596');
      expect(url,
          'https://www.mangago.me/read-manga/jinx/uu/br_chapter-128596/');
    });
  });

  group('Mangago response parsing', () {
    test('parseSearch extracts entries from #search_list', () {
      const html = '''
        <ul id="search_list" class="pic_list">
          <li>
            <div class="box">
              <div class="left">
                <a class="thm-effect" href="https://www.mangago.me/read-manga/jinx/" title="Jinx">
                  <img src="https://i7.mangapicgallery.com/r/coverlink/jinx.jpg?4" alt="Jinx" />
                </a>
              </div>
              <div class="row-1"><h2><a href="https://www.mangago.me/read-manga/jinx/">Jinx</a></h2></div>
              <div class="row-3"><span class="blue">Author: </span>Mingwa</div>
              <div class="row-4"><span class="gray">Yaoi</span></div>
              <div class="row-5">
                <span class="blue">Latest Chapters: </span><a class="chico" href="#">Ch.18.2</a>
                <span class="blue">Update Date: </span>18 minutes
              </div>
            </div>
          </li>
        </ul>
      ''';
      final result = source.parseSearch(html);
      expect(result.length, 1);
      expect(result[0].id, 'jinx');
      expect(result[0].sourceId, 'mangago');
      expect(result[0].title, 'Jinx');
      expect(result[0].coverUrl, contains('coverlink'));
      expect(result[0].author, 'Mingwa');
    });

    test('parseDiscovery uses the same list markup', () {
      const html = '''
        <ul id="search_list" class="pic_list">
          <li>
            <div class="box">
              <a class="thm-effect" href="https://www.mangago.me/read-manga/futago/" title="Futago">
                <img src="https://i7.mangapicgallery.com/r/coverlink/futago.jpg" alt="Futago" />
              </a>
              <div class="row-1"><h2><a href="https://www.mangago.me/read-manga/futago/">Futago</a></h2></div>
            </div>
          </li>
        </ul>
      ''';
      final result = source.parseDiscovery(html);
      expect(result.length, 1);
      expect(result[0].id, 'futago');
      expect(result[0].title, 'Futago');
    });

    test('parseDiscovery falls back to genre page .updatesli markup', () {
      const html = '''
        <div class="pic_list">
          <div class="updatesli">
            <div class="left">
              <a class="thm-effect" href="https://www.mangago.me/read-manga/some_yaoi/" title="Some Yaoi">
                <img src="data:image/gif;base64,PLACEHOLDER"
                     data-src="https://i0.mangapicgallery.com/r/coverlink/some_yaoi.png" />
              </a>
            </div>
            <span class="title"><a href="https://www.mangago.me/read-manga/some_yaoi/">Some Yaoi</a></span>
          </div>
        </div>
      ''';
      final result = source.parseDiscovery(html);
      expect(result.length, 1);
      expect(result[0].id, 'some_yaoi');
      expect(result[0].title, 'Some Yaoi');
      // Cover taken from data-src (lazy load), not the placeholder src.
      expect(result[0].coverUrl,
          'https://i0.mangapicgallery.com/r/coverlink/some_yaoi.png');
    });

    test('parseMangaInfo extracts title, cover, status, author, tags', () {
      const html = '''
        <h1>Jinx (Yaoi)</h1>
        <div class="content" id="information">
          <div class="left cover"><img src="https://i7.mangapicgallery.com/r/coverlink/jinx.jpg" /></div>
          <div class="manga_right">
            <table class="left">
              <tr><td><label>Status:</label><span>Completed</span></td></tr>
              <tr><td><label>Author:</label><a href="/r/l_search/?name=Mingwa">Mingwa</a></td></tr>
              <tr><td><label>Genre(s):</label><a href="/genre/Yaoi/">Yaoi</a><a href="/genre/Drama/">Drama</a></td></tr>
            </table>
          </div>
        </div>
        <div class="manga_summary">A story about jinx.</div>
        <div id="chapter_table">
          <a class="chico" href="https://www.mangago.me/read-manga/jinx/mkk/nml_chapter-18.2/pg-1/"><b>Ch.18.2</b></a>
          <a class="chico" href="https://www.mangago.me/read-manga/jinx/mkk/mk_v-1-chapter-1/"><b>Vol.1 Ch.1</b></a>
        </div>
      ''';
      final detail = source.parseMangaInfo(html, 'jinx');
      expect(detail.id, 'jinx');
      expect(detail.title, 'Jinx (Yaoi)');
      expect(detail.coverUrl, contains('coverlink'));
      expect(detail.status, MangaStatus.completed);
      expect(detail.author, 'Mingwa');
      expect(detail.tags, containsAll(<String>['Yaoi', 'Drama']));
      expect(detail.description, 'A story about jinx.');
      // Chapters embedded and reversed to oldest-first.
      expect(detail.chapters.length, 2);
      expect(detail.chapters.first.title, 'Vol.1 Ch.1');
      expect(detail.chapters.last.title, 'Ch.18.2');
    });

    test('parseChapterList extracts chapters, reverses, derives stable ids', () {
      const html = '''
        <div id="chapter_table">
          <a class="chico" href="https://www.mangago.me/read-manga/jinx/mkk/nml_chapter-18.2/pg-1/"><b>Ch.18.2</b></a>
          <a class="chico" href="https://www.mangago.me/read-manga/jinx/mkk/mk_v-1-chapter-1/"><b>Vol.1 Ch.1</b></a>
        </div>
      ''';
      final result = source.parseChapterList(html, 'jinx');
      expect(result.chapters.length, 2);
      // Newest-first in the DOM -> reversed to oldest-first.
      expect(result.chapters.first.title, 'Vol.1 Ch.1');
      expect(result.chapters.first.id, 'mkk/mk_v-1-chapter-1');
      expect(result.chapters.last.title, 'Ch.18.2');
      // Trailing pg-N stripped from the id.
      expect(result.chapters.last.id, 'mkk/nml_chapter-18.2');
      expect(result.chapters.first.mangaId, 'jinx');
    });

    test('parseChapter decrypts imgsrcs into the full image list', () {
      // AES-128-CBC (ZeroPadding) ciphertext of:
      //   <url1>,<url2>,<cspiclink placeholder>,1
      // produced with the site's fixed key/IV. The cspiclink entry and the
      // trailing "1" flag must be dropped.
      const cipher =
          '0rIV9sZ8fWHELOHLFLl0T1p6nL0Pt1O15exDQR7zTIGUJ+vN/zfb4yjNyNwRhFX'
          '1eGRuPWOTJ5nuFzhBoWqx49VI+M+VmVVTaPiurM2YHUKgN2cv2vka5jR/Z0Cc6W'
          'EKROo9mWsruQ4Y0fn/0EWA9IrzbpqLGWeD1M0gbTQJl+XBJ3NXcsvS+MOjeFESW'
          'H78utow5QseRrTc/MBZf+aBKUyxSUrze6qGKWnkZyrMJX1hvAmYJzyb/l6APigX'
          '2k9giozVqZBCUwtW4P0cXgv5MPl9JUnHKg6pNV5RVZTrf9c=';
      const html = "<script>var imgsrcs = '$cipher';</script>";

      final result =
          source.parseChapter(html, 'jinx', 'uu/br_chapter-128596', 1);
      // 2 real URLs; cspiclink placeholder and trailing "1" flag dropped.
      expect(result.chapter.images.length, 2);
      expect(result.chapter.images[0].url,
          'https://iweb15.mangapicgallery.com/r/newpiclink/jinx/128596/128596_1.jpg');
      expect(result.chapter.images[1].url,
          'https://iweb15.mangapicgallery.com/r/newpiclink/jinx/128596/128596_2.jpg');
      expect(result.chapter.images[0].headers?['Referer'],
          'https://www.mangago.me/');
      // Whole chapter fetched at once — no pagination.
      expect(result.canLoadMore, false);
      expect(result.nextPage, isNull);
    });

    test('parseChapter returns no images when imgsrcs is missing', () {
      const html = '<div id="pic_container"></div>';
      final result =
          source.parseChapter(html, 'jinx', 'uu/br_chapter-128596', 1);
      expect(result.chapter.images, isEmpty);
      expect(result.canLoadMore, false);
    });
  });
}
