import 'package:flutter/material.dart';
import '../models/router_connection.dart';
import '../services/openwrt_service.dart';
import '../services/storage_service.dart';
import '../services/client_monitor.dart';
import 'about_screen.dart';
import 'dashboard_screen.dart';
import 'monitor_screen.dart';
import 'network_screen.dart';
import 'vpn_screen.dart';
import 'clients_screen.dart';
import 'packages_screen.dart';
import 'system_screen.dart';
import 'wifi_screen.dart';
import 'login_screen.dart';
import 'terminal_screen.dart';
import 'mac_changer_screen.dart';
import 'wps_audit_screen.dart';
import 'firewall_screen.dart';

class HomeScreen extends StatefulWidget {
  final RouterConnection config;

  const HomeScreen({super.key, required this.config});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final OpenWrtService service;
  late final PageController pageController;
  int index = 0;
  bool _checkedDeps = false;
  bool _hideNonFunctional = false;

  final destinations = const [
    NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Обзор'),
    NavigationDestination(icon: Icon(Icons.network_check_outlined), selectedIcon: Icon(Icons.network_check), label: 'Сеть'),
    NavigationDestination(icon: Icon(Icons.wifi_outlined), selectedIcon: Icon(Icons.wifi), label: 'Wi-Fi'),
    NavigationDestination(icon: Icon(Icons.vpn_key_outlined), selectedIcon: Icon(Icons.vpn_key), label: 'VPN'),
    NavigationDestination(icon: Icon(Icons.devices_outlined), selectedIcon: Icon(Icons.devices), label: 'Клиенты'),
    NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Пакеты'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Система'),
  ];

  @override
  void initState() {
    super.initState();
    service = OpenWrtService(widget.config);
    pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstStartCheck());
    StorageService.isHideNonFunctionalSections().then((v) {
      if (mounted) setState(() => _hideNonFunctional = v);
    });
    ClientMonitor.instance.onClientConnected = _onClientConnected;
    ClientMonitor.instance.start(service);
  }

  void _onClientConnected(Map<String, String> c) {
    if (!mounted) return;
    final name = c['hostname']!.isNotEmpty ? c['hostname']! : c['mac']!;
    final ip = c['ip']!.isNotEmpty ? ' • ${c['ip']}' : '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.add_circle, color: Colors.green),
        const SizedBox(width: 10),
        Expanded(child: Text('Новое устройство: $name$ip')),
      ]),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _firstStartCheck() async {
    if (_checkedDeps) return;
    _checkedDeps = true;

    final alreadyChecked = await StorageService.wasDepsChecked(widget.config.host);
    if (alreadyChecked) return;

    // Пользователь явно попросил больше не напоминать
    if (await StorageService.isDepsReminderHidden()) {
      await StorageService.markDepsChecked(widget.config.host);
      return;
    }

    try {
      await service.connect();
      final pkg = await service.detectPackageManager();
      final allDeps = await service.checkDependencies();
      OpenWrtService.lastDepsStatus = allDeps;
      await service.disconnect();
      if (!mounted) return;

      final isStock = (String k) => k == 'ubus' || k == 'uci' || k == 'jsonfilter' || k == 'dnsmasq';
      final missing = allDeps.entries.where((e) => !e.value && !isStock(e.key)).toList();
      if (missing.isEmpty) {
        await StorageService.markDepsChecked(widget.config.host);
        return;
      }

      _showDepsDialog(pkg, allDeps);
    } catch (_) {}
  }

  void _showDepsDialog(String pkgManager, Map<String, bool> allDeps) {
    final isStock = (String k) => k == 'ubus' || k == 'uci' || k == 'jsonfilter' || k == 'dnsmasq';
    final entries = allDeps.entries.where((e) => !isStock(e.key)).toList();
    final missingEntries = entries.where((e) => !e.value).toList();
    final status = <String, String>{};
    var installing = false;
    String? resultMsg;
    var dontShowAgain = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Row(children: [
              const Icon(Icons.checklist_rtl),
              const SizedBox(width: 8),
              Expanded(child: Text('Зависимости — $pkgManager', style: const TextStyle(fontSize: 17))),
              Text('${entries.where((e) => e.value).length}/${entries.length}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ...entries.map((e) {
                  final ok = status[e.key] == 'done' || (status[e.key] != 'error' && e.value);
                  final failed = status[e.key] == 'error';
                  final loading = status[e.key] == 'downloading';
                  final pn = OpenWrtService.packageForDependency[e.key];
                  final alts = OpenWrtService.packageAlternatives[e.key];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      if (loading)
                        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(ok && !failed ? Icons.check_circle : Icons.cancel, size: 22, color: ok && !failed ? Colors.green : Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.key, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            if (!e.value && pn != null)
                              Text(
                                alts != null ? '→ $pn (${alts.join(', ')})' : '→ $pn',
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ]),
                  );
                }),
                if (installing) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                if (resultMsg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(resultMsg!, style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600))),
                CheckboxListTile(
                  value: dontShowAgain,
                  onChanged: installing ? null : (v) => setSt(() => dontShowAgain = v!),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Больше не показывать это окно', style: TextStyle(fontSize: 13)),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: installing
                    ? null
                    : () async {
                        if (dontShowAgain) {
                          await StorageService.setDepsReminderHidden(true);
                          await StorageService.markDepsChecked(widget.config.host);
                        }
                        Navigator.pop(ctx);
                      },
                child: const Text('Закрыть'),
              ),
              if (missingEntries.isNotEmpty)
                FilledButton.icon(
                  onPressed: installing ? null : () async {
                    final isStock = (String k) => k == 'ubus' || k == 'uci' || k == 'jsonfilter' || k == 'dnsmasq' || k == 'wget/uclient';
                    final toInstall = missingEntries
                        .where((e) => !isStock(e.key))
                        .map((e) => OpenWrtService.packageForDependency[e.key])
                        .whereType<String>()
                        .toList();
                    if (toInstall.isEmpty) return;
                    setSt(() => installing = true);
                    try {
                      await service.connect();
                      for (final e in missingEntries) {
                        if (isStock(e.key)) continue;
                        final primary = OpenWrtService.packageForDependency[e.key];
                        if (primary == null) continue;
                        setSt(() { status[e.key] = 'downloading'; resultMsg = 'Загрузка $primary...'; });
                        try {
                          await service.installPackages([primary]);
                          setSt(() { status[e.key] = 'done'; resultMsg = 'Готово $primary'; });
                        } catch (_) {
                          try {
                            final alt = await service.findAlternativePackage(e.key);
                            if (alt != null && alt != primary) {
                              await service.installPackages([alt]);
                              setSt(() { status[e.key] = 'done'; resultMsg = 'Готово $alt (альтернатива)'; });
                            } else {
                              rethrow;
                            }
                          } catch (_) {
                            setSt(() { status[e.key] = 'error'; resultMsg = 'Ошибка $primary'; });
                          }
                        }
                        await Future.delayed(const Duration(milliseconds: 300));
                      }
                      await service.disconnect();
                      setSt(() { installing = false; resultMsg = 'Готово'; });
                      await StorageService.markDepsChecked(widget.config.host);
                      await Future.delayed(const Duration(seconds: 2));
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      _offerRebootAfterInstall();
                    } catch (e) {
                      setSt(() { installing = false; resultMsg = 'Ошибка: $e'; });
                    }
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Установить'),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    ClientMonitor.instance.stop();
    pageController.dispose();
    super.dispose();
  }

  void _showConnLogDialog(BuildContext outerCtx) {
    showDialog(
      context: outerCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final log = List<Map<String, String>>.from(ClientMonitor.instance.log);
          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.history),
              const SizedBox(width: 8),
              const Expanded(child: Text('Недавние подключения')),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Очистить',
                onPressed: () async {
                  await ClientMonitor.instance.clearLog();
                  if (ctx.mounted) setSt(() {});
                },
              ),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              child: log.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Пока нет событий', textAlign: TextAlign.center),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: log.map((e) {
                        final name = e['hostname']!.isNotEmpty ? e['hostname']! : e['mac']!;
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.devices, size: 20, color: Colors.green),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text([e['mac'], if (e['ip']!.isNotEmpty) e['ip'], e['time']].whereType<String>().where((x) => x.isNotEmpty).join(' • ')),
                        );
                      }).toList(),
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
            ],
          );
        },
      ),
    );
  }

  void _offerRebootAfterInstall() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Перезагрузить роутер?'),
        content: const Text('Некоторые пакеты требуют перезагрузки.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Позже')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await service.connect();
                await service.reboot();
                await service.disconnect();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Роутер перезагружается...')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
              }
            },
            child: const Text('Перезагрузить'),
          ),
        ],
      ),
    );
  }

  void _onPageChanged(int i) => setState(() => index = i);

  void _onTabSelected(int i) {
    pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _switchRouter() async {
    final routers = await StorageService.loadRouters();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Выбор роутера', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            ...routers.map((r) => ListTile(
                  leading: const Icon(Icons.router),
                  title: Text(r.name),
                  subtitle: Text('${r.username}@${r.host}:${r.port}'),
                  trailing: r.host == widget.config.host ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => HomeScreen(config: r)),
                    );
                  },
                )),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Выйти на экран входа'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.tertiary]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset('assets/icon/router_icon.png', width: 64, height: 64),
                    const SizedBox(height: 16),
                    Text(widget.config.name, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('${widget.config.username}@${widget.config.host}', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.multiline_chart),
                title: const Text('Мониторинг соединений'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MonitorScreen(service: service)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Сменить роутер'),
                onTap: () {
                  Navigator.pop(context);
                  _switchRouter();
                },
              ),
              ListTile(
                leading: const Icon(Icons.terminal),
                title: const Text('Терминал (Beta)'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TerminalScreen(service: service)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('MAC Changer'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MacChangerScreen(service: service)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.wifi_lock),
                title: const Text('WPS Audit'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => WpsAuditScreen(service: service)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.shield),
                title: const Text('Фаервол'),
                subtitle: const Text('Зоны, правила, проброс портов'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FirewallScreen(service: service)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_suggest),
                title: const Text('Настройки'),
                subtitle: const Text('Скрытие неработающих разделов'),
                onTap: () async {
                  final notifEnabled = await StorageService.isNotificationsEnabled();
                  if (!mounted) return;
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (ctx) => StatefulBuilder(
                      builder: (ctx, setSt) {
                        var nf = notifEnabled;
                        return AlertDialog(
                        title: const Text('Настройки'),
                        content: SingleChildScrollView(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SwitchListTile(
                              value: _hideNonFunctional,
                              onChanged: (v) async {
                                setSt(() => _hideNonFunctional = v);
                                setState(() => _hideNonFunctional = v);
                                await StorageService.setHideNonFunctionalSections(v);
                              },
                              title: const Text('Скрывать неработающие разделы'),
                              subtitle: const Text('Пункты, требующие неустановленные пакеты (nmap и др.)'),
                            ),
                            SwitchListTile(
                              value: nf,
                              onChanged: (v) async {
                                nf = v;
                                setSt(() {});
                                await StorageService.setNotificationsEnabled(v);
                                await ClientMonitor.instance.refreshNotificationsFlag();
                              },
                              title: const Text('Уведомления о подключениях'),
                              subtitle: const Text('Оповещать, когда к Wi-Fi подключается новое устройство (пока приложение открыто)'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.history),
                              title: const Text('Недавние подключения'),
                              subtitle: Text('${ClientMonitor.instance.log.length} событий'),
                              onTap: () {
                                setSt(() {});
                                _showConnLogDialog(ctx);
                              },
                            ),
ListTile(
                              leading: const Icon(Icons.notifications_off_outlined),
                              title: const Text('Вернуть напоминание о зависимостях'),
                              subtitle: const Text('Показывать окно зависимостей при входе'),
                              onTap: () async {
                                await StorageService.setDepsReminderHidden(false);
                                await StorageService.resetDepsChecked(widget.config.host);
                                setSt(() {});
                                if (ctx.mounted) Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Напоминание будет показано при следующем входе')));
                              },
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                );
              },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('О приложении'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
                },
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('OPENWRT - Global v3.7.0\nРыбинскLAB', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
      body: PageView(
        controller: pageController,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: [
          DashboardScreen(service: service),
          NetworkScreen(service: service),
          WifiScreen(service: service),
          VpnScreen(service: service),
          ClientsScreen(service: service),
          PackagesScreen(service: service),
          SystemScreen(service: service),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _onTabSelected,
        animationDuration: const Duration(milliseconds: 400),
        destinations: destinations,
      ),
    );
  }
}
