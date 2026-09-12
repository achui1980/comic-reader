import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:comic_reader/data/local/auth_store.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';

/// Attempts auto-login for [source] using its built-in credentials.
/// Returns true if login succeeded (or the source was already authenticated).
/// Returns false immediately (without any network call) if [source] does
/// not support auto-login.
Future<bool> tryAutoLogin(MangaSource source) async {
  try {
    if (!source.supportsAutoLogin) return false;
    if (source.isAuthenticated) return true;

    final email = source.autoLoginEmail;
    final password = source.autoLoginPassword;
    if (email == null || password == null) return false;

    final httpClient = GetIt.instance<HttpClient>();
    final config = source.buildSignInRequest(email, password);
    final response = await httpClient.execute(config);
    final data = source.parseSignIn(response.data);
    if (data == null) return false;

    source.syncExtraData(data);
    final authStore = GetIt.instance<AuthStore>();
    await authStore.saveExtra(source.id, data);

    if (source is PicaComic) {
      final token = data['token'] as String?;
      if (token != null) await _registerProxyToken(token);
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Attempts to refresh [source]'s session if it reports
/// [MangaSource.needsSessionRefresh]. Returns true if no refresh was needed
/// or the refresh succeeded; false if a refresh was needed but failed.
Future<bool> tryRefreshSession(MangaSource source) async {
  if (!source.needsSessionRefresh) return true;
  try {
    final httpClient = GetIt.instance<HttpClient>();
    final config = source.buildRefreshRequest();
    final response = await httpClient.execute(config);
    final data = source.parseRefresh(response.data);
    if (data == null) return false;

    source.syncExtraData(data);
    final authStore = GetIt.instance<AuthStore>();
    await authStore.saveExtra(source.id, data);
    return true;
  } catch (_) {
    return false;
  }
}

/// Shows a generic email/password login dialog for [source].
/// Returns true if login succeeded, false/null otherwise.
Future<bool?> showLoginDialog(BuildContext context, MangaSource source) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _LoginDialog(source: source),
  );
}

class _LoginDialog extends StatefulWidget {
  final MangaSource source;
  const _LoginDialog({required this.source});

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.source.autoLoginEmail ?? '',
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.source.autoLoginPassword ?? '',
  );
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
      final source = widget.source;
      final httpClient = GetIt.instance<HttpClient>();
      final config = source.buildSignInRequest(email, password);
      final response = await httpClient.execute(config);

      final data = source.parseSignIn(response.data);
      if (data != null) {
        source.syncExtraData(data);
        final authStore = GetIt.instance<AuthStore>();
        await authStore.saveExtra(source.id, data);

        if (source is PicaComic) {
          final token = data['token'] as String?;
          if (token != null) await _registerProxyToken(token);
        }

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
      if (msg.contains('1004') ||
          msg.contains('invalid email') ||
          msg.contains('invalid_credentials') ||
          msg.contains('Invalid login credentials')) {
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

  Future<void> _openRegisterPage() async {
    final url = widget.source.registerUrl;
    if (url == null) return;

    // Drop any stale message (e.g. a previous failed login) so whatever this
    // flow ends up showing is the only thing left on screen.
    if (_error != null) setState(() => _error = null);

    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (opened) return;

    // No browser available (or the platform refused). Hand the user the URL
    // instead of dead-ending. Uses the dialog's own inline error text rather
    // than a SnackBar: this AlertDialog sits in the Navigator overlay, above
    // the Scaffold that ScaffoldMessenger would render the SnackBar into.
    // The clipboard can refuse too (e.g. web without transient user activation,
    // or Linux with no clipboard service), so fall back to showing the raw URL.
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      setState(() => _error = '无法打开浏览器，注册链接已复制到剪贴板');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '无法打开浏览器，请手动访问 $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.login, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Text('${source.name} 登录'),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              source.loginDescription ?? '使用账号登录后即可浏览',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
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
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              enabled: !_loading,
              onSubmitted: (_) => _login(),
            ),
            if (source.registerUrl != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loading ? null : _openRegisterPage,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('还没有账号？去注册'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
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

/// Register PICA auth token with CORS proxy so CDN images can be served.
/// Only needed on web platform. No-op for other sources.
Future<void> _registerProxyToken(String token) async {
  if (!kIsWeb) return;
  try {
    await Dio().post(
      'http://localhost:9090/__host_token',
      data: {
        'host': 'picacomic.com',
        'token': token,
        'header': 'Authorization',
      },
    );
  } catch (_) {
    // Non-critical: images will fail but app still works
  }
}
