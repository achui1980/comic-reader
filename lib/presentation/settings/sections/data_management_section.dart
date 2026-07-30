import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:file_picker/file_picker.dart';

import 'package:comic_reader/data/local/backup_service.dart';
import '../bloc/settings_cubit.dart';
import 'section_widgets.dart';

/// "数据管理" section (was `_SettingsView._buildDataSection`).
class DataManagementSection extends StatelessWidget {
  const DataManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('数据管理'),
        if (!kIsWeb) ...[
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('备份数据'),
            subtitle: const Text('导出收藏、历史、设置到文件'),
            onTap: () async {
              try {
                final backupService = GetIt.instance<BackupService>();
                await backupService.shareBackup();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('备份文件已生成')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('备份失败: $e')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('恢复数据'),
            subtitle: const Text('从备份文件恢复所有数据'),
            onTap: () => showSettingsConfirmDialog(
              context,
              title: '恢复数据',
              content: '恢复将覆盖当前所有数据（收藏、历史、设置）。确定继续吗？',
              onConfirm: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );
                if (result == null || result.files.isEmpty) return;

                final file = File(result.files.single.path!);
                final json = await file.readAsString();

                final backupService = GetIt.instance<BackupService>();
                final success = await backupService.importData(json);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? '恢复成功，请重启应用' : '恢复失败：文件格式错误'),
                    ),
                  );
                }
              },
            ),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.bookmark_remove_outlined),
          title: const Text('清除收藏'),
          subtitle: const Text('删除所有收藏的漫画'),
          onTap: () => showSettingsConfirmDialog(
            context,
            title: '清除收藏',
            content: '确定要删除所有收藏吗？此操作不可撤销。',
            onConfirm: cubit.clearFavorites,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history_toggle_off),
          title: const Text('清除阅读历史'),
          subtitle: const Text('删除所有阅读进度记录'),
          onTap: () => showSettingsConfirmDialog(
            context,
            title: '清除阅读历史',
            content: '确定要删除所有阅读历史吗？此操作不可撤销。',
            onConfirm: cubit.clearReadingHistory,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('清除图片缓存'),
          subtitle: const Text('释放缓存占用的存储空间'),
          onTap: () => showSettingsConfirmDialog(
            context,
            title: '清除图片缓存',
            content: '确定要清除所有缓存的图片吗？',
            onConfirm: cubit.clearImageCache,
          ),
        ),
        const Divider(),
      ],
    );
  }
}
