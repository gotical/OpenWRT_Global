import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/client_info.dart';
import '../services/openwrt_service.dart';
import '../services/storage_service.dart';
import 'client_detail_screen.dart';

class ClientsScreen extends StatefulWidget {
  final OpenWrtService service;
  const ClientsScreen({super.key, required this.service});
  @override
  State<ClientsScreen> createState() => ClientsScreenState();
}

class ClientsScreenState extends State<ClientsScreen> {
  List<ClientInfo> allClients = [];
  List<ClientInfo> filtered = [];
  List<String> blockedMacs = [];
  Map<String, int> limits = {};
  Map<String, String> deviceNames = {};
  Map<String, String> vendorCache = {};
  Map<String, String> deviceTypes = {};
  bool loading = true;
  String? error;
  final _searchCtrl = TextEditingController();
  bool treeView = true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_filter);
    _load();
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      final data = await widget.service.fetchClientsWithTraffic();
      final blocked = await widget.service.fetchBlockedMacs();
      final lim = await StorageService.loadTrafficLimits();
      final names = await StorageService.loadDeviceNames();
      setState(() {
        allClients = data;
        blockedMacs = blocked.map((m) => m.toLowerCase()).toList();
        limits = lim;
        deviceNames = names;
        _filter();
        loading = false;
        error = null;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() => filtered = allClients.where((c) =>
        c.hostname.toLowerCase().contains(q) ||
        c.mac.toLowerCase().contains(q) ||
        (c.ip?.toLowerCase().contains(q) ?? false)).toList());
  }

  Map<String, List<ClientInfo>> get _byInterface {
    final map = <String, List<ClientInfo>>{};
    // Сортировка: WiFi 2.4, WiFi 5, LAN
    final order = ['Wi-Fi 2.4GHz', 'Wi-Fi 5GHz', 'Wi-Fi 6GHz', 'LAN'];
    for (final label in order) {
      final clients = allClients.where((c) => c.connectionType == label).toList();
      if (clients.isNotEmpty) map[label] = clients;
    }
    // Остальные
    for (final c in allClients) {
      if (!order.contains(c.connectionType)) {
        final key = c.connectionType ?? 'Другое';
        map.putIfAbsent(key, () => []).add(c);
      }
    }
    return map;
  }

  Future<void> _toggleBlock(ClientInfo c) async {
    final blocked = blockedMacs.contains(c.mac);
    try {
      if (blocked) {
        await widget.service.unblockClient(c.mac);
        blockedMacs.remove(c.mac);
      } else {
        await widget.service.blockClient(c.mac);
        blockedMacs.add(c.mac);
      }
      setState(() {});
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _setLimit(ClientInfo client) async {
    final cur = limits[client.mac];
    final ctrl = TextEditingController(text: cur != null ? _gb(cur) : '');
    final gb = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Лимит — ${client.hostname}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'ГБ (0 — без лимита)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (gb == null) return;
    await StorageService.setTrafficLimit(client.mac, (gb * 1073741824).toInt());
    final lim = await StorageService.loadTrafficLimits();
    setState(() => limits = lim);
  }

  Future<void> _setSpeedLimit(ClientInfo c) async {
    final ctrl = TextEditingController(text: '0');
    final kbps = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Скорость — ${c.hostname}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'КБ/с (0=снять)'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (kbps == null) return;
    await widget.service.applySpeedLimit(c.mac, kbps);
    if (mounted) _snack(kbps == 0 ? 'Снято' : 'Скорость: $kbps КБ/с');
  }

  Future<void> _setStaticIp(ClientInfo c) async {
    final leases = await widget.service.fetchStaticLeases();
    final ex = leases.where((e) => e['mac'] == c.mac).firstOrNull;
    final ipCtrl = TextEditingController(text: ex?['ip'] ?? c.ip ?? '192.168.1.100');
    final nameCtrl = TextEditingController(text: ex?['name'] ?? c.hostname);
    final act = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Стат. IP — ${c.hostname}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ex != null)
              Chip(
                label: Text('Назначен: ${ex['ip']}'),
                backgroundColor: Colors.green.withValues(alpha: 0.1),
              ),
            TextField(controller: ipCtrl, decoration: const InputDecoration(labelText: 'IP-адрес')),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Имя')),
          ],
        ),
        actions: [
          if (ex != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Удалить', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Сохранить')),
        ],
      ),
    );
    if (act == null) return;
    if (act == 'delete') {
      await widget.service.removeStaticLease(c.mac);
    } else {
      await widget.service.setStaticLease(mac: c.mac, ip: ipCtrl.text, hostname: nameCtrl.text);
    }
    if (mounted) _snack('Готово');
    await _load();
  }

  Future<void> _renameClient(ClientInfo c) async {
    final cur = deviceNames[c.mac] ?? c.hostname;
    final ctrl = TextEditingController(text: cur);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Имя — ${c.mac}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Имя устройства'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await StorageService.saveDeviceName(c.mac, name);
    final names = await StorageService.loadDeviceNames();
    setState(() => deviceNames = names);
  }

  String _displayName(ClientInfo c) => deviceNames[c.mac] ?? c.hostname;

  String _vendor(ClientInfo c) =>
      c.mac.length >= 8 ? _lookupOui(c.mac.substring(0, 8)) : '';

  String _lookupOui(String prefix) => vendorCache[prefix] ?? '';

  Future<void> _loadVendor(ClientInfo c) async {
    if (vendorCache.containsKey(c.mac.substring(0, 8))) return;
    final v = await widget.service.fetchMacVendor(c.mac);
    setState(() => vendorCache[c.mac.substring(0, 8)] = v);
  }

  Future<void> _classify(ClientInfo c) async {
    if (deviceTypes.containsKey(c.mac)) return;
    final t = await widget.service.classifyDevice(
      mac: c.mac,
      hostname: _displayName(c),
      ip: c.ip,
    );
    setState(() => deviceTypes[c.mac] = t);
  }

  IconData _typeIcon(String? type) {
    if (type == null) return Icons.devices;
    final t = type.toLowerCase();
    if (t.contains('iphone') || t.contains('телефон') || t.contains('android') ||
        t.contains('samsung') || t.contains('huawei') || t.contains('xiaomi')) {
      return Icons.phone_android;
    }
    if (t.contains('mac') || t.contains('пк') || t.contains('ноутбук') ||
        t.contains('apple') || t.contains('windows') || t.contains('linux')) {
      return Icons.computer;
    }
    if (t.contains('tv') || t.contains('chromecast') || t.contains('bravia') ||
        t.contains('lg')) {
      return Icons.tv;
    }
    if (t.contains('роутер') || t.contains('openwrt') || t.contains('сетевое') ||
        t.contains('asus') || t.contains('tplink')) {
      return Icons.router;
    }
    if (t.contains('xbox') || t.contains('playstation') || t.contains('nintendo') ||
        t.contains('игр')) {
      return Icons.sports_esports;
    }
    if (t.contains('принтер')) return Icons.print;
    if (t.contains('raspberry')) return Icons.memory;
    if (t.contains('google') || t.contains('amazon') || t.contains('умный')) {
      return Icons.lightbulb;
    }
    if (t.contains('камера') || t.contains('ip-')) return Icons.videocam;
    return Icons.devices;
  }

  String? _deviceType(ClientInfo c) => deviceTypes[c.mac];

  String _gb(int b) => NumberFormat('#0.0').format(b / 1073741824);

  double _progress(ClientInfo c) {
    final l = limits[c.mac];
    if (l == null || l <= 0) return 0;
    return (c.totalBytes / l).clamp(0.0, 1.0);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
      ));

  List<Widget> _buildSection(String name, List<ClientInfo> list, ThemeData t) => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Icon(
                name.contains('5GHz') ? Icons.wifi : 
                name.contains('2.4GHz') ? Icons.wifi : 
                name.contains('6GHz') ? Icons.signal_cellular_alt : 
                Icons.settings_ethernet,
                size: 20,
                color: name.contains('5GHz') ? const Color(0xFF0077CC) :
                       name.contains('2.4GHz') ? const Color(0xFF2E7D32) :
                       name.contains('6GHz') ? const Color(0xFF9C27B0) :
                       t.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(name,
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: t.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${list.length}',
                    style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate:
                SliverChildBuilderDelegate((_, i) => _clientCard(list[i], t), childCount: list.length),
          ),
        ),
      ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sections = _byInterface;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Клиенты'),
              actions: [
                IconButton(
                  icon: Icon(treeView ? Icons.list : Icons.account_tree),
                  onPressed: () => setState(() => treeView = !treeView),
                  tooltip: 'Вид',
                ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: SearchBar(
                  controller: _searchCtrl,
                  hintText: 'Поиск',
                  leading: const Icon(Icons.search),
                  trailing: _searchCtrl.text.isNotEmpty
                      ? [
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        ]
                      : null,
                ),
              ),
            ),
            if (loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: t.colorScheme.error),
                      const SizedBox(height: 16),
                      Text('Ошибка', style: t.textTheme.titleMedium),
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.tonal(onPressed: _load, child: const Text('Повторить')),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              const SliverFillRemaining(child: Center(child: Text('Клиенты не найдены')))
            else if (!treeView)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _clientCard(filtered[i], t),
                    childCount: filtered.length,
                  ),
                ),
              )
            else ...[
              for (final e in sections.entries) ..._buildSection(e.key, e.value, t),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }

  Widget _btn(VoidCallback onTap, IconData icon, String label, [Color? color]) => ActionChip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );

  Widget _r(ThemeData t, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: t.textTheme.bodyMedium)),
        ]),
      );

  Widget _clientCard(ClientInfo c, ThemeData t) {
    final blocked = blockedMacs.contains(c.mac);
    final limit = limits[c.mac];
    final progress = _progress(c);
    final bandColor = c.connectionType?.contains('6GHz') == true ? const Color(0xFF9C27B0) :
                      c.connectionType?.contains('5GHz') == true ? const Color(0xFF0077CC) :
                      c.connectionType?.contains('2.4GHz') == true ? const Color(0xFF2E7D32) :
                      const Color(0xFF6D4C41);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientDetailScreen(service: widget.service, client: c),
        ),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor:
                blocked ? Colors.red.withValues(alpha: 0.15) : bandColor.withValues(alpha: 0.15),
            child: Icon(
              blocked ? Icons.block : _typeIcon(_deviceType(c)),
              size: 20,
              color: blocked ? Colors.red : bandColor,
            ),
          ),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _loadVendor(c);
              _classify(c);
            }
          },
          title: Row(
            children: [
              Expanded(child: Text(_displayName(c),
                  style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))),
              if (c.isWifi) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: bandColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    c.connectionType?.contains('5GHz') == true ? '5G' :
                    c.connectionType?.contains('6GHz') == true ? '6G' : '2.4G',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: bandColor),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (c.dlSpeed != null && c.dlSpeed! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.dlSpeed! > 10 ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${c.dlSpeed!.toStringAsFixed(1)} Мбит/с',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold,
                      color: c.dlSpeed! > 10 ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(
              '${c.ip ?? '-'} • ${c.mac}${_vendor(c).isNotEmpty ? ' (${_vendor(c)})' : ''}'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_deviceType(c) != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Chip(
                        avatar: Icon(_typeIcon(_deviceType(c)), size: 16),
                        label: Text(_deviceType(c)!, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: bandColor.withValues(alpha: 0.08),
                      ),
                    ),
                  _r(t, 'Тип', c.connectionType ?? '—'),
                  _r(t, 'Точка доступа', c.accessPoint ?? c.interface ?? '—'),
                  if (c.rxBitrate != null) _r(t, 'Битрейт (RX)', c.rxBitrate!),
                  if (c.txBitrate != null) _r(t, 'Битрейт (TX)', c.txBitrate!),
                  if (c.dlSpeed != null && c.dlSpeed! > 0) _r(t, '↓ Скорость', c.dlSpeedHuman),
                  if (c.ulSpeed != null && c.ulSpeed! > 0) _r(t, '↑ Скорость', c.ulSpeedHuman),
                  _r(t, '↓ Получено', c.rxHuman),
                  _r(t, '↑ Отправлено', c.txHuman),
                  if (c.monthTotalBytes > 0) ...[
                    const Divider(height: 16),
                    _r(t, 'Трафик за месяц', c.monthTotalHuman),
                    _r(t, '↓ Месяц', c.monthRxHuman),
                    _r(t, '↑ Месяц', c.monthTxHuman),
                  ],
                  if (limit != null && limit > 0) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: t.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress > 0.9 ? Colors.red : t.colorScheme.primary,
                      ),
                    ),
                    Text('Лимит: ${_gb(limit)} ГБ (${(progress * 100).toStringAsFixed(0)}%)',
                        style: t.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _btn(() {
                      _loadVendor(c);
                      _renameClient(c);
                    }, Icons.edit, 'Имя', t.colorScheme.primary),
                    _btn(() {
                      _loadVendor(c);
                      _classify(c);
                    }, Icons.psychology, _deviceType(c) ?? 'Тип', t.colorScheme.secondary),
                    _btn(
                      () => _toggleBlock(c),
                      blocked ? Icons.lock_open : Icons.block,
                      blocked ? 'Разблок' : 'Блок',
                      blocked ? Colors.green : Colors.red,
                    ),
                    _btn(() => _setLimit(c), Icons.data_usage, 'ГБ'),
                    _btn(() => _setSpeedLimit(c), Icons.speed, 'КБ/с'),
                    _btn(() => _setStaticIp(c), Icons.router, 'IP'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}