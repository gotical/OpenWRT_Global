import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/wifi_info.dart';
import '../services/openwrt_service.dart';
import '../services/local_wifi_scanner.dart';
import '../models/channel_scan_result.dart';
import 'channel_analyzer_screen.dart';
import '../widgets/safe_command_dialog.dart';

class WifiScreen extends StatefulWidget {
  final OpenWrtService service;

  const WifiScreen({super.key, required this.service});

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  AppStrings get s => AppStrings.of(context);
  List<WifiDevice> devices = [];
  List<WifiNetwork> networks = [];
  Map<String, List<int>> availableChannels = {};
  Map<String, Map<int, int>> channelInterference = {};
  bool loading = true;
  String? error;
  Map<String, bool> processing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      final devs = await widget.service.fetchWirelessDevices();
      final nets = await widget.service.fetchWifiNetworks();
      setState(() {
        devices = devs;
        networks = nets;
        loading = false;
        error = null;
      });
      // Параллельно грузим каналы
      for (final d in devs) {
        _loadChannels(d.name);
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _loadChannels(String device) async {
    try {
      final channels = await widget.service.getAvailableChannels(device);
      final interference = await widget.service.scanWifiChannels(device);
      setState(() {
        availableChannels[device] = channels;
        channelInterference[device] = interference;
      });
    } catch (_) {}
  }

  Future<void> _showHeatmap(WifiDevice dev) async {
    setState(() => processing['heatmap_${dev.name}'] = true);
    try {
      final ch = await widget.service.getAvailableChannels(dev.name);
      final interfer = await widget.service.scanWifiChannels(dev.name);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${s.text('Помехи')} — ${dev.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _legendDot(Colors.green, s.text('Свободно')), const SizedBox(width: 8),
                  _legendDot(Colors.orange, s.text('Средне')), const SizedBox(width: 8),
                  _legendDot(Colors.red, s.text('Занято')),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: ch.length,
                    itemBuilder: (_, i) {
                      final channel = ch[i];
                      final count = interfer[channel] ?? 0;
                      final color = count == 0 ? Colors.green : (count <= 2 ? Colors.orange : Colors.red);
                      final maxBars = 10;
                      final filled = (count.clamp(0, maxBars).toDouble() / maxBars).clamp(0.05, 1.0);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                           SizedBox(width: 60, child: Text('${s.text('К')} $channel', style: const TextStyle(fontWeight: FontWeight.w600))),
                          Expanded(
                            child: Container(
                              height: 18,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: LinearGradient(
                                  colors: [color.withValues(alpha: 0.4), color],
                                  stops: const [0, 1],
                                ),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 4),
                              child: FractionallySizedBox(
                                widthFactor: filled,
                                child: Container(
                                  height: 18,
                                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                           Text('$count ${s.text('сетей')}', style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color)),
                        ]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => processing.remove('heatmap_${dev.name}'));
    }
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ]);
  }

  Future<void> _reloadWifi() async {
    setState(() => processing['reload'] = true);
    try {
      await widget.service.wifiReload();
      if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('Wi-Fi перезагружен'))));
      await _load();
    } catch (e) {
      if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    } finally {
      if (mounted) setState(() => processing.remove('reload'));
    }
  }

  Future<void> _startWps(WifiDevice dev) async {
    setState(() => processing['wps_${dev.name}'] = true);
    String iface = dev.name;
    try {
      iface = await widget.service.getWifiIface(dev.name);
      final ok = await widget.service.startWpsPbc(iface);
      if (!mounted) return;
      setState(() => processing.remove('wps_${dev.name}'));
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(s.text('Не удалось запустить WPS (нужен wpad с поддержкой WPS)'))));
        return;
      }
      await _showWpsCountdown(dev.name, iface);
    } catch (e) {
      if (!mounted) return;
      setState(() => processing.remove('wps_${dev.name}'));
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    }
  }

  Future<void> _showWpsCountdown(String devName, String iface) async {
    const total = 120;
    final started = DateTime.now();
    Set<String> baseline = {};
    try {
      baseline = (await widget.service.wpsClients(iface)).map((c) => c['mac']!).toSet();
    } catch (_) {}
    Timer? timer;
    Timer? poller;
    var finished = false;
    var joinedCount = 0;
    Map<String, String>? joined;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (!ctx.mounted) return;
            final remain = total - DateTime.now().difference(started).inSeconds;
            if (remain <= 0 && !finished) {
              timer?.cancel();
              poller?.cancel();
              widget.service.wpsCancel(iface);
              Navigator.pop(ctx);
            } else {
              setSt(() {});
            }
          });
          poller ??= Timer.periodic(const Duration(seconds: 3), (_) async {
            if (finished || !ctx.mounted) return;
            try {
              final clients = await widget.service.wpsClients(iface);
              if (!ctx.mounted || finished) return;
              final current = clients.map((c) => c['mac']!).toSet();
              joinedCount = (current.length - baseline.length).clamp(0, 999);
              final newOnes = clients.where((c) => !baseline.contains(c['mac'])).toList();
              if (newOnes.isNotEmpty) {
                joined = newOnes.first;
                finished = true;
                setSt(() {});
                timer?.cancel();
                poller?.cancel();
                await Future.delayed(const Duration(seconds: 3));
                if (ctx.mounted) Navigator.pop(ctx);
                widget.service.wpsCancel(iface);
                return;
              }
              setSt(() {});
            } catch (_) {}
          });
          final remain = (total - DateTime.now().difference(started).inSeconds).clamp(0, total);
          final theme = Theme.of(ctx);
          return AlertDialog(
             title: Text(finished ? s.text('Устройство подключено') : s.text('WPS подключение')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(finished ? Icons.check_circle : Icons.wifi_tethering, size: 52, color: finished ? Colors.green : Colors.orange),
                const SizedBox(height: 12),
                 Text(finished ? s.text('Клиент полностью подключился к сети') : s.text('Нажмите кнопку WPS на подключаемом устройстве')),
                const SizedBox(height: 16),
                if (finished && joined != null) ...[
                  Card(
                    color: Colors.green.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(children: [
                        const Icon(Icons.devices, color: Colors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(joined!['hostname']!.isNotEmpty ? joined!['hostname']! : joined!['mac']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                [joined!['mac'], if (joined!['ip']!.isNotEmpty) joined!['ip']].whereType<String>().where((e) => e.isNotEmpty).join(' • '),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: CircularProgressIndicator(
                            value: remain / total,
                            strokeWidth: 6,
                            backgroundColor: Colors.green.withValues(alpha: 0.15),
                          ),
                        ),
                        Text('$remain', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                   Text(s.text('секунд до конца окна'), style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                Text(
                   finished ? s.text('Окно WPS будет закрыто') : '$devName ($iface) • ${s.text('устройств')}: $joinedCount',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  timer?.cancel();
                  poller?.cancel();
                  widget.service.wpsCancel(iface);
                  Navigator.pop(ctx);
                },
                child: Text(finished ? s.text('Готово') : s.text('Отменить')),
              ),
            ],
          );
        },
      ),
    );
    timer?.cancel();
    poller?.cancel();
  }

  Future<void> _toggleNetwork(WifiNetwork net) async {
    setState(() => processing[net.section] = true);
    try {
      await widget.service.toggleWifiNetwork(net.section, net.disabled);
      await _load();
    } catch (e) {
      if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    } finally {
      if (mounted) setState(() => processing.remove(net.section));
    }
  }

  Future<void> _showNetworkEdit(WifiNetwork net) async {
    final ssidCtrl = TextEditingController(text: net.ssid);
    final keyCtrl = TextEditingController();
    String encryption = net.encryption ?? 'none';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(s.text('Настройки сети')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: ssidCtrl, decoration: InputDecoration(labelText: s.text('Название сети (SSID)'))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: encryption,
                  decoration: InputDecoration(labelText: s.text('Защита')),
                   items: [
                     DropdownMenuItem(value: 'none', child: Text(s.text('Открытая'))),
                    DropdownMenuItem(value: 'psk2', child: Text('WPA2-PSK')),
                    DropdownMenuItem(value: 'psk2+ccmp', child: Text('WPA2-PSK/CCMP')),
                    DropdownMenuItem(value: 'sae', child: Text('WPA3-SAE')),
                    DropdownMenuItem(value: 'sae-mixed', child: Text('WPA2/WPA3')),
                    DropdownMenuItem(value: 'wpa3', child: Text('WPA3-Enterprise')),
                  ],
                  onChanged: (v) => setSt(() => encryption = v ?? 'none'),
                ),
                if (encryption != 'none') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyCtrl,
                     decoration: InputDecoration(labelText: s.text('Пароль (оставьте пустым, чтобы не менять)')),
                    obscureText: true,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Отмена'))),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.service.setWifiNetwork(
                    section: net.section,
                    ssid: ssidCtrl.text.trim(),
                    encryption: encryption,
                    key: keyCtrl.text.isNotEmpty ? keyCtrl.text : null,
                  );
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  if (!mounted) return;
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
                }
              },
              child: Text(s.text('Сохранить')),
            ),
          ],
        ),
      ),
    );
  }

  String _cleanHt(String? ht) {
    if (ht == null || ht.isEmpty) return '';
    // Убираем мусор типа ${htMode} который мог записаться из-за старого бага
    final cleaned = ht.replaceAll(RegExp(r'\$\{.*?\}'), '').trim();
    return cleaned.isEmpty ? '' : cleaned;
  }

  Future<void> _setHtMode(WifiDevice dev) async {
    try {
      final modes = await widget.service.getAvailableHtModes(dev.name);
      if (!mounted) return;
      final current = _cleanHt(dev.htMode);
      // Рекомендованные: для 5GHz — HE80/HE160, для 2.4GHz — HT40
      final is5G = (dev.band ?? '').contains('5');
      final recommended = is5G ? ['HE80', 'HE160', 'VHT80', 'VHT160'] : ['HT40', 'HE40'];
      String? sel;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
           title: Text('${s.text('Ширина канала')} ${dev.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: modes.length,
              itemBuilder: (_, i) {
                final m = modes[i];
                final isCurrent = m == current;
                final isRec = recommended.contains(m);
                return ListTile(
                  leading: Icon(isCurrent ? Icons.radio_button_checked : Icons.radio_button_off, color: isRec ? Colors.green : Theme.of(ctx).colorScheme.outline),
                  title: Text(m, style: TextStyle(fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400)),
                   subtitle: isRec ? Text(s.text('Рекомендуется'), style: const TextStyle(color: Colors.green, fontSize: 11)) : null,
                   trailing: isCurrent ? Chip(label: Text(s.text('Установлена'), style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, backgroundColor: Colors.green.withValues(alpha: 0.1)) : null,
                  onTap: () { sel = m; Navigator.pop(ctx); },
                );
              },
            ),
          ),
        ),
      );
      if (sel == null) return;
      setState(() => processing['ht_${dev.name}'] = true);
      await widget.service.setWifiHtMode(dev.name, sel!);
      await _load();
    } catch (e) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    } finally {
      if (mounted) setState(() => processing.remove('ht_${dev.name}'));
    }
  }

  Future<void> _setChannel(WifiDevice dev) async {
    final channels = availableChannels[dev.name] ?? [];
    final interference = channelInterference[dev.name] ?? {};
    int? selected;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text('${s.text('Канал')} ${dev.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: channels.length,
            itemBuilder: (_, i) {
              final ch = channels[i];
              final count = interference[ch] ?? 0;
              final color = count == 0 ? Colors.green : (count < 3 ? Colors.orange : Colors.red);
              return ListTile(
                leading: Icon(Icons.circle, color: color, size: 14),
                 title: Text('${s.text('Канал')} $ch'),
                 subtitle: Text(count == 0 ? s.text('Нет помех') : '$count ${s.text('сетей')}'),
                trailing: selected == ch ? const Icon(Icons.check) : null,
                onTap: () {
                  selected = ch;
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );

    if (selected == null) return;
    setState(() => processing['ch_${dev.name}'] = true);
    try {
      await widget.service.setWifiChannel(dev.name, selected.toString());
      await _load();
    } catch (e) {
      if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    } finally {
      if (mounted) setState(() => processing.remove('ch_${dev.name}'));
    }
  }

  Future<void> _autoChannel(WifiDevice dev) async {
    setState(() => processing['auto_${dev.name}'] = true);
    try {
      final best = await widget.service.recommendChannel(dev.name);
      if (!mounted) return;
      if (best == null) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('Не удалось просканировать сети'))));
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
           title: Text(s.text('Рекомендуемый канал')),
           content: Text('${s.text('Установить канал')} $best ${s.text('для')} ${dev.name}?'),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('Отмена'))),
             FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.text('Установить'))),
          ],
        ),
      );
      if (ok == true) {
        await widget.service.setWifiChannel(dev.name, best.toString());
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    } finally {
      if (mounted) setState(() => processing.remove('auto_${dev.name}'));
    }
  }

  Future<void> _showWifiScanner(WifiDevice dev) async {
    setState(() => processing['scan_${dev.name}'] = true);
    try {
      final nets = await widget.service.scanNearbyWifi(dev.name);
      if (!mounted) return;
      setState(() => processing.remove('scan_${dev.name}'));
      if (nets.isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('Сети не найдены'))));
        return;
      }
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
           title: Text('${s.text('Сети')} — ${dev.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: nets.length,
              itemBuilder: (_, i) {
                final n = nets[i];
                final sig = int.tryParse(n['signal'] ?? '-200') ?? -200;
                final color = sig > -50 ? Colors.green : (sig > -70 ? Colors.orange : Colors.red);
                return ListTile(
                  leading: Icon(Icons.wifi, color: color),
                  title: Text(n['ssid'] ?? '?'),
                 subtitle: Text('${s.text('Сигнал')}: ${n['signal']} dBm • ${s.text('Канал')} ${n['channel']}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _connectToWifi(dev, n['ssid']!);
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
       if (mounted) { setState(() => processing.remove('scan_${dev.name}')); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e'))); }
    }
  }

  Future<void> _connectToWifi(WifiDevice dev, String ssid) async {
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text('${s.text('Подключиться к')} $ssid'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
           Text(s.text('Подключиться как клиент (WAN)? Текущая точка доступа будет сохранена.')),
          const SizedBox(height: 8),
           TextField(controller: passCtrl, decoration: InputDecoration(labelText: s.text('Пароль (если есть)'))),
        ]),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('Отмена'))),
           FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.text('Подключить'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.wifiClientConnect(dev.name, ssid, passCtrl.text.isEmpty ? null : passCtrl.text);
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('Wi-Fi перезагружен, подключение к сети...'))));
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    }
  }

  Future<void> _aiOptimize(WifiDevice dev) async {
    setState(() => processing['ai_${dev.name}'] = true);
    try {
      // Собираем данные с телефона для анализа
      List<ChannelScanResult>? phoneScans;
      try {
        final scanResult = await LocalWifiScanner.scan();
        if (scanResult.success && scanResult.results.isNotEmpty) {
          phoneScans = scanResult.results
              .where((s) => LocalWifiScanner.bandForChannel(s.channel) == (dev.band ?? '2.4g'))
              .toList();
        }
      } catch (_) {}

      final result = await widget.service.aiOptimizeWifi(dev.name, phoneScans: phoneScans);
      if (!mounted) return;
      setState(() => processing.remove('ai_${dev.name}'));

      final ch = result['recommended_channel'];
      final ht = result['recommended_htmode'];
      final level = result['interference_level'] as int;
       final levelText = level == 0 ? s.text('Отлично — канал свободен') : '$level ${s.text('сетей')}';

      final apply = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
           title: Text('${dev.name} — ${s.text('Автооптимизация')}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
             Row(children: [Text(s.text('Канал:')), const SizedBox(width: 8), Text('$ch', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18))]),
            const SizedBox(height: 4),
             Row(children: [Text(s.text('Ширина:')), const SizedBox(width: 8), Text('$ht', style: const TextStyle(fontWeight: FontWeight.w600))]),
            const SizedBox(height: 4),
             Text('${s.text('Помех:')} $levelText', style: TextStyle(color: level == 0 ? Colors.green : Colors.orange)),
            const SizedBox(height: 12),
             if (result['channels'] is Map) Text('${s.text('Каналы:')} ${(result['channels'] as Map).entries.map((e) => '${e.key}(${e.value})').join(', ')}', style: const TextStyle(fontSize: 11)),
          ]),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('Отмена'))),
             FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.text('Применить'))),
          ],
        ),
      );
      if (apply == true && ch != null) {
        await widget.service.setWifiChannel(dev.name, ch.toString());
        if (ht != null) await widget.service.setWifiHtMode(dev.name, ht);
        await _load();
      }
    } catch (e) {
       if (mounted) { setState(() => processing.remove('ai_${dev.name}')); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e'))); }
    }
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
              title: Text(s.wifi),
              actions: [
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
                  child: FilledButton.tonalIcon(
                    onPressed: processing.containsKey('reload') ? null : _reloadWifi,
                    icon: processing.containsKey('reload') ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                    label: Text(s.text('Перезагрузить Wi-Fi')),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(s.text('Радиомодули'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              if (devices.isEmpty)
                 SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                   sliver: SliverToBoxAdapter(child: Text(s.text('Радиомодули не найдены'))),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final d = devices[i];
                        final interference = channelInterference[d.name] ?? {};
                        final hasData = interference.isNotEmpty;
                        final maxCount = hasData ? interference.values.reduce((a, b) => a > b ? a : b) : 0;
                        final summary = hasData
                             ? '${s.text('Найдено')} ${interference.length} ${s.text('каналов, макс.')} $maxCount ${s.text('сетей')}'
                             : s.text('Загрузка каналов...');
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.wifi_tethering, color: d.up ? Colors.green : theme.colorScheme.error),
                                  title: Text(d.name),
                                  subtitle: Text('${s.text('Канал')} ${d.channel ?? '-'} • ${d.band ?? ''} • ${_cleanHt(d.htMode)}'),
                                  trailing: Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(d.up ? s.text('Вкл') : s.text('Выкл')),
                                    backgroundColor: d.up ? Colors.green.withValues(alpha: 0.15) : theme.colorScheme.surfaceContainerHighest,
                                  ),
                                ),
                                Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: processing.containsKey('scan_${d.name}') ? null : () => _showWifiScanner(d),
                                        icon: const Icon(Icons.wifi_find),
                                        label: Text(s.text('Сканер')),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: processing.containsKey('ai_${d.name}') ? null : () => _aiOptimize(d),
                                        icon: const Icon(Icons.auto_awesome),
                                        label: const Text('AI'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: processing.containsKey('ht_${d.name}') ? null : () => _setHtMode(d),
                                        icon: const Icon(Icons.height),
                                        label: Text(s.text('Ширина')),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: processing.containsKey('heatmap_${d.name}') ? null : () => _showHeatmap(d),
                                        icon: const Icon(Icons.map),
                                        label: Text(s.text('Карта')),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: processing.containsKey('ch_${d.name}') ? null : () => _setChannel(d),
                                        icon: const Icon(Icons.tune),
                                        label: Text(s.text('Канал')),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: processing.containsKey('auto_${d.name}') ? null : () => _autoChannel(d),
                                        icon: const Icon(Icons.auto_fix_high),
                                        label: Text(s.text('Авто')),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: processing.containsKey('wps_${d.name}') ? null : () => _startWps(d),
                                        icon: processing.containsKey('wps_${d.name}')
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.wifi_tethering, size: 18),
                                        label: const Text('WPS', style: TextStyle(fontSize: 13)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ChannelAnalyzerScreen(
                                              service: widget.service,
                                              deviceName: d.name,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(Icons.analytics, size: 18),
                                        label: Text(s.text('Анализатор'), style: const TextStyle(fontSize: 13)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: devices.length,
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(s.text('Сети'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              if (networks.isEmpty)
                 SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                   sliver: SliverToBoxAdapter(child: Text(s.text('Сети не найдены'))),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final n = networks[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.wifi),
                            title: Text(n.ssid),
                            subtitle: Text('${n.device} • ${n.encryption ?? s.text('открытая')}'),
                            trailing: processing.containsKey(n.section)
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : Switch(
                                    value: !n.disabled,
                                    onChanged: (_) => _toggleNetwork(n),
                                  ),
                            onTap: () => _showNetworkEdit(n),
                          ),
                        );
                      },
                      childCount: networks.length,
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
