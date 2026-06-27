import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:comic_reader/data/sources/jcomic.dart';

/// Manual verification script for JComic source.
/// Run with: dart run test/verify_jcomic.dart
void main() async {
  final source = JComic();

  print('=== JComic Source Verification ===\n');

  // 1. Test discovery
  print('--- Discovery (最近更新, page 1) ---');
  final discoveryConfig =
      source.prepareDiscoveryFetch(1, {'category': '最近更新'});
  print('URL: ${discoveryConfig.url}');

  final discoveryResp = await http.get(
    Uri.parse(discoveryConfig.url),
    headers: discoveryConfig.headers,
  );
  print('Status: ${discoveryResp.statusCode}');

  if (discoveryResp.statusCode == 200) {
    final items = source.parseDiscovery(discoveryResp.body);
    print('Found ${items.length} items');
    if (items.isNotEmpty) {
      final first = items.first;
      print('  First: ${first.title} (id=${first.id}, author=${first.author})');
      if (first.coverUrl.length > 80) {
        print('  Cover: ${first.coverUrl.substring(0, 80)}...');
      } else {
        print('  Cover: ${first.coverUrl}');
      }
    }

    // 2. Test manga info (pick first multi-chapter item)
    final multiItem =
        items.where((i) => !i.id.startsWith('__single__')).firstOrNull;
    if (multiItem != null) {
      print('\n--- Manga Info (multi-chapter: ${multiItem.title}) ---');
      final infoConfig = source.prepareMangaInfoFetch(multiItem.id);
      print('URL: ${infoConfig.url}');
      final infoResp = await http.get(
        Uri.parse(infoConfig.url),
        headers: infoConfig.headers,
      );
      print('Status: ${infoResp.statusCode}');
      if (infoResp.statusCode == 200) {
        final detail = source.parseMangaInfo(infoResp.body, multiItem.id);
        print('  Title: ${detail.title}');
        print('  Author: ${detail.author}');
        print('  Tags: ${detail.tags.join(", ")}');
        print('  Chapters: ${detail.chapters.length}');
        if (detail.chapters.isNotEmpty) {
          print(
              '  First chapter: ${detail.chapters.first.title} (id=${detail.chapters.first.id})');

          // 3. Test chapter content
          print('\n--- Chapter Content ---');
          final chConfig = source.prepareChapterFetch(
              multiItem.id, detail.chapters.first.id, 1);
          print('URL: ${chConfig.url}');
          final chResp = await http.get(
            Uri.parse(chConfig.url),
            headers: chConfig.headers,
          );
          print('Status: ${chResp.statusCode}');
          if (chResp.statusCode == 200) {
            final result = source.parseChapter(
                chResp.body, multiItem.id, detail.chapters.first.id, 1);
            print('  Images: ${result.chapter.images.length}');
            if (result.chapter.images.isNotEmpty) {
              final imgUrl = result.chapter.images.first.url;
              if (imgUrl.length > 80) {
                print('  First image: ${imgUrl.substring(0, 80)}...');
              } else {
                print('  First image: $imgUrl');
              }
            }
          }
        }
      }
    }

    // 4. Test single-chapter item
    final singleItem =
        items.where((i) => i.id.startsWith('__single__')).firstOrNull;
    if (singleItem != null) {
      print('\n--- Manga Info (single-chapter: ${singleItem.title}) ---');
      final infoConfig = source.prepareMangaInfoFetch(singleItem.id);
      print('URL: ${infoConfig.url}');
      final infoResp = await http.get(
        Uri.parse(infoConfig.url),
        headers: infoConfig.headers,
      );
      print('Status: ${infoResp.statusCode}');
      if (infoResp.statusCode == 200) {
        final detail = source.parseMangaInfo(infoResp.body, singleItem.id);
        print('  Title: ${detail.title}');
        print('  Chapters: ${detail.chapters.length} (should be 1)');
      }
    }
  }

  // 5. Test search
  print('\n--- Search (keyword: "火影") ---');
  final searchConfig = source.prepareSearchFetch('火影', 1, {});
  print('URL: ${searchConfig.url}');
  final searchResp = await http.get(
    Uri.parse(searchConfig.url),
    headers: searchConfig.headers,
  );
  print('Status: ${searchResp.statusCode}');
  if (searchResp.statusCode == 200) {
    final searchItems = source.parseSearch(searchResp.body);
    print('Found ${searchItems.length} results');
    if (searchItems.isNotEmpty) {
      print('  First: ${searchItems.first.title}');
    }
  }

  print('\n=== Verification Complete ===');
  exit(0);
}
