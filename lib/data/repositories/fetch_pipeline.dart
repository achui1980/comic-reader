import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/remote/cloudflare_interceptor.dart';
import 'package:comic_reader/data/sources/jm_comic.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/wu55comic.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Handles header merging, Cloudflare preflight checks, and domain
/// fallback/discovery retries for outgoing requests (was three private
/// methods on `MangaRepositoryImpl`).
class FetchPipeline {
  final HttpClient _httpClient;

  FetchPipeline(this._httpClient);

  /// Merge source auth headers (cookies from CF bypass) into config
  /// and inject source metadata into extras for interceptors.
  FetchConfig mergeHeaders(FetchConfig config, MangaSource source) {
    final extra = <String, dynamic>{
      'sourceId': source.id,
      'needsCloudflare': source.needsCloudflare,
      if (source.usesWebViewFetch && source.cloudflareUrl != null) ...{
        'useWebViewFetch': true,
        'cloudflareUrl': source.cloudflareUrl,
      },
      ...?config.extra,
    };
    final headers = <String, String>{
      ...?source.defaultHeaders,
      ...?config.headers,
      ...source.extraHeaders,
    };
    return config.copyWith(headers: headers, extra: extra);
  }

  /// Preflight check: HEAD-request the first image to detect CF on image CDN.
  /// Throws [CloudflareException] so the UI can prompt CF verification.
  Future<void> preflightImageCf(MangaSource source, ChapterImage image) async {
    try {
      final preflightConfig = FetchConfig(
        url: image.url,
        headers: {
          ...?source.defaultHeaders,
          ...source.extraHeaders,
        },
        responseType: ResponseType.plain,
      );
      final merged = mergeHeaders(preflightConfig, source);
      await _httpClient.execute(merged);
      // If we get here, image CDN is accessible — no CF block.
    } on DioException catch (e) {
      // If the interceptor already converted it to CloudflareException, rethrow
      if (e.error is CloudflareException) rethrow;
      // Manual detection for 403 without interceptor catching it
      if (e.response?.statusCode == 403) {
        final body = e.response?.data?.toString() ?? '';
        if (body.contains('cloudflare') || body.contains('Cloudflare') ||
            body.contains('cf_chl_opt') || body.contains('challenges.cloudflare.com')) {
          throw DioException(
            requestOptions: e.requestOptions,
            response: e.response,
            type: DioExceptionType.unknown,
            error: CloudflareException(
              sourceId: source.id,
              url: source.cloudflareUrl ?? image.url,
            ),
          );
        }
      }
      // Non-CF error — don't block chapter loading
      debugPrint('[_preflightImageCf] Non-CF error: $e');
    } catch (e) {
      // Any non-Dio error (e.g. WebView-fetch StateError) must not crash the
      // reader. The preflight is best-effort CF detection only.
      debugPrint('[_preflightImageCf] Unexpected error (ignored): $e');
    }
  }

  /// Execute a request with domain fallback for JMComic and domain discovery for Wu55Comic.
  /// If request fails with a network/timeout error, switches to next domain and retries.
  Future<Response> executeWithFallback(
    FetchConfig config,
    MangaSource source,
    FetchConfig Function() rebuildConfig,
  ) async {
    if (source is! JmComic && source is! Wu55Comic) {
      return _httpClient.execute(config);
    }

    // For Wu55Comic: try execute, on failure attempt domain discovery + retry
    if (source is Wu55Comic) {
      try {
        return await _httpClient.execute(config);
      } catch (e) {
        debugPrint('[Wu55] Request failed: $e, trying domain discovery...');
        try {
          final discoveryConfig = source.prepareDomainDiscoveryFetch();
          final discoveryResponse = await _httpClient.execute(discoveryConfig);
          final changed = source.parseDomainDiscovery(discoveryResponse.data);
          if (changed) {
            debugPrint('[Wu55] Domain updated to: ${source.baseUrl}');
            final newConfig = rebuildConfig();
            return await _httpClient.execute(mergeHeaders(newConfig, source));
          }
        } catch (de) {
          debugPrint('[Wu55] Domain discovery also failed: $de');
        }
        rethrow;
      }
    }

    // For JmComic: rotate through fallback domains
    final jmSource = source as JmComic;
    Object? lastError;

    for (int attempt = 0; attempt <= jmSource.maxDomainRetries; attempt++) {
      try {
        final effectiveConfig = attempt == 0 ? config : mergeHeaders(rebuildConfig(), source);
        return await _httpClient.execute(effectiveConfig);
      } on DioException catch (e) {
        lastError = e;
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          debugPrint('[JMC Fallback] Domain failed (${e.type}), switching to next domain...');
          jmSource.switchToNextDomain();
          continue;
        }
        // Non-timeout errors (e.g., 403) — also try next domain
        if (e.response?.statusCode == 403 || e.response?.statusCode == 502 || e.response?.statusCode == 503) {
          debugPrint('[JMC Fallback] HTTP ${e.response?.statusCode}, switching domain...');
          jmSource.switchToNextDomain();
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('All JMC domains exhausted');
  }
}
