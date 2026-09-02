import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:intl/intl.dart';
import '../models/client_info.dart';
import '../services/openwrt_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/empty_state.dart';
import 'client_detail_screen.dart';

class ClientsScreen extends StatefulWidget {
  final OpenWrtService service;
  const ClientsScreen({super.key, required this.service});
  @override
  State<ClientsScreen> createState() => ClientsScreenState();
}

class ClientsScreenState extends State<ClientsScreen> {
  String _t(String source) => AppStrings.of(context).text(source);
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
  bool _showOffline = true;

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
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      filtered = allClients.where((c) {
        final matchesSearch = c.hostname.toLowerCase().contains(q) ||
            c.mac.toLowerCase().contains(q) ||
            (c.ip?.toLowerCase().contains(q) ?? false);
        final matchesOffline = _showOffline || c.active;
        return matchesSearch && matchesOffline;
      }).toList();
      // Сначала онлайн, потом оффлайн (визуально естественнее).
      filtered.sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
      });
    });
  }

  Map<String, List<ClientInfo>> get _byInterface {
    final map = <String, List<ClientInfo>>{};
    // Сортировка: WiFi 2.4, WiFi 5, LAN
    final order = ['Wi-Fi 2.4GHz', 'Wi-Fi 5GHz', 'Wi-Fi 6GHz', 'LAN'];
    for (final label in order) {
      final clients = allClients.where((c) => c.active && c.connectionType == label).toList();
      if (clients.isNotEmpty) map[label] = clients;
    }
    // Остальные (активные)
    for (final c in allClients) {
      if (c.active && !order.contains(c.connectionType)) {
        final key = c.connectionType ?? _t('Другое');
        map.putIfAbsent(key, () => []).add(c);
      }
    }
    // Оффлайн — отдельной секцией в конце.
    if (_showOffline) {
      final offline = allClients.where((c) => !c.active).toList()
        ..sort((a, b) => a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase()));
      if (offline.isNotEmpty) {
        map[_t('Не в сети')] = offline;
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
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  /// Отключить Wi-Fi клиента (идея из OpenWrtManager: hostapd del_client).
  Future<void> _kickClient(ClientInfo c) async {
    final iface = c.accessPoint ?? c.interface;
    if (iface == null || iface.isEmpty) {
      _snack(_t('Интерфейс не определён'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Отключить устройство?')),
        content: Text('${_displayName(c)}\n${c.mac}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Отключить'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.kickWifiClient(iface, c.mac);
      if (mounted) _snack(_t('Устройство отключено'));
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
         title: Text('${_t('Лимит')} — ${client.hostname}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
           decoration: InputDecoration(labelText: _t('ГБ (0 — без лимита)')),
        ),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Отмена'))),
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
         title: Text('${_t('Скорость')} — ${c.hostname}'),
        content: TextField(
          controller: ctrl,
           decoration: InputDecoration(labelText: _t('КБ/с (0=снять)')),
          keyboardType: TextInputType.number,
        ),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Отмена'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (kbps == null) return;
    try {
      await widget.service.applySpeedLimit(c.mac, kbps);
      if (mounted) _snack(kbps == 0 ? _t('Снято') : '${_t('Скорость')}: $kbps ${_t('КБ/с')}');
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _setStaticIp(ClientInfo c) async {
    List<Map<String, String>> leases;
    try {
      leases = await widget.service.fetchStaticLeases();
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
      return;
    }
    final ex = leases.where((e) => e['mac'] == c.mac).firstOrNull;
    final ipCtrl = TextEditingController(text: ex?['ip'] ?? c.ip ?? '192.168.1.100');
    final nameCtrl = TextEditingController(text: ex?['name'] ?? c.hostname);
    final act = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text('${_t('Стат. IP')} — ${c.hostname}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ex != null)
              Chip(
                 label: Text('${_t('Назначен:')} ${ex['ip']}'),
                backgroundColor: Colors.green.withValues(alpha: 0.1),
              ),
             TextField(controller: ipCtrl, decoration: InputDecoration(labelText: _t('IP-адрес'))),
             TextField(controller: nameCtrl, decoration: InputDecoration(labelText: _t('Имя'))),
          ],
        ),
        actions: [
          if (ex != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
               child: Text(_t('Удалить'), style: const TextStyle(color: Colors.red)),
            ),
           TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Отмена'))),
           FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(_t('Сохранить'))),
        ],
      ),
    );
    if (act == null) return;
    try {
      if (act == 'delete') {
        await widget.service.removeStaticLease(c.mac);
      } else {
        await widget.service.setStaticLease(mac: c.mac, ip: ipCtrl.text, hostname: nameCtrl.text);
      }
      if (mounted) _snack(_t('Готово'));
      await _load();
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _renameClient(ClientInfo c) async {
    final cur = deviceNames[c.mac] ?? c.hostname;
    final ctrl = TextEditingController(text: cur);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text('${_t('Имя')} — ${c.mac}'),
        content: TextField(
          controller: ctrl,
           decoration: InputDecoration(labelText: _t('Имя устройства')),
          autofocus: true,
        ),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Отмена'))),
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
    if (c.mac.length < 8) return; // защита от некорректных MAC
    final prefix = c.mac.substring(0, 8);
    if (vendorCache.containsKey(prefix)) return;
    try {
      final v = await widget.service.fetchMacVendor(c.mac);
      if (mounted) setState(() => vendorCache[prefix] = v);
    } catch (_) {}
  }

  Future<void> _classify(ClientInfo c) async {
    if (deviceTypes.containsKey(c.mac)) return;
    try {
      final t = await widget.service.classifyDevice(
        mac: c.mac,
        hostname: _displayName(c),
        ip: c.ip,
      );
      if (mounted) setState(() => deviceTypes[c.mac] = t);
    } catch (_) {}
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

  List<Widget> _buildSection(String name, List<ClientInfo> list, ThemeData t) {
    final isOffline = name == _t('Не в сети');
    final iconColor = isOffline
        ? t.colorScheme.onSurfaceVariant
        : name.contains('5GHz') ? const Color(0xFF0077CC) :
          name.contains('2.4GHz') ? const Color(0xFF2E7D32) :
          name.contains('6GHz') ? const Color(0xFF9C27B0) :
          t.colorScheme.primary;
    return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Icon(
                isOffline ? Icons.cloud_off :
                name.contains('5GHz') ? Icons.wifi :
                name.contains('2.4GHz') ? Icons.wifi :
                name.contains('6GHz') ? Icons.signal_cellular_alt :
                Icons.settings_ethernet,
                size: 20,
                color: iconColor,
              ),
              const SizedBox(width: 8),
              Text(name,
                  style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isOffline ? t.colorScheme.onSurfaceVariant : null)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${list.length}',
                    style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: iconColor)),
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
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = Theme.of(context);
    final sections = _byInterface;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: Text(s.clients),
              actions: [
                IconButton(
                  icon: Icon(treeView ? Icons.list : Icons.account_tree),
                  onPressed: () => setState(() => treeView = !treeView),
                   tooltip: _t('Вид'),
                ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                if (filtered.any((c) => !c.active))
                  IconButton(
                    tooltip: _showOffline ? _t('Скрыть не в сети') : _t('Показать не в сети'),
                    icon: Icon(_showOffline ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showOffline = !_showOffline),
                  ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: SearchBar(
                  controller: _searchCtrl,
                   hintText: _t('Поиск'),
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
            if (!loading && error == null && filtered.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _onlineOfflineCounts(t),
                ),
              ),
            ],
            if (loading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const AppCardSkeleton(lines: 2),
                    const AppCardSkeleton(lines: 2),
                    const AppCardSkeleton(lines: 2),
                    const AppCardSkeleton(lines: 2),
                  ]),
                ),
              )
            else if (error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: t.colorScheme.error),
                      const SizedBox(height: 16),
                       Text(_t('Ошибка'), style: t.textTheme.titleMedium),
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                       FilledButton.tonal(onPressed: _load, child: Text(_t('Повторить'))),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  asset: 'assets/empty_states/no_clients.png',
                  title: _t('Клиенты не найдены'),
                  message: _t('Проверьте, что устройства подключены к сети'),
                  icon: Icons.refresh,
                  actionLabel: _t('Обновить'),
                  onAction: _load,
                ),
              )
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

  /// Бейдж-счётчик «N онлайн · M не в сети».
  Widget _onlineOfflineCounts(ThemeData t) {
    final online = filtered.where((c) => c.active).length;
    final offline = filtered.where((c) => !c.active).toList();
    return Row(
      children: [
        _statusChip(t, Icons.wifi_tethering, '$online ${_t('онлайн')}',
            t.colorScheme.primary),
        if (offline.isNotEmpty) ...[
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showOfflineDialog(offline),
            child: _statusChip(t, Icons.cloud_off,
                '${offline.length} ${_t('не в сети')}',
                t.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  /// Диалог со списком оффлайн-устройств и кнопкой «Очистить».
  Future<void> _showOfflineDialog(List<ClientInfo> offline) async {
    final t = Theme.of(context);
    final s = AppStrings.of(context);
    final cleared = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStLocal) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.cloud_off),
            const SizedBox(width: 8),
            Text('${_t('Не в сети')} (${offline.length})'),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _t('Эти устройства сейчас не в сети. Их имена сохранены локально и могут быть очищены.'),
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: offline
                          .map((c) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.cloud_off, color: Colors.grey),
                                title: Text(_displayName(c),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${c.mac} • ${c.ip ?? '—'}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('Закрыть')),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(_t('Очистить')),
            ),
          ],
        ),
      ),
    );
    if (cleared == true) {
      await _clearOffline(offline);
    }
  }

  /// Удаляет имена оффлайн-устройств из настроек и из списка.
  Future<void> _clearOffline(List<ClientInfo> offline) async {
    final macs = offline.map((c) => c.mac).toList();
    int removed = 0;
    try {
      removed = await StorageService.removeDeviceNames(macs);
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
      return;
    }
    // Убираем из локального кэша имён.
    for (final c in offline) {
      deviceNames.remove(c.mac);
    }
    // Убираем из текущего списка.
    setState(() {
      allClients = allClients.where((c) => c.active).toList();
      _filter();
    });
    if (mounted) {
      _snack(removed > 0
          ? '${_t('Удалено')}: $removed'
          : _t('Нечего удалять'));
    }
  }

  Widget _statusChip(ThemeData t, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: t.textTheme.bodySmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _clientCard(ClientInfo c, ThemeData t) {
    final blocked = blockedMacs.contains(c.mac);
    final limit = limits[c.mac];
    final isOffline = !c.active;
    final progress = _progress(c);
    final bandColor = c.connectionType?.contains('6GHz') == true ? const Color(0xFF9C27B0) :
                      c.connectionType?.contains('5GHz') == true ? const Color(0xFF0077CC) :
                      c.connectionType?.contains('2.4GHz') == true ? const Color(0xFF2E7D32) :
                      const Color(0xFF6D4C41);
    final card = GestureDetector(
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
                  style: t.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isOffline ? t.colorScheme.onSurfaceVariant : null))),
              if (isOffline) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_t('Не в сети'),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: t.colorScheme.onSurfaceVariant)),
                ),
              ],
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
                     '${c.dlSpeed!.toStringAsFixed(1)} ${_t('Мбит/с')}',
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
                   _r(t, _t('Тип'), c.connectionType ?? '—'),
                   _r(t, _t('Точка доступа'), c.accessPoint ?? c.interface ?? '—'),
                   if (c.rxBitrate != null) _r(t, _t('Битрейт (RX)'), c.rxBitrate!),
                   if (c.txBitrate != null) _r(t, _t('Битрейт (TX)'), c.txBitrate!),
                   if (c.dlSpeed != null && c.dlSpeed! > 0) _r(t, _t('↓ Скорость'), c.dlSpeedHuman),
                   if (c.ulSpeed != null && c.ulSpeed! > 0) _r(t, _t('↑ Скорость'), c.ulSpeedHuman),
                   _r(t, _t('↓ Получено'), c.rxHuman),
                   _r(t, _t('↑ Отправлено'), c.txHuman),
                  if (c.monthTotalBytes > 0) ...[
                    const Divider(height: 16),
                     _r(t, _t('Трафик за месяц'), c.monthTotalHuman),
                     _r(t, _t('↓ Месяц'), c.monthRxHuman),
                     _r(t, _t('↑ Месяц'), c.monthTxHuman),
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
                     Text('${_t('Лимит:')} ${_gb(limit)} ${_t('ГБ')} (${(progress * 100).toStringAsFixed(0)}%)',
                        style: t.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _btn(() {
                      _loadVendor(c);
                      _renameClient(c);
                     }, Icons.edit, _t('Имя'), t.colorScheme.primary),
                    _btn(() {
                      _loadVendor(c);
                      _classify(c);
                     }, Icons.psychology, _deviceType(c) ?? _t('Тип'), t.colorScheme.secondary),
                    _btn(
                      () => _toggleBlock(c),
                      blocked ? Icons.lock_open : Icons.block,
                       blocked ? _t('Разблок') : _t('Блок'),
                      blocked ? Colors.green : Colors.red,
                    ),
                     _btn(() => _setLimit(c), Icons.data_usage, _t('ГБ')),
                     _btn(() => _setSpeedLimit(c), Icons.speed, _t('КБ/с')),
                    _btn(() => _setStaticIp(c), Icons.router, 'IP'),
                    if (c.isWifi)
                      _btn(
                        () => _kickClient(c),
                        Icons.link_off,
                        _t('Откл.'),
                        Colors.orange,
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (isOffline) return Opacity(opacity: 0.55, child: IgnorePointer(ignoring: false, child: card));
    return card;
  }
}
