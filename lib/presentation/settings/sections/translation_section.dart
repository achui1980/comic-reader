import 'package:flutter/material.dart';

import '../bloc/settings_state.dart';
import '../translation_settings_screen.dart';
import 'section_widgets.dart';

/// 「漫画翻译」入口。照 `ai_section.dart` 的跳转型写法（原生 Navigator，
/// 不走 go_router）。
class TranslationSection extends StatelessWidget {
  const TranslationSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final enabled = state.settings.mangaTranslationEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('漫画翻译'),
        ListTile(
          leading: const Icon(Icons.translate),
          title: const Text('漫画翻译'),
          subtitle: Text(enabled ? '已启用' : '未启用'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TranslationSettingsScreen(),
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}
