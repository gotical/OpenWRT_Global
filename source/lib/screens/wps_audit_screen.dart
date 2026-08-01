import 'package:flutter/material.dart';
import '../services/openwrt_service.dart';
import '../services/local_wifi_scanner.dart';

class WpsAuditScreen extends StatefulWidget {
  final OpenWrtService service;

  const WpsAuditScreen({super.key, required this.service});

  @override
  State<WpsAuditScreen> createState() => _WpsAuditScreenState();
}

class _WifiScanEntry {
  final String ssid;
  final String bssid;
  final int signal;
  final int channel;
  final int width;
  final String capabilities;

  _WifiScanEntry({
    required this.ssid,
    required this.bssid,
    required this.signal,
    required this.channel,
    this.width = 20,
    this.capabilities = '',
  });

  bool get hasWps => capabilities.toUpperCase().contains('[WPS]');
  String get encryptionType {
    final c = capabilities.toUpperCase();
    if (c.contains('WPA3') || c.contains('SAE')) return 'WPA3';
    if (c.contains('WPA2')) return 'WPA2';
    if (c.contains('WPA')) return 'WPA';
    if (c.contains('WEP')) return 'WEP';
    return 'Открытая';
  }
}

class _WpsAuditScreenState extends State<WpsAuditScreen> {
  List<_WifiScanEntry> _networks = [];
  bool _loading = false;
  String? _device;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _getDevice();
  }

  Future<void> _getDevice() async {
    try {
      final devs = await widget.service.fetchWirelessDevices();
      if (devs.isNotEmpty && mounted) {
        setState(() => _device = devs.first.name);
      }
    } catch (_) {}
  }

  // Получаем реальный сетевой интерфейс для radio (radio0 -> wlan0)
  Future<String?> _getIface(String radio) async {
    try {
      final raw = await widget.service.runCommand(
          'uci show wireless 2>/dev/null | grep device=\'$radio\' | head -1 | cut -d. -f2 || echo ""');
      final section = raw.trim();
      if (section.isNotEmpty) {
        final iface = (await widget.service
                .runCommand('uci get wireless.$section.ifname 2>/dev/null || echo ""'))
            .trim();
        if (iface.isNotEmpty) return iface;
      }
    } catch (_) {}
    // fallback: iw dev
    try {
      final raw = await widget.service.runCommand('iw dev 2>/dev/null | grep Interface | awk \'{print \$2}\'');
      for (final line in raw.split('\n')) {
        final name = line.trim();
        if (name.isNotEmpty) {
          final phy = (await widget.service.runCommand('iw dev $name info 2>/dev/null | grep wiphy || echo ""')).trim();
          final phyNum = radio.replaceAll(RegExp(r'[^0-9]'), '');
          if (phy.contains('wiphy $phyNum')) return name;
        }
      }
    } catch (_) {}
    return radio;
  }

  Future<void> _scanRouter() async {
    if (_device == null) return;
    setState(() { _loading = true; _status = 'Сканирование эфира с роутера...'; });

    String iface = _device!;
    try {
      iface = (await _getIface(_device!)) ?? _device!;
      if (mounted) setState(() => _status = 'Сканирование через $iface...');

      final raw = await widget.service.runCommand('iw dev $iface scan 2>/dev/null || echo ""');
      final networks = <_WifiScanEntry>[];
      Map<String, String>? current;

      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('BSS ')) {
          if (current != null) _addEntry(networks, current);
          current = {
            'bssid': trimmed.split(' ')[1].toLowerCase(),
            'capabilities': '',
          };
        } else if (current != null) {
          if (trimmed.startsWith('SSID:')) {
            current['ssid'] = trimmed.substring(5).trim().replaceAll('"', '');
          } else if (trimmed.contains('signal:')) {
            current['signal'] = RegExp(r'-?\d+').firstMatch(trimmed)?.group(0) ?? '-100';
          } else if (trimmed.contains('DS Parameter set: channel') || trimmed.contains('primary channel:')) {
            current['channel'] = RegExp(r'\d+').firstMatch(trimmed)?.group(0) ?? '0';
          } else if (trimmed.contains('WPS:')) {
            current['wps'] = 'yes';
          } else if (trimmed.contains('Version: 1.0')) {
            current['wps_locked'] = 'no';
          } else if (trimmed.contains('0x15')) {
            current['wps_locked'] = 'yes';
          } else if (trimmed.contains('RSN:') || trimmed.contains('Group cipher')) {
            current['capabilities'] = '${current['capabilities']} [WPA2]';
          }
        }
      }
      if (current != null) _addEntry(networks, current);

      if (mounted) {
        setState(() {
          _networks = networks;
          _loading = false;
          _status = networks.isEmpty
              ? 'Сетей не найдено (попробуйте телефонное сканирование)'
              : 'Найдено сетей: ${networks.length}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _status = 'Ошибка роутера: $e'; });
      }
    }
  }

  void _addEntry(List<_WifiScanEntry> networks, Map<String, String> cur) {
    final bssid = cur['bssid'] ?? '';
    if (bssid.isEmpty) return;
    networks.add(_WifiScanEntry(
      ssid: cur['ssid'] ?? '(скрытая)',
      bssid: bssid,
      signal: int.tryParse(cur['signal'] ?? '-100') ?? -100,
      channel: int.tryParse(cur['channel'] ?? '0') ?? 0,
      capabilities: cur['capabilities'] ?? '',
    ));
  }

  Future<void> _scanPhone() async {
    setState(() { _loading = true; _status = 'Сканирование эфира с телефона...'; });
    final scanStatus = await LocalWifiScanner.scan();
    final networks = <_WifiScanEntry>[];
    if (scanStatus.success) {
      final seen = <String>{};
      for (final s in scanStatus.results) {
        if (seen.contains(s.bssid)) continue;
        seen.add(s.bssid);
        networks.add(_WifiScanEntry(
          ssid: s.ssid.isNotEmpty ? s.ssid : '(скрытая)',
          bssid: s.bssid,
          signal: s.signalStrength,
          channel: s.channel,
          width: s.width,
        ));
      }
    }
    if (mounted) {
      setState(() {
        _networks = networks;
        _loading = false;
        _status = !scanStatus.success
            ? scanStatus.message
            : networks.isEmpty
                ? 'Сетей не найдено (телефон)'
                : 'Найдено сетей: ${networks.length} (телефон)';
      });
    }
  }

  void _selectNetwork(_WifiScanEntry n) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (ctx) => _NetworkDetailSheet(service: widget.service, network: n),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('WPS Audit'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _scanRouter,
            icon: const Icon(Icons.router),
            tooltip: 'Сканировать с роутера',
          ),
          IconButton(
            onPressed: _loading ? null : _scanPhone,
            icon: const Icon(Icons.phone_android),
            tooltip: 'Сканировать с телефона',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_status.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  if (_loading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status, style: TextStyle(fontSize: 12))),
                ],
              ),
            ),
          Expanded(
            child: _networks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_find, size: 64, color: theme.colorScheme.outline),
                        const SizedBox(height: 16),
                        Text('Сканируйте эфир', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Сканирование с роутера — через iw dev\nСканирование с телефона — через WiFi API',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _networks.length,
                    itemBuilder: (_, i) => _buildNetworkCard(_networks[i], theme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkCard(_WifiScanEntry n, ThemeData theme) {
    final sigColor = n.signal > -50 ? Colors.green : (n.signal > -70 ? Colors.orange : Colors.red);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _selectNetwork(n),
        leading: Icon(
          n.encryptionType == 'Открытая' ? Icons.wifi : Icons.lock,
          color: n.encryptionType == 'Открытая' ? Colors.orange : theme.colorScheme.primary,
        ),
        title: Text(n.ssid, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${n.bssid} • К${n.channel} • ${n.encryptionType}',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, fontFamily: 'monospace'),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: sigColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('${n.signal}dBm', style: TextStyle(fontSize: 12, color: sigColor, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _NetworkDetailSheet extends StatefulWidget {
  final OpenWrtService service;
  final _WifiScanEntry network;

  const _NetworkDetailSheet({required this.service, required this.network});

  @override
  State<_NetworkDetailSheet> createState() => _NetworkDetailSheetState();
}

class _NetworkDetailSheetState extends State<_NetworkDetailSheet> {
  final _passCtrl = TextEditingController();
  bool _connecting = false;
  bool _checking = false;
  String? _checkResult;
  bool _connectingAsClient = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkSecurity() async {
    setState(() { _checking = true; _checkResult = null; });
    try {
      final n = widget.network;
      final lines = <String>[];

      lines.add('Точка: ${n.ssid}');
      lines.add('BSSID: ${n.bssid}');
      lines.add('Канал: ${n.channel}');
      lines.add('Шифрование: ${n.encryptionType}');

      // Проверка WPS с роутера (iw scan)
      final wpsInfo = await _checkWpsFromRouter(n);
      lines.addAll(wpsInfo);

      // Анализ безопасности
      final enc = n.encryptionType;
      final securityIssues = <String>[];
      if (enc == 'Открытая') {
        securityIssues.add('⚠ Открытая сеть — любой может подключиться');
      } else if (enc == 'WEP') {
        securityIssues.add('⚠ WEP — легко взломать за минуты');
      }
      if (wpsInfo.any((l) => l.contains('WPS: Открыт') || l.contains('WPS: включён'))) {
        securityIssues.add('⚠ WPS включён без блокировки — возможна атака Pixie Dust');
        securityIssues.add('  Рекомендация: отключить WPS или включить блокировку после 3 попыток');
      }
      if (enc == 'WPA2') {
        securityIssues.add('✓ WPA2 — хороший уровень защиты (используйте сложный пароль)');
      }
      if (enc == 'WPA3') {
        securityIssues.add('✓ WPA3 — максимальный уровень защиты');
      }

      if (securityIssues.isEmpty) {
        lines.add('\nИтог: безопасность не определена');
      } else {
        lines.add('\nРезультат проверки:');
        lines.addAll(securityIssues);
      }

      setState(() { _checkResult = lines.join('\n'); _checking = false; });
    } catch (e) {
      setState(() { _checkResult = 'Ошибка: $e'; _checking = false; });
    }
  }

  Future<List<String>> _checkWpsFromRouter(_WifiScanEntry target) async {
    try {
      final devs = await widget.service.fetchWirelessDevices();
      if (devs.isEmpty) return ['WPS: не удалось проверить (нет радио)'];
      final radio = devs.first.name;

      // Получаем интерфейс для сканирования
      String iface = radio;
      try {
        final raw = await widget.service.runCommand(
            'uci show wireless 2>/dev/null | grep device=\'$radio\' | head -1 | cut -d. -f2 || echo ""');
        final section = raw.trim();
        if (section.isNotEmpty) {
          final i = (await widget.service.runCommand('uci get wireless.$section.ifname 2>/dev/null || echo ""')).trim();
          if (i.isNotEmpty) iface = i;
        }
      } catch (_) {}

      final raw = await widget.service.runCommand('iw dev $iface scan 2>/dev/null | grep -A 20 "BSS ${target.bssid}" || echo ""');
      if (raw.isEmpty) return ['WPS: точка не найдена в эфире роутера'];

      final hasWps = raw.contains('WPS:');
      final locked = raw.contains('Version: 1.0') && raw.contains('0x15');
      if (hasWps) {
        return locked
            ? ['WPS: Заблокирован (после неудачных попыток)', 'Pixie Dust: защита от атаки включена']
            : ['WPS: Открыт (уязвим)', 'Pixie Dust: ВОЗМОЖНА АТАКА — рекомендуем отключить WPS'];
      }
      return ['WPS: не поддерживается'];
    } catch (e) {
      return ['WPS: ошибка проверки ($e)'];
    }
  }

  Future<void> _connectAsClient() async {
    if (_passCtrl.text.isEmpty) {
      setState(() {
        _checkResult = 'Введите пароль сети';
      });
      return;
    }
    setState(() { _connecting = true; _checkResult = null; });
    try {
      final devs = await widget.service.fetchWirelessDevices();
      if (devs.isEmpty) throw Exception('Радио не найдено');
      final radio = devs.first.name;
      await widget.service.wifiClientConnect(radio, widget.network.ssid, _passCtrl.text);
      setState(() { _connecting = false; _checkResult = 'Подключено! Роутер теперь клиент этой сети (WAN)'; });
    } catch (e) {
      setState(() { _connecting = false; _checkResult = 'Ошибка подключения: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.network;
    final sigColor = n.signal > -50 ? Colors.green : (n.signal > -70 ? Colors.orange : Colors.red);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: sigColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${n.signal} dBm', style: TextStyle(fontWeight: FontWeight.bold, color: sigColor)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.ssid, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${n.bssid} • К${n.channel} • ${n.width}MHz',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Шифрование: ${n.encryptionType}',
                  style: TextStyle(fontSize: 13, color: n.encryptionType == 'Открытая' ? Colors.orange : theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              // Проверка безопасности
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _checking ? null : _checkSecurity,
                  icon: _checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.security),
                  label: const Text('Проверить безопасность (WPS / Pixie Dust)'),
                ),
              ),
              const SizedBox(height: 12),

              // Ввод пароля
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль сети',
                  hintText: 'Для подключения роутера как клиента',
                  prefixIcon: Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _connecting ? null : _connectAsClient,
                  icon: _connecting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_connectingAsClient ? 'Подключение...' : 'Подключить роутер к этой сети'),
                ),
              ),

              if (_checkResult != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_checkResult!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}