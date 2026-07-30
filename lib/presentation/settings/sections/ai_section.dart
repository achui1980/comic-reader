import 'package:flutter/material.dart';

import 'package:comic_reader/presentation/settings/ai_settings_screen.dart';
import 'section_widgets.dart';

/// "AI 智能" section (was `_SettingsView._buildAiSection`).
class AiSection extends StatelessWidget {
  const AiSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('AI 智能'),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('AI 设置'),
          subtitle: const Text('自然语言搜索与元数据归一化（自备 API Key）'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AiSettingsScreen(),
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}
