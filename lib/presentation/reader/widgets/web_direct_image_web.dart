// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Tracks registered view factories to avoid duplicate registration errors.
final Set<String> _registeredFactories = {};

/// Web implementation: loads image directly via HTML <img> element.
/// This bypasses CORS proxy and lets the browser use its own cookies
/// (including Cloudflare cf_clearance) to load the image.
///
/// NOTE: We intentionally do NOT set `referrerpolicy=no-referrer` here.
/// The default policy (strict-origin-when-cross-origin) sends the origin as
/// referrer, and — more importantly — lets the browser attach the
/// `cf_clearance` cookie (SameSite=None; Secure) that it obtained after the
/// user passed the Cloudflare challenge on the image CDN. Suppressing the
/// referrer previously also disturbed cookie handling and made every image
/// fail with a 403 challenge.
Widget? buildWebDirectImage({
  required String imageUrl,
  required BoxFit fit,
  required String viewId,
  VoidCallback? onLoadError,
}) {
  // Register a unique view factory for this image (only once per viewId).
  // Callers can force a fresh <img> (e.g. after passing the CF challenge) by
  // supplying a new viewId (see MangaCoverImage's reload nonce).
  final factoryId = 'web-direct-img-$viewId';

  if (!_registeredFactories.contains(factoryId)) {
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(factoryId, (int id) {
      final img = html.ImageElement()
        ..src = imageUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = _boxFitToCss(fit)
        ..style.display = 'block';
      if (onLoadError != null) {
        img.onError.listen((_) => onLoadError());
      }
      return img;
    });
    _registeredFactories.add(factoryId);
  }

  return HtmlElementView(viewType: factoryId);
}

String _boxFitToCss(BoxFit fit) {
  switch (fit) {
    case BoxFit.contain:
      return 'contain';
    case BoxFit.cover:
      return 'cover';
    case BoxFit.fill:
      return 'fill';
    case BoxFit.fitWidth:
      return 'contain'; // CSS doesn't have fit-width; contain is closest
    case BoxFit.fitHeight:
      return 'contain';
    case BoxFit.none:
      return 'none';
    case BoxFit.scaleDown:
      return 'scale-down';
  }
}
