import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'webview_fetcher.dart';

/// Native [WebViewFetcher] backed by a headless InAppWebView per source.
///
/// The webview navigates to the source's Cloudflare URL once so the CF
/// challenge is solved with the real WebKit/Chromium TLS fingerprint. All
/// subsequent requests are issued from inside that page via `fetch()`, so they
/// reuse the same fingerprint, cookies, and origin — bypassing the Dio/JA3
/// mismatch that causes 403s.
class _NativeWebViewFetcher implements WebViewFetcher {
  final Map<String, _SourceWebView> _instances = {};

  @override
  bool get isSupported => true;

  _SourceWebView _instanceFor(String sourceId) {
    return _instances.putIfAbsent(sourceId, () => _SourceWebView(sourceId));
  }

  @override
  Future<void> warmUp({
    required String sourceId,
    required String cloudflareUrl,
    String? userAgent,
  }) async {
    final wv = _instanceFor(sourceId);
    await wv.ensureReady(cloudflareUrl, userAgent);
  }

  @override
  Future<WebViewFetchResult> fetch({
    required String sourceId,
    required String cloudflareUrl,
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    String? userAgent,
    bool binary = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final wv = _instanceFor(sourceId);
    await wv.ensureReady(cloudflareUrl, userAgent);
    return wv.fetch(
      url: url,
      method: method,
      headers: headers,
      body: body,
      binary: binary,
      timeout: timeout,
    );
  }

  @override
  Future<void> dispose() async {
    for (final wv in _instances.values) {
      await wv.dispose();
    }
    _instances.clear();
  }
}

/// A single headless webview bound to one source, kept alive for reuse.
class _SourceWebView {
  final String sourceId;

  _SourceWebView(this.sourceId);

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  String? _navigatedUrl;
  bool _disposed = false;

  /// Ensure the webview is running and has finished loading [cloudflareUrl].
  Future<void> ensureReady(String cloudflareUrl, String? userAgent) async {
    if (_disposed) {
      throw StateError('WebViewFetcher for $sourceId already disposed');
    }
    if (_controller != null && _navigatedUrl == cloudflareUrl) {
      // Already navigated to the CF origin; assume session is warm.
      return;
    }

    // (Re)create the headless webview.
    await _teardown();

    final completer = Completer<void>();
    _navigatedUrl = cloudflareUrl;

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(cloudflareUrl)),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        cacheEnabled: true,
        sharedCookiesEnabled: true,
        thirdPartyCookiesEnabled: true,
        clearCache: false,
        incognito: false,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
      },
      onLoadStop: (controller, url) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onReceivedError: (controller, request, error) {
        if (!completer.isCompleted) {
          // Do not fail hard on subresource errors; the page may still be
          // usable for fetch(). Complete so we can proceed.
          completer.complete();
        }
      },
      onReceivedServerTrustAuthRequest: (controller, challenge) async {
        return ServerTrustAuthResponse(
          action: ServerTrustAuthResponseAction.PROCEED,
        );
      },
    );

    _headless = headless;
    await headless.run();

    // Wait for initial load (bounded so we never hang forever).
    try {
      await completer.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      debugPrint('[WVFetch] $sourceId warm-up load timed out, proceeding');
    }

    // Give Cloudflare's JS challenge a brief moment to settle after load.
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  Future<WebViewFetchResult> fetch({
    required String url,
    required String method,
    Map<String, String>? headers,
    String? body,
    required bool binary,
    required Duration timeout,
  }) async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('WebView for $sourceId not ready');
    }

    // JS runs fetch() in the page origin. For binary we read an ArrayBuffer and
    // base64-encode it; for text we read response.text(). Returns a plain
    // object so callAsyncJavaScript can serialize it.
    const functionBody = r'''
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const resp = await fetch(url, {
          method: method,
          headers: headers || {},
          body: (method === 'GET' || method === 'HEAD') ? undefined : (body || undefined),
          credentials: 'include',
          redirect: 'follow',
          signal: controller.signal,
        });
        const status = resp.status;
        const contentType = resp.headers.get('content-type') || '';
        if (binary) {
          const buf = await resp.arrayBuffer();
          let binaryStr = '';
          const bytesArr = new Uint8Array(buf);
          const chunk = 0x8000;
          for (let i = 0; i < bytesArr.length; i += chunk) {
            binaryStr += String.fromCharCode.apply(
              null, bytesArr.subarray(i, i + chunk));
          }
          const b64 = btoa(binaryStr);
          return { status: status, contentType: contentType, base64: b64 };
        } else {
          const text = await resp.text();
          return { status: status, contentType: contentType, text: text };
        }
      } catch (e) {
        return { status: 0, error: String(e) };
      } finally {
        clearTimeout(timer);
      }
    ''';

    final result = await controller.callAsyncJavaScript(
      functionBody: functionBody,
      arguments: <String, dynamic>{
        'url': url,
        'method': method,
        'headers': headers ?? <String, String>{},
        'body': body,
        'binary': binary,
        'timeoutMs': timeout.inMilliseconds,
      },
    );

    if (result == null) {
      throw StateError('WebView fetch returned null for $url');
    }
    if (result.error != null) {
      throw StateError('WebView fetch JS error for $url: ${result.error}');
    }

    final value = result.value;
    if (value is! Map) {
      throw StateError('WebView fetch unexpected result type for $url');
    }
    final map = Map<String, dynamic>.from(value);
    final jsError = map['error'];
    if (jsError != null) {
      throw StateError('WebView fetch failed for $url: $jsError');
    }

    final status = (map['status'] as num?)?.toInt() ?? 0;
    final contentType = map['contentType'] as String?;

    if (binary) {
      final b64 = map['base64'] as String? ?? '';
      final bytes = b64.isEmpty ? <int>[] : base64.decode(b64);
      return WebViewFetchResult(
        statusCode: status,
        bytes: bytes,
        contentType: contentType,
      );
    } else {
      final text = map['text'] as String? ?? '';
      return WebViewFetchResult(
        statusCode: status,
        body: text,
        contentType: contentType,
      );
    }
  }

  Future<void> _teardown() async {
    final headless = _headless;
    _controller = null;
    _headless = null;
    if (headless != null) {
      try {
        await headless.dispose();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
  }
}

WebViewFetcher createWebViewFetcher() => _NativeWebViewFetcher();
