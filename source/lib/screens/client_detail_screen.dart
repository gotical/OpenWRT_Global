import 'package:flutter/material.dart';
import '../models/client_info.dart';
import '../services/openwrt_service.dart';
import '../services/storage_service.dart';

class ClientDetailScreen extends StatefulWidget {
  final OpenWrtService service;
  final ClientInfo client;
  const ClientDetailScreen({super.key, required this.service, required this.client});
  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  String deviceType = '', vendor = '', apInfo = '', connectionPath = '';
  List<String> domains = [];
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final c = widget.client;
    try {
      // Тип из локальных данных
      deviceType = c.connectionType?.contains('Wi-Fi') == true ? 'Wi-Fi устройство' : 'Проводное устройство';
      apInfo = c.accessPoint ?? c.interface ?? (c.connectionType?.contains('Wi-Fi') == true ? 'Wi-Fi' : 'LAN');

      // Пробуем получить вендор с роутера (быстро, без интернета)
      try {
        await widget.service.connect();
        try { vendor = await widget.service.fetchMacVendor(c.mac); } catch (_) {}
        try { deviceType = await widget.service.classifyDevice(mac: c.mac, hostname: c.hostname, ip: c.ip); } catch (_) {}
        // Активные соединения
        try {
          final raw = await widget.service.runCommand('conntrack -L 2>/dev/null | grep "${c.ip}" | head -20 || cat /proc/net/nf_conntrack 2>/dev/null | grep "${c.ip}" | head -20 || echo ""');
          domains = raw.split('\n').where((l) => l.isNotEmpty).take(20).toList();
        } catch (_) {}
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client; final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(c.hostname)),
      body: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
        _card(t, 'Устройство', [
          _r('Имя', c.hostname), _r('IP', c.ip ?? '—'), _r('MAC', c.mac),
          if (vendor.isNotEmpty) _r('Производитель', vendor),
          if (deviceType.isNotEmpty) _r('Тип', deviceType),
        ]),
        const SizedBox(height: 12),
        _card(t, 'Подключение', [
          _r('Интерфейс', apInfo),
          _r('Тип', c.connectionType ?? '—'),
          _r('Сигнал', c.signal != null ? '${c.signal} dBm' : '—'),
        ]),
        const SizedBox(height: 12),
        _card(t, 'Трафик (сессия)', [
          _r('Принято', c.rxHuman), _r('Отправлено', c.txHuman), _r('Всего', c.totalHuman),
        ]),
        const SizedBox(height: 12),
        if (domains.isNotEmpty)
          _card(t, 'Соединения (${domains.length})', [
            ...domains.map((l) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(l.length > 60 ? '${l.substring(0,60)}...' : l, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')))),
          ])
        else
          _card(t, 'Соединения', [const Text('Установите conntrack для просмотра')]),
        const SizedBox(height: 16),
        _actions(),
      ]),
    );
  }

  Widget _actions() => Row(children: [
    Expanded(child: FilledButton.icon(onPressed: _rename, icon: const Icon(Icons.edit), label: const Text('Имя'))),
    const SizedBox(width: 8),
    Expanded(child: FilledButton.tonalIcon(onPressed: _block, icon: const Icon(Icons.block), label: const Text('Блок'))),
    const SizedBox(width: 8),
    Expanded(child: OutlinedButton.icon(onPressed: _staticIp, icon: const Icon(Icons.router), label: const Text('IP'))),
  ]);

  Widget _card(ThemeData t, String title, List<Widget> children) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 8), ...children])));
  Widget _r(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [SizedBox(width: 110, child: Text(l, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))), Expanded(child: Text(v, style: const TextStyle(fontSize: 14)))]));

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: widget.client.hostname);
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Имя'), content: TextField(controller: ctrl, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK'))]));
    if (name != null) { await StorageService.saveDeviceName(widget.client.mac, name); if (mounted) Navigator.pop(context, true); }
  }

  Future<void> _block() async {
    try { await widget.service.blockClient(widget.client.mac); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заблокирован'))); Navigator.pop(context); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _staticIp() async {
    final ipCtrl = TextEditingController(text: widget.client.ip ?? '192.168.1.100');
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Статический IP'), content: TextField(controller: ipCtrl, decoration: const InputDecoration(labelText: 'IP')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(ctx, ipCtrl.text.trim()), child: const Text('OK'))]));
    if (name != null) { await widget.service.setStaticLease(mac: widget.client.mac, ip: name, hostname: widget.client.hostname); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IP сохранён'))); }
  }
}
