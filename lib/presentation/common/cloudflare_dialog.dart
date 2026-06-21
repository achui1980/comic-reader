import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/data/remote/cloudflare_interceptor.dart';

/// Shows a dialog prompting the user to complete Cloudflare verification.
/// Returns true if user navigated to WebView and returned (regardless of result).
Future<bool> showCloudflareDialog(BuildContext context, {String? sourceId, String? sourceName}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.shield_outlined, size: 48, color: Colors.orange),
      title: const Text('需要验证'),
      content: Text(
        sourceName != null
            ? '$sourceName 需要完成 Cloudflare 人机验证后才能访问。\n\n点击「去验证」将打开网页，请手动完成验证。'
            : '该站点需要完成 Cloudflare 人机验证后才能访问。\n\n点击「去验证」将打开网页，请手动完成验证。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.verified_user_outlined, size: 18),
          label: const Text('去验证'),
        ),
      ],
    ),
  );

  if (result == true && sourceId != null && context.mounted) {
    // await push so caller knows when user returns from WebView
    await context.push(AppRoutes.webviewPath(sourceId));
    return true;
  }
  return false;
}

/// Checks if an error is a CloudflareException and shows the dialog if so.
/// Returns true if it was a CF error and was handled.
Future<bool> handleCloudflareError(BuildContext context, Object error, {String? sourceName}) async {
  CloudflareException? cfException;

  if (error is CloudflareException) {
    cfException = error;
  } else if (error.toString().contains('CloudflareException')) {
    // Extract sourceId from error string if possible
    final match = RegExp(r'source: (\w+)').firstMatch(error.toString());
    cfException = CloudflareException(
      sourceId: match?.group(1) ?? '',
      url: '',
    );
  }

  if (cfException != null && cfException.sourceId.isNotEmpty) {
    await showCloudflareDialog(
      context,
      sourceId: cfException.sourceId,
      sourceName: sourceName,
    );
    return true;
  }
  return false;
}
