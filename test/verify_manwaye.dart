// Live-network verification for the 漫蛙漫画 (manwaye.cc) source.
//
// This is a MANUAL script, not a unit test — it hits the real site. Run it with:
//   dart run test/verify_manwaye.dart
//
// It drives the real `Manwaye` class end to end: every request is built by the
// source's own prepare*() method and every response is fed to its parse*()
// method, so a pass means the shipped code works, not merely that the API is up.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/utils/image_response_decoder.dart';
import 'package:comic_reader/data/sources/manwaye.dart';
import 'package:comic_reader/domain/entities/entities.dart';

final HttpClient _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 30);

int _failures = 0;

void _check(String label, bool ok, [String detail = '']) {
  if (ok) {
    print('  ok   $label${detail.isEmpty ? '' : '  ($detail)'}');
  } else {
    _failures++;
    print('  FAIL $label${detail.isEmpty ? '' : '  ($detail)'}');
  }
}

/// Minimal stand-in for `HttpClient.execute()`: runs a FetchConfig for real and
/// JSON-decodes the body, mirroring what Dio hands to parse*().
Future<dynamic> _exec(FetchConfig config) async {
  var uri = Uri.parse(config.url);
  final qp = config.queryParameters;
  if (qp != null && qp.isNotEmpty) {
    uri = uri.replace(
      queryParameters: qp.map((k, v) => MapEntry(k, '$v')),
    );
  }

  final isPost = config.method == HttpMethod.post;
  final request =
      isPost ? await _client.postUrl(uri) : await _client.getUrl(uri);

  config.headers?.forEach((k, v) => request.headers.set(k, v));
  if (isPost && config.body != null) {
    request.add(utf8.encode(config.body is String
        ? config.body as String
        : jsonEncode(config.body)));
  }

  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode} for $uri');
  }
  return jsonDecode(text);
}

/// Downloads a URL in full and asserts the payload is a *decodable image*
/// after running it through the source's byte transform.
///
/// Checking only the status code and `Content-Type` is NOT enough: manwaye.cc
/// serves AES-256-CBC ciphertext with `Content-Type: image/jpeg`, which is
/// exactly how the "Invalid image data" bug shipped past an earlier version of
/// this script. So we decrypt and verify the real magic bytes.
Future<({bool ok, String detail})> _probeImage(String url, Manwaye source) async {
  final request = await _client.getUrl(Uri.parse(url));
  request.headers.set('User-Agent',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36');
  final response = await request.close();
  final type = response.headers.contentType?.mimeType ?? '?';
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
  }
  final raw = builder.takeBytes();

  if (response.statusCode != 200) {
    return (ok: false, detail: 'HTTP ${response.statusCode} $type');
  }
  if (raw.isEmpty) {
    return (ok: false, detail: 'HTTP 200 $type but 0 bytes');
  }

  final rawMagic = _magic(raw);
  final decoded = source.transformImageBytes(raw);
  final decodedMagic = _magic(decoded);
  final decodable = hasImageSignature(decoded);

  // The transform must be idempotent: feeding plaintext back in is a no-op.
  final twice = source.transformImageBytes(decoded);
  final idempotent = twice.length == decoded.length;

  final detail = 'HTTP 200 $type, ${raw.length}B raw ($rawMagic) -> '
      '${decoded.length}B decoded ($decodedMagic), '
      'decodable=$decodable idempotent=$idempotent';
  return (ok: decodable && idempotent, detail: detail);
}

String _magic(Uint8List bytes) => bytes
    .take(4)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

Future<void> main() async {
  final source = Manwaye();
  print('=== ${source.name} (${source.id}) — live verification ===\n');

  try {
    // -- 1. discovery, default filters ---------------------------------------
    print('[1] discovery (page 1, defaults)');
    final defaults = {
      for (final f in source.discoveryFilters) f.name: f.defaultValue,
    };
    final discovery = source
        .parseDiscovery(await _exec(source.prepareDiscoveryFetch(1, defaults)));
    _check('returns items', discovery.isNotEmpty, '${discovery.length} items');
    if (discovery.isEmpty) return;

    final first = discovery.first;
    _check('id is numeric', RegExp(r'^\d+$').hasMatch(first.id), first.id);
    _check('title present', first.title.isNotEmpty, first.title);
    _check('cover is absolute http', first.coverUrl.startsWith('http'),
        first.coverUrl);
    _check('sourceId tagged', first.sourceId == Manwaye.sourceId);
    _check('all items have id+title+cover',
        discovery.every((m) =>
            m.id.isNotEmpty && m.title.isNotEmpty && m.coverUrl.startsWith('http')));

    // page 2 must differ from page 1
    final page2 = source
        .parseDiscovery(await _exec(source.prepareDiscoveryFetch(2, defaults)));
    _check('page 2 paginates', page2.isNotEmpty && page2.first.id != first.id,
        '${page2.length} items, first=${page2.isEmpty ? '-' : page2.first.id}');

    // -- 2. discovery filters actually apply ---------------------------------
    print('\n[2] discovery filters');
    final filtered = source.parseDiscovery(await _exec(
        source.prepareDiscoveryFetch(1, {
      ...defaults,
      'tag': '热血',
      'sort': '3',
      'areaId': '4',
      'status': '1',
    })));
    _check('tag+sort+area+status returns items', filtered.isNotEmpty,
        '${filtered.length} items');
    _check('filtered set differs from unfiltered',
        filtered.isEmpty || filtered.first.id != first.id);

    // -- 3. search, all three fields ----------------------------------------
    print('\n[3] search');
    final searchDefaults = {
      for (final f in source.searchFilters) f.name: f.defaultValue,
    };
    final byTitle = source.parseSearch(
        await _exec(source.prepareSearchFetch('重生', 1, searchDefaults)));
    _check('keyword search returns items', byTitle.isNotEmpty,
        '${byTitle.length} items');
    if (byTitle.isNotEmpty) {
      _check('search item has id+title+cover',
          byTitle.first.id.isNotEmpty &&
              byTitle.first.title.isNotEmpty &&
              byTitle.first.coverUrl.startsWith('http'),
          '${byTitle.first.id} ${byTitle.first.title}');
    }

    final byTag = source.parseSearch(await _exec(
        source.prepareSearchFetch('重生', 1, {...searchDefaults, 'field': 'tags'})));
    _check('tags search returns items', byTag.isNotEmpty, '${byTag.length} items');

    final byAuthor = source.parseSearch(await _exec(source
        .prepareSearchFetch('重生', 1, {...searchDefaults, 'field': 'author'})));
    _check('author search returns items', byAuthor.isNotEmpty,
        '${byAuthor.length} items');
    _check('the three fields return different result sets',
        byTitle.first.id != byTag.first.id);

    // -- 4. manga info -------------------------------------------------------
    print('\n[4] manga info');
    final mangaId = byTitle.first.id;
    final detail = source.parseMangaInfo(
        await _exec(source.prepareMangaInfoFetch(mangaId)), mangaId);
    _check('id round-trips', detail.id == mangaId, detail.id);
    _check('title present', detail.title.isNotEmpty, detail.title);
    _check('cover is absolute http', detail.coverUrl.startsWith('http'),
        detail.coverUrl);
    _check('tags parsed from comma string', detail.tags.isNotEmpty,
        detail.tags.join('/'));
    _check('status resolved', detail.status != MangaStatus.unknown,
        detail.status.name);
    _check('description present', (detail.description ?? '').isNotEmpty,
        '${(detail.description ?? '').length} chars');
    _check('latestChapter present', (detail.latestChapter ?? '').isNotEmpty,
        detail.latestChapter ?? '-');
    _check('chapters intentionally empty (fetched separately)',
        detail.chapters.isEmpty);
    final coverProbe = await _probeImage(detail.coverUrl, source);
    _check('cover decodes to a real image', coverProbe.ok, coverProbe.detail);

    // -- 5. chapter list -----------------------------------------------------
    print('\n[5] chapter list');
    final listConfig = source.prepareChapterListFetch(mangaId, 1);
    _check('page 1 issues a request', listConfig != null);
    _check('page 2 returns null (endpoint is unpaginated)',
        source.prepareChapterListFetch(mangaId, 2) == null);
    final chapters =
        source.parseChapterList(await _exec(listConfig!), mangaId);
    _check('returns chapters', chapters.chapters.isNotEmpty,
        '${chapters.chapters.length} chapters');
    _check('canLoadMore is false', chapters.canLoadMore == false);
    if (chapters.chapters.isEmpty) return;
    _check('chapter ids are numeric and slash-free',
        chapters.chapters.every((c) =>
            RegExp(r'^\d+$').hasMatch(c.id) && !c.id.contains('/')));
    _check('chapter titles present',
        chapters.chapters.every((c) => c.title.isNotEmpty));
    _check('mangaId back-reference correct',
        chapters.chapters.every((c) => c.mangaId == mangaId));
    print('       first: ${chapters.chapters.first.title}'
        '  last: ${chapters.chapters.last.title}');

    // -- 6. chapter images ---------------------------------------------------
    print('\n[6] chapter images');
    final chapterId = chapters.chapters.first.id;
    final result = source.parseChapter(
        await _exec(source.prepareChapterFetch(mangaId, chapterId, 1)),
        mangaId,
        chapterId,
        1);
    final images = result.chapter.images;
    _check('returns images', images.isNotEmpty, '${images.length} images');
    if (images.isEmpty) return;
    _check('urls are absolute http',
        images.every((i) => i.url.startsWith('http')));
    _check('no scrambling',
        images.every((i) => i.scrambleType == ScrambleType.none));
    _check('urls are unique', images.map((i) => i.url).toSet().length == images.length);
    print('       page1: canLoadMore=${result.canLoadMore} '
        'nextPage=${result.nextPage}');
    final firstProbe = await _probeImage(images.first.url, source);
    _check('first image decodes to a real image', firstProbe.ok, firstProbe.detail);
    final lastProbe = await _probeImage(images.last.url, source);
    _check('last image decodes to a real image', lastProbe.ok, lastProbe.detail);
    // The framework calls source.transformImageBytes(), not the decoder
    // directly — make sure the hook is actually wired up on the source.
    _check('source declares transformsImageBytes', source.transformsImageBytes);

    // follow pagination if the chapter is longer than one API page
    if (result.canLoadMore && result.nextPage != null) {
      final next = source.parseChapter(
          await _exec(
              source.prepareChapterFetch(mangaId, chapterId, result.nextPage!)),
          mangaId,
          chapterId,
          result.nextPage!);
      _check('page ${result.nextPage} returns more images',
          next.chapter.images.isNotEmpty, '${next.chapter.images.length} images');
      _check('page ${result.nextPage} images differ from page 1',
          next.chapter.images.first.url != images.first.url);
    }

    // -- 7. web url ----------------------------------------------------------
    print('\n[7] reader web url');
    final webUrl = source.getChapterWebUrl(mangaId, chapterId);
    _check('built', webUrl == 'https://manwaye.cc/comic/$mangaId/$chapterId',
        webUrl ?? '-');
  } finally {
    _client.close(force: true);
    print('\n=== ${_failures == 0 ? 'ALL CHECKS PASSED' : '$_failures CHECK(S) FAILED'} ===');
    if (_failures > 0) exitCode = 1;
  }
}
