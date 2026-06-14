import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:comic_reader/app/theme/app_theme.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'bloc/settings_cubit.dart';
import 'bloc/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SettingsCubit(
        settingsStore: GetIt.instance<SettingsStore>(),
        localStorage: GetIt.instance<LocalStorage>(),
        sourceRegistry: GetIt.instance<SourceRegistry>(),
      )..init(),
      child: const _SettingsView(),
    );
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
              _buildReadingSection(context, state),
              _buildThemeSection(context, state),
              _buildPluginSection(context, state),
              _buildDataSection(context),
              _buildAboutSection(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.deepPurple,
        ),
      ),
    );
  }

  Widget _buildReadingSection(BuildContext context, SettingsState state) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('阅读设置'),
        ListTile(
          title: const Text('默认布局'),
          subtitle: Text(
            state.layoutMode == LayoutMode.horizontal ? '横向翻页' : '纵向滚动',
          ),
          trailing: SegmentedButton<LayoutMode>(
            segments: const [
              ButtonSegment(
                value: LayoutMode.horizontal,
                label: Text('横向'),
                icon: Icon(Icons.swap_horiz, size: 16),
              ),
              ButtonSegment(
                value: LayoutMode.vertical,
                label: Text('纵向'),
                icon: Icon(Icons.swap_vert, size: 16),
              ),
            ],
            selected: {state.layoutMode},
            onSelectionChanged: (set) => cubit.setLayoutMode(set.first),
          ),
        ),
        ListTile(
          title: const Text('阅读方向'),
          subtitle: Text(
            state.readingDirection == ReadingDirection.ltr ? '从左到右' : '从右到左',
          ),
          trailing: SegmentedButton<ReadingDirection>(
            segments: const [
              ButtonSegment(
                value: ReadingDirection.ltr,
                label: Text('LTR'),
              ),
              ButtonSegment(
                value: ReadingDirection.rtl,
                label: Text('RTL'),
              ),
            ],
            selected: {state.readingDirection},
            onSelectionChanged: (set) =>
                cubit.setReadingDirection(set.first),
          ),
        ),
        SwitchListTile(
          title: const Text('自动翻页'),
          subtitle: Text(
            state.autoPageTurn
                ? '每 ${state.autoPageTurnInterval} 秒翻一页'
                : '已关闭',
          ),
          value: state.autoPageTurn,
          onChanged: cubit.setAutoPageTurn,
        ),
        if (state.autoPageTurn)
          ListTile(
            title: const Text('翻页间隔'),
            subtitle: Slider(
              value: state.autoPageTurnInterval.toDouble(),
              min: 2,
              max: 15,
              divisions: 13,
              label: '${state.autoPageTurnInterval}s',
              onChanged: (v) => cubit.setAutoPageTurnInterval(v.round()),
            ),
          ),
        const Divider(),
      ],
    );
  }

  Widget _buildThemeSection(BuildContext context, SettingsState state) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('主题设置'),
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

  Widget _buildPluginSection(BuildContext context, SettingsState state) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('插件管理'),
        ...state.plugins.map((plugin) {
          final enabled = !state.disabledSources.contains(plugin.id);
          return SwitchListTile(
            title: Text(plugin.name),
            subtitle: Text(
              '${plugin.description ?? ''} • 评分: ${plugin.score.toStringAsFixed(1)}',
            ),
            value: enabled,
            onChanged: (v) => cubit.toggleSource(plugin.id, v),
          );
        }),
        const Divider(),
      ],
    );
  }

  Widget _buildDataSection(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('数据管理'),
        ListTile(
          leading: const Icon(Icons.bookmark_remove_outlined),
          title: const Text('清除收藏'),
          subtitle: const Text('删除所有收藏的漫画'),
          onTap: () => _showConfirmDialog(
            context,
            title: '清除收藏',
            content: '确定要删除所有收藏吗？此操作不可撤销。',
            onConfirm: cubit.clearFavorites,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history_toggle_off),
          title: const Text('清除阅读历史'),
          subtitle: const Text('删除所有阅读进度记录'),
          onTap: () => _showConfirmDialog(
            context,
            title: '清除阅读历史',
            content: '确定要删除所有阅读历史吗？此操作不可撤销。',
            onConfirm: cubit.clearReadingHistory,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('清除图片缓存'),
          subtitle: const Text('释放缓存占用的存储空间'),
          onTap: () => _showConfirmDialog(
            context,
            title: '清除图片缓存',
            content: '确定要清除所有缓存的图片吗？',
            onConfirm: cubit.clearImageCache,
          ),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('关于'),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Comic Reader'),
          subtitle: Text('版本 1.0.0'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onConfirm();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title 完成')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
