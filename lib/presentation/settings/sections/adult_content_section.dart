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
        SwitchListTile(
          secondary: Icon(
            state.adultUnlocked ? Icons.lock_open : Icons.lock_outline,
            color: state.adultUnlocked ? Colors.green : null,
          ),
          title: const Text('显示成人内容数据源'),
          subtitle: Text(
            state.adultUnlocked ? '已解锁 18+ 数据源' : '需年龄确认后显示',
          ),
          value: state.adultUnlocked,
          onChanged: (value) {
            if (value) {
              _showAgeConfirmDialog(context, cubit);
            } else {
              cubit.setAdultUnlocked(false);
            }
          },
        ),
        const Divider(),
      ],
    );
  }
}

void _showAgeConfirmDialog(BuildContext context, SettingsCubit cubit) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认年龄'),
      content: const Text('请确认你已年满 18 周岁。开启后将显示成人内容数据源。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            cubit.setAdultUnlocked(true);
            Navigator.pop(dialogContext);
          },
          child: const Text('确认'),
        ),
      ],
    ),
  );
}
