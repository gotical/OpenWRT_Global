import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/channel_scan_result.dart';
import '../services/openwrt_service.dart';
import '../services/channel_analyzer.dart';
import '../services/local_wifi_scanner.dart';

class ChannelAnalyzerScreen extends StatefulWidget {
  final OpenWrtService service;
  final String deviceName;

  const ChannelAnalyzerScreen({
    super.key,
    required this.service,
    required this.deviceName,
  });

  @override
  State<ChannelAnalyzerScreen> createState() => _ChannelAnalyzerScreenState();
}

class _ChannelAnalyzerScreenState extends State<ChannelAnalyzerScreen> {
  AppStrings get s => AppStrings.of(context);
  ChannelAnalysis? _analysis;
  bool _loading = true;
  String? _error;
  int _selectedWidth = 80;
  bool _phoneScanAvailable = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      final granted = await LocalWifiScanner.requestPermissions();
      if (mounted) setState(() => _phoneScanAvailable = granted);

      final analyzer = ChannelAnalyzer(widget.service);
      final analysis = await analyzer.analyze(widget.deviceName);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _applyChannel(int channel, String? htMode) async {
    try {
      await widget.service.setWifiChannel(widget.deviceName, channel.toString());
      if (htMode != null) {
        await widget.service.setWifiHtMode(widget.deviceName, htMode);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('${s.text('Канал установлен')}: $channel${htMode != null ? ", $htMode" : ""}')),
        );
        _init();
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
         title: Text('${s.text('Анализатор')} — ${widget.deviceName}'),
        actions: [
          IconButton(onPressed: _init, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                         FilledButton.tonal(onPressed: _init, child: Text(s.text('Повторить'))),
                      ],
                    ),
                  ),
                )
              : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final a = _analysis!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(theme, a),
        const SizedBox(height: 16),
        _buildWidthSelector(theme),
        const SizedBox(height: 16),
        _buildCombinedHeatmap(theme, a),
        const SizedBox(height: 16),
        _buildRecommendations(theme, a),
        const SizedBox(height: 16),
        if (_phoneScanAvailable) ...[
          _buildPhoneNetworks(theme, a),
          const SizedBox(height: 16),
        ],
        _buildRouterNetworks(theme, a),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildInfoCard(ThemeData theme, ChannelAnalysis a) {
    final phoneCount = a.phoneScans.length;
    final routerCount = a.routerScans.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_tethering, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(widget.deviceName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                 _infoChip(theme, s.text('Диапазон'), a.band.toUpperCase()),
                const SizedBox(width: 8),
                 _infoChip(theme, s.text('Текущий канал'), '${a.currentChannel}'),
                const SizedBox(width: 8),
                 _infoChip(theme, s.text('Ширина'), a.currentHtMode),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone_android, size: 16, color: phoneCount > 0 ? Colors.green : Colors.grey),
                const SizedBox(width: 4),
                 Text('${s.text('Телефон:')} $phoneCount ${s.text('сетей')}', style: theme.textTheme.bodySmall),
                const SizedBox(width: 16),
                Icon(Icons.router, size: 16, color: routerCount > 0 ? Colors.green : Colors.grey),
                const SizedBox(width: 4),
                 Text('${s.text('Роутер:')} $routerCount ${s.text('сетей')}', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildWidthSelector(ThemeData theme) {
    final widths = [20, 40, 80, 160];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(s.text('Целевая ширина канала'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: widths.map((w) {
                final selected = _selectedWidth == w;
                final htMode = _analysis!.band == '5g'
                    ? (w >= 80 ? 'HE$w' : 'HT$w')
                    : (w >= 40 ? 'HE$w' : 'HT$w');
                return ChoiceChip(
                  label: Text('${w}MHz'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedWidth = w),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedHeatmap(ThemeData theme, ChannelAnalysis a) {
    final allCh = a.allChannels;
    final combined = a.combinedInterference;
    final maxCount = combined.values.isEmpty ? 1 : combined.values.reduce((a, b) => a > b ? a : b);

    // Определяем занятые каналы с учётом ширины
    final phoneOccupied = <int, int>{};
    for (final scan in a.phoneScans) {
      for (final ch in scan.occupiedChannels) {
        phoneOccupied[ch] = (phoneOccupied[ch] ?? 0) + 1;
      }
    }
    final routerOccupied = <int, int>{};
    for (final scan in a.routerScans) {
      for (final ch in scan.occupiedChannels) {
        routerOccupied[ch] = (routerOccupied[ch] ?? 0) + 1;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
               Text(s.text('Спектр каналов'), style: theme.textTheme.titleSmall),
              const Spacer(),
               _legendDot(Colors.blue, s.text('Роутер')),
              const SizedBox(width: 12),
               _legendDot(Colors.orange, s.text('Телефон')),
            ]),
            const SizedBox(height: 4),
             Text(s.text('Ширина учтена (20/40/80/160 MHz)'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allCh.length,
                itemBuilder: (_, i) {
                  final ch = allCh[i];
                  final routerCount = routerOccupied[ch] ?? 0;
                  final phoneCount = phoneOccupied[ch] ?? 0;
                  final total = combined[ch] ?? 0;
                  final rectColor = total == 0
                      ? Colors.green
                      : (total <= 2 ? Colors.orange : Colors.red);
                  final maxBars = maxCount.clamp(1, 15);
                  final filled = maxBars > 0 ? (total.toDouble() / maxBars).clamp(0.05, 1.0) : 0.05;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                           child: Text('${s.text('К')} $ch', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              // Bar for router
                              if (routerCount > 0)
                                Container(
                                  height: 6,
                                  margin: const EdgeInsets.only(bottom: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: (routerCount / maxBars).clamp(0.2, 1.0)),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  width: (routerCount / maxBars).clamp(0.1, 1.0) * double.infinity,
                                ),
                              // Bar for phone
                              if (phoneCount > 0)
                                Container(
                                  height: 6,
                                  margin: const EdgeInsets.only(bottom: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: (phoneCount / maxBars).clamp(0.2, 1.0)),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  width: (phoneCount / maxBars).clamp(0.1, 1.0) * double.infinity,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 60,
                          height: 18,
                          decoration: BoxDecoration(
                            color: rectColor.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          alignment: Alignment.center,
                          child: FractionallySizedBox(
                            widthFactor: filled,
                            child: Container(
                              height: 18,
                              decoration: BoxDecoration(
                                color: rectColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 30,
                          child: Text('$total', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text(label, style: const TextStyle(fontSize: 10)),
    ]);
  }

  Widget _buildRecommendations(ThemeData theme, ChannelAnalysis a) {
    final best = a.recommendedChannels.isNotEmpty
        ? a.recommendedChannels.first
        : (a.allChannels.isNotEmpty ? a.allChannels.first : 0);
    final htMode = a.band == '5g'
        ? (_selectedWidth >= 80 ? 'HE$_selectedWidth' : 'HT$_selectedWidth')
        : (_selectedWidth >= 40 ? 'HE$_selectedWidth' : 'HT$_selectedWidth');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(s.text('Рекомендации'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _recommendTile(
                    theme,
                    icon: Icons.tune,
                     label: s.text('Канал'),
                    value: '$best',
                    color: Colors.green,
                    onTap: () => _applyChannel(best, null),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _recommendTile(
                    theme,
                    icon: Icons.height,
                     label: s.text('Ширина'),
                    value: htMode,
                    color: Colors.blue,
                    onTap: () => _applyChannel(a.currentChannel, htMode),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (a.recommendedChannels.length > 1) ...[
               Text(s.text('Другие свободные каналы:'), style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: a.recommendedChannels.take(6).map((ch) {
                  final isBest = ch == best;
                  return ActionChip(
                     label: Text('${s.text('К')} $ch', style: TextStyle(fontSize: 12, fontWeight: isBest ? FontWeight.bold : FontWeight.normal)),
                    onPressed: isBest ? null : () => _applyChannel(ch, htMode),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 8),
            // Quick actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _applyChannel(best, htMode),
                    icon: const Icon(Icons.check_circle, size: 18),
                     label: Text(s.text('Применить')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _applyChannel(0, null), // auto
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                     label: Text(s.text('Авто')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recommendTile(ThemeData theme, {required IconData icon, required String label, required String value, required Color color, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneNetworks(ThemeData theme, ChannelAnalysis a) {
    if (a.phoneScans.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.phone_android, size: 18, color: Colors.orange),
              const SizedBox(width: 6),
               Text('${s.text('Сканирование с телефона')} (${a.phoneScans.length})', style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            ...a.phoneScans.take(20).map((s) => _scanTile(s, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildRouterNetworks(ThemeData theme, ChannelAnalysis a) {
    if (a.routerScans.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.router, size: 18, color: Colors.blue),
              const SizedBox(width: 6),
               Text('${s.text('Сканирование с роутера')} (${a.routerScans.length})', style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            ...a.routerScans.take(20).map((s) => _scanTile(s, theme)),
          ],
        ),
      ),
    );
  }

  Widget _scanTile(ChannelScanResult s, ThemeData theme) {
    final sigColor = s.signalStrength > -50
        ? Colors.green
        : (s.signalStrength > -70 ? Colors.orange : Colors.red);
    final widthLabel = '${s.width}MHz';
    final chRange = s.width > 20
        ? ' (${s.startChannel}-${s.endChannel})'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: sigColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${s.signalStrength}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sigColor)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text(s.ssid.isNotEmpty ? s.ssid : '(${AppStrings.of(context).text('скрытая')})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text('К${s.channel}$chRange • $widthLabel • ${s.bssid.length >= 8 ? s.bssid.substring(0, 8) : s.bssid}...',
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: s.source == 'phone' ? Colors.orange.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(widthLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
