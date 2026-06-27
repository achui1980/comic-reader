import 'package:flutter/material.dart';

/// Stub for non-web platforms - web direct image is only used on web.
/// Returns null to signal that the caller should use the normal loading path.
Widget? buildWebDirectImage({
  required String imageUrl,
  required BoxFit fit,
  required String viewId,
}) {
  return null;
}
