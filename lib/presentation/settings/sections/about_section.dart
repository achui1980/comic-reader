import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:comic_reader/core/update/app_update_service.dart';
import 'package:comic_reader/presentation/common/app_update_dialog.dart';

import 'section_widgets.dart';

/// "关于" section (was `_SettingsView._buildAboutSection`).
class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  String _version = '';
  bool _checkingUpdate = false;

  bool get _supportsUpdateCheck {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isAndroid;
  }

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

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final info = await GetIt.instance<AppUpdateService>().checkForUpdate(
        ignoreSkipped: true,
      );
      if (!mounted) return;
      if (info != null) {
        await showAppUpdateDialog(
          context,
          info,
          GetIt.instance<AppUpdateService>(),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('检查更新失败，请检查网络连接')),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
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
        if (_supportsUpdateCheck)
          ListTile(
            leading: _checkingUpdate
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_outlined),
            title: const Text('检查更新'),
            onTap: _checkingUpdate ? null : _checkForUpdate,
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}
