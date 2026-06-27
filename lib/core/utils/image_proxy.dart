import 'package:flutter/foundation.dart' show kIsWeb;

/// Utility to proxy image URLs through the CORS proxy on web platform.
///
/// On native platforms, returns the URL unchanged.
/// On web, prepends the local CORS proxy URL so images can be loaded
/// without being blocked by browser CORS policy.
class ImageProxy {
  static const String _proxyBaseUrl = 'http://localhost:9090/';

  /// Browser-unsafe headers that cannot be set on web XMLHttpRequest/img tags.
  static const _unsafeHeaders = {'referer', 'user-agent', 'x-requested-with', 'cookie'};

  /// Returns a URL that can be loaded in the current platform.
  /// On web: proxied through localhost:9090
  /// On native: original URL unchanged
  static String url(String imageUrl) {
    if (!kIsWeb) return imageUrl;
    if (imageUrl.isEmpty) return imageUrl;
    // Don't double-proxy
    if (imageUrl.startsWith(_proxyBaseUrl)) return imageUrl;
    return '$_proxyBaseUrl$imageUrl';
  }

  /// Filter headers for image loading.
  /// On web, converts browser-unsafe headers (Referer, User-Agent) to
  /// X-Proxy-* prefixed versions so the CORS proxy can restore them.
  /// On native, returns headers unchanged.
  static Map<String, String>? safeHeaders(Map<String, String>? headers) {
    if (!kIsWeb || headers == null || headers.isEmpty) return headers;
    final filtered = <String, String>{};
    for (final entry in headers.entries) {
      final lower = entry.key.toLowerCase();
      if (lower == 'referer') {
        filtered['X-Proxy-Referer'] = entry.value;
      } else if (lower == 'user-agent') {
        filtered['X-Proxy-User-Agent'] = entry.value;
      } else if (lower == 'cookie') {
        filtered['X-Proxy-Cookie'] = entry.value;
      } else if (!_unsafeHeaders.contains(lower)) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered.isEmpty ? null : filtered;
  }
}
