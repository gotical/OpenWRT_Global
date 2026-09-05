import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/vpn_info.dart';
import '../services/offline_cache.dart';
import '../services/openwrt_service.dart';

class VpnScreen extends StatefulWidget {
  final OpenWrtService service;

  const VpnScreen({super.key, required this.service});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  AppStrings get s => AppStrings.of(context);
  List<VpnInterface> vpns = [];
  bool loading = true;
  String? error;
  String? _toggling;

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
    final cached = await OfflineCacheService.loadVpnInterfaces(key);
    if (!mounted || cached.isEmpty) return;
    setState(() {
      vpns = cached;
      loading = false;
    });
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      final data = await widget.service.fetchVpnStatus();
      if (!mounted) return;
      setState(() {
        vpns = data;
        loading = false;
        error = null;
      });
      // Сохраняем в оффлайн-кеш.
      // ignore: discarded_futures
      OfflineCacheService.saveVpnInterfaces(
        OfflineCacheService.hostKey(
          widget.service.config.host,
          widget.service.config.port,
          widget.service.config.username,
        ),
        data,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _toggle(VpnInterface v) async {
    try {
      setState(() => _toggling = v.name);
      if (v.up) {
        // Выключение
        await widget.service.vpnDown(v.name);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${v.name} ${s.text('Выключен')}')));
      } else {
        // Взаимное исключение: выключаем другие VPN того же типа
        final others = vpns.where((o) =>
            o.name != v.name &&
            o.up &&
            ((v.type == 'WireGuard' || v.type == 'AmneziaWG') &&
             (o.type == 'WireGuard' || o.type == 'AmneziaWG') ||
             (v.type == 'OpenVPN' && o.type == 'OpenVPN')));
        for (final other in others) {
          await widget.service.vpnDown(other.name);
          await Future.delayed(const Duration(milliseconds: 500));
        }
        // Включение
        await widget.service.vpnUp(v.name);
        // Проверка IP (до 15 сек)
        if (v.type == 'WireGuard' || v.type == 'AmneziaWG' || v.type == 'OpenVPN') {
          final oldIp = await widget.service.fetchPublicIp();
          for (int i = 0; i < 15; i++) {
            await Future.delayed(const Duration(seconds: 1));
            try {
              final newIp = await widget.service.fetchPublicIp();
              if (newIp != oldIp && !newIp.contains('недоступно')) break;
            } catch (_) {}
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${v.name} ${s.text('Включён')}')));
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e'), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _toggling = null);
    }
  }

  Future<void> _enableDisable(VpnInterface v, bool enable) async {
    try {
      if (enable) {
        await widget.service.vpnEnable(v.name, v.type);
      } else {
        await widget.service.vpnDisable(v.name, v.type);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    }
  }

  Future<void> _remove(VpnInterface v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('Удалить VPN?')),
        content: Text('${v.name} (${v.type})'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.text('Удалить'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.removeVpn(v.name, v.type);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    }
  }

  void _showImportDialog() {
    final ctrl = TextEditingController();
    final nameCtrl = TextEditingController(text: 'wg_imported');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('Импорт WireGuard .conf')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: s.text('Название интерфейса'))),
            const SizedBox(height: 8),
            TextField(controller: ctrl, maxLines: 8, decoration: InputDecoration(labelText: s.text('Содержимое .conf'))),
            const SizedBox(height: 8),
            Text(s.text('Автоматически распознаются: Address, PrivateKey, PublicKey, Endpoint, DNS'), style: const TextStyle(fontSize: 11)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))),
          FilledButton(onPressed: () async {
            try {
              final lines = ctrl.text.split('\n');
              String? addr, priv, pub, ep, dns;
              for (final l in lines) {
                final trimmed = l.trim();
                if (trimmed.startsWith('Address')) addr = trimmed.split('=').last.trim();
                if (trimmed.startsWith('PrivateKey')) priv = trimmed.split('=').last.trim();
                if (trimmed.startsWith('PublicKey')) pub = trimmed.split('=').last.trim();
                if (trimmed.startsWith('Endpoint')) ep = trimmed.split('=').last.trim();
                if (trimmed.startsWith('DNS')) dns = trimmed.split('=').last.trim();
              }
              if (priv == null || addr == null || pub == null || ep == null) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('Недостаточно данных в .conf'))));
                return;
              }
              await widget.service.addWireGuard(
                name: nameCtrl.text.trim().replaceAll(' ', '_'),
                privateKey: priv,
                addresses: addr.replaceAll(',', ' '),
                publicKey: pub,
                endpoint: ep,
                allowedIps: '0.0.0.0/0, ::/0',
                dns: dns ?? '1.1.1.1',
              );
              if (!mounted) return;
              Navigator.pop(ctx);
              await _load();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
            }
          }, child: Text(s.text('Импортировать'))),
        ],
      ),
    );
  }

  void _showL2tpDialog() {
    final name = TextEditingController(), server = TextEditingController(), user = TextEditingController(), pass = TextEditingController(), secret = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('L2TP/IPsec'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: s.text('Название'))),
        TextField(controller: server, decoration: InputDecoration(labelText: s.text('Сервер'))),
        TextField(controller: user, decoration: InputDecoration(labelText: s.text('Логин'))),
        TextField(controller: pass, decoration: InputDecoration(labelText: s.text('Пароль')), obscureText: true),
        TextField(controller: secret, decoration: InputDecoration(labelText: s.text('IPsec Secret (опц.)'))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))), FilledButton(onPressed: () async {
        try {
          await widget.service.addL2tpClient(name: name.text, server: server.text, username: user.text, password: pass.text, secret: secret.text.isNotEmpty ? secret.text : null);
          if (!mounted) return; Navigator.pop(ctx); await _load(); _snack(s.text('L2TP добавлен'));
        } catch (e) {
          if (mounted) _snack('${s.text('Ошибка')}: $e');
        }
      }, child: Text(s.text('Добавить')))],
    ));
  }

  void _showPptpDialog() {
    final name = TextEditingController(), server = TextEditingController(), user = TextEditingController(), pass = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('PPTP'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: s.text('Название'))),
        TextField(controller: server, decoration: InputDecoration(labelText: s.text('Сервер'))),
        TextField(controller: user, decoration: InputDecoration(labelText: s.text('Логин'))),
        TextField(controller: pass, decoration: InputDecoration(labelText: s.text('Пароль')), obscureText: true),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))), FilledButton(onPressed: () async {
        try {
          await widget.service.addPptpClient(name: name.text, server: server.text, username: user.text, password: pass.text);
          if (!mounted) return; Navigator.pop(ctx); await _load(); _snack(s.text('PPTP добавлен'));
        } catch (e) {
          if (mounted) _snack('${s.text('Ошибка')}: $e');
        }
      }, child: Text(s.text('Добавить')))],
    ));
  }

  void _editVpn(VpnInterface v) async {
    if (v.type == 'WireGuard' || v.type == 'AmneziaWG') {
      // Получаем текущие настройки и даём изменить
      try {
        final priv = (await widget.service.runCommand('uci get network.${v.name}.private_key 2>/dev/null || echo ""')).trim();
        final addr = (await widget.service.runCommand('uci get network.${v.name}.addresses 2>/dev/null || echo ""')).trim();
        final dns = (await widget.service.runCommand('uci get network.${v.name}.peer_dns 2>/dev/null || echo ""')).trim();
        final pub = (await widget.service.runCommand('uci get network.${v.name}_peer.public_key 2>/dev/null || echo ""')).trim();
        final ep = (await widget.service.runCommand('uci get network.${v.name}_peer.endpoint_host 2>/dev/null || echo ""')).trim();
        final eport = (await widget.service.runCommand('uci get network.${v.name}_peer.endpoint_port 2>/dev/null || echo "51820"')).trim();

        final privCtrl = TextEditingController(text: priv);
        final pubCtrl = TextEditingController(text: pub);
        final addrCtrl = TextEditingController(text: addr);
        final epCtrl = TextEditingController(text: '$ep:$eport');
        final dnsCtrl = TextEditingController(text: dns);
        await showDialog(context: context, builder: (ctx) => AlertDialog(
          title: Text('${s.text('Изменить')} ${v.name}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: privCtrl, decoration: const InputDecoration(labelText: 'Private key')),
            TextField(controller: pubCtrl, decoration: InputDecoration(labelText: s.text('Public key сервера'))),
            TextField(controller: addrCtrl, decoration: InputDecoration(labelText: s.text('IP клиента'))),
            TextField(controller: epCtrl, decoration: InputDecoration(labelText: s.text('Сервер:порт'))),
            TextField(controller: dnsCtrl, decoration: const InputDecoration(labelText: 'DNS')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))),
            FilledButton(onPressed: () async {
              Navigator.pop(ctx);
              final esc = (String s) => s.replaceAll("'", "'\\''");
              final parts = epCtrl.text.split(':');
              await widget.service.runCommand("uci set network.${v.name}.private_key='${esc(privCtrl.text)}'; uci set network.${v.name}.addresses='${esc(addrCtrl.text)}'; uci set network.${v.name}_peer.public_key='${esc(pubCtrl.text)}'; uci set network.${v.name}_peer.endpoint_host='${esc(parts[0])}'; uci set network.${v.name}_peer.endpoint_port='${esc(parts.length > 1 ? parts[1] : '51820')}'; uci commit network; /etc/init.d/network reload");
              await _load();
            }, child: Text(s.text('Сохранить'))),
          ],
        ));
      } catch (e) { if (mounted) _snack('$e'); }
    } else {
      _snack(s.text('Редактирование доступно для WireGuard'));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  void _showSstpDialog() {
    final n = TextEditingController(), server = TextEditingController(), u = TextEditingController(), p = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('SSTP'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: n, decoration: InputDecoration(labelText: s.text('Название'))), TextField(controller: server, decoration: InputDecoration(labelText: s.text('Сервер'))), TextField(controller: u, decoration: InputDecoration(labelText: s.text('Логин'))), TextField(controller: p, decoration: InputDecoration(labelText: s.text('Пароль')), obscureText: true),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))), FilledButton(onPressed: () async {
      try {
        await widget.service.addSstpClient(name: n.text, server: server.text, username: u.text, password: p.text);
        if (!mounted) return; Navigator.pop(ctx); await _load(); _snack(s.text('SSTP добавлен'));
      } catch (e) {
        if (mounted) _snack('${s.text('Ошибка')}: $e');
      }
    }, child: Text(s.text('Добавить')))]));
  }

  void _showIpsecDialog() {
    final n = TextEditingController(), server = TextEditingController(), u = TextEditingController(), p = TextEditingController(), psk = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('IPsec / IKEv2'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: n, decoration: InputDecoration(labelText: s.text('Название'))), TextField(controller: server, decoration: InputDecoration(labelText: s.text('Сервер'))), TextField(controller: u, decoration: InputDecoration(labelText: s.text('Логин'))), TextField(controller: p, decoration: InputDecoration(labelText: s.text('Пароль')), obscureText: true), TextField(controller: psk, decoration: const InputDecoration(labelText: 'Pre-Shared Key')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))), FilledButton(onPressed: () async {
      try {
        await widget.service.addIpsecClient(name: n.text, server: server.text, username: u.text, password: p.text, psk: psk.text);
        if (!mounted) return; Navigator.pop(ctx); await _load(); _snack(s.text('IPsec добавлен'));
      } catch (e) {
        if (mounted) _snack('${s.text('Ошибка')}: $e');
      }
    }, child: Text(s.text('Добавить')))]));
  }

  void _showOvpnImport() {
    final n = TextEditingController(text: 'openvpn_client'), ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(s.text('Импорт OpenVPN')), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: n, decoration: InputDecoration(labelText: s.text('Название'))), TextField(controller: ctrl, maxLines: 6, decoration: InputDecoration(labelText: s.text('Содержимое .ovpn'))),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))), FilledButton(onPressed: () async {
      try {
        await widget.service.importOpenvpnConfig(name: n.text, ovpnContent: ctrl.text);
        if (!mounted) return; Navigator.pop(ctx); await _load(); _snack(s.text('OpenVPN импортирован'));
      } catch (e) {
        if (mounted) _snack('${s.text('Ошибка')}: $e');
      }
    }, child: Text(s.text('Импорт'))) ]));
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final privCtrl = TextEditingController();
    final pubCtrl = TextEditingController();
    final addrCtrl = TextEditingController(text: '10.8.1.2/24');
    final endpCtrl = TextEditingController();
    final allowedCtrl = TextEditingController(text: '0.0.0.0/0, ::/0');
    final dnsCtrl = TextEditingController(text: '1.1.1.1');
    bool amnezia = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(s.text('Добавить WireGuard / AmneziaWG')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: s.text('Название интерфейса'))),
                TextField(controller: privCtrl, decoration: const InputDecoration(labelText: 'Private key'), maxLines: 2),
                TextField(controller: pubCtrl, decoration: InputDecoration(labelText: s.text('Public key сервера')), maxLines: 2),
                TextField(controller: addrCtrl, decoration: InputDecoration(labelText: s.text('IP клиента'))),
                TextField(controller: endpCtrl, decoration: InputDecoration(labelText: s.text('Сервер:порт'))),
                TextField(controller: allowedCtrl, decoration: const InputDecoration(labelText: 'Allowed IPs')),
                TextField(controller: dnsCtrl, decoration: const InputDecoration(labelText: 'DNS')),
                SwitchListTile(
                  value: amnezia,
                  onChanged: (v) => setSt(() => amnezia = v),
                  title: const Text('AmneziaWG'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.service.addWireGuard(
                    name: nameCtrl.text.trim(),
                    privateKey: privCtrl.text.trim(),
                    addresses: addrCtrl.text.trim(),
                    publicKey: pubCtrl.text.trim(),
                    endpoint: endpCtrl.text.trim(),
                    allowedIps: allowedCtrl.text.trim(),
                    dns: dnsCtrl.text.trim(),
                    amnezia: amnezia,
                  );
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
                }
              },
              child: Text(s.text('Добавить')),
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
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              automaticallyImplyLeading: false,
              title: Text(s.vpn),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    if (v == 'add_wg') _showAddDialog();
                    if (v == 'add_l2tp') _showL2tpDialog();
                    if (v == 'add_pptp') _showPptpDialog();
                    if (v == 'add_sstp') _showSstpDialog();
                    if (v == 'add_ipsec') _showIpsecDialog();
                    if (v == 'add_ovpn') _showOvpnImport();
                    if (v == 'import') _showImportDialog();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'add_wg', child: ListTile(leading: Icon(Icons.security), title: Text('WireGuard / AmneziaWG'))),
                    const PopupMenuItem(value: 'add_ovpn', child: ListTile(leading: Icon(Icons.vpn_lock), title: Text('OpenVPN (.ovpn)'))),
                    const PopupMenuItem(value: 'add_ipsec', child: ListTile(leading: Icon(Icons.shield), title: Text('IPsec / IKEv2'))),
                    const PopupMenuItem(value: 'add_l2tp', child: ListTile(leading: Icon(Icons.lan), title: Text('L2TP/IPsec'))),
                    const PopupMenuItem(value: 'add_pptp', child: ListTile(leading: Icon(Icons.cable), title: Text('PPTP'))),
                    const PopupMenuItem(value: 'add_sstp', child: ListTile(leading: Icon(Icons.https), title: Text('SSTP'))),
                    PopupMenuItem(value: 'import', child: ListTile(leading: const Icon(Icons.file_open), title: Text(s.text('Импорт .conf (WG)')))),
                  ],
                ),
              ],
            ),
            if (loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              _buildError(theme)
            else if (vpns.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.vpn_key_outlined, size: 80, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(s.text('VPN-интерфейсы не найдены'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(s.text('Установите WireGuard / AmneziaWG или OpenVPN\nчерез кнопку "+"'), textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final v = vpns[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  v.type == 'OpenVPN' ? Icons.vpn_lock : Icons.security,
                                  color: v.up ? Colors.green : theme.colorScheme.outline,
                                ),
                                title: Text(v.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                subtitle: Text(v.type),
trailing: _toggling == v.name
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Switch(
                                        value: v.up,
                                        onChanged: (_) => _toggle(v),
                                      ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.tonal(
                                      onPressed: v.enabled ? () => _enableDisable(v, false) : () => _enableDisable(v, true),
                                      child: Text(v.enabled ? s.text('Отключить') : s.text('Включить')),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _editVpn(v),
                                    icon: const Icon(Icons.edit),
                                    tooltip: s.text('Редактировать'),
                                  ),
                                  IconButton(
                                    onPressed: () => _remove(v),
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: vpns.length,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
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
              Text(s.text('Ошибка'), style: theme.textTheme.titleMedium),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: _load, child: Text(s.text('Повторить'))),
            ],
          ),
        ),
      ),
    );
  }
}
