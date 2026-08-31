import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/network_info.dart';
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
    _load();
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
      setState(() {
        interfaces = data; publicIp = ip.trim();
        wifiWanSsid = staSsid; wifiWanDevice = staDev;
        loading = false; error = null;
      });
    } catch (e) { setState(() { error = e.toString(); loading = false; }); }
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
        await widget.service.configureWan(prov, username: user.text, password: pass.text);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('WAN настроен, сеть перезапускается...'))));
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
        await widget.service.configureWan(prov,
            ip: ipCtrl.text.trim(), netmask: maskCtrl.text.trim(), gateway: gwCtrl.text.trim(), dns: dnsCtrl.text.trim());
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('WAN настроен (Static), сеть перезапускается...'))));
      }
    } else {
      await widget.service.configureWan(prov);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('WAN настроен (DHCP) — сеть перезапускается'))));
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
     showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Text(_t('Проверка speedtest...'))])));
    try {
      await widget.service.connect();
      // Проверяем все доступные методы (Cloudflare-тест работает через curl)
      String? availableMethod;
      for (final method in ['curl', 'iperf3', 'speedtest-netperf', 'wget']) {
        final check = await widget.service.runCommand('(type $method || command -v $method || test -x /usr/bin/$method || test -x /usr/sbin/$method) >/dev/null 2>&1 && echo OK || echo NO');
        if (check.trim() == 'OK') { availableMethod = method; break; }
      }

      if (!mounted) return;
      Navigator.pop(context);

      if (availableMethod == null) {
        final install = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
             title: Text(_t('Не найдены инструменты замера')),
             content: Text('${_t('Установить curl и iperf3?')}\n\n'
                 '${_t('curl — универсальный тест через Cloudflare (точки в РФ/СНГ/ЕС)')}\n'
                 '${_t('iperf3 — точный замер в обе стороны')}\n\n'
                 '${_t('Также доступны: speedtest-netperf, wget')}'),
            actions: [
               TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
               FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Установить curl + iperf3'))),
            ],
          ),
        );
        if (install != true) return;
         showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Text(_t('Установка curl и iperf3...'))])));
        try {
          await widget.service.installPackages(['curl', 'iperf3']);
          if (!mounted) return;
          Navigator.pop(context);
        } catch (e) {
          if (!mounted) return;
          Navigator.pop(context);
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка установки')}: $e')));
          return;
        }
      }

       showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Text(_t('Speedtest... (~20-40 сек)'))])));
      final result = await widget.service.runSpeedtest();
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Speedtest'),
          content: SingleChildScrollView(child: SelectableText(result)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
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
                  setSt(() => result = res);
                } catch (e) {
                   setSt(() => result = '${_t('Ошибка')}: $e');
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
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
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
