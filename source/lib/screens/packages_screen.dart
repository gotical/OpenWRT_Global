import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/package_info.dart';
import '../services/offline_cache.dart';
import '../services/openwrt_service.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/empty_state.dart';

class PackagesScreen extends StatefulWidget {
  final OpenWrtService service;

  const PackagesScreen({super.key, required this.service});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  String _t(String source) => AppStrings.of(context).text(source);
  Map<String, dynamic>? _diskInfo;
  List<PackageInfo> installed = [];
  List<PackageInfo> searchResults = [];
  bool loading = true;
  bool searching = false;
  String? error;
  final _searchCtrl = TextEditingController();
  int _tabIndex = 0;
  int _neededKey = 0;

  @override
  void initState() {
    super.initState();
    _showCacheFirst();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Показывает кешированные данные МГНОВЕННО, без спиннера.
  Future<void> _showCacheFirst() async {
    final key = OfflineCacheService.hostKey(
      widget.service.config.host,
      widget.service.config.port,
      widget.service.config.username,
    );
    final cached = await OfflineCacheService.loadPackages(key);
    if (!mounted || cached.isEmpty) return;
    setState(() {
      installed = cached;
      loading = false;
    });
  }

  Future<void> _load() async {
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      final data = await widget.service.fetchInstalledPackages();
      String? dfRaw;
      try { dfRaw = await widget.service.runCommand('df /overlay 2>/dev/null | tail -1 || echo ""'); } catch (_) {}
      if (!mounted) return;
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
      // Сохраняем в оффлайн-кеш.
      // ignore: discarded_futures
      OfflineCacheService.savePackages(
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

  Future<void> _search(String q) async {
    if (q.length < 2) return;
    setState(() => searching = true);
    try {
      final res = await widget.service.searchPackages(q);
      if (!mounted) return;
      setState(() {
        searchResults = res;
        searching = false;
      });
    } catch (e) {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _updateLists() async {
    showDialog(
      context: context,
      barrierDismissible: false,
       builder: (ctx) => AlertDialog(
          content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Text(_t('Обновление списков...'))]),
      ),
    );
    try {
      await widget.service.updatePackageLists();
      if (!mounted) return;
      Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t('Списки пакетов обновлены'))));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка')}: $e')));
    }
  }

  Future<void> _install(PackageInfo pkg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text(_t('Установить пакет?')),
        content: Text('${pkg.name} ${pkg.version}'),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
           FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Установить'))),
        ],
      ),
    );
    if (ok != true) return;
    _showProgress('${_t('Установка')} ${pkg.name}...');
    try {
      await widget.service.installPackage(pkg.name);
      if (!mounted) return;
      Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${pkg.name} ${_t('установлен')}')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка')}: $e')));
    }
  }

  Future<void> _remove(PackageInfo pkg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text(_t('Удалить пакет?')),
        content: Text('${pkg.name} ${pkg.version}'),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
           FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Удалить'))),
        ],
      ),
    );
    if (ok != true) return;
    _showProgress('${_t('Удаление')} ${pkg.name}...');
    try {
      await widget.service.removePackage(pkg.name);
      if (!mounted) return;
      Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${pkg.name} ${_t('удалён')}')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка')}: $e')));
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
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
            SliverAppBar.large(
              title: Text(s.packages),
              actions: [
                IconButton(onPressed: _updateLists, icon: const Icon(Icons.download)),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
              bottom: TabBar(
                onTap: (i) => setState(() => _tabIndex = i),
               tabs: [
                   Tab(icon: const Icon(Icons.check_circle), text: _t('Установленные')),
                   Tab(icon: const Icon(Icons.fact_check), text: _t('Нужные')),
                   Tab(icon: const Icon(Icons.search), text: _t('Поиск')),
                ],
              ),
            ),
          ],
          body: loading && _tabIndex == 0
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    AppCardSkeleton(),
                    AppCardSkeleton(),
                    AppCardSkeleton(),
                  ],
                )
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
    if (installed.isEmpty && !loading) {
      return EmptyState(
        asset: 'assets/empty_states/no_logs.png',
        title: _t('Список пакетов пуст'),
        message: _t('Не удалось получить список установленных пакетов'),
        icon: Icons.refresh,
        actionLabel: _t('Обновить'),
        onAction: _load,
      );
    }
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
                     Text(_t('Память overlay'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
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
                   Text('${_t('Свободно:')} ${d['free'] ?? '-'} • ${_t('Занято:')} ${d['used'] ?? '-'} • ${_t('Всего:')} ${d['total'] ?? '-'}',
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
      key: ValueKey(_neededKey),
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
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('${_t('Ошибка')}: ${snap.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => setState(() => _neededKey = DateTime.now().millisecondsSinceEpoch),
                    child: Text(_t('Повторить')),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final deps = snap.data!['deps'] as Map<String, bool>;
        final repo = snap.data!['repo'] as Map<String, String>;
        final entries = deps.entries.where((e) => e.key != 'ubus').toList();
        return RefreshIndicator(
          onRefresh: () async { setState(() => _neededKey = DateTime.now().millisecondsSinceEpoch); },
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
                 if (rs == 'in_repo') { subtitle = '→ $pn (${_t('в репозитории')})'; }
                 else if (rs != null && rs.startsWith('alt:')) { subtitle = '→ ${rs.substring(4)} (${_t('альтернатива')})'; installPkg = rs.substring(4); }
                 else if (rs == 'missing') { subtitle = _t('Нет в репозитории'); installPkg = ''; }
                 else { subtitle = _t('проверка...'); }
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
                         if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$installPkg ${_t('установлен')}'))); }
                      } catch (e) {
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_t('Ошибка')}: $e')));
                      }
                    },
                     child: Text(_t('Уст.')),
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
             hintText: _t('Название пакета'),
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
                         ? Chip(label: Text(_t('Установлен')), visualDensity: VisualDensity.compact)
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
             Text(_t('Ошибка'), style: theme.textTheme.titleMedium),
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
             FilledButton.tonal(onPressed: _load, child: Text(_t('Повторить'))),
          ],
        ),
      ),
    );
  }
}
