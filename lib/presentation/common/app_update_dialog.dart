import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:comic_reader/core/update/app_update_service.dart';

/// Shows a dialog informing the user that a newer app version is
/// available, with options to open the release page or skip this version.
Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdateInfo info,
  AppUpdateService service,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('发现新版本 ${info.version}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              info.changelog.isEmpty ? '暂无更新说明' : info.changelog,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await service.skipVersion(info.version);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('跳过此版本'),
          ),
          FilledButton(
            onPressed: () async {
              await launchUrl(
                Uri.parse(info.htmlUrl),
                mode: LaunchMode.externalApplication,
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('去下载'),
          ),
        ],
      );
    },
  );
}
