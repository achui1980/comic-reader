import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:web/web.dart' as web;
import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';

Widget buildWebViewScreen({
  required BuildContext context,
  required String sourceId,
  String? initialUrl,
}) {
  return _WebCookieInputScreen(sourceId: sourceId, initialUrl: initialUrl);
}

/// On web platform, we can't use InAppWebView (iframe blocked by X-Frame-Options,
/// JS handlers not implemented). Instead, guide the user to:
/// 1. Open the site in a new tab
/// 2. Complete CF verification manually
/// 3. Copy cookies from browser DevTools and paste here
class _WebCookieInputScreen extends StatefulWidget {
  final String sourceId;
  final String? initialUrl;

  const _WebCookieInputScreen({required this.sourceId, this.initialUrl});

  @override
  State<_WebCookieInputScreen> createState() => _WebCookieInputScreenState();
}

class _WebCookieInputScreenState extends State<_WebCookieInputScreen> {
  final _cookieController = TextEditingController();
  final AuthStore _authStore = GetIt.instance<AuthStore>();
  final SourceRegistry _registry = GetIt.instance<SourceRegistry>();
  bool _saved = false;

  String get _siteUrl {
    final source = _registry.get(widget.sourceId);
    return widget.initialUrl ?? source?.href ?? '';
  }

  String get _sourceName {
    return _registry.get(widget.sourceId)?.name ?? widget.sourceId;
  }

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  void _openInNewTab() {
    web.window.open(_siteUrl, '_blank');
  }

  Future<void> _saveCookie() async {
    var cookie = _cookieController.text.trim();
    if (cookie.isEmpty) return;

    // If user pasted just a raw value (no '=' sign), assume it's cf_clearance
    if (!cookie.contains('=')) {
      cookie = 'cf_clearance=$cookie';
    }
    // If user pasted just "value" from the cf_clearance row in DevTools,
    // and it doesn't look like a full cookie string (no semicolons),
    // wrap it as cf_clearance=value
    else if (!cookie.contains(';') && !cookie.startsWith('cf_clearance=')) {
      // Looks like a single key=value pair that isn't cf_clearance - use as-is
    }

    final data = {'cookie': cookie};
    await _authStore.saveExtra(widget.sourceId, data);

    final source = _registry.get(widget.sourceId);
    source?.syncExtraData(data);

    setState(() => _saved = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cookie 已保存！请返回重试'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('验证 - $_sourceName'),
        actions: [
          if (_saved)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.check_circle, color: Colors.green),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step 1
                _buildStepCard(
                  step: 1,
                  title: '在新标签页打开网站',
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '点击下方按钮，在新标签页中打开 $_sourceName。完成 Cloudflare 验证（等待几秒即可通过）。',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _openInNewTab,
                        icon: const Icon(Icons.open_in_new),
                        label: Text('打开 $_sourceName'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Step 2
                _buildStepCard(
                  step: 2,
                  title: '复制 Cookie',
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('验证通过后，按 F12 打开开发者工具：'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildCodeStep('1. 切换到 Console（控制台）标签'),
                            _buildCodeStep('2. 输入: document.cookie'),
                            _buildCodeStep('3. 按 Enter，复制输出的内容'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '或者：Application → Cookies → 复制 cf_clearance 的值',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Step 3
                _buildStepCard(
                  step: 3,
                  title: '粘贴 Cookie',
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('将复制的 Cookie 粘贴到下方输入框：'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cookieController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: '粘贴 document.cookie 的完整输出\n或者粘贴 cf_clearance 的值',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste),
                            tooltip: '粘贴',
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              if (data?.text != null) {
                                _cookieController.text = data!.text!;
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saveCookie,
                          icon: const Icon(Icons.save),
                          label: const Text('保存 Cookie'),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_saved) ...[
                  const SizedBox(height: 24),
                  Card(
                    color: Colors.green.shade50,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '验证完成！返回上一页重新加载即可。',
                              style: TextStyle(color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required int step,
    required String title,
    required Widget content,
  }) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    '$step',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildCodeStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }
}
