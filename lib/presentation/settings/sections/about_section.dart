import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'section_widgets.dart';

/// "关于" section (was `_SettingsView._buildAboutSection`).
class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('关于'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Comic Reader'),
          subtitle: Text(_version.isEmpty ? '版本 —' : '版本 $_version'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
