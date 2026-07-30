import 'package:flutter/material.dart';

/// Section header used by every settings section (was
/// `_SettingsView._buildSectionHeader`).
Widget buildSettingsSectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.deepPurple,
      ),
    ),
  );
}

/// Generic confirm/cancel dialog used by data-management actions (was
/// `_SettingsView._showConfirmDialog`).
void showSettingsConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required Future<void> Function() onConfirm,
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await onConfirm();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$title 完成')),
              );
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
