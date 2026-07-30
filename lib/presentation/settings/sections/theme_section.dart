import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:comic_reader/app/theme/app_theme.dart';
import '../bloc/settings_cubit.dart';
import '../bloc/settings_state.dart';
import 'section_widgets.dart';

/// "主题设置" section (was `_SettingsView._buildThemeSection`).
class ThemeSection extends StatelessWidget {
  const ThemeSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('主题设置'),
        ...AppThemeMode.values.map((mode) {
          final labels = {
            AppThemeMode.light: '浅色',
            AppThemeMode.dark: '深色',
            AppThemeMode.amoled: 'AMOLED',
            AppThemeMode.system: '跟随系统',
          };
          final icons = {
            AppThemeMode.light: Icons.light_mode,
            AppThemeMode.dark: Icons.dark_mode,
            AppThemeMode.amoled: Icons.brightness_1,
            AppThemeMode.system: Icons.settings_brightness,
          };
          final isSelected = state.themeMode == mode;
          return ListTile(
            leading: Icon(icons[mode]),
            title: Text(labels[mode]!),
            trailing: isSelected
                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                : const Icon(Icons.circle_outlined),
            onTap: () => cubit.setThemeMode(mode),
          );
        }),
        const Divider(),
      ],
    );
  }
}
