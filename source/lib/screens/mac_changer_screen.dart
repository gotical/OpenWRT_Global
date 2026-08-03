import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';
import '../services/openwrt_service.dart';

class MacChangerScreen extends StatefulWidget {
  final OpenWrtService service;

  const MacChangerScreen({super.key, required this.service});

  @override
  State<MacChangerScreen> createState() => _MacChangerScreenState();
}

class _MacChangerScreenState extends State<MacChangerScreen> {
  List<Map<String, String>> _interfaces = [];
  String? _selectedIface;
  String _currentMac = '-';
  String _permanentMac = '-';
  String _vendor = '';
  bool _loading = true;
  bool _changing = false;
  String? _error;

  final _ouiPool = [
    'Apple', 'Intel', 'Samsung', 'Huawei', 'Google',
    'Cisco', 'TP-Link', 'D-Link', 'Realtek', 'Xiaomi',
  ];

  static const _ouiMap = {
    'Apple': '00:1B:63',
    'Intel': '00:1B:21',
    'Samsung': '00:1E:68',
    'Huawei': '00:1A:2E',
    'Google': '00:1A:11',
    'Cisco': '00:1A:A1',
    'TP-Link': '50:C7:BF',
    'D-Link': '00:1B:11',
    'Realtek': '00:E0:4C',
    'Xiaomi': '18:FE:34',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Получаем список интерфейсов
      final raw = await widget.service.runCommand(
        "for i in \$(ls /sys/class/net/); do echo \"\$i:\$(cat /sys/class/net/\$i/address 2>/dev/null)\"; done"
      );
      final lines = raw.split('\n');
      final ifaces = <Map<String, String>>[];
      for (final line in lines) {
        final parts = line.trim().split(':');
        if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].length == 17) {
          ifaces.add({'name': parts[0], 'mac': parts[1].toLowerCase()});
        }
      }
      if (ifaces.isEmpty) {
        // fallback: ip link
        final raw2 = await widget.service.runCommand("ip link show | grep -E '^[0-9]' | awk '{print \$2}' | tr -d ':'");
        for (final name in raw2.split('\n').where((n) => n.trim().isNotEmpty)) {
          try {
            final mac = (await widget.service.runCommand("cat /sys/class/net/$name/address 2>/dev/null || echo '?'")).trim();
            ifaces.add({'name': name.trim(), 'mac': mac});
          } catch (_) {}
        }
      }
      setState(() { _interfaces = ifaces; _loading = false; });
      if (ifaces.isNotEmpty) {
        _selectedIface = ifaces[0]['name'];
        _loadMacInfo(ifaces[0]['name']!);
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMacInfo(String iface) async {
    try {
      final cur = (await widget.service.runCommand("cat /sys/class/net/$iface/address 2>/dev/null || echo '?'")).trim();
      final perm = (await widget.service.runCommand("macchanger -s $iface 2>/dev/null | grep -i permanent | awk '{print \$3}' || echo '$cur'")).trim();
      final vendor = (await widget.service.runCommand("macchanger -s $iface 2>/dev/null | grep -i vendor | cut -d: -f2- || echo ''")).trim();
      setState(() {
        _currentMac = cur;
        _permanentMac = perm;
        _vendor = vendor;
      });
    } catch (_) {}
  }

  String _randomMac() {
    final r = DateTime.now().microsecondsSinceEpoch;
    final b = List.generate(6, (i) => (r >> (i * 8) & 0xFF));
    b[0] = (b[0] & 0xFC) | 0x02; // locally administered
    return b.map((n) => n.toRadixString(16).padLeft(2, '0')).join(':');
  }

  String _ouiMac(String oui) {
    final ouiPrefix = _ouiMap[oui] ?? '02:00:00';
    final rest = _randomMac().split(':').sublist(3).join(':');
    return '$ouiPrefix:$rest';
  }

  Future<void> _changeMac(String newMac) async {
    if (_selectedIface == null) return;
    setState(() => _changing = true);
    try {
      final iface = _selectedIface!;
      // Проверяем macchanger
      final hasMacchanger = await widget.service.runCommand("which macchanger 2>/dev/null && echo OK || echo NO").then((s) => s.trim());
      if (hasMacchanger == 'OK') {
        await widget.service.runCommand("ip link set $iface down && macchanger $iface -m $newMac && ip link set $iface up");
      } else {
        await widget.service.runCommand("ip link set $iface down && ip link set $iface address $newMac && ip link set $iface up");
      }
      await _loadMacInfo(iface);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('MAC $iface ${AppStrings.of(context).text('изменён на')} $newMac'), backgroundColor: Colors.green.shade700),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('${AppStrings.of(context).text('Ошибка')}: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.text('MAC Changer'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                   FilledButton.tonal(onPressed: _load, child: Text(AppStrings.of(context).text('Повторить'))),
                ]))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Text(s.text('Интерфейс'), style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedIface,
                              items: _interfaces.map((i) => DropdownMenuItem(
                                value: i['name'],
                                child: Text('${i['name']} (${i['mac']})', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                              )).toList(),
                              onChanged: (v) {
                                setState(() => _selectedIface = v);
                                if (v != null) _loadMacInfo(v);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             _infoRow(s.text('Текущий MAC'), _currentMac, theme),
                             _infoRow(s.text('Постоянный MAC'), _permanentMac, theme),
                             if (_vendor.isNotEmpty) _infoRow(s.text('Вендор'), _vendor, theme),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                     Text(s.text('Быстрый выбор'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          label: const Text('Random'),
                          avatar: const Icon(Icons.shuffle, size: 16),
                          onPressed: _changing ? null : () => _changeMac(_randomMac()),
                        ),
                        ..._ouiPool.map((oui) => ActionChip(
                          label: Text(oui, style: const TextStyle(fontSize: 12)),
                          onPressed: _changing ? null : () => _changeMac(_ouiMac(oui)),
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                     Text(s.text('Произвольный MAC'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(text: _randomMac()),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'XX:XX:XX:XX:XX:XX',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: (v) {},
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _changing ? null : () => _changeMac(_randomMac()),
                          child: _changing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                               : Text(s.text('Применить')),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _infoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
             tooltip: AppStrings.of(context).text('Копировать'),
          ),
        ],
      ),
    );
  }
}
