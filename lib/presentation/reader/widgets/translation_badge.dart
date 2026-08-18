import 'package:flutter/material.dart';

/// Small circular badge shown over a page while it's being translated
/// (loading spinner) or after translation failed (tappable error icon).
class TranslationBadge extends StatelessWidget {
  const TranslationBadge.loading({super.key})
      : onTap = null,
        isError = false;
  const TranslationBadge.error({super.key, required VoidCallback this.onTap})
      : isError = true;

  final bool isError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: isError
          ? const Icon(Icons.error_outline, color: Colors.redAccent, size: 16)
          : const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
    );
    return isError ? GestureDetector(onTap: onTap, child: content) : content;
  }
}
