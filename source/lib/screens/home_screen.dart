import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/router_connection.dart';
import '../services/openwrt_service.dart';
import '../services/storage_service.dart';
import '../services/client_monitor.dart';
import '../services/biometric_auth_service.dart';
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
  bool _locked = false;
  DateTime _lastActivity = DateTime.now();
  Timer? _autoLockTimer;

  List<NavigationDestination> get destinations {
    final s = AppStrings.of(context);
    return [
      NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: s.overview),
      NavigationDestination(icon: const Icon(Icons.network_check_outlined), selectedIcon: const Icon(Icons.network_check), label: s.network),
      NavigationDestination(icon: const Icon(Icons.wifi_outlined), selectedIcon: const Icon(Icons.wifi), label: s.wifi),
      NavigationDestination(icon: const Icon(Icons.vpn_key_outlined), selectedIcon: const Icon(Icons.vpn_key), label: s.vpn),
      NavigationDestination(icon: const Icon(Icons.devices_outlined), selectedIcon: const Icon(Icons.devices), label: s.clients),
      NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2), label: s.packages),
      NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: s.system),
    ];
  }

  @override
  void initState() {
    super.initState();
    service = OpenWrtService(widget.config);
    service.onVerifyHostKey = _verifyHostKey;
    service.onFingerprintAccepted = (fp) => _saveFingerprint(fp);
    pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstStartCheck());
    StorageService.isHideNonFunctionalSections().then((v) {
      if (mounted) setState(() => _hideNonFunctional = v);
    });
    ClientMonitor.instance.onClientConnected = _onClientConnected;
    ClientMonitor.instance.start(service);
    _startAutoLock();
  }

  void _startAutoLock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (_locked) return;
      if (DateTime.now().difference(_lastActivity).inMinutes >= 5) {
        setState(() => _locked = true);
      }
    });
  }

  Future<bool> _verifyHostKey(String fingerprint) async {
    final host = widget.config.host;
    // Если fingerprint уже сохранён в конфиге, сверяем.
    if (widget.config.fingerprint != null && widget.config.fingerprint!.isNotEmpty) {
      return widget.config.fingerprint == fingerprint;
    }
    // Ищем в отдельном хранилище.
    final stored = await StorageService.loadFingerprint(host);
    if (stored != null && stored.isNotEmpty) return stored == fingerprint;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
         title: Row(children: [
          Icon(Icons.verified_user_outlined),
          SizedBox(width: 10),
           Text(AppStrings.of(context).text('Проверка SSH ключа')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(AppStrings.of(context).text('Отпечаток (SHA256):')),
            const SizedBox(height: 10),
            SelectableText(
              fingerprint,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
             Text(AppStrings.of(context).text('Принять ключ и сохранить для этого роутера?')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
             child: Text(AppStrings.of(context).text('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
             child: Text(AppStrings.of(context).text('Принять')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _saveFingerprint(String fingerprint) async {
    final host = widget.config.host;
    // Всегда сохраняем в отдельное хранилище.
    await StorageService.saveFingerprint(host, fingerprint);
    // Обновляем в сохранённых конфигурациях роутеров.
    final routers = await StorageService.loadRouters();
    var changed = false;
    final updated = routers.map((r) {
      if (r.host != host) return r;
      changed = true;
      return RouterConnection(
        name: r.name,
        host: r.host,
        port: r.port,
        username: r.username,
        password: r.password,
        sshKey: r.sshKey,
        useKey: r.useKey,
        useHttps: r.useHttps,
        fingerprint: fingerprint,
      );
    }).toList();
    if (changed) {
      await StorageService.saveRouters(updated);
    }
  }

  void _resetActivity() {
    _lastActivity = DateTime.now();
  }

  Future<void> _biometricUnlock() async {
    final ok = await BiometricAuthService.authenticate();
    if (ok && mounted) {
      setState(() {
        _locked = false;
        _lastActivity = DateTime.now();
      });
    }
  }

  void _onClientConnected(Map<String, String> c) {
    if (!mounted) return;
    final name = c['hostname']!.isNotEmpty ? c['hostname']! : c['mac']!;
    final ip = c['ip']!.isNotEmpty ? ' • ${c['ip']}' : '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.add_circle, color: Colors.green),
        const SizedBox(width: 10),
        Expanded(child: Text('${AppStrings.of(context).text('Новое устройство')}: $name$ip')),
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
      await service.detectCapabilities();
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
    final s = AppStrings.of(context);
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
              Expanded(child: Text('${s.text('Зависимости —')} $pkgManager', style: const TextStyle(fontSize: 17))),
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
                  title: Text(s.text('Больше не показывать это окно'), style: const TextStyle(fontSize: 13)),
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
                child: Text(s.close),
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
                         setSt(() { status[e.key] = 'downloading'; resultMsg = '${s.text('Загрузка')} $primary...'; });
                        try {
                          await service.installPackages([primary]);
                           setSt(() { status[e.key] = 'done'; resultMsg = '${s.text('Готово')} $primary'; });
                        } catch (_) {
                          try {
                            final alt = await service.findAlternativePackage(e.key);
                            if (alt != null && alt != primary) {
                              await service.installPackages([alt]);
                               setSt(() { status[e.key] = 'done'; resultMsg = '${s.text('Готово')} $alt (${s.text('альтернатива')})'; });
                            } else {
                              rethrow;
                            }
                          } catch (_) {
                             setSt(() { status[e.key] = 'error'; resultMsg = '${s.text('Ошибка')} $primary'; });
                          }
                        }
                        await Future.delayed(const Duration(milliseconds: 300));
                      }
                      await service.disconnect();
                       setSt(() { installing = false; resultMsg = s.text('Готово'); });
                      await StorageService.markDepsChecked(widget.config.host);
                      await Future.delayed(const Duration(seconds: 2));
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      _offerRebootAfterInstall();
                    } catch (e) {
                       setSt(() { installing = false; resultMsg = '${s.text('Ошибка')}: $e'; });
                    }
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(s.text('Установить')),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    ClientMonitor.instance.stop();
    pageController.dispose();
    super.dispose();
  }

  void _showConnLogDialog(BuildContext outerCtx) {
    final s = AppStrings.of(outerCtx);
    showDialog(
      context: outerCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final log = List<Map<String, String>>.from(ClientMonitor.instance.log);
          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.history),
              const SizedBox(width: 8),
              Expanded(child: Text(s.text('Недавние подключения'))),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                 tooltip: AppStrings.of(context).text('Очистить'),
                onPressed: () async {
                  await ClientMonitor.instance.clearLog();
                  if (ctx.mounted) setSt(() {});
                },
              ),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              child: log.isEmpty
                   ? Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(s.text('Пока нет событий'), textAlign: TextAlign.center),
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.close)),
            ],
          );
        },
      ),
    );
  }

  void _offerRebootAfterInstall() {
    final s = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('Перезагрузить роутер?')),
        content: Text(s.text('Некоторые пакеты требуют перезагрузки.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Позже'))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await service.connect();
                await service.reboot();
                await service.disconnect();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('Роутер перезагружается...'))));
              } catch (e) {
                 if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
              }
            },
            child: Text(s.text('Перезагрузить')),
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
              child: Text(AppStrings.of(ctx).text('Выбор роутера'), style: Theme.of(ctx).textTheme.titleLarge),
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
               title: Text(AppStrings.of(ctx).text('Выйти на экран входа')),
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
    final body = Scaffold(
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
                 title: Text(AppStrings.of(context).text('Мониторинг соединений')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MonitorScreen(service: service)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                 title: Text(AppStrings.of(context).text('Сменить роутер')),
                onTap: () {
                  Navigator.pop(context);
                  _switchRouter();
                },
              ),
              ListTile(
                leading: const Icon(Icons.terminal),
                 title: Text(AppStrings.of(context).text('Терминал (Beta)')),
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
                 title: Text(AppStrings.of(context).text('Фаервол')),
                 subtitle: Text(AppStrings.of(context).text('Зоны, правила, проброс портов')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FirewallScreen(service: service)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_suggest),
                 title: Text(AppStrings.of(context).text('Настройки')),
                 subtitle: Text(AppStrings.of(context).text('Скрытие неработающих разделов')),
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
                         title: Text(AppStrings.of(ctx).text('Настройки')),
                        content: SingleChildScrollView(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SwitchListTile(
                              value: _hideNonFunctional,
                              onChanged: (v) async {
                                setSt(() => _hideNonFunctional = v);
                                setState(() => _hideNonFunctional = v);
                                await StorageService.setHideNonFunctionalSections(v);
                              },
                               title: Text(AppStrings.of(ctx).text('Скрывать неработающие разделы')),
                               subtitle: Text(AppStrings.of(ctx).text('Пункты, требующие неустановленные пакеты (nmap и др.)')),
                            ),
                            SwitchListTile(
                              value: nf,
                              onChanged: (v) async {
                                nf = v;
                                setSt(() {});
                                await StorageService.setNotificationsEnabled(v);
                                await ClientMonitor.instance.refreshNotificationsFlag();
                              },
                               title: Text(AppStrings.of(ctx).text('Уведомления о подключениях')),
                               subtitle: Text(AppStrings.of(ctx).text('Оповещать, когда к Wi-Fi подключается новое устройство (пока приложение открыто)')),
                            ),
                            ListTile(
                              leading: const Icon(Icons.history),
                               title: Text(AppStrings.of(ctx).text('Недавние подключения')),
                               subtitle: Text('${ClientMonitor.instance.log.length} ${AppStrings.of(ctx).text('событий')}'),
                              onTap: () {
                                setSt(() {});
                                _showConnLogDialog(ctx);
                              },
                            ),
ListTile(
                              leading: const Icon(Icons.notifications_off_outlined),
                               title: Text(AppStrings.of(ctx).text('Вернуть напоминание о зависимостях')),
                               subtitle: Text(AppStrings.of(ctx).text('Показывать окно зависимостей при входе')),
                              onTap: () async {
                                await StorageService.setDepsReminderHidden(false);
                                await StorageService.resetDepsChecked(widget.config.host);
                                setSt(() {});
                                if (ctx.mounted) Navigator.pop(ctx);
                                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context).text('Напоминание будет показано при следующем входе'))));
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
                 title: Text(AppStrings.of(context).about),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
                },
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.all(16),
                  child: Text('OPENWRT - Global v4.0.3\nРыбинскLAB', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
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
    return Stack(
      children: [
        Listener(
          onPointerDown: (_) => _resetActivity(),
          onPointerMove: (_) => _resetActivity(),
          child: body,
        ),
        if (_locked)
          Positioned.fill(
            child: GestureDetector(
              onTap: _biometricUnlock,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 24),
                       Text(AppStrings.of(context).text('Приложение заблокировано'), style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _biometricUnlock,
                        icon: const Icon(Icons.fingerprint),
                         label: Text(AppStrings.of(context).text('Разблокировать')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
