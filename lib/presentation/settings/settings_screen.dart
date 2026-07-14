import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:comic_reader/app/router/routes.dart';
import 'package:comic_reader/app/theme/app_theme.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/local/backup_service.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/common/pica_login_dialog.dart';
import 'bloc/settings_cubit.dart';
import 'bloc/settings_state.dart';

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
              _buildReadingSection(context, state),
              _buildReaderEnhancementsSection(context, state),
              _buildThemeSection(context, state),
              if (kIsWeb) const _ProxySettingsSection(),
              if (!kIsWeb) _buildNativeProxySection(context, state),
              _buildAdultSection(context, state),
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

  Widget _buildReaderEnhancementsSection(BuildContext context, SettingsState state) {
    final cubit = context.read<SettingsCubit>();
    final s = state.settings;
    final isAndroid = !kIsWeb && Platform.isAndroid;
    const scaleLabels = {
      ScaleType.fitScreen: '适应屏幕',
      ScaleType.fitWidth: '适应宽度',
      ScaleType.fitHeight: '适应高度',
      ScaleType.original: '原始大小',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('阅读器增强'),
        ListTile(
          title: const Text('缩放模式'),
          subtitle: Text('${scaleLabels[s.scaleType]}（横向翻页时生效）'),
          trailing: DropdownButton<ScaleType>(
            value: s.scaleType,
            underline: const SizedBox.shrink(),
            items: ScaleType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(scaleLabels[t]!),
                    ))
                .toList(),
            onChanged: (t) {
              if (t != null) cubit.setScaleType(t);
            },
          ),
        ),
        SwitchListTile(
          title: const Text('显示页码'),
          subtitle: const Text('在阅读器角落显示当前页码'),
          value: s.showPageNumber,
          onChanged: cubit.setShowPageNumber,
        ),
        SwitchListTile(
          title: const Text('屏幕常亮'),
          subtitle: Text(
            (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                ? '阅读时保持屏幕点亮'
                : '阅读时保持屏幕点亮（仅移动端生效）',
          ),
          value: s.keepScreenOn,
          onChanged: cubit.setKeepScreenOn,
        ),
        SwitchListTile(
          title: const Text('显示点击区域'),
          subtitle: const Text('横向翻页时叠加显示上一页/菜单/下一页区域'),
          value: s.showTapZones,
          onChanged: cubit.setShowTapZones,
        ),
        SwitchListTile(
          title: const Text('反转点击区域'),
          subtitle: const Text('交换左右点击翻页方向'),
          value: s.tapZonesInvert,
          onChanged: cubit.setTapZonesInvert,
        ),
        SwitchListTile(
          title: const Text('裁剪白边'),
          subtitle: const Text('自动裁掉图片周围的空白边缘'),
          value: s.cropBorders,
          onChanged: cubit.setCropBorders,
        ),
        SwitchListTile(
          title: const Text('拆分宽图'),
          subtitle: const Text('将横向宽图拆分为两页显示'),
          value: s.splitWidePages,
          onChanged: cubit.setSplitWidePages,
        ),
        if (isAndroid)
          SwitchListTile(
            title: const Text('音量键翻页'),
            subtitle: const Text('使用音量键上下翻页（仅 Android）'),
            value: s.volumeKeyTurn,
            onChanged: cubit.setVolumeKeyTurn,
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

  Widget _buildNativeProxySection(BuildContext context, SettingsState state) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('网络代理'),
        SwitchListTile(
          title: const Text('启用代理'),
          subtitle: Text(state.proxyEnabled ? '所有请求通过代理转发' : '直连（不使用代理）'),
          value: state.proxyEnabled,
          onChanged: (v) => cubit.setProxyEnabled(v),
        ),
        ListTile(
          title: const Text('代理地址'),
          subtitle: Text(state.proxyAddress.isEmpty ? '未设置' : state.proxyAddress),
          enabled: state.proxyEnabled,
          trailing: const Icon(Icons.edit),
          onTap: state.proxyEnabled
              ? () => _showProxyAddressDialog(context, state.proxyAddress)
              : null,
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildAdultSection(BuildContext context, SettingsState state) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('成人内容'),
        SwitchListTile(
          title: const Text('显示成人内容数据源'),
          subtitle: Text(
            state.adultUnlocked ? '已解锁 18+ 数据源' : '需年龄确认后显示',
          ),
          value: state.adultUnlocked,
          onChanged: (v) {
            if (v) {
              _showConfirmDialog(
                context,
                title: '年龄确认',
                content: '请确认你已年满 18 周岁。开启后将显示成人内容数据源。',
                onConfirm: () => cubit.setAdultUnlocked(true),
              );
            } else {
              cubit.setAdultUnlocked(false);
            }
          },
        ),
        const Divider(),
      ],
    );
  }

  void _showProxyAddressDialog(BuildContext context, String currentAddress) {
    final controller = TextEditingController(text: currentAddress);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('代理地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '127.0.0.1:2222',
            helperText: '格式: host:port',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              context.read<SettingsCubit>().setProxyAddress(controller.text.trim());
              Navigator.pop(dialogContext);
            },
            child: const Text('确定'),
          ),
        ],
      ),
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

  Widget _buildDataSection(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('数据管理'),
        if (!kIsWeb) ...[
          ListTile(
            leading: const Icon(Icons.upload),
            title: const Text('备份数据'),
            subtitle: const Text('导出收藏、历史、设置到文件'),
            onTap: () async {
              try {
                final backupService = GetIt.instance<BackupService>();
                await backupService.shareBackup();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('备份文件已生成')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('备份失败: $e')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('恢复数据'),
            subtitle: const Text('从备份文件恢复所有数据'),
            onTap: () => _showConfirmDialog(
              context,
              title: '恢复数据',
              content: '恢复将覆盖当前所有数据（收藏、历史、设置）。确定继续吗？',
              onConfirm: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );
                if (result == null || result.files.isEmpty) return;

                final file = File(result.files.single.path!);
                final json = await file.readAsString();

                final backupService = GetIt.instance<BackupService>();
                final success = await backupService.importData(json);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? '恢复成功，请重启应用' : '恢复失败：文件格式错误'),
                    ),
                  );
                }
              },
            ),
          ),
        ],
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

/// Proxy settings section shown only on web platform.
/// Allows users to configure an upstream proxy (e.g., http://127.0.0.1:2222)
/// that the CORS proxy server will use for all outbound requests.
class _ProxySettingsSection extends StatefulWidget {
  const _ProxySettingsSection();

  @override
  State<_ProxySettingsSection> createState() => _ProxySettingsSectionState();
}

class _ProxySettingsSectionState extends State<_ProxySettingsSection> {
  final _controller = TextEditingController();
  String _currentProxy = '';
  bool _loading = true;
  String? _status;

  static const _configUrl = 'http://localhost:9090/__proxy_config';

  @override
  void initState() {
    super.initState();
    _loadCurrentProxy();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProxy() async {
    try {
      final dio = Dio();
      final response = await dio.get(_configUrl);
      final proxy = (response.data['proxy'] as String?) ?? '';
      if (mounted) {
        setState(() {
          _currentProxy = proxy;
          _controller.text = proxy;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _status = '无法连接 CORS 代理服务';
        });
      }
    }
  }

  Future<void> _saveProxy() async {
    final newProxy = _controller.text.trim();
    setState(() { _status = null; });
    try {
      final dio = Dio();
      final response = await dio.post(
        _configUrl,
        data: {'proxy': newProxy},
      );
      if (response.data['status'] == 'ok') {
        setState(() {
          _currentProxy = newProxy;
          _status = newProxy.isEmpty ? '已关闭代理（直连）' : '代理已设置为 $newProxy';
        });
      }
    } catch (e) {
      setState(() {
        _status = '设置失败: ${e.toString().substring(0, 50)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            '网络设置',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        if (_loading)
          const ListTile(
            leading: SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('正在获取代理配置...'),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: '上游代理地址',
                      hintText: 'http://127.0.0.1:2222',
                      helperText: _currentProxy.isEmpty
                          ? '未设置代理（直连）'
                          : '当前: $_currentProxy',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _saveProxy(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saveProxy,
                  child: const Text('保存'),
                ),
                if (_currentProxy.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      _controller.clear();
                      _saveProxy();
                    },
                    child: const Text('清除'),
                  ),
                ],
              ],
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _status!,
                style: TextStyle(
                  fontSize: 12,
                  color: _status!.contains('失败')
                      ? Colors.red
                      : Colors.green.shade700,
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        const Divider(),
      ],
    );
  }
}
