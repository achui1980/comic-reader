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
///
/// 「$title 完成」只在 [onConfirm] 正常返回时提示；抛异常时改提示
/// 「$title 失败：$e」并**吞掉**异常（`onPressed` 是 fire-and-forget 的
/// 异步回调，向上抛只会变成未捕获异步异常）。因此调用方不要自己再 catch
/// 后静默返回 —— 那会让失败被误报成成功。
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
            try {
              await onConfirm();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title 失败：$e')),
                );
              }
              return;
            }
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
