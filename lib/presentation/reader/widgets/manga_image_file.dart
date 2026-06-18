import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';

/// Web stub - file loading is not supported on web.
/// This code path should never be reached because _canCache is false on web.
Widget buildFileImage({
  required String path,
  required BoxFit fit,
  required VoidCallback onFailed,
  Widget Function(ExtendedImageState state)? onCompleted,
}) {
  return const Center(
    child: Text('File loading not supported on web'),
  );
}
