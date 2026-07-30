import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';

import '../bloc/settings_cubit.dart';
import '../bloc/settings_state.dart';
import 'section_widgets.dart';

/// "网络代理" section for native platforms (was
/// `_SettingsView._buildNativeProxySection`).
class ProxySection extends StatelessWidget {
  const ProxySection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('网络代理'),
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

/// Proxy settings section shown only on web platform.
/// Allows users to configure an upstream proxy (e.g., http://127.0.0.1:2222)
/// that the CORS proxy server will use for all outbound requests.
/// (was `_SettingsView._ProxySettingsSection`).
class WebProxySection extends StatefulWidget {
  const WebProxySection({super.key});

  @override
  State<WebProxySection> createState() => _WebProxySectionState();
}

class _WebProxySectionState extends State<WebProxySection> {
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
