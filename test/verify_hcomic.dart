// Quick test: verify h_comic SSR data parsing works
// Run with: dart run test/verify_hcomic.dart

import 'dart:io';
import 'dart:convert';
import 'package:comic_reader/data/sources/h_comic.dart';

void main() async {
  final source = HComic();
  print('Testing HComic source...');

  // Fetch real HTML
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse('https://h-comic.com/?page=1'));
  final response = await request.close();
  final html = await response.transform(utf8.decoder).join();
  print('HTML length: ${html.length}');

  // Debug: check if marker regex matches
  final marker = RegExp(r'(?:"data"|data)\s*:\s*\[null,\{"type":"data","data":\{');
  final markerMatch = marker.firstMatch(html);
  print('Marker match: ${markerMatch != null}');
  if (markerMatch != null) {
    print('  Match at: ${markerMatch.start}-${markerMatch.end}');
    print('  Matched text: "${html.substring(markerMatch.start, markerMatch.end)}"');

    // Show what comes after
    final after = html.substring(markerMatch.end, markerMatch.end + 100);
    print('  After marker: "$after"');

    // Simulate extraction logic
    final dataStart = markerMatch.end;
    final scriptEnd = html.indexOf('</script>', dataStart);
    print('  Script end at: $scriptEnd');
    final segment = html.substring(dataStart, scriptEnd);
    print('  Segment length: ${segment.length}');

    // Check uses marker
    const usesMarker = ',"uses":';
    final usesIdx = segment.lastIndexOf(usesMarker);
    print('  Uses marker at: $usesIdx');
    if (usesIdx != -1) {
      print('  Content before uses (last 50 chars): "${segment.substring(usesIdx - 50, usesIdx)}"');
      final jsContent = segment.substring(0, usesIdx);
      final jsObj = '{$jsContent}';
      print('  JS obj first 100: "${jsObj.substring(0, 100)}"');
      print('  JS obj last 100: "${jsObj.substring(jsObj.length - 100)}"');
    }
  }

  // Test full parsing
  final results = source.parseDiscovery(html);
  print('\nParsed ${results.length} comics');
  if (results.isNotEmpty) {
    final first = results.first;
    print('  First: id=${first.id}, title=${first.title}');
    print('  Cover: ${first.coverUrl}');
    print('  Author: ${first.author}');
  }

  // Test reader page if discovery works
  if (results.isNotEmpty) {
    print('\n--- Reader Test ---');
    final mangaId = results.first.id;
    final req2 = await client.getUrl(
        Uri.parse('https://h-comic.com/comics/$mangaId/reader'));
    final res2 = await req2.close();
    final html2 = await res2.transform(utf8.decoder).join();
    print('Reader HTML length: ${html2.length}');

    final detail = source.parseMangaInfo(html2, mangaId);
    print('Title: ${detail.title}');
    print('Author: ${detail.author}');
    print('Tags: ${detail.tags}');
    print('Chapters: ${detail.chapters.length}');

    final chapter = source.parseChapter(html2, mangaId, '1', 1);
    print('Images: ${chapter.chapter.images.length}');
    if (chapter.chapter.images.isNotEmpty) {
      print('  First: ${chapter.chapter.images.first.url}');
      print('  Last: ${chapter.chapter.images.last.url}');
    }
  }

  client.close();
  print('\nDone!');
}
