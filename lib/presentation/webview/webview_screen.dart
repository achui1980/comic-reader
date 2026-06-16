import 'package:flutter/material.dart';

// Conditional import: use InAppWebView only on native platforms
import 'webview_native.dart' if (dart.library.html) 'webview_web.dart' as platform;

class WebViewScreen extends StatelessWidget {
  final String sourceId;
  final String? initialUrl;

  const WebViewScreen({
    super.key,
    required this.sourceId,
    this.initialUrl,
  });

  @override
  Widget build(BuildContext context) {
    return platform.buildWebViewScreen(
      context: context,
      sourceId: sourceId,
      initialUrl: initialUrl,
    );
  }
}
