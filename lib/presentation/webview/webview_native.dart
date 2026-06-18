import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/data/local/auth_store.dart';
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
  Widget build(BuildContext context) {
    final source = _registry.get(widget.sourceId);
    final url = widget.initialUrl ?? source?.href ?? '';

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
                iframeAllow: 'cross-origin-isolated',
                iframeAllowFullscreen: true,
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
              onLoadStop: (controller, url) async {
                await _injectCookieExtractor(controller);
              },
              onCreateWindow: (controller, createWindowAction) async {
                // Allow Cloudflare Turnstile iframes to open
                // Return false to let the WebView handle it naturally
                return false;
              },
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
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
    if (title == 'Just a moment...') return;

    // Use CookieManager to get ALL cookies including httpOnly (cf_clearance etc.)
    final cookies =
        await CookieManager.instance().getCookies(url: currentUrl);
    if (cookies.isEmpty) return;

    // Build cookie string from CookieManager (includes httpOnly cookies)
    final cookieStr =
        cookies.map((c) => '${c.name}=${c.value}').join('; ');

    if (cookieStr.isNotEmpty) {
      // Get user agent from JS
      final ua = await controller.evaluateJavascript(
              source: 'navigator.userAgent') as String? ??
          '';

      await _onDataReceived({
        'cookie': cookieStr,
        'userAgent': ua,
        'title': title,
      });
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
