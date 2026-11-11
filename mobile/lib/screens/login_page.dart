import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/github_update_service.dart';
import 'workspace_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _server = TextEditingController(text: 'https://smartstir-gateway-production.up.railway.app');
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _connect() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final api = await SmartStirApi.login(
        _server.text, _username.text.trim(), _password.text);
      if (!mounted) { api.close(); return; }
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => WorkspacePage(api: api)));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _server.dispose(); _username.dispose(); _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 16),
          const Center(child: Icon(Icons.science_outlined, size: 72, color: Color(0xFF1B365D))),
          const SizedBox(height: 18),
          const Text('SmartStir Lab', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800,
              color: Color(0xFF1B365D), letterSpacing: -.5)),
          const SizedBox(height: 5),
          const Text('实验设备远程管理 · 测试版 V1.2.0', textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 28),
          Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('连接实验室服务', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              TextField(controller: _server, keyboardType: TextInputType.url,
                autofillHints: const [AutofillHints.url],
                decoration: const InputDecoration(labelText: '后端 HTTPS 地址',
                  hintText: 'https://your-api.up.railway.app', prefixIcon: Icon(Icons.cloud_outlined))),
              const SizedBox(height: 13),
              TextField(controller: _username,
                decoration: const InputDecoration(labelText: 'APP 管理员用户名',
                  prefixIcon: Icon(Icons.person_outline))),
              const SizedBox(height: 13),
              TextField(controller: _password, obscureText: _obscure,
                onSubmitted: (_) => _connect(),
                decoration: InputDecoration(labelText: 'APP 登录密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility)))),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C)))),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: _busy ? null : _connect,
                icon: _busy ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.login),
                label: Text(_busy ? '正在连接…' : '安全登录'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50))),
            ],
          ))),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () => SmartStirUpdateService.showUpdateDialog(context),
            icon: const Icon(Icons.system_update_alt),
            label: const Text('检查 GitHub 更新'),
          ),
          const Text('APP 仅连接你们的 HTTPS 后端，不保存 MQTT 密码；'
            '本版本是有人现场监护的研发原型。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        ],
      )),
    ))));
  }
}
