import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/openwrt_service.dart';

class MonitorScreen extends StatefulWidget {
  final OpenWrtService service;
  const MonitorScreen({super.key, required this.service});
  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  String _t(String source) => AppStrings.of(context).text(source);
  List<Map<String, String>> connections = [];
  List<Map<String, String>> filtered = [];
  bool loading = true;
  Timer? _timer;
  final _searchCtrl = TextEditingController();
  bool byDevice = false;

  @override
  void initState() { super.initState(); _searchCtrl.addListener(() => setState(() => _filter())); _load(); _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load()); }
  @override
  void dispose() { _timer?.cancel(); _searchCtrl.dispose(); super.dispose(); }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() => filtered = connections.where((c) => c['src']!.contains(q) || c['dst']!.contains(q) || c['sport']!.contains(q) || c['dport']!.contains(q)).toList());
  }

  Map<String, List<Map<String, String>>> get _byDevice {
    final map = <String, List<Map<String, String>>>{};
    for (final c in connections) {
      final key = c['src']!;
      map.putIfAbsent(key, () => []).add(c);
    }
    return map;
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      String raw = '';
      try { raw = await widget.service.runCommand('conntrack -L 2>/dev/null | head -200 || echo ""'); } catch (_) {}
      if (raw.trim().isEmpty) { try { raw = await widget.service.runCommand('cat /proc/net/nf_conntrack 2>/dev/null | head -200 || echo ""'); } catch (_) {} }
      final list = <Map<String, String>>[];
      for (final line in LineSplitter.split(raw).take(200)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 4 || (parts[0] != 'tcp' && parts[0] != 'udp')) continue;
        final proto = parts[0]; final state = parts.length > 3 ? parts[3] : '-';
        String? src, dst, sport, dport;
        for (final p in parts) { if (p.startsWith('src=')) src = p.substring(4); if (p.startsWith('dst=')) dst = p.substring(4); if (p.startsWith('sport=')) sport = p.substring(6); if (p.startsWith('dport=')) dport = p.substring(6); }
        if (src != null && dst != null && !src.startsWith('127.') && !dst.startsWith('127.')) list.add({'proto': proto, 'state': state, 'src': src, 'dst': dst, 'sport': sport ?? '-', 'dport': dport ?? '-'});
      }
      if (!mounted) return;
      setState(() { connections = list; _filter(); loading = false; });
    } catch (_) { if (mounted) setState(() => loading = false); }
  }

  List<Widget> _groupSection(String key, List<Map<String, String>> list, ThemeData t) => [
     SliverPadding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), sliver: SliverToBoxAdapter(child: Row(children: [const Icon(Icons.computer, size: 18), const SizedBox(width: 6), Text(key, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(width: 6), Text('${list.length} ${_t('соед.')}', style: t.textTheme.bodySmall)]))),
    SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: SliverList(delegate: SliverChildBuilderDelegate((_, i) {
      final c = list[i];
      return Padding(padding: const EdgeInsets.only(bottom: 4, left: 8), child: Row(children: [
        Icon(Icons.arrow_forward, size: 14, color: t.colorScheme.outline),
        const SizedBox(width: 4),
        Expanded(child: Text('${c['dport']} → ${c['dst']}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
        Text(c['proto']!.toUpperCase(), style: TextStyle(fontSize: 10, color: t.colorScheme.onSurfaceVariant)),
      ]));
    }, childCount: list.length))),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = Theme.of(context);
    final groups = _byDevice;
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar.large(title: Text(s.text('Мониторинг')), actions: [
             IconButton(icon: Icon(byDevice ? Icons.list : Icons.person), onPressed: () => setState(() => byDevice = !byDevice), tooltip: _t('По устройствам')),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ]),
           SliverPadding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), sliver: SliverToBoxAdapter(child: SearchBar(controller: _searchCtrl, hintText: _t('IP или порт'), leading: const Icon(Icons.search), trailing: _searchCtrl.text.isNotEmpty ? [IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchCtrl.clear())] : null))),
          if (loading) const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
           else if (filtered.isEmpty) SliverFillRemaining(child: Center(child: Text(_t('Нет активных соединений'))))
          else if (!byDevice)
            SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: SliverList(delegate: SliverChildBuilderDelegate((_, i) {
              final c = filtered[i];
              return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: Icon(c['proto'] == 'tcp' ? Icons.settings_ethernet : Icons.public, color: t.colorScheme.primary, size: 20), title: Text('${c['src']} → ${c['dst']}', style: const TextStyle(fontSize: 13)), subtitle: Text('${c['sport']} → ${c['dport']} • ${c['state']}', style: const TextStyle(fontSize: 11))));
            }, childCount: filtered.length)))
          else
            ...[
              for (final e in groups.entries)
                ..._groupSection(e.key, e.value, t),
            ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}
