import 'package:dio/dio.dart';

/// Exception thrown when Cloudflare protection is detected.
class CloudflareException implements Exception {
  final String sourceId;
  final String url;
  final String message;

  CloudflareException({
    required this.sourceId,
    required this.url,
    this.message = '需要完成 Cloudflare 验证',
  });

  @override
  String toString() => 'CloudflareException: $message (source: $sourceId, url: $url)';
}

/// Interceptor that detects Cloudflare challenge pages in responses.
class CloudflareDetectorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Only check HTML responses
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.contains('text/html') && response.data is String) {
      final html = response.data as String;
      // Check for Cloudflare challenge indicators
      if (_isCloudflareChallenge(html)) {
        final sourceId = response.requestOptions.extra['sourceId'] as String? ?? '';
        handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.unknown,
            error: CloudflareException(
              sourceId: sourceId,
              url: response.requestOptions.uri.toString(),
            ),
          ),
        );
        return;
      }
    }
    handler.next(response);
  }

  bool _isCloudflareChallenge(String html) {
    // Check page title
    final titleMatch = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(html);
    if (titleMatch != null) {
      final title = titleMatch.group(1)?.trim() ?? '';
      if (title == 'Just a moment...' ||
          title == 'Attention Required! | Cloudflare' ||
          title == '403 Forbidden') {
        return true;
      }
    }
    // Check for CF challenge script markers
    if (html.contains('challenges.cloudflare.com') ||
        html.contains('cf-browser-verification') ||
        html.contains('cf_chl_opt')) {
      return true;
    }
    return false;
  }
}
