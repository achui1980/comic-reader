import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/routes.dart';
import 'bloc/settings_cubit.dart';
import 'bloc/settings_state.dart';
import 'sections/about_section.dart';
import 'sections/adult_content_section.dart';
import 'sections/ai_section.dart';
import 'sections/data_management_section.dart';
import 'sections/plugin_section.dart';
import 'sections/proxy_section.dart';
import 'sections/reader_enhancements_section.dart';
import 'sections/reading_section.dart';
import 'sections/theme_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsView();
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              ReadingSection(state: state),
              ReaderEnhancementsSection(state: state),
              ThemeSection(state: state),
              if (kIsWeb) const WebProxySection() else ProxySection(state: state),
              AdultContentSection(state: state),
              const AiSection(),
              PluginSection(state: state),
              const DataManagementSection(),
              const AboutSection(),
              if (kDebugMode)
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: const Text('翻译管道调试页（临时）'),
                  onTap: () => context.push(AppRoutes.pocTranslation),
                ),
            ],
          );
        },
      ),
    );
  }
}
