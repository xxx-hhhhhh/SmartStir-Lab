import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/github_update_service.dart';
import 'login_page.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.api});
  final SmartStirApi api;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  Timer? _timer;
  int _tab = 0;
  bool _loading = false;
  int _pendingOperations = 0;
  int _actionGeneration = 0;
  bool _stopPending = false;
  bool get _busy => _pendingOperations > 0;
  bool _fetching = false;
  Map<String, dynamic>? _device;
  List<Map<String, dynamic>> _events = [];
  double _pwm = 30;
  String? _error;
  String _actionInfo = '等待设备状态…';
  DateTime? _lastFetch;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_fetching) return;
    _fetching = true;
    if (_device == null && mounted) setState(() => _loading = true);
    try {
      final data = await widget.api.device();
      if (!mounted) return;
      setState(() {
        _device = data;
        _lastFetch = DateTime.now();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '状态查询失败：$e');
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshEvents() async {
    try {
      final data = await widget.api.events();
      if (mounted) setState(() { _events = data; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '事件查询失败：$e');
    }
  }

  Future<void> _send(String command, [int? value]) async {
    if (_busy && command != 'STOP') return;
    if (command == 'STOP' && _stopPending) return;
    if (command == 'START') {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('确认申请启动'),
        content: const Text('请确认现场有人监护，电机和磁铁已固定、容器安全，'
          '并可随时通过独立的 12V 电源开关断电。运行时间最长 3 分钟。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('已确认现场安全')),
        ],
      ));
      if (confirmed != true || !mounted) return;
    }
    final generation = ++_actionGeneration;
    setState(() {
      _pendingOperations++;
      if (command == 'STOP') _stopPending = true;
      _actionInfo = '$command：指令已提交，等待设备确认…';
    });
    try {
      final accepted = await widget.api.sendCommand(command, value: value);
      final id = accepted['command_id'];
      if (id is! String) throw ApiError('服务器没有返回指令编号');
      var state = 'PENDING';
      var errorCode = '';
      for (int n = 0; n < 12 && state == 'PENDING'; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        final result = await widget.api.commandStatus(id);
        state = (result['status'] ?? 'PENDING').toString();
        final ackRaw = result['ack_json'];
        if (ackRaw is String && ackRaw.isNotEmpty) {
          try {
            final ack = jsonDecode(ackRaw) as Map<String, dynamic>;
            errorCode = (ack['error_code'] ?? '').toString();
          } catch (_) { /* Ignore non-JSON fallback. */ }
        }
      }
      if (mounted && generation == _actionGeneration) {
        setState(() => _actionInfo = '$command：$state${errorCode.isEmpty ? '' : '（$errorCode）'}');
      }
      await _refresh();
    } catch (e) {
      if (mounted && generation == _actionGeneration) {
        setState(() => _actionInfo = '$command 指令未确认：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingOperations--;
          if (command == 'STOP') _stopPending = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {
      // Offline logout still discards the token on this phone.
    }
    if (!mounted) return;
    widget.api.close();
    Navigator.pushAndRemoveUntil(context,
      MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  @override
  void dispose() { _timer?.cancel(); widget.api.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartStir Lab', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: '刷新', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(tooltip: '退出登录', onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: IndexedStack(index: _tab, children: [
          _controlTab(), _eventsTab(), _settingsTab(),
        ]),
      ))),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) {
          setState(() => _tab = v);
          if (v == 1) _refreshEvents();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed), label: '控制台'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long), label: '运行事件'),
          NavigationDestination(icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }

  Widget _controlTab() {
    final online = _device?['online'] == true && _error == null;
    final enabled = _device?['motor_enabled'] == true;
    final confirmedPwm = _device?['pwm_percent'];
    final rpm = _device?['actual_rpm'];
    final recentlySeen = _lastFetch == null ||
      DateTime.now().difference(_lastFetch!) < const Duration(seconds: 12);
    final canOperate = online && recentlySeen && !_busy;
    return RefreshIndicator(onRefresh: _refresh, child: ListView(
      padding: const EdgeInsets.all(20), children: [
        Text('设备控制台', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800, color: const Color(0xFF1B365D))),
        const SizedBox(height: 4),
        const Text('实验室 01  ·  stirrer-001', style: TextStyle(color: Color(0xFF64748B))),
        const SizedBox(height: 18),
        if (_error != null) _notice(_error!, const Color(0xFFB91C1C), Icons.error_outline),
        if (_loading) const LinearProgressIndicator(),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: online ? const Color(0xFF15803D) : const Color(0xFFB91C1C)),
              const SizedBox(width: 9),
              Text(online ? '设备在线' : '设备离线 / 状态未知',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Chip(label: const Text('不使用 GPIO32 许可'),
                visualDensity: VisualDensity.compact),
            ]),
            const Divider(height: 24),
            Row(children: [
              Expanded(child: _metric('电机驱动状态', !online ? '未知' : enabled ? '已启用' : '已停止',
                '命令状态，不代表实际旋转')),
              Expanded(child: _metric('已确认 PWM',
                online ? '${confirmedPwm ?? '—'} %' : '—', '非实际 RPM')),
            ]),
            const SizedBox(height: 14),
            _metric('实际转速', rpm == null ? '未接入' : '$rpm RPM',
              rpm == null ? '霍尔传感器尚未集成' : '由传感器上报'),
          ],
        ))),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: Text('PWM 预设占空比', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('${_pwm.round()}%', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            ]),
            Slider(value: _pwm, min: 0, max: 100, divisions: 20,
              onChanged: _busy ? null : (v) => setState(() => _pwm = v)),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
              Text('0%', style: TextStyle(color: Color(0xFF64748B))),
              Text('100%', style: TextStyle(color: Color(0xFF64748B))),
            ]),
            const SizedBox(height: 7),
            OutlinedButton.icon(onPressed: canOperate ? () => _send('SET_PWM', _pwm.round()) : null,
              icon: const Icon(Icons.tune), label: const Text('应用 PWM 设置')),
            const SizedBox(height: 13),
            FilledButton.icon(onPressed: canOperate && _pwm > 0 ? () => _send('START') : null,
              icon: const Icon(Icons.play_arrow), label: const Text('申请启动（现场监护）'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => _send('STOP'),
              icon: const Icon(Icons.stop_circle_outlined), label: const Text('请求停止'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB91C1C),
                minimumSize: const Size.fromHeight(52))),
            const SizedBox(height: 10),
            _notice(_actionInfo, const Color(0xFF1B365D), Icons.info_outline),
          ],
        ))),
        const SizedBox(height: 12),
        const Text('注意：网络异常时远程停止可能无法送达。必须保留现场独立断电开关，'
          '不得将此版本用于无人值守运行。',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ],
    ));
  }

  Widget _eventsTab() {
    return RefreshIndicator(onRefresh: _refreshEvents, child: ListView(
      padding: const EdgeInsets.all(20), children: [
        Text('运行事件', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800, color: const Color(0xFF1B365D))),
        const SizedBox(height: 6),
        const Text('展示后端保存的最近 100 条事件；不是合规级不可篡改审计记录。',
          style: TextStyle(color: Color(0xFF64748B))),
        const SizedBox(height: 14),
        if (_events.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(28),
          child: Center(child: Text('暂时没有事件，向下拉动刷新。')))),
        ..._events.map((e) {
          final unix = e['created_at'];
          final date = unix is int ? DateTime.fromMillisecondsSinceEpoch(unix * 1000).toLocal() : null;
          final when = date == null ? '—' : '${date.year}-${_two(date.month)}-${_two(date.day)}  '
            '${_two(date.hour)}:${_two(date.minute)}:${_two(date.second)}';
          String details = (e['data_json'] ?? '').toString();
          try {
            final raw = jsonDecode(details);
            if (raw is Map) {
              details = raw.entries.map((v) => '${v.key}: ${v.value}').join('  ·  ');
            }
          } catch (_) {}
          return Card(child: ListTile(
            leading: const Icon(Icons.event_note_outlined, color: Color(0xFF1B365D)),
            title: Text((e['kind'] ?? '未知事件').toString(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$when\n$details', maxLines: 4, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
          ));
        }),
      ],
    ));
  }

  Widget _settingsTab() => ListView(padding: const EdgeInsets.all(20), children: [
    Text('连接与安全', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800, color: const Color(0xFF1B365D))),
    const SizedBox(height: 14),
    Card(child: Column(children: [
      ListTile(leading: const Icon(Icons.dns_outlined), title: const Text('后端服务'),
        subtitle: Text(widget.api.baseUrl)),
      const Divider(height: 1),
      const ListTile(leading: Icon(Icons.memory_outlined), title: Text('设备编号'),
        subtitle: Text('stirrer-001')),
      const Divider(height: 1),
      const ListTile(leading: Icon(Icons.router_outlined), title: Text('通信路径'),
        subtitle: Text('APP → HTTPS API → MQTT/TLS → ESP32')),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.system_update_alt_outlined),
        title: const Text('检查 GitHub 更新'),
        subtitle: const Text('检查 Releases 中的新版本 APK'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => SmartStirUpdateService.showUpdateDialog(context),
      ),
    ])),
    const SizedBox(height: 16),
    _notice('本版本不使用 GPIO32 现场许可引脚，电机 12V 供电必须具备独立的实体断电方式。'
      '程序设置了最长 180 秒运行限制；尚未进行实机安全验证。',
      const Color(0xFF8A4A06), Icons.warning_amber_rounded),
    const SizedBox(height: 18),
    OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout),
      label: const Text('退出当前账号')),
  ]);

  static String _two(int n) => n.toString().padLeft(2, '0');

  Widget _metric(String title, String value, String note) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
        color: Color(0xFF1B365D))),
      const SizedBox(height: 2),
      Text(note, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
    ],
  );

  Widget _notice(String content, Color tint, IconData icon) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: tint.withValues(alpha: 0.07),
      border: Border.all(color: tint.withValues(alpha: 0.24)),
      borderRadius: BorderRadius.circular(12)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: tint, size: 20),
      const SizedBox(width: 9),
      Expanded(child: Text(content, style: TextStyle(color: tint, fontSize: 13))),
    ]),
  );
}
