import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../models/system_info.dart';
import '../services/error_handler.dart';
import '../services/openwrt_service.dart';
import '../widgets/info_tile.dart';

class DashboardScreen extends StatefulWidget {
  final OpenWrtService service;
  const DashboardScreen({super.key, required this.service});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  SystemInfo? info;
  bool loading = true;
  String? error;
  String publicIp = '';
  String vpnIp = '';
  int totalClients = 0, wifiClients = 0, lanClients = 0;
  String vpnStatus = '—';
  bool internetOk = false;
  String dnsServers = '—';
  String wifi24Name = '—', wifi5Name = '—';
  String interferenceLevel = '—';
  Color interferenceColor = Colors.grey;
  // Живая скорость WAN (идея из OpenWrtManager NetworkTraffic / luci-mobile).
  String wanRxSpeed = '—', wanTxSpeed = '—';
  final List<FlSpot> _cpu = [], _mem = [];
  int _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // Автообновление ТОЛЬКО когда приложение активно и вкладка видна —
  // раньше таймер тикал даже в фоне (идея из OpenWrtManager mainPage).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _silent();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _silent());
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      final d = await widget.service.fetchSystemInfo();
      _update(d);

      int w = 0, l = 0;
      try {
        final clients = await widget.service.fetchClientsWithTraffic();
        for (final c in clients) {
          if (c.connectionType?.contains('Wi-Fi') == true) w++; else l++;
        }
      } catch (_) {}

      bool inet = false;
      String wanIp = '', vpnIpStr = '';
      try {
        final ip = await widget.service.fetchPublicIp();
        inet = ip.isNotEmpty && !ip.contains('недоступно');
        if (inet) wanIp = ip.trim();
      } catch (_) {}
      // Если VPN активен, получаем IP через VPN
      try {
        final vpns = await widget.service.fetchVpnStatus();
        final active = vpns.where((v) => v.up).toList();
        if (active.isNotEmpty) {
          vpnStatus = active.map((v) => v.name).join(', ');
          if (inet) { vpnIpStr = wanIp; wanIp = ''; }
        }
      } catch (_) {}

      // DNS
      try {
        final dnsRaw = await widget.service.fetchDnsSettings();
        final servers = <String>[];
        final re = RegExp(r"server='([^']+)'");
        for (final m in re.allMatches(dnsRaw)) { servers.add(m.group(1)!); }
        dnsServers = servers.isNotEmpty ? servers.take(2).join('\n') : '—';
      } catch (_) {}

      // WiFi SSID
      try {
        final nets = await widget.service.fetchWifiNetworks();
        for (final n in nets) {
          final dev = n.device;
          if (dev == 'radio0' && wifi24Name == '—') wifi24Name = n.ssid;
          if (dev == 'radio1' && wifi5Name == '—') wifi5Name = n.ssid;
        }
      } catch (_) {}

      // Помехи
      try {
        final devs = await widget.service.fetchWirelessDevices();
        if (devs.isNotEmpty) {
          final scan = await widget.service.scanWifiChannels(devs.first.name);
          final maxCount = scan.values.isEmpty ? 0 : scan.values.reduce((a, b) => a > b ? a : b);
           if (maxCount == 0) { interferenceLevel = AppStrings.of(context).text('Чисто'); interferenceColor = Colors.green; }
           else if (maxCount <= 3) { interferenceLevel = AppStrings.of(context).text('Слабые'); interferenceColor = Colors.orange; }
           else if (maxCount <= 6) { interferenceLevel = AppStrings.of(context).text('Средние'); interferenceColor = Colors.deepOrange; }
           else { interferenceLevel = AppStrings.of(context).text('Сильные'); interferenceColor = Colors.red; }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        info = d; totalClients = w + l; wifiClients = w; lanClients = l;
        internetOk = inet; publicIp = wanIp; vpnIp = vpnIpStr;
        loading = false; error = null;
      });
    } catch (e) { if (mounted) setState(() { error = e.toString(); loading = false; }); }
  }

  Future<void> _silent() async {
    if (!mounted || loading || info == null) return;
    // Обновляемся только если вкладка «Обзор» сейчас видима.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    try {
      final d = await widget.service.fetchSystemInfo();
      _update(d);
      String rx = wanRxSpeed, tx = wanTxSpeed;
      try {
        final t = await widget.service.fetchWanThroughput();
        rx = _fmtSpeed(t.rxRate);
        tx = _fmtSpeed(t.txRate);
      } catch (_) {}
      if (!mounted) return;
      setState(() { info = d; wanRxSpeed = rx; wanTxSpeed = tx; });
    } catch (_) {}
  }

  String _fmtSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '—';
    final bps = bytesPerSec * 8;
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Мбит/с';
    if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} Кбит/с';
    return '${bps.toStringAsFixed(0)} бит/с';
  }

  void _update(SystemInfo d) {
    _tick++;
    _cpu.add(FlSpot(_tick.toDouble(), d.cpuLoad * 100));
    _mem.add(FlSpot(_tick.toDouble(), d.memoryTotal > 0 ? (d.memoryUsed / d.memoryTotal) * 100 : 0));
    if (_cpu.length > 30) { _cpu.removeRange(0, _cpu.length - 30); _mem.removeRange(0, _mem.length - 30); }
  }

  String _h(int b) { if (b <= 0) return '0 B'; const s = ['B','KB','MB','GB']; int i=0; double d=b.toDouble(); while(d>=1024&&i<3){d/=1024;i++;} return '${NumberFormat('#0.0').format(d)} ${s[i]}'; }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = AppStrings.of(context);
    return RefreshIndicator(onRefresh: _load, child: CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
       SliverAppBar.large(title: Text(s.overview), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      if (loading) const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
      else if (error != null) _err(t)
      else if (info != null) SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: SliverList(delegate: SliverChildListDelegate([
        _header(t), const SizedBox(height: 12),
        _statusRow(t), const SizedBox(height: 8),
        _statusRow2(t), const SizedBox(height: 16),
         Row(children: [Expanded(child: _stat(t, Icons.memory, 'CPU', '${(info!.cpuLoad*100).toStringAsFixed(1)}%', t.colorScheme.primary)), const SizedBox(width: 12), Expanded(child: _stat(t, Icons.storage, 'RAM', _h(info!.memoryUsed), t.colorScheme.tertiary, sub: '${s.text('из')} ${_h(info!.memoryTotal)}'))]),
        const SizedBox(height: 12),
         Row(children: [Expanded(child: _stat(t, Icons.arrow_downward, s.text('↓ Скорость'), wanRxSpeed, Colors.green)), const SizedBox(width: 12), Expanded(child: _stat(t, Icons.arrow_upward, s.text('↑ Скорость'), wanTxSpeed, Colors.blue))]),
        const SizedBox(height: 16),
         _chart(t, s.text('Загрузка CPU (%)'), _cpu, t.colorScheme.primary),
        const SizedBox(height: 12),
         _chart(t, 'RAM (%)', _mem, t.colorScheme.tertiary),
        const SizedBox(height: 24),
      ]))),
    ]));
  }

  Widget _header(ThemeData t) => TweenAnimationBuilder<double>(duration: const Duration(milliseconds: 600), tween: Tween(begin: 0.95, end: 1.0), curve: Curves.easeOutBack, builder: (_, v, c) => Transform.scale(scale: v, child: c), child: Card(
    child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [t.colorScheme.primary, t.colorScheme.tertiary]), borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.router, color: Colors.white)), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('OpenWRT ${info!.firmwareVersion.replaceAll('OpenWrt ', '')}', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
            Text(info!.model, style: t.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
          ])),
        ]),
        const Divider(height: 24, color: Colors.white24),
         InfoTile(icon: Icons.timer, label: AppStrings.of(context).text('Время работы'), value: info!.uptime),
         InfoTile(icon: Icons.system_update, label: AppStrings.of(context).text('Прошивка'), value: info!.firmwareVersion),
      ]),
    ),
  ));

  Widget _statusRow(ThemeData t) => Row(children: [
     _miniWidget(t, Icons.language, AppStrings.of(context).text('Интернет'), internetOk ? AppStrings.of(context).text('Есть') : AppStrings.of(context).text('Нет'), internetOk ? Colors.green : Colors.red, ip: internetOk ? publicIp : ''),
    const SizedBox(width: 8),
     _miniWidget(t, Icons.vpn_key, 'VPN', vpnStatus, vpnStatus != '—' ? t.colorScheme.secondary : t.colorScheme.outline, ip: vpnIp),
    const SizedBox(width: 8),
     _miniWidget(t, Icons.devices, AppStrings.of(context).clients, '$totalClients', t.colorScheme.primary, sub: 'WiFi:$wifiClients LAN:$lanClients'),
  ]);

  Widget _statusRow2(ThemeData t) => Row(children: [
    _miniWidget(t, Icons.dns, 'DNS', dnsServers, t.colorScheme.tertiary),
    const SizedBox(width: 8),
     _miniWidget(t, Icons.wifi_tethering, AppStrings.of(context).text('Помехи'), interferenceLevel, interferenceColor),
    const SizedBox(width: 8),
     _miniWidget(t, Icons.wifi, AppStrings.of(context).text('WiFi сети'), wifi24Name != '—' ? '2.4: $wifi24Name' : '—', t.colorScheme.primary, sub: wifi5Name != '—' ? '5: $wifi5Name' : null),
  ]);

  Widget _miniWidget(ThemeData t, IconData icon, String label, String value, Color color, {String? sub, String? ip}) => Expanded(
    child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, fontSize: 10)),
      ]),
      const SizedBox(height: 2),
      if (ip != null && ip.isNotEmpty)
        SelectableText(ip, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: color), maxLines: 1),
      if ((ip == null || ip.isEmpty) && value.isNotEmpty)
        Text(value, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
      if (sub != null) Text(sub, style: TextStyle(fontSize: 9, color: t.colorScheme.onSurfaceVariant)),
    ]))),
  );

  Widget _stat(ThemeData t, IconData icon, String label, String value, Color color, {String? sub}) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
      const SizedBox(height: 12), Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      if (sub != null) Text(sub, style: t.textTheme.bodySmall),
    ])),
  );

  Widget _chart(ThemeData t, String title, List<FlSpot> spots, Color color) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SizedBox(height: 110, child: spots.length < 2 ? Center(child: Text('...', style: TextStyle(color: t.colorScheme.onSurfaceVariant))) : LineChart(LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: t.colorScheme.outlineVariant.withValues(alpha: 0.3))),
        titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), minY: 0, maxY: 100,
        lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: color, barWidth: 2.5, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.06)))],
      ))),
    ])),
  );

  Widget _err(ThemeData t) => SliverFillRemaining(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
     Icon(Icons.cloud_off, size: 72, color: t.colorScheme.error), const SizedBox(height: 16), Text(AppStrings.of(context).text('Ошибка подключения'), style: t.textTheme.titleMedium),
     Text(ErrorHandler.friendlyMessage(error), textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
    const SizedBox(height: 20),
    Row(mainAxisSize: MainAxisSize.min, children: [
      FilledButton.tonal(onPressed: _load, child: Text(AppStrings.of(context).text('Повторить'))),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: () => ErrorHandler.copyDiagnostics(context, error ?? ''),
        icon: const Icon(Icons.copy, size: 16),
        label: Text(AppStrings.of(context).text('Диагностика')),
      ),
    ]),
  ]))));
}
