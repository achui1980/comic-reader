import 'package:flutter/foundation.dart' show kIsWeb;

/// Utility to proxy image URLs through the CORS proxy on web platform.
///
/// On native platforms, returns the URL unchanged.
/// On web, prepends the local CORS proxy URL so images can be loaded
/// without being blocked by browser CORS policy.
class ImageProxy {
  static const String _proxyBaseUrl = 'http://localhost:9090/';

  /// Browser-unsafe headers that cannot be set on web XMLHttpRequest/img tags.
  static const _unsafeHeaders = {'referer', 'user-agent', 'x-requested-with'};

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
  /// On web, removes headers that browsers refuse to set (Referer, User-Agent, etc.)
  /// since the CORS proxy handles them automatically.
  /// On native, returns headers unchanged.
  static Map<String, String>? safeHeaders(Map<String, String>? headers) {
    if (!kIsWeb || headers == null || headers.isEmpty) return headers;
    final filtered = <String, String>{};
    for (final entry in headers.entries) {
      if (!_unsafeHeaders.contains(entry.key.toLowerCase())) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered.isEmpty ? null : filtered;
  }
}
