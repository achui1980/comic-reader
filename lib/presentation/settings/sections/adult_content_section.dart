import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/settings_cubit.dart';
import '../bloc/settings_state.dart';
import 'section_widgets.dart';

/// "成人内容" section (was `_SettingsView._buildAdultSection`).
class AdultContentSection extends StatelessWidget {
  const AdultContentSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('成人内容'),
        ListTile(
          leading: Icon(
            state.adultUnlocked ? Icons.lock_open : Icons.lock_outline,
            color: state.adultUnlocked ? Colors.green : null,
          ),
          title: Text(state.adultUnlocked ? '已激活 18+ 数据源' : '输入激活码解锁 18+ 数据源'),
          subtitle: Text(
            state.adultUnlocked
                ? '成人内容数据源已显示。点击可锁定。'
                : '需要有效激活码，且已年满 18 周岁。',
          ),
          trailing: state.adultUnlocked
              ? TextButton(
                  onPressed: () => _showLockConfirmDialog(context, cubit),
                  child: const Text('锁定'),
                )
              : const Icon(Icons.chevron_right),
          onTap: state.adultUnlocked
              ? null
              : () => _showActivationDialog(context, cubit),
        ),
        const Divider(),
      ],
    );
  }
}

void _showActivationDialog(BuildContext context, SettingsCubit cubit) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (dialogContext) {
      String? errorText;
      var submitting = false;
      return StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> submit() async {
            final code = controller.text.trim();
            if (code.isEmpty) {
              setState(() => errorText = '请输入激活码');
              return;
            }
            setState(() {
              submitting = true;
              errorText = null;
            });
            final error = await cubit.unlockWithCode(code);
            if (!dialogContext.mounted) return;
            if (error == null) {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('激活成功，已解锁成人内容数据源')),
              );
            } else {
              setState(() {
                submitting = false;
                errorText = error;
              });
            }
          }

          return AlertDialog(
            title: const Text('输入激活码'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '请确认你已年满 18 周岁。输入激活码以解锁成人内容数据源。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '粘贴激活码',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => submitting ? null : submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    submitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('激活'),
              ),
            ],
          );
        },
      );
    },
  );
}

void _showLockConfirmDialog(BuildContext context, SettingsCubit cubit) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('锁定成人内容'),
      content: const Text('锁定后将隐藏成人内容数据源，需重新输入激活码才能再次解锁。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            cubit.lockAdult();
            Navigator.pop(dialogContext);
          },
          child: const Text('锁定'),
        ),
      ],
    ),
  );
}
