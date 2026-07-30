import 'package:flutter/foundation.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/hitomi.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'fetch_pipeline.dart';

/// Hitomi: enrich nozomi ID list with galleryblock HTML to get titles and covers.
/// Fetches galleryblock/{id}.html in parallel for each ID.
Future<List<MangaSummary>> enrichHitomiResults(
  HttpClient httpClient,
  FetchPipeline pipeline,
  Hitomi source,
  dynamic responseData,
) async {
  final ids = source.parseNozomiIds(responseData);
  debugPrint('[Hitomi] Enriching ${ids.length} gallery IDs with galleryblock...');

  if (ids.isEmpty) return [];

  // Fetch galleryblock HTML for each ID in parallel
  final futures = ids.map((id) async {
    try {
      var config = source.prepareGalleryBlockFetch(id);
      config = pipeline.mergeHeaders(config, source);
      final response = await httpClient.execute(config);
      final html = response.data?.toString() ?? '';
      return source.parseGalleryBlock(html, id);
    } catch (e) {
      debugPrint('[Hitomi] Failed to fetch galleryblock for $id: $e');
      // Return a placeholder if fetch fails
      return MangaSummary(
        id: id,
        sourceId: Hitomi.sourceId,
        title: 'Gallery #$id',
        coverUrl: '',
      );
    }
  }).toList();

  final results = await Future.wait(futures);
  final summaries = results.whereType<MangaSummary>().toList();
  debugPrint('[Hitomi] Enriched ${summaries.length} items, first: ${summaries.isNotEmpty ? summaries.first.id : "none"}');
  return summaries;
}
