import 'package:flutter/foundation.dart' show kIsWeb;

/// Utility to proxy image URLs through the CORS proxy on web platform.
///
/// On native platforms, returns the URL unchanged.
/// On web, prepends the local CORS proxy URL so images can be loaded
/// without being blocked by browser CORS policy.
class ImageProxy {
  static const String _proxyBaseUrl = 'http://localhost:9090/';

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
}
