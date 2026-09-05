import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/network_info.dart';
import '../services/offline_cache.dart';
import '../services/openwrt_service.dart';

class NetworkScreen extends StatefulWidget {
  final OpenWrtService service;

  const NetworkScreen({super.key, required this.service});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  String _t(String source) => AppStrings.of(context).text(source);
  List<NetworkInterface> interfaces = [];
  bool loading = true;
  String? error;
  String publicIp = '';
  String? wifiWanSsid;
  String? wifiWanDevice;

  @override
  void initState() {
    super.initState();
    _showCacheFirst();
    _load();
  }

  /// Показывает кешированные данные МГНОВЕННО, без спиннера.
  Future<void> _showCacheFirst() async {
    final key = OfflineCacheService.hostKey(
      widget.service.config.host,
      widget.service.config.port,
      widget.service.config.username,
    );
    final cached = await OfflineCacheService.loadNetworkInterfaces(key);
    if (!mounted || cached.isEmpty) return;
    setState(() {
      interfaces = cached;
      loading = false;
    });
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      final data = await widget.service.fetchNetworkInterfaces();
      final ip = await widget.service.fetchPublicIp();
      // Проверяем WiFi-клиент (STA mode)
      String? staSsid, staDev;
      try {
        final staRaw = await widget.service.runCommand('iwinfo 2>/dev/null | grep -A5 "Mode: Client" | grep -E "ESSID:|Access Point" | head -2 || echo ""');
        for (final line in LineSplitter.split(staRaw)) {
          if (line.contains('ESSID:')) staSsid = line.split(':').last.trim().replaceAll('"', '');
          if (line.contains('Access Point')) staDev = line.split(':').last.trim();
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        interfaces = data; publicIp = ip.trim();
        wifiWanSsid = staSsid; wifiWanDevice = staDev;
        loading = false; error = null;
      });
      // Сохраняем в оффлайн-кеш.
      // ignore: discarded_futures
      OfflineCacheService.saveNetworkInterfaces(
        OfflineCacheService.hostKey(
          widget.service.config.host,
          widget.service.config.port,
          widget.service.config.username,
        ),
        data,
      );
    } catch (e) { if (mounted) setState(() { error = e.toString(); loading = false; }); }
  }

  Future<void> _disconnectWifiWan() async {
    try {
      // Удаляем ТОЛЬКО клиентскую (sta) секцию — раньше удалялась последняя
      // wifi-iface секция, из-за чего могла отключиться основная точка доступа.
      await widget.service.runCommand('''
for s in \$(uci show wireless 2>/dev/null | grep '=wifi-iface' | cut -d. -f2 | cut -d= -f1); do
  m=\$(uci get wireless.\$s.mode 2>/dev/null || echo ap)
  [ "\$m" = "sta" ] && uci delete wireless.\$s
done
uci commit wireless
wifi reload
''');
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('WiFi-клиент отключён'))));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _setupWan() async {
    // Шаг 1: выбор страны.
    String? country;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Выберите страну')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in OpenWrtService.countryNames.entries)
              ListTile(
                leading: const Icon(Icons.public),
                title: Text(e.value),
                subtitle: Text(_t('Быстрая настройка проводного интернета')),
                onTap: () { country = e.key; Navigator.pop(ctx); },
              ),
          ]),
        ),
      ),
    );
    if (country == null || !mounted) return;

    // Шаг 2: выбор провайдера страны.
    final providers = OpenWrtService.countryProviders[country]!;
    Map<String, String>? provider;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Выберите провайдера')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ...providers.entries.map((e) => ListTile(
              leading: const Icon(Icons.business),
              title: Text(e.value['name']!),
              subtitle: Text(e.value['desc']!),
              trailing: Text(e.value['proto']!.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              onTap: () { provider = e.value; Navigator.pop(ctx); },
            )),
          ]),
        ),
      ),
    );
    if (provider == null || !mounted) return;
    final prov = provider!;

    final proto = prov['proto']!;
    if (proto == 'pppoe') {
      final user = TextEditingController();
      final pass = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_t('PPPoE — логин и пароль')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: user, decoration: InputDecoration(labelText: _t('Логин'))),
            const SizedBox(height: 8),
            TextField(controller: pass, decoration: InputDecoration(labelText: _t('Пароль')), obscureText: true),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Применить'))),
          ],
        ),
      );
      if (ok == true) {
        try {
          await widget.service.configureWan(prov, username: user.text, password: pass.text);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('WAN настроен, сеть перезапускается...'))));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка')}: $e')));
        }
      }
    } else if (proto == 'static') {
      final ipCtrl = TextEditingController();
      final maskCtrl = TextEditingController(text: '255.255.255.0');
      final gwCtrl = TextEditingController();
      final dnsCtrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_t('Статический IP')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Обычная клавиатура: IP содержит точки, цифровая их не показывает.
              TextField(controller: ipCtrl, decoration: InputDecoration(labelText: _t('IP-адрес'))),
              const SizedBox(height: 8),
              TextField(controller: maskCtrl, decoration: InputDecoration(labelText: _t('Маска'))),
              const SizedBox(height: 8),
              TextField(controller: gwCtrl, decoration: InputDecoration(labelText: _t('Шлюз'))),
              const SizedBox(height: 8),
              TextField(controller: dnsCtrl, decoration: InputDecoration(labelText: _t('DNS'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Применить'))),
          ],
        ),
      );
      if (ok == true) {
        try {
          await widget.service.configureWan(prov,
              ip: ipCtrl.text.trim(), netmask: maskCtrl.text.trim(), gateway: gwCtrl.text.trim(), dns: dnsCtrl.text.trim());
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('WAN настроен (Static), сеть перезапускается...'))));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка')}: $e')));
        }
      }
    } else {
      try {
        await widget.service.configureWan(prov);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('WAN настроен (DHCP) — сеть перезапускается'))));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка')}: $e')));
      }
    }
  }

  Future<void> _showTopology() async {
     showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Text(_t('Сканирование сети...'))])));
    try {
      final devices = await widget.service.fetchTopology();
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
           title: Row(children: [const Icon(Icons.account_tree), const SizedBox(width: 8), Text('${_t('Топология')} (${devices.length})')]),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (_, i) {
                final d = devices[i];
                final typeIcon = d['type'] == 'router' ? Icons.router : (d['type'] == 'dhcp' ? Icons.devices : Icons.computer);
                return ListTile(
                  leading: Icon(typeIcon, size: 28, color: d['type'] == 'router' ? Colors.orange : Colors.blue),
                  title: Text(d['hostname'] ?? d['ip'] ?? '?'),
                  subtitle: Text('${d['mac'] ?? ''} • ${d['iface'] ?? ''} ${d['port'] != null ? '• ${d['port']}' : ''}'),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  Future<void> _speedtest() async {
    final dlgKey = GlobalKey<_SpeedTestDialogState>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SpeedTestDialog(key: dlgKey),
    );
    try {
      await widget.service.connect();
      final result = await widget.service.runSpeedtest(
        onProgress: (stage, mbps) {
          final label = switch (stage) {
            'ping' => _t('Задержка'),
            'download' => _t('Скачивание'),
            'upload' => _t('Загрузка'),
            'fallback' => _t('wget'),
            _ => stage,
          };
          dlgKey.currentState?.update(label, mbps);
        },
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Speedtest'),
          content: SingleChildScrollView(child: SelectableText(result)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть')))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка')}: $e')));
    }
  }

  Future<void> _ping() async {
    final ctrl = TextEditingController(text: '8.8.8.8');
    String? result;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
           title: const Text('Ping'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               TextField(controller: ctrl, decoration: InputDecoration(labelText: _t('Хост'))),
              if (result != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.maxFinite,
                  height: 200,
                  child: SingleChildScrollView(child: SelectableText(result!)),
                ),
              ],
            ],
          ),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
            FilledButton(
              onPressed: () async {
                 setSt(() => result = _t('Проверка...'));
                try {
                  final res = await widget.service.pingHost(ctrl.text.trim());
                  if (ctx.mounted) setSt(() => result = res);
                } catch (e) {
                  if (ctx.mounted) setSt(() => result = '${_t('Ошибка')}: $e');
                }
              },
              child: const Text('Ping'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              automaticallyImplyLeading: false,
              title: Text(s.network),
              actions: [
                PopupMenuButton<String>(onSelected: (v) { if (v == 'speedtest') _speedtest(); if (v == 'ping') _ping(); if (v == 'wan') _setupWan(); if (v == 'topology') _showTopology(); },
                  itemBuilder: (ctx) => [
                     PopupMenuItem(value: 'topology', child: ListTile(leading: const Icon(Icons.account_tree), title: Text(_t('Топология сети')))),
                     PopupMenuItem(value: 'wan', child: ListTile(leading: const Icon(Icons.settings_ethernet), title: Text(_t('Настроить WAN')))),
                    const PopupMenuItem(value: 'speedtest', child: ListTile(leading: Icon(Icons.speed), title: Text('Speedtest'))),
                    const PopupMenuItem(value: 'ping', child: ListTile(leading: Icon(Icons.network_ping), title: Text('Ping'))),
                  ],
                ),
              ],
            ),
            if (loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              _buildError(theme)
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.public, color: theme.colorScheme.primary, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                 Text(_t('Публичный IP'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                Text(
                                  publicIp.isEmpty ? '—' : publicIp,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (wifiWanSsid != null && wifiWanSsid!.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Card(
                      color: Colors.orange.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          const Icon(Icons.wifi, color: Colors.orange, size: 28),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                             Text(_t('Интернет через Wi-Fi'), style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange)),
                            Text(wifiWanSsid!, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ])),
                           OutlinedButton.icon(onPressed: _disconnectWifiWan, icon: const Icon(Icons.link_off), label: Text(_t('Откл.')), style: OutlinedButton.styleFrom(foregroundColor: Colors.orange)),
                        ]),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final iface = interfaces[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: Icon(
                            iface.up ? Icons.check_circle : Icons.cancel,
                            color: iface.up ? Colors.green : theme.colorScheme.error,
                          ),
                          title: Text(iface.name),
                          subtitle: Text('${iface.protocol?.toUpperCase() ?? ''} • ${iface.device ?? ''}'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _row('IP', iface.ipAddresses?.join('\n') ?? '—'),
                                  if ((iface.ipv6Addresses ?? const []).isNotEmpty)
                                    _row('IPv6', (iface.ipv6Addresses ?? const []).join('\n')),
                                   _row(_t('Шлюз'), iface.gateway ?? '—'),
                                  _row('DNS', iface.dns ?? '—'),
                                   _row(_t('Трафик'), iface.bytesHuman),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: interfaces.length,
                  ),
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return SliverFillRemaining(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
               Text(_t('Ошибка'), style: theme.textTheme.titleMedium),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
               FilledButton.tonal(onPressed: _load, child: Text(_t('Повторить'))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Живой диалог speedtest: текущая стадия и скорость.
class _SpeedTestDialog extends StatefulWidget {
  const _SpeedTestDialog({super.key});
  @override
  State<_SpeedTestDialog> createState() => _SpeedTestDialogState();
}

class _SpeedTestDialogState extends State<_SpeedTestDialog> {
  String _stage = '';
  double? _mbps;

  void update(String stage, double? mbps) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _mbps = mbps;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(s.text('Speedtest')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(width: 16),
            Expanded(child: Text(_stage.isEmpty ? s.text('Подготовка...') : _stage)),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _mbps != null ? '${_mbps!.toStringAsFixed(1)} ${s.text('Мбит/с')}' : '—',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.green),
            ),
          ),
        ]),
      ),
    );
  }
}
