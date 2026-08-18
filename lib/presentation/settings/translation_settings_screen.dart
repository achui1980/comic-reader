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

  /// isReady() 抛异常时的错误文本（与下载失败区分开）。
  String? _modelsError;

  /// 上一次 downloadAll 失败（决定按钮显示「重试下载」）。
  bool _downloadFailed = false;
  bool _downloading = false;

  /// relativePath -> 该文件已收字节数。downloadAll 的 onProgress 是**逐文件**
  /// 进度，这里按文件累计以合成总进度；已完成/续传的文件会立刻回调
  /// received == total，因此不需要关心文件顺序。
  final Map<String, int> _receivedByFile = {};

  /// 进度 setState 节流用的水位。`downloadAll` 的 onProgress 是**逐 HTTP
  /// chunk** 回调的，460MB / 8~64KB chunk ≈ 7k~58k 次整页 rebuild，低端机上
  /// 会表现为下载卡死。-1 / 纪元 0 保证每轮下载的第一个回调必定刷新。
  int _lastPercent = -1;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// 全部模型文件字节数之和（从常量求和，避免硬编码）。
  static final int _totalBytes =
      kTranslationModelFiles.fold<int>(0, (sum, f) => sum + f.sizeBytes);

  bool _aiUsable = false;

  /// 总下载进度 0.0~1.0，无法计算（总大小为 0）时为 null。
  /// received 可能超过 total（服务器多发字节），必须夹紧，否则
  /// LinearProgressIndicator 会断言失败、百分比会显示 101%。
  double? get _progress {
    if (_totalBytes <= 0) return null;
    final received =
        _receivedByFile.values.fold<int>(0, (sum, v) => sum + v);
    return (received / _totalBytes).clamp(0.0, 1.0);
  }

  /// 由 [_progress] 派生，因此天然被夹在 0~100。
  int get _percent => ((_progress ?? 0) * 100).floor();

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
      _downloadFailed = false;
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
    // load() 会做 JSON 解析 + SecureStore 读取，两者都可能抛；这里由
    // initState fire-and-forget 调用，不能让异常逃逸成未捕获异步异常。
    try {
      final config = await _aiStore.load();
      if (!mounted) return;
      setState(() => _aiUsable = config.isUsable);
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiUsable = false);
    }
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _downloadFailed = false;
      _receivedByFile.clear();
      _lastPercent = -1;
      _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
    });
    try {
      await _models.downloadAll(onProgress: (file, received, total) {
        if (!mounted) return;
        // 先更新累计 map（_percent 由它派生），再决定要不要 rebuild。
        _receivedByFile[file] = received;
        final now = DateTime.now();
        // 某个文件收满时无条件刷新，否则被节流掉的最后一帧会让进度条永远
        // 停在 99%。received 可能超过 total（服务器多发字节），故用 >=。
        final isFileDone = received >= total;
        if (!isFileDone &&
            _percent == _lastPercent &&
            now.difference(_lastTick).inMilliseconds < 200) {
          return;
        }
        _lastPercent = _percent;
        _lastTick = now;
        setState(() {});
      });
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _modelsReady = true;
        // 之前 isReady() 检测失败过的话，此刻结论已被下载成功推翻。
        _modelsError = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('模型下载完成')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _modelsReady = false;
        // 下载失败后不再声称「无法检测」：状态确定为「未下载」+「重试下载」。
        _modelsError = null;
        _downloadFailed = true;
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
      // 不在这里 catch：helper 只在成功时提示「完成」，失败时由它提示
      // 「清空翻译缓存 失败：$e」，避免一次失败弹出两条相反的 SnackBar。
      onConfirm: _cache.clearAll,
    );
  }

  String get _modelStatusText {
    if (_downloading) return '下载中 $_percent%';
    if (_modelsReady == null) return '检测中…';
    if (_modelsReady!) return '已就绪';
    if (_modelsError != null) return '无法检测（$_modelsError）';
    return '未下载（约 460MB）';
  }

  Widget? _modelTrailing() {
    if (_downloading) return Text('$_percent%');
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
    final retry = _modelsError != null || _downloadFailed;
    return TextButton(
      onPressed: _download,
      child: Text(retry ? '重试下载' : '下载'),
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
                      child: LinearProgressIndicator(value: _progress),
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
