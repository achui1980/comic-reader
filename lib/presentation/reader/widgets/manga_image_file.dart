import 'package:flutter/material.dart';

/// Web stub - file loading is not supported on web.
/// This code path should never be reached because _canCache is false on web.
Widget buildFileImage({
  required String path,
  required BoxFit fit,
  required VoidCallback onFailed,
}) {
  return const Center(
    child: Text('File loading not supported on web'),
  );
}
