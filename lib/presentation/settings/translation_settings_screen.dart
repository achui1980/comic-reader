import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../core/ai/ai_config.dart';
import '../../data/translation/translation_cache_store.dart';
import '../../data/translation/translation_model_manager.dart';
import 'ai_settings_screen.dart';
import 'bloc/settings_cubit.dart';
import 'bloc/settings_state.dart';
import 'sections/section_widgets.dart';

/// 「漫画翻译」二级设置页：功能总开关 + 模型下载 + AI 配置入口 + 清缓存。
class TranslationSettingsScreen extends StatefulWidget {
  const TranslationSettingsScreen({super.key});

  @override
  State<TranslationSettingsScreen> createState() =>
      _TranslationSettingsScreenState();
}

class _TranslationSettingsScreenState extends State<TranslationSettingsScreen> {
  final TranslationModelManager _models =
      GetIt.instance<TranslationModelManager>();
  final TranslationCacheStore _cache = GetIt.instance<TranslationCacheStore>();
  final AiConfigStore _aiStore = GetIt.instance<AiConfigStore>();

  /// null = 检测中
  bool? _modelsReady;
  String? _modelsError;
  bool _downloading = false;
  int _received = 0;
  int _total = 0;
  bool _aiUsable = false;

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
    _refreshAiStatus();
  }

  Future<void> _refreshModelStatus() async {
    setState(() {
      _modelsReady = null;
      _modelsError = null;
    });
    try {
      final ready = await _models.isReady();
      if (!mounted) return;
      setState(() => _modelsReady = ready);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelsReady = false;
        _modelsError = '$e';
      });
    }
  }

  Future<void> _refreshAiStatus() async {
    final config = await _aiStore.load();
    if (!mounted) return;
    setState(() => _aiUsable = config.isUsable);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _received = 0;
      _total = 0;
    });
    try {
      await _models.downloadAll(onProgress: (file, received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          _total = total;
        });
      });
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _modelsReady = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('模型下载完成')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _modelsReady = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('下载失败：$e')));
    }
  }

  void _clearCache() {
    showSettingsConfirmDialog(
      context,
      title: '清空翻译缓存',
      content: '删除所有已缓存的翻译结果。已翻译过的页面下次阅读时需要重新调用 AI 翻译。',
      onConfirm: () async {
        try {
          await _cache.clearAll();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('清空失败：$e')));
        }
      },
    );
  }

  String get _modelStatusText {
    if (_downloading) {
      final pct = _total > 0 ? (_received * 100 / _total).floor() : 0;
      return '下载中 $pct%';
    }
    if (_modelsError != null) return '无法检测（$_modelsError）';
    if (_modelsReady == null) return '检测中…';
    return _modelsReady! ? '已就绪' : '未下载（约 460MB）';
  }

  Widget? _modelTrailing() {
    if (_downloading) {
      final pct = _total > 0 ? (_received * 100 / _total).floor() : 0;
      return Text('$pct%');
    }
    if (_modelsReady == true) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (_modelsReady == null) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return TextButton(
      onPressed: _download,
      child: Text(_modelsError == null ? '下载' : '重试下载'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 下载中禁止退出：downloadAll 没有互斥锁，重入会让两个 sink 写同一个
      // .part 文件。
      canPop: !_downloading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _downloading) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('模型下载中，请等待完成')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('漫画翻译')),
        body: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            final cubit = context.read<SettingsCubit>();
            final enabled = state.settings.mangaTranslationEnabled;
            return ListView(
              children: [
                SwitchListTile(
                  title: const Text('启用漫画翻译'),
                  subtitle:
                      const Text('开启后，竖向滚动阅读时顶栏会出现翻译按钮'),
                  value: enabled,
                  onChanged: _downloading
                      ? null
                      : cubit.setMangaTranslationEnabled,
                ),
                if (enabled) ...[
                  buildSettingsSectionHeader('翻译模型'),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('模型状态'),
                    subtitle: Text(_modelStatusText),
                    trailing: _modelTrailing(),
                  ),
                  if (_downloading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(
                        // received 可能超过 total（服务器多发字节），必须夹紧，
                        // 否则 LinearProgressIndicator 会断言失败。
                        value: _total > 0
                            ? (_received / _total).clamp(0.0, 1.0)
                            : null,
                      ),
                    ),
                  buildSettingsSectionHeader('AI 服务'),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('AI 设置'),
                    subtitle:
                        Text(_aiUsable ? '已配置' : '未启用或未填 API Key'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AiSettingsScreen(),
                        ),
                      );
                      await _refreshAiStatus();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    title: const Text('清空翻译缓存',
                        style: TextStyle(color: Colors.redAccent)),
                    subtitle: const Text('不会删除已下载的模型'),
                    onTap: _downloading ? null : _clearCache,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
