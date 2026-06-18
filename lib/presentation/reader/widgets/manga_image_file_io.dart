import 'dart:io';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';

/// Native implementation - loads image from local file system.
/// [onCompleted] allows callers to provide a custom widget for completed state
/// (e.g., for JMC unscrambling). If null, uses default state.completedWidget.
Widget buildFileImage({
  required String path,
  required BoxFit fit,
  required VoidCallback onFailed,
  Widget Function(ExtendedImageState state)? onCompleted,
}) {
  return ExtendedImage.file(
    File(path),
    fit: fit,
    loadStateChanged: (state) {
      switch (state.extendedImageLoadState) {
        case LoadState.loading:
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        case LoadState.completed:
          if (onCompleted != null) {
            return onCompleted(state);
          }
          return state.completedWidget;
        case LoadState.failed:
          onFailed();
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
      }
    },
  );
}
