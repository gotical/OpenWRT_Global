import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/openwrt_service.dart';

class FirewallScreen extends StatefulWidget {
  final OpenWrtService service;

  const FirewallScreen({super.key, required this.service});

  @override
  State<FirewallScreen> createState() => _FirewallScreenState();
}

class _FirewallScreenState extends State<FirewallScreen> {
  String _t(String source) => AppStrings.of(context).text(source);
  List<Map<String, String>> zones = [];
  List<Map<String, String>> forwards = [];
  List<Map<String, String>> rules = [];
  List<Map<String, String>> redirects = [];
  List<Map<String, String>> blocks = [];
  bool running = false;
  bool loading = true;
  String? error;
  String blockFilter = '';
  Map<String, bool> processing = {};
  final TextEditingController _blockSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      final cfg = await widget.service.fetchFirewallConfig();
      final isRunning = await widget.service.fetchFirewallRunning();
      final bl = await widget.service.fetchBlocklist();
      if (!mounted) return;
      setState(() {
        zones = (cfg['zones'] as List?)?.cast<Map<String, String>>() ?? [];
        forwards = (cfg['forwards'] as List?)?.cast<Map<String, String>>() ?? [];
        rules = (cfg['rules'] as List?)?.cast<Map<String, String>>() ?? [];
        redirects = (cfg['redirects'] as List?)?.cast<Map<String, String>>() ?? [];
        blocks = bl;
        running = isRunning;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _action(String key, String action) async {
    setState(() => processing['$key:$action'] = true);
    try {
      await widget.service.firewallAction(action);
      if (!mounted) return;
      final r = await widget.service.fetchFirewallRunning();
      if (mounted) setState(() => running = r);
      _snack('${_t('Фаервол')}: $action');
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    } finally {
      if (mounted) setState(() => processing.remove('$key:$action'));
    }
  }

  Future<void> _toggle(Map<String, String> s, bool enabled) async {
    setState(() => processing['t_${s['key']}'] = true);
    try {
      await widget.service.setFirewallSectionEnabled(s['key']!, enabled);
      if (!mounted) return;
      s['enabled'] = enabled ? '1' : '0';
      setState(() {});
      _snack(_t(enabled ? 'Правило включено' : 'Правило отключено'));
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    } finally {
      if (mounted) setState(() => processing.remove('t_${s['key']}'));
    }
  }

  Future<void> _delete(Map<String, String> s, String kind) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text('${_t('Удалить')} $kind?'),
        content: Text(s['name'] ?? s['key']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Удалить'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.deleteFirewallSection(s['key']!);
      if (!mounted) return;
       _snack(_t('Удалено'));
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _addBlock() async {
    final value = await _blockDialog('', _t('Добавить'));
    if (value == null || !mounted) return;
    try {
      await widget.service.addBlock(value);
      if (!mounted) return;
      _snack('${_t('Заблокировано')}: $value');
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _editBlock(Map<String, String> b) async {
    final value = await _blockDialog(b['value']!, _t('Изменить'));
    if (value == null || value == b['value'] || !mounted) return;
    try {
      await widget.service.removeBlock(b);
      await widget.service.addBlock(value);
      if (!mounted) return;
      _snack('${_t('Обновлено')}: $value');
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _deleteBlock(Map<String, String> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text('${_t('Снять блокировку')}?'),
        content: Text(b['value']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Разблокировать'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.removeBlock(b);
      if (!mounted) return;
       _snack('${_t('Разблокировано')}: ${b['value']}');
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<String?> _blockDialog(String initial, String title) async {
    final controller = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: controller,
            autofocus: true,
             decoration: InputDecoration(
               labelText: _t('Домен или IP'),
               hintText: _t('example.com или 1.2.3.4'),
            ),
          ),
          const SizedBox(height: 8),
           Text(_t('Домен блокируется через DNS (все запросы → 0.0.0.0), IP — через правило фаервола REJECT.'),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Заблокировать'))),
        ],
      ),
    );
    if (ok != true) return null;
    final v = controller.text.trim();
    return v.isEmpty ? null : v;
  }

  List<Map<String, String>> get _filteredBlocks {
    final f = blockFilter.trim().toLowerCase();
    if (f.isEmpty) return blocks;
    return blocks.where((b) => b['value']!.toLowerCase().contains(f)).toList();
  }

  Future<void> _addForward() async {
    final values = await _forwardDialog(null);
    if (values == null || !mounted) return;
    try {
      await widget.service.addPortForward(
        name: values['name']!,
        srcDport: values['dport']!,
        destIp: values['ip']!,
        destPort: values['dp']!,
        proto: values['proto']!,
      );
      if (!mounted) return;
       _snack(_t('Проброс добавлен'));
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _editForward(Map<String, String> r) async {
    final values = await _forwardDialog({
      'name': r['name'] ?? '-',
      'proto': r['proto'] ?? '-',
      'dport': r['src_dport'] ?? '-',
      'ip': r['dest_ip'] ?? '-',
      'dp': r['dest_port'] ?? '-',
      'enabled': r['enabled'] == '0' ? '0' : '1',
    });
    if (values == null || !mounted) return;
    try {
      await widget.service.updatePortForward(
        section: r['key']!,
        name: values['name']!,
        srcDport: values['dport']!,
        destIp: values['ip']!,
        destPort: values['dp']!,
        proto: values['proto']!,
        enabled: values['enabled'] == '1',
      );
      if (!mounted) return;
       _snack(_t('Проброс обновлён'));
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<Map<String, String>?> _forwardDialog(Map<String, String>? existing) async {
    final name = TextEditingController(text: existing?['name'] == '-' ? '' : (existing?['name'] ?? ''));
    final port = TextEditingController(text: existing?['dport'] == '-' ? '' : (existing?['dport'] ?? ''));
    final ip = TextEditingController(text: existing?['ip'] == '-' ? '' : (existing?['ip'] ?? ''));
    final dport = TextEditingController(text: existing?['dp'] == '-' ? '' : (existing?['dp'] ?? ''));
    String proto = existing?['proto'] ?? 'tcp';
    bool enabled = (existing?['enabled'] ?? '1') != '0';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
           title: Text(_t(existing == null ? 'Новое правило' : 'Изменить правило')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
               TextField(controller: name, decoration: InputDecoration(labelText: _t('Название'))),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: proto,
                 items: [
                  DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                  DropdownMenuItem(value: 'udp', child: Text('UDP')),
                   DropdownMenuItem(value: 'tcp udp', child: Text(_t('Оба'))),
                ],
                onChanged: (v) => setSt(() => proto = v!),
              ),
               TextField(controller: port, decoration: InputDecoration(labelText: _t('Внешний порт (WAN)')), keyboardType: TextInputType.number),
               TextField(controller: ip, decoration: InputDecoration(labelText: _t('Локальный IP')), keyboardType: TextInputType.number),
               TextField(controller: dport, decoration: InputDecoration(labelText: _t('Локальный порт')), keyboardType: TextInputType.number),
              SwitchListTile(
                value: enabled,
                onChanged: (v) => setSt(() => enabled = v),
                 title: Text(_t('Правило включено')),
              ),
            ]),
          ),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
               child: Text(_t(existing == null ? 'Добавить' : 'Сохранить')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    return {
      'name': name.text.trim().isEmpty ? 'redirect_${DateTime.now().millisecondsSinceEpoch}' : name.text.trim(),
      'proto': proto,
      'dport': port.text.trim(),
      'ip': ip.text.trim(),
      'dp': dport.text.trim(),
      'enabled': enabled ? '1' : '0',
    };
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void dispose() {
    _blockSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: Text(s.text('Фаервол')),
              actions: [
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
                        const SizedBox(height: 16),
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                         FilledButton.tonal(onPressed: _load, child: Text(_t('Повторить'))),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shield, color: running ? Colors.green : theme.colorScheme.error),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                     Text(_t(running ? 'Фаервол работает' : 'Фаервол остановлен'),
                                        style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 4),
                                     Text('${_t('Правил:')} ${zones.length + forwards.length + rules.length + redirects.length}',
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _fwActionButton('restart', Icons.refresh, _t('Перезагрузить')),
                              const SizedBox(width: 8),
                              _fwActionButton('start', Icons.play_arrow, _t('Старт')),
                              const SizedBox(width: 8),
                              _fwActionButton('stop', Icons.stop, _t('Стоп')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
               _sectionHeader(theme, _t('Блокировка доменов и IP')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _blockSearch,
                          onChanged: (v) => setState(() => blockFilter = v),
                          decoration: InputDecoration(
                             hintText: '${_t('Поиск по списку')} (${blocks.length})',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _addBlock,
                        icon: const Icon(Icons.add, size: 18),
                         label: Text(_t('Добавить')),
                      ),
                    ],
                  ),
                ),
              ),
              if (_filteredBlocks.isEmpty)
                 SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green),
                        SizedBox(width: 12),
                         Expanded(child: Text(_t('Заблокированных нет'))),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _blockCard(theme, _filteredBlocks[i]),
                      childCount: _filteredBlocks.length,
                    ),
                  ),
                ),
              if (zones.isNotEmpty) ...[
                 _sectionHeader(theme, _t('Зоны')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _zoneCard(theme, zones[i]),
                      childCount: zones.length,
                    ),
                  ),
                ),
              ],
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                       Expanded(child: Text(_t('Проброс портов'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                       IconButton(onPressed: _addForward, icon: const Icon(Icons.add_circle_outline), tooltip: _t('Добавить')),
                    ],
                  ),
                ),
              ),
              if (redirects.isEmpty)
                 SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                   sliver: SliverToBoxAdapter(child: Text(_t('Пробросов нет'))),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _redirectCard(theme, redirects[i]),
                      childCount: redirects.length,
                    ),
                  ),
                ),
              if (forwards.isNotEmpty) ...[
                 _sectionHeader(theme, _t('Переадресация между зонами')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _ruleCard(theme, forwards[i], Icons.swap_horiz),
                      childCount: forwards.length,
                    ),
                  ),
                ),
              ],
              if (rules.isNotEmpty) ...[
                 _sectionHeader(theme, _t('Правила трафика')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _ruleCard(theme, rules[i], Icons.rule),
                      childCount: rules.length,
                    ),
                  ),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fwActionButton(String action, IconData icon, String label) {
    final disabled = processing.containsKey('fw:$action');
    const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)));
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
      shape: WidgetStatePropertyAll(shape),
    );
    return Expanded(
      child: SizedBox(
        height: 44,
        child: FilledButton.tonalIcon(
          style: style,
          onPressed: disabled ? null : () => _action('fw', action),
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _zoneCard(ThemeData theme, Map<String, String> z) {
    final policy = (String? p) => p == null || p.isEmpty ? '-' : p;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.layers, color: theme.colorScheme.primary),
        title: Text(z['name'] ?? z['key']!),
        subtitle: Text([
           if ((z['network'] ?? '').isNotEmpty) '${_t('Сеть')}: ${z['network']}',
           '${_t('Вход')}: ${policy(z['input'])}',
           '${_t('Выход')}: ${policy(z['output'])}',
           '${_t('Перенаправление')}: ${policy(z['forward'])}',
          if (z['masq'] == '1') 'MASQUERADE',
        ].join(' • ')),
      ),
    );
  }

  Widget _redirectCard(ThemeData theme, Map<String, String> r) {
    final enabled = (r['enabled'] ?? '1') != '0';
    final name = (r['name'] ?? '').isNotEmpty ? r['name']! : 'redirect';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.swap_horiz, color: enabled ? theme.colorScheme.primary : theme.colorScheme.outline),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${r['proto'] ?? 'tcp'} ${r['src_dport'] ?? '-'} → ${r['dest_ip'] ?? '-'}:${r['dest_port'] ?? '-'}'
            '${(r['src'] ?? 'wan').isNotEmpty && r['src'] != 'wan' ? ' (${r['src']})' : ''}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (processing['t_${r['key']}'] == true)
              const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              Switch(
                value: enabled,
                onChanged: (v) => _toggle(r, v),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
               tooltip: _t('Изменить'),
              onPressed: () => _editForward(r),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
               tooltip: _t('Удалить'),
               onPressed: () => _delete(r, _t('правило')),
            ),
          ],
        ),
        onTap: () => _editForward(r),
      ),
    );
  }

  Widget _ruleCard(ThemeData theme, Map<String, String> r, IconData icon) {
    final enabled = (r['enabled'] ?? '1') != '0';
    final name = (r['name'] ?? '').isNotEmpty ? r['name']! : (r['type'] ?? 'rule');
    final target = r['target'] ?? '';
    final color = target.contains('ACCEPT')
        ? Colors.green
        : target.contains('REJECT') || target.contains('DROP')
            ? theme.colorScheme.error
            : null;
    final spec = [
      if ((r['proto'] ?? '').isNotEmpty) r['proto']!,
      if ((r['src_port'] ?? '').isNotEmpty) 'src:${r['src_port']}',
      if ((r['dest_port'] ?? '').isNotEmpty) 'dport:${r['dest_port']}',
      if ((r['src_ip'] ?? '').isNotEmpty) '${r['src_ip']}',
      if ((r['dest_ip'] ?? '').isNotEmpty) '→ ${r['dest_ip']}',
      if ((r['src'] ?? '').isNotEmpty) '(${r['src']})',
      if ((r['dest'] ?? '').isNotEmpty) '→ (${r['dest']})',
    ].join(' ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: color ?? theme.colorScheme.primary),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([if (target.isNotEmpty) target, spec].where((e) => e.isNotEmpty).join(' • ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (processing['t_${r['key']}'] == true)
              const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              Switch(
                value: enabled,
                onChanged: (v) => _toggle(r, v),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
               tooltip: _t('Удалить'),
               onPressed: () => _delete(r, _t('правило')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockCard(ThemeData theme, Map<String, String> b) {
    final isIp = b['type'] == 'ip';
    final enabled = b['enabled'] != '0';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(
            isIp ? Icons.dns : Icons.language,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(b['value']!, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Icon(
              enabled ? Icons.block : Icons.block_flipped,
              size: 14,
              color: enabled ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
             Text(isIp ? _t('IP • REJECT') : _t('домен • DNS'), style: theme.textTheme.bodySmall),
            if (!enabled) ...[
              const SizedBox(width: 8),
               Text(_t('выкл'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isIp)
              processing['t_${b['key']}'] == true
                  ? const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Switch(
                      value: enabled,
                      onChanged: (v) async {
                        setState(() => processing['t_${b['key']}'] = true);
                        try {
                          await widget.service.setBlockEnabled(b, v);
                          if (!mounted) return;
                          b['enabled'] = v ? '1' : '0';
                          setState(() {});
                           _snack(_t(v ? 'Включено' : 'Выключено'));
                        } catch (e) {
                          if (!mounted) return;
                           _snack('${_t('Ошибка')}: $e');
                        } finally {
                          if (mounted) setState(() => processing.remove('t_${b['key']}'));
                        }
                      },
                    ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
               tooltip: _t('Изменить'),
              onPressed: () => _editBlock(b),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
               tooltip: _t('Разблокировать'),
              onPressed: () => _deleteBlock(b),
            ),
          ],
        ),
      ),
    );
  }
}
