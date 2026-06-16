import 'package:comic_reader/data/sources/ehentai.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:dio/dio.dart';

void main() async {
  final source = EHentai();
  final httpClient = HttpClient(dio: Dio());
  
  // Use a known gallery - let's use Seira_Kasai test gallery
  // gid/token from URL: e-hentai.org/g/3249614/bf7e7faed1/
  final mangaId = '3249614';
  final chapterId = '3249614/bf7e7faed1';
  
  print('--- Testing E-Hentai chapter fetch ---');
  print('Gallery: https://e-hentai.org/g/$chapterId/');
  
  // Step 1: Fetch gallery thumbnail page
  final config = source.prepareChapterFetch(mangaId, chapterId, 0);
  print('\nFetch URL: ${config.url}');
  print('Query: ${config.queryParameters}');
  
  final response = await httpClient.execute(FetchConfig(
    url: config.url,
    queryParameters: config.queryParameters,
    headers: {'Referer': 'https://e-hentai.org'},
  ));
  
  print('\nResponse length: ${(response.data as String).length} chars');
  
  // Step 2: Parse chapter
  final result = source.parseChapter(response.data, mangaId, chapterId, 0);
  print('\nParsed:');
  print('  images.length: ${result.chapter.images.length}');
  print('  canLoadMore: ${result.canLoadMore}');
  print('  nextPage: ${result.nextPage}');
  print('  nextExtra is null: ${result.nextExtra == null}');
  
  if (result.nextExtra != null) {
    final urls = result.nextExtra!;
    // Show first 3 URLs
    final decoded = urls.substring(0, urls.length.clamp(0, 500));
    print('  nextExtra (first 500 chars): $decoded');
  }
  
  // Step 3: If we have image page URLs, try fetching one
  if (result.nextExtra != null) {
    import 'dart:convert';
    // Can't import above, let's use raw parsing
    final allUrls = result.nextExtra!;
    // Extract first URL from JSON array
    final firstUrl = allUrls.split('"')[1];
    print('\n--- Fetching image page: $firstUrl ---');
    
    final imgResp = await httpClient.execute(FetchConfig(
      url: firstUrl,
      headers: {'Referer': 'https://e-hentai.org'},
    ));
    
    final imgHtml = imgResp.data as String;
    print('Image page length: ${imgHtml.length}');
    
    // Find img#img
    final match1 = RegExp(r'<img[^>]+id="img"[^>]+src="([^"]+)"').firstMatch(imgHtml);
    final match2 = RegExp(r'<img[^>]+src="([^"]+)"[^>]+id="img"').firstMatch(imgHtml);
    final imgSrc = match1?.group(1) ?? match2?.group(1);
    print('Resolved image URL: $imgSrc');
  }
}
