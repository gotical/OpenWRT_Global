import 'package:flutter/material.dart';
import '../models/package_info.dart';
import '../services/openwrt_service.dart';

class PackagesScreen extends StatefulWidget {
  final OpenWrtService service;

  const PackagesScreen({super.key, required this.service});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  Map<String, dynamic>? _diskInfo;
  List<PackageInfo> installed = [];
  List<PackageInfo> searchResults = [];
  bool loading = true;
  bool searching = false;
  String? error;
  final _searchCtrl = TextEditingController();
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      final data = await widget.service.fetchInstalledPackages();
      String? dfRaw;
      try { dfRaw = await widget.service.runCommand('df /overlay 2>/dev/null | tail -1 || echo ""'); } catch (_) {}
      setState(() {
        installed = data;
        if (dfRaw != null && dfRaw.trim().isNotEmpty) {
          final parts = dfRaw.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            _diskInfo = {'total': parts[1], 'used': parts[2], 'free': parts[3], 'use': parts.length >= 5 ? parts[4] : '-'};
          }
        }
        loading = false;
        error = null;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _search(String q) async {
    if (q.length < 2) return;
    setState(() => searching = true);
    try {
      final res = await widget.service.searchPackages(q);
      setState(() {
        searchResults = res;
        searching = false;
      });
    } catch (e) {
      setState(() => searching = false);
    }
  }

  Future<void> _updateLists() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Обновление списков...')]),
      ),
    );
    try {
      await widget.service.updatePackageLists();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Списки пакетов обновлены')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _install(PackageInfo pkg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Установить пакет?'),
        content: Text('${pkg.name} ${pkg.version}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Установить')),
        ],
      ),
    );
    if (ok != true) return;
    _showProgress('Установка ${pkg.name}...');
    try {
      await widget.service.installPackage(pkg.name);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${pkg.name} установлен')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _remove(PackageInfo pkg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить пакет?'),
        content: Text('${pkg.name} ${pkg.version}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    _showProgress('Удаление ${pkg.name}...');
    try {
      await widget.service.removePackage(pkg.name);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${pkg.name} удалён')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  void _showProgress(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Expanded(child: Text(message))]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
            SliverAppBar.large(
              title: const Text('Пакеты'),
              actions: [
                IconButton(onPressed: _updateLists, icon: const Icon(Icons.download)),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
              bottom: TabBar(
                onTap: (i) => setState(() => _tabIndex = i),
                tabs: const [
                  Tab(icon: Icon(Icons.check_circle), text: 'Установленные'),
                  Tab(icon: Icon(Icons.fact_check), text: 'Нужные'),
                  Tab(icon: Icon(Icons.search), text: 'Поиск'),
                ],
              ),
            ),
          ],
          body: loading && _tabIndex == 0
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    _buildInstalledList(theme),
                    _buildNeededTab(theme),
                    _buildSearchList(theme),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildInstalledList(ThemeData theme) {
    if (error != null) return _buildError(theme);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: installed.length + (_diskInfo != null ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (_diskInfo != null && i == 0) {
            final d = _diskInfo!;
            final pct = (d['use'] ?? '').replaceAll('%', '');
            final usedPercent = double.tryParse(pct) ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.storage, size: 20),
                    const SizedBox(width: 8),
                    Text('Память overlay', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${usedPercent.toStringAsFixed(0)}%', style: TextStyle(color: usedPercent > 85 ? Colors.red : theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: usedPercent / 100,
                      minHeight: 10,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(usedPercent > 85 ? Colors.red : theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Свободно: ${d['free'] ?? '-'} • Занято: ${d['used'] ?? '-'} • Всего: ${d['total'] ?? '-'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
            );
          }
          final idx = _diskInfo != null ? i - 1 : i;
          final p = installed[idx];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(p.name),
              subtitle: Text(p.version),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _remove(p),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNeededTab(ThemeData theme) {
    return FutureBuilder<Map<String, dynamic>>(
      future: () async {
        if (!widget.service.isConnected) await widget.service.connect();
        final deps = await widget.service.checkDependencies();
        // Проверяем наличие в репо для отсутствующих
        final repoStatus = <String, String>{};
        for (final e in deps.entries.where((e) => !e.value && e.key != 'ubus')) {
          final pn = OpenWrtService.packageForDependency[e.key];
          if (pn != null) {
            final inRepo = await widget.service.isPackageInRepo(pn);
            if (inRepo) {
              repoStatus[e.key] = 'in_repo';
            } else {
              final alt = await widget.service.findAlternativePackage(e.key);
              repoStatus[e.key] = alt != null ? 'alt:$alt' : 'missing';
            }
          }
        }
        return {'deps': deps, 'repo': repoStatus};
      }(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final deps = snap.data!['deps'] as Map<String, bool>;
        final repo = snap.data!['repo'] as Map<String, String>;
        final entries = deps.entries.where((e) => e.key != 'ubus').toList();
        return RefreshIndicator(
          onRefresh: () async { setState(() {}); },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (ctx, i) {
              final e = entries[i];
              final ok = e.value;
              final pn = OpenWrtService.packageForDependency[e.key];
              final rs = repo[e.key];
              String subtitle = '';
              String installPkg = pn ?? '';
              if (!ok) {
                if (rs == 'in_repo') { subtitle = '→ $pn (в репозитории)'; }
                else if (rs != null && rs.startsWith('alt:')) { subtitle = '→ ${rs.substring(4)} (альтернатива)'; installPkg = rs.substring(4); }
                else if (rs == 'missing') { subtitle = 'Нет в репозитории'; installPkg = ''; }
                else { subtitle = 'проверка...'; }
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : (installPkg.isEmpty ? Colors.grey : Colors.red), size: 22),
                  title: Text(e.key, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
                  trailing: (ok || installPkg.isEmpty) ? null : FilledButton.tonal(
                    onPressed: () async {
                      try {
                        await widget.service.installPackages([installPkg]);
                        if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$installPkg установлен'))); }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                      }
                    },
                    child: const Text('Уст.'),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchList(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            controller: _searchCtrl,
            hintText: 'Название пакета',
            leading: const Icon(Icons.search),
            trailing: [
              if (_searchCtrl.text.isNotEmpty)
                IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchCtrl.clear()),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _search(_searchCtrl.text.trim()),
              ),
            ],
            onSubmitted: (v) => _search(v.trim()),
          ),
        ),
        if (searching)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: searchResults.length,
              itemBuilder: (ctx, i) {
                final p = searchResults[i];
                final isInstalled = installed.any((x) => x.name == p.name);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(p.name),
                    subtitle: Text('${p.version}${p.description != null ? '\n${p.description}' : ''}'),
                    isThreeLine: p.description != null,
                    trailing: isInstalled
                        ? const Chip(label: Text('Установлен'), visualDensity: VisualDensity.compact)
                        : IconButton(
                            icon: const Icon(Icons.download, color: Colors.green),
                            onPressed: () => _install(p),
                          ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Ошибка', style: theme.textTheme.titleMedium),
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
