import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';

Widget buildWebViewScreen({
  required BuildContext context,
  required String sourceId,
  String? initialUrl,
}) {
  return _NativeWebViewScreen(sourceId: sourceId, initialUrl: initialUrl);
}

class _NativeWebViewScreen extends StatefulWidget {
  final String sourceId;
  final String? initialUrl;

  const _NativeWebViewScreen({required this.sourceId, this.initialUrl});

  @override
  State<_NativeWebViewScreen> createState() => _NativeWebViewScreenState();
}

class _NativeWebViewScreenState extends State<_NativeWebViewScreen> {
  // Use a standard browser UA to avoid Cloudflare blocking WebView
  static const String _defaultUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 '
      'Mobile/15E148 Safari/604.1';

  InAppWebViewController? _controller;
  final AuthStore _authStore = GetIt.instance<AuthStore>();
  final SourceRegistry _registry = GetIt.instance<SourceRegistry>();
  String _title = '验证中...';
  double _progress = 0;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _configureProxy();
  }

  /// Configure WebView proxy to match app settings.
  /// InAppWebView's ProxyController only works on Android.
  /// On macOS/iOS (WKWebView), system proxy settings are used automatically.
  /// We log the proxy state for debugging.
  Future<void> _configureProxy() async {
    final settingsStore = GetIt.instance<SettingsStore>();
    final settings = await settingsStore.load();
    debugPrint('[WebView] Proxy config: enabled=${settings.proxyEnabled} address=${settings.proxyAddress}');

    if (settings.proxyEnabled && settings.proxyAddress.isNotEmpty) {
      if (Platform.isAndroid) {
        // Android: use InAppWebView's ProxyController
        final proxyController = ProxyController.instance();
        await proxyController.clearProxyOverride();
        await proxyController.setProxyOverride(
          settings: ProxySettings(
            proxyRules: [
              ProxyRule(url: 'http://${settings.proxyAddress}'),
            ],
          ),
        );
        debugPrint('[WebView] Android proxy set to: ${settings.proxyAddress}');
      } else {
        // macOS/iOS: WKWebView respects system proxy settings
        // Log a hint if proxy is enabled in app but might not be in system
        debugPrint('[WebView] macOS/iOS: WKWebView uses system proxy settings.');
        debugPrint('[WebView] Make sure system proxy is configured to: ${settings.proxyAddress}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _registry.get(widget.sourceId);
    final url = widget.initialUrl ?? source?.href ?? '';
    debugPrint('[WebView] Building with sourceId=${widget.sourceId} url=$url userAgent=${source?.userAgent ?? _defaultUserAgent}');

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_verified)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.check_circle, color: Colors.green),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1.0)
            LinearProgressIndicator(value: _progress),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(url)),
              initialSettings: InAppWebViewSettings(
                userAgent: source?.userAgent ?? _defaultUserAgent,
                sharedCookiesEnabled: true,
                thirdPartyCookiesEnabled: true,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                cacheEnabled: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                supportZoom: true,
                builtInZoomControls: true,
                displayZoomControls: false,
                javaScriptCanOpenWindowsAutomatically: true,
                mediaPlaybackRequiresUserGesture: true,
                allowsInlineMediaPlayback: true,
                allowsBackForwardNavigationGestures: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'onData',
                  callback: (args) async {
                    if (args.isNotEmpty && args[0] is Map) {
                      final data = Map<String, dynamic>.from(args[0] as Map);
                      await _onDataReceived(data);
                    }
                  },
                );
              },
              onProgressChanged: (controller, progress) {
                setState(() => _progress = progress / 100.0);
              },
              onTitleChanged: (controller, title) {
                setState(() => _title = title ?? '验证中...');
              },
              onLoadStart: (controller, url) {
                debugPrint('[WebView] onLoadStart: $url');
              },
              onLoadStop: (controller, url) async {
                debugPrint('[WebView] onLoadStop: $url');
                await _injectCookieExtractor(controller);
              },
              onLoadError: (controller, url, code, message) {
                debugPrint('[WebView] onLoadError: $url code=$code msg=$message');
              },
              onLoadHttpError: (controller, url, statusCode, description) {
                debugPrint('[WebView] onLoadHttpError: $url status=$statusCode desc=$description');
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('[WebView] console: ${consoleMessage.message}');
              },
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                // Accept all SSL certificates for verification page
                return ServerTrustAuthResponse(
                  action: ServerTrustAuthResponseAction.PROCEED,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _injectCookieExtractor(InAppWebViewController controller) async {
    final source = _registry.get(widget.sourceId);

    if (source?.injectedJavaScript != null) {
      await controller.evaluateJavascript(source: source!.injectedJavaScript!);
      return;
    }

    // Get current URL for CookieManager
    final currentUrl = await controller.getUrl();
    if (currentUrl == null) return;

    // Get page title to check if still on challenge page
    final title = await controller.getTitle() ?? '';
    debugPrint('[WebView] Page title: "$title"');
    if (title == 'Just a moment...' ||
        title.contains('Attention Required') ||
        title == '403 Forbidden') {
      debugPrint('[WebView] Still on CF challenge page, skipping cookie extraction');
      return;
    }

    // Strategy 1: Use CookieManager to get cookies (works on most platforms)
    final cookies =
        await CookieManager.instance().getCookies(url: currentUrl);
    debugPrint('[WebView] CookieManager returned ${cookies.length} cookies');
    for (final c in cookies) {
      debugPrint('[WebView]   cookie: ${c.name}=${c.value.toString().substring(0, (c.value.toString().length > 20) ? 20 : c.value.toString().length)}... (httpOnly=${c.isHttpOnly})');
    }

    // Build cookie string from CookieManager
    String cookieStr =
        cookies.map((c) => '${c.name}=${c.value}').join('; ');

    // Strategy 2: If CookieManager didn't get cf_clearance, try JS document.cookie
    // as a supplement (note: JS can't access httpOnly cookies, but on some macOS
    // WKWebView versions, CookieManager also can't access them)
    if (!cookieStr.contains('cf_clearance')) {
      debugPrint('[WebView] cf_clearance NOT found via CookieManager, trying JS fallback...');
      final jsCookies = await controller.evaluateJavascript(
              source: 'document.cookie') as String? ??
          '';
      debugPrint('[WebView] JS document.cookie: $jsCookies');
      if (jsCookies.contains('cf_clearance')) {
        // Merge JS cookies with CookieManager cookies
        if (cookieStr.isNotEmpty) {
          cookieStr = '$cookieStr; $jsCookies';
        } else {
          cookieStr = jsCookies;
        }
      } else if (cookieStr.isEmpty && jsCookies.isNotEmpty) {
        cookieStr = jsCookies;
      }
    }

    // Strategy 3: If still no cf_clearance, try getting cookies for the base domain
    // (handles cases where cookie domain is .wnacg.com but URL is www.wnacg.com)
    if (!cookieStr.contains('cf_clearance') && currentUrl.host.startsWith('www.')) {
      final baseDomain = currentUrl.host.substring(4); // remove "www."
      final baseUrl = WebUri('https://$baseDomain/');
      debugPrint('[WebView] Trying base domain cookies for: $baseUrl');
      final baseCookies = await CookieManager.instance().getCookies(url: baseUrl);
      for (final c in baseCookies) {
        if (c.name == 'cf_clearance') {
          debugPrint('[WebView] Found cf_clearance from base domain!');
          if (cookieStr.isNotEmpty) {
            cookieStr = '$cookieStr; ${c.name}=${c.value}';
          } else {
            cookieStr = '${c.name}=${c.value}';
          }
          break;
        }
      }
    }

    debugPrint('[WebView] Final cookie string (${cookieStr.length} chars): ${cookieStr.substring(0, cookieStr.length > 80 ? 80 : cookieStr.length)}...');

    if (cookieStr.isNotEmpty) {
      // Get user agent from JS
      final ua = await controller.evaluateJavascript(
              source: 'navigator.userAgent') as String? ??
          '';
      debugPrint('[WebView] User-Agent: $ua');

      await _onDataReceived({
        'cookie': cookieStr,
        'userAgent': ua,
        'title': title,
      });
    } else {
      debugPrint('[WebView] WARNING: No cookies obtained after all strategies!');
    }
  }

  Future<void> _onDataReceived(Map<String, dynamic> data) async {
    final cookie = data['cookie'] as String?;
    if (cookie == null || cookie.isEmpty) return;

    await _authStore.saveExtra(widget.sourceId, data);

    final source = _registry.get(widget.sourceId);
    source?.syncExtraData(data);

    if (!_verified) {
      setState(() => _verified = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('验证成功！Cookie 已保存'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
