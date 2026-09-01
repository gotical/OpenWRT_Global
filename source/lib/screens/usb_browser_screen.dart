import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../l10n/app_strings.dart';
import '../models/network_info.dart';
import '../services/openwrt_service.dart';

/// Полноценный файловый менеджер для USB/SSD/HDD накопителей роутера:
/// навигация, скачивание, загрузка, переименование, создание папок,
/// удаление, информация и форматирование.
class UsbBrowserScreen extends StatefulWidget {
  final OpenWrtService service;
  final String startPath;
  final String? devicePath; // /dev/sda1 и т.п. — для форматирования

  const UsbBrowserScreen({
    super.key,
    required this.service,
    required this.startPath,
    this.devicePath,
  });

  @override
  State<UsbBrowserScreen> createState() => _UsbBrowserScreenState();
}

class _UsbBrowserScreenState extends State<UsbBrowserScreen> {
  late String _path = widget.startPath;
  List<Map<String, String>> _entries = [];
  bool _loading = true;
  String? _error;
  Map<String, bool> _busy = {};
  Map<String, String> _disk = {};

  String get _folderName {
    final t = _path.trim().endsWith('/')
        ? _path.trim().substring(0, _path.trim().length - 1)
        : _path.trim();
    final i = t.lastIndexOf('/');
    return i < 0 ? t : t.substring(i + 1);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadDiskStats();
  }

  Future<void> _loadDiskStats() async {
    try {
      final d = await widget.service.diskStats(_path);
      if (mounted) setState(() => _disk = d);
    } catch (_) {}
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
      _loadDiskStats();
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

  String _full(String name) => _path.endsWith('/') ? '$_path$name' : '$_path/$name';

  Future<void> _download(Map<String, String> entry) async {
    if (_busy['op'] == true) return;
    _busy['op'] = true;
    final s = AppStrings.of(context);
    if (entry['isDir'] == '1') { _busy['op'] = false; return; }
    Directory? dir;
    try {
      dir = await getExternalStorageDirectory();
    } catch (_) {}
    if (dir == null) {
      _snack(s.text('Не удалось получить каталог для сохранения'));
      _busy['op'] = false;
      return;
    }
    final base = dir.path;
    var name = entry['name']!;
    if (name.contains('/')) name = name.split('/').last;
    var dest = File('$base/$name');
    var dup = 1;
    final stem = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
    while (dest.existsSync()) {
      dest = File('$base/${stem}_$dup$ext');
      dup++;
    }

    final sink = dest.openWrite();
    final dlgKey = GlobalKey<_ProgressDialogState>();
    final dlg = _ProgressDialog(key: dlgKey, title: s.text('Скачивание'), label: name);
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => dlg);
    try {
      await widget.service.downloadFile(
        remotePath: _full(entry['name']!),
        localSink: sink,
        onProgress: (d, t) => dlgKey.currentState?.update(d, t),
      );
      await sink.flush();
      await sink.close();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _snack('${s.text('Сохранено:')} $dest', ok: true);
    } catch (e) {
      try { await sink.flush(); } catch (_) {}
      try { await sink.close(); } catch (_) {}
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _snack('${s.text('Ошибка')}: $e');
    } finally {
      _busy['op'] = false;
    }
  }

  Future<void> _upload() async {
    if (_busy['op'] == true) return;
    final s = AppStrings.of(context);
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    final path = f.path;
    if (path == null) {
      _snack(s.text('Не удалось открыть файл'));
      return;
    }
    final file = File(path);
    final size = await file.length();
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    bool sftpOk;
    try {
      sftpOk = await widget.service.sftpAvailable();
    } catch (e) {
      if (mounted) _snack('${s.text('Ошибка')}: $e');
      return;
    }
    if (!sftpOk) {
      if (mounted) _snack(s.text('Для загрузки нужен openssh-sftp-server на роутере'));
      return;
    }

    _busy['op'] = true;
    final dlgKey = GlobalKey<_ProgressDialogState>();
    final dlg = _ProgressDialog(key: dlgKey, title: s.text('Загрузка'), label: f.name, total: size);
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => dlg);
    try {
      await widget.service.uploadFileSftp(
        remotePath: _full(f.name),
        data: bytes,
        onProgress: (d, _) => dlgKey.currentState?.update(d, size),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _snack('${s.text('Загружено:')} ${f.name}', ok: true);
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _snack('${s.text('Ошибка')}: $e');
    } finally {
      _busy['op'] = false;
    }
  }

  Future<void> _rename(Map<String, String> entry) async {
    final s = AppStrings.of(context);
    final ctrl = TextEditingController(text: entry['name']!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('Переименовать')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.text('Сохранить'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final newName = ctrl.text.trim();
    if (newName.isEmpty || newName == entry['name']) return;
    try {
      await widget.service.renamePath(_full(entry['name']!), _full(newName));
      _snack(s.text('Переименовано'), ok: true);
      await _load();
    } catch (e) {
      _snack('${s.text('Ошибка')}: $e');
    }
  }

  Future<void> _newFolder() async {
    final s = AppStrings.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('Новая папка')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.text('Создать'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    try {
      await widget.service.makeDir(_full(name));
      _snack(s.text('Создано'), ok: true);
      await _load();
    } catch (e) {
      _snack('${s.text('Ошибка')}: $e');
    }
  }

  Future<void> _delete(Map<String, String> entry) async {
    final s = AppStrings.of(context);
    final isDir = entry['isDir'] == '1';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDir ? s.text('Удалить папку?') : s.text('Удалить файл?')),
        content: Text('${entry['name']}\n\n${s.text('Это действие нельзя отменить.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.text('Удалить'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.removePath(_full(entry['name']!), directory: isDir);
      _snack('${s.text('Удалено:')} ${entry['name']}');
      await _load();
    } catch (e) {
      _snack('${s.text('Ошибка')}: $e');
    }
  }

  Future<void> _info(Map<String, String> entry) async {
    final s = AppStrings.of(context);
    final full = _full(entry['name']!);
    int sizeBytes = 0;
    if (entry['isDir'] != '1') {
      try {
        sizeBytes = await widget.service.getRemoteFileSize(full);
      } catch (_) {}
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('Информация')),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _infoRow(s.text('Имя'), entry['name']!),
            _infoRow(s.text('Тип'), entry['isDir'] == '1' ? s.text('Папка') : s.text('Файл')),
            if (entry['isDir'] != '1') _infoRow(s.text('Размер'), NetworkInterface.formatBytes(sizeBytes)),
            _infoRow(s.text('Путь'), full),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('Закрыть')))],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Future<void> _format() async {
    final s = AppStrings.of(context);
    final device = widget.devicePath ?? '';
    if (device.isEmpty) {
      _snack(s.text('Устройство не найдено'));
      return;
    }
    String? fs;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          icon: const Icon(Icons.warning_amber, color: Colors.red, size: 40),
          title: Text(s.text('Форматирование')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.text('Все данные на')} $device ${s.text('будут удалены!')}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 12),
              Text(s.text('Выберите файловую систему:')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: fs,
                isExpanded: true,
                items: OpenWrtService.supportedFileSystems.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setSt(() => fs = v),
              ),
              const SizedBox(height: 8),
              Text(s.text('Накопитель должен быть размонтирован.'),
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('Отмена'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: fs == null ? null : () => Navigator.pop(ctx, true),
              child: Text(s.text('Форматировать')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || fs == null) return;
    _showProgress(s.text('Форматирование...'));
    try {
      await widget.service.formatDevice(device, fs!);
      if (!mounted) return;
      Navigator.pop(context);
      _snack('${s.text('Отформатировано')}: $device (${OpenWrtService.supportedFileSystems[fs]!})', ok: true);
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('${s.text('Ошибка')}: $e');
    }
  }

  void _showProgress(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Expanded(child: Text(msg))]),
      ),
    );
  }

  void _snack(String m, {bool ok = false}) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: ok ? Colors.green.shade700 : null),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    final dirs = _entries.where((e) => e['isDir'] == '1').toList();
    final files = _entries.where((e) => e['isDir'] != '1').toList();
    final usePct = _disk['use']?.replaceAll('%', '');
    final useVal = double.tryParse(usePct ?? '');
    return Scaffold(
      appBar: AppBar(
        title: Text(_folderName.isEmpty ? s.text('USB-накопитель') : _folderName),
        actions: [
          IconButton(icon: const Icon(Icons.upload_file), tooltip: s.text('Загрузить файл'), onPressed: _upload),
          IconButton(icon: const Icon(Icons.create_new_folder), tooltip: s.text('Новая папка'), onPressed: _newFolder),
          if (widget.devicePath != null)
            IconButton(
                icon: const Icon(Icons.drive_file_rename_outline), tooltip: s.text('Форматировать'), onPressed: _format),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          // Путь и занятость диска
          Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(onPressed: _canGoUp ? _goUp : null, icon: const Icon(Icons.arrow_upward), tooltip: s.text('На уровень вверх')),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(_path, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                    ),
                  ),
                ]),
                if (_disk.isNotEmpty && useVal != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(children: [
                      const Icon(Icons.storage, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (useVal / 100).clamp(0, 1),
                            minHeight: 6,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(useVal > 85 ? Colors.red : theme.colorScheme.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${useVal.toStringAsFixed(0)}%', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 6),
                      Text('${s.text('свободно')} ${_disk['avail'] ?? '-'}M', style: theme.textTheme.bodySmall),
                    ]),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? ListView(children: [for (var i = 0; i < 6; i++) const ListTile(leading: CircleAvatar(), title: SizedBox(height: 14, child: AppSkeletonShim()))])
                  : _error != null
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          Icon(Icons.folder_off_outlined, size: 64, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          Center(child: Text(_error!, textAlign: TextAlign.center)),
                        ])
                      : _entries.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 120),
                              Icon(Icons.folder_open, size: 64, color: theme.colorScheme.outline),
                              const SizedBox(height: 16),
                              Center(child: Text(s.text('Папка пуста'))),
                            ])
                          : ListView.separated(
                              itemCount: dirs.length + files.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final isDir = index < dirs.length;
                                final e = isDir ? dirs[index] : files[index - dirs.length];
                                final sizeB = int.tryParse(e['size'] ?? '0') ?? 0;
                                return ListTile(
                                  leading: Icon(
                                    isDir ? Icons.folder : _fileIcon(e['name']!.toLowerCase(), e['mode'] ?? ''),
                                    color: isDir ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  title: Text(e['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: isDir ? null : Text(NetworkInterface.formatBytes(sizeB), style: theme.textTheme.bodySmall),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert),
                                    onSelected: (v) {
                                      if (v == 'download' && !isDir) _download(e);
                                      if (v == 'rename') _rename(e);
                                      if (v == 'info') _info(e);
                                      if (v == 'delete') _delete(e);
                                    },
                                    itemBuilder: (ctx) => [
                                      if (!isDir)
                                        PopupMenuItem(value: 'download', child: ListTile(leading: const Icon(Icons.download), title: Text(s.text('Скачать')))),
                                      PopupMenuItem(value: 'rename', child: ListTile(leading: const Icon(Icons.edit), title: Text(s.text('Переименовать')))),
                                      PopupMenuItem(value: 'info', child: ListTile(leading: const Icon(Icons.info_outline), title: Text(s.text('Информация')))),
                                      PopupMenuItem(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(s.text('Удалить')))),
                                    ],
                                  ),
                                  onTap: isDir ? () => _open(e) : () => _info(e),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String name, String perms) {
    if (perms.startsWith('l')) return Icons.link;
    if (name.endsWith('.mp4') || name.endsWith('.mkv') || name.endsWith('.avi') || name.endsWith('.mov')) return Icons.movie;
    if (name.endsWith('.jpg') || name.endsWith('.png') || name.endsWith('.gif') || name.endsWith('.webp') || name.endsWith('.jpeg')) return Icons.image;
    if (name.endsWith('.mp3') || name.endsWith('.wav') || name.endsWith('.flac') || name.endsWith('.ogg')) return Icons.music_note;
    if (name.endsWith('.zip') || name.endsWith('.tar') || name.endsWith('.gz') || name.endsWith('.7z') || name.endsWith('.rar')) return Icons.archive;
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (name.endsWith('.txt') || name.endsWith('.conf') || name.endsWith('.log') || name.endsWith('.md')) return Icons.description;
    if (name.endsWith('.apk') || name.endsWith('.deb')) return Icons.android;
    if (name.endsWith('.iso') || name.endsWith('.img')) return Icons.disc_full;
    return Icons.insert_drive_file_outlined;
  }
}

/// Диалог с живым прогрессом переноса файла.
class _ProgressDialog extends StatefulWidget {
  final String title;
  final String label;
  final int? total;
  const _ProgressDialog({super.key, required this.title, required this.label, this.total});

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  int _done = 0;
  int? _total;
  final DateTime _start = DateTime.now();

  void update(int done, int? total) {
    if (!mounted) return;
    setState(() {
      _done = done;
      _total = total;
    });
  }

  double? get _pct {
    final t = _total ?? widget.total;
    if (t == null || t <= 0) return null;
    return (_done / t).clamp(0.0, 1.0);
  }

  double? get _speedMbps {
    final secs = DateTime.now().difference(_start).inMilliseconds / 1000.0;
    if (secs <= 0 || _done <= 0) return null;
    return (_done * 8 / secs / 1000000);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final total = _total ?? widget.total;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _pct),
          const SizedBox(height: 8),
          Text(
            '${NetworkInterface.formatBytes(_done)} / ${total != null ? NetworkInterface.formatBytes(total) : '...'}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            _speedMbps != null ? '${_speedMbps!.toStringAsFixed(1)} ${s.text('Мбит/с')}' : '',
            style: const TextStyle(fontSize: 12, color: Colors.green),
          ),
        ]),
      ),
    );
  }
}

/// Простая shimmer-заглушка для строк списка.
class AppSkeletonShim extends StatelessWidget {
  const AppSkeletonShim({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}
