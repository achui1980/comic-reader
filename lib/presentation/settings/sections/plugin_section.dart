import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';
import '../bloc/settings_cubit.dart';
import '../bloc/settings_state.dart';
import 'section_widgets.dart';

/// "插件管理" section (was `_SettingsView._buildPluginSection`).
class PluginSection extends StatelessWidget {
  const PluginSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('插件管理'),
        ...state.plugins.map((plugin) {
          final enabled = !state.disabledSources.contains(plugin.id);
          return ListTile(
            title: Row(
              children: [
                Text(plugin.name),
                if (plugin.needsProxy)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.vpn_lock, color: Colors.blue, size: 16),
                  ),
                if (plugin.isAdult)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.eighteen_up_rating,
                        color: Colors.redAccent, size: 16),
                  ),
              ],
            ),
            subtitle: Text(
              '${plugin.description ?? ''} • 评分: ${plugin.score.toStringAsFixed(1)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (plugin.href != null)
                  TextButton.icon(
                    onPressed: () => _navigateToVerify(context, plugin.id),
                    icon: const Icon(Icons.verified_user_outlined, size: 18),
                    label: const Text('验证'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                Switch(
                  value: enabled,
                  onChanged: (v) => cubit.toggleSource(plugin.id, v),
                ),
              ],
            ),
          );
        }),
        const Divider(),
      ],
    );
  }
}

void _navigateToVerify(BuildContext context, String sourceId) {
  final registry = GetIt.instance<SourceRegistry>();
  final source = registry.get(sourceId);
  if (source != null && source.requiresLogin) {
    // Show login dialog for sources that need email/password
    showPicaLoginDialog(context);
  } else {
    context.push(AppRoutes.webviewPath(sourceId));
  }
}
