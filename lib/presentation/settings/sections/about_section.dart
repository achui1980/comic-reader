import 'package:flutter/material.dart';

import 'section_widgets.dart';

/// "关于" section (was `_SettingsView._buildAboutSection`).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('关于'),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Comic Reader'),
          subtitle: Text('版本 1.0.0'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
