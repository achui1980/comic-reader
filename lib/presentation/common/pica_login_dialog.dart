import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';
import 'package:comic_reader/data/sources/source_registry.dart';

/// Shows a login dialog for PicaComic.
/// Returns true if login succeeded, false/null otherwise.
Future<bool?> showPicaLoginDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => const _PicaLoginDialog(),
  );
}

class _PicaLoginDialog extends StatefulWidget {
  const _PicaLoginDialog();

  @override
  State<_PicaLoginDialog> createState() => _PicaLoginDialogState();
}

class _PicaLoginDialogState extends State<_PicaLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入邮箱和密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final registry = GetIt.instance<SourceRegistry>();
      final source = registry.get(PicaComic.sourceId);
      if (source is! PicaComic) {
        setState(() {
          _loading = false;
          _error = '插件未找到';
        });
        return;
      }

      final httpClient = GetIt.instance<HttpClient>();
      final config = source.buildSignInRequest(email, password);
      final response = await httpClient.execute(config);

      final token = source.parseSignIn(response.data);
      if (token != null) {
        // Save token to persistent store
        final authStore = GetIt.instance<AuthStore>();
        await authStore.saveExtra(PicaComic.sourceId, {'token': token});

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _loading = false;
          _error = '登录失败，请检查账号密码';
        });
      }
    } catch (e) {
      final msg = e.toString();
      String errorText;
      if (msg.contains('1004') || msg.contains('invalid email')) {
        errorText = '邮箱或密码错误';
      } else if (msg.contains('timeout') || msg.contains('SocketException')) {
        errorText = '网络连接失败，请检查代理设置';
      } else {
        errorText = '登录失败: ${msg.length > 80 ? msg.substring(0, 80) : msg}';
      }
      setState(() {
        _loading = false;
        _error = errorText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.login, color: Colors.deepPurple),
          SizedBox(width: 8),
          Text('哔咔漫画登录'),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '使用哔咔漫画账号登录后即可浏览',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '邮箱',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              enabled: !_loading,
              onSubmitted: (_) => _login(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
        ),
      ],
    );
  }
}
