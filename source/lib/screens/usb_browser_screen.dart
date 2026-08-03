import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/network_info.dart';
import '../services/openwrt_service.dart';

class UsbBrowserScreen extends StatefulWidget {
  final OpenWrtService service;
  final String startPath;

  const UsbBrowserScreen({super.key, required this.service, required this.startPath});

  @override
  State<UsbBrowserScreen> createState() => _UsbBrowserScreenState();
}

class _UsbBrowserScreenState extends State<UsbBrowserScreen> {
  late String _path = widget.startPath;
  List<Map<String, String>> _entries = [];
  bool _loading = true;
  String? _error;

  String get _folderName {
    final t = _path.trim().endsWith('/') ? _path.trim().substring(0, _path.trim().length - 1) : _path.trim();
    final i = t.lastIndexOf('/');
    return i < 0 ? t : t.substring(i + 1);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.service.listUsbDir(_path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _canGoUp => _path.trim() != '/' && !_path.trim().endsWith(':/');

  void _goUp() {
    var p = _path.trim();
    while (p.endsWith('/')) p = p.substring(0, p.length - 1);
    final i = p.lastIndexOf('/');
    setState(() {
      _path = i <= 0 ? '/' : p.substring(0, i);
    });
    _load();
  }

  void _open(Map<String, String> entry) {
    if (entry['isDir'] != '1') return;
    final name = entry['name']!;
    setState(() {
      _path = _path.endsWith('/') ? '$_path$name' : '$_path/$name';
    });
    _load();
  }

  Future<void> _delete(Map<String, String> entry) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text(s.text('Удалить файл?')),
         content: Text('${entry['name']}\n\n${s.text('Это действие нельзя отменить.')}'),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
             child: Text(s.text('Удалить'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final full = _path.endsWith('/') ? '$_path${entry['name']}' : '$_path/${entry['name']}';
    try {
      await widget.service.deleteUsbFile(full);
      if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Удалено:')} ${entry['name']}')));
      _load();
    } catch (e) {
      if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text('Ошибка')}: $e')));
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    final dirs = _entries.where((e) => e['isDir'] == '1').toList();
    final files = _entries.where((e) => e['isDir'] != '1').toList();
    return Scaffold(
      appBar: AppBar(
         title: Text(_folderName.isEmpty ? s.text('USB-накопитель') : _folderName),
      ),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Row(
              children: [
                IconButton(
                  onPressed: _canGoUp ? _goUp : null,
                  icon: const Icon(Icons.arrow_upward),
                   tooltip: s.text('На уровень вверх'),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                   tooltip: s.text('Обновить'),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            Icon(Icons.folder_off_outlined, size: 64, color: theme.colorScheme.outline),
                            const SizedBox(height: 16),
                            Center(child: Text(_error!, textAlign: TextAlign.center)),
                          ],
                        )
                      : _entries.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 120),
                                Icon(Icons.folder_open, size: 64, color: theme.colorScheme.outline),
                                const SizedBox(height: 16),
                                 Center(child: Text(s.text('Папка пуста'))),
                              ],
                            )
                          : ListView.separated(
                              itemCount: dirs.length + files.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final isDir = index < dirs.length;
                                final e = isDir ? dirs[index] : files[index - dirs.length];
                                return ListTile(
                                  leading: Icon(
                                    isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                                    color: isDir ? theme.colorScheme.primary : null,
                                  ),
                                  title: Text(e['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: isDir
                                      ? null
                                      : Text(NetworkInterface.formatBytes(int.tryParse(e['size'] ?? '0') ?? 0)),
                                  trailing: isDir
                                      ? const Icon(Icons.chevron_right)
                                      : IconButton(
                                          icon: const Icon(Icons.delete_outline),
                                           tooltip: s.text('Удалить'),
                                          onPressed: () => _delete(e),
                                        ),
                                  onTap: isDir ? () => _open(e) : () => _snack(e['name']!),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
