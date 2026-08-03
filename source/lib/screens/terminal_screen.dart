import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_strings.dart';
import '../services/openwrt_service.dart';
import '../widgets/ansi_terminal.dart';

class TerminalScreen extends StatefulWidget {
  final OpenWrtService service;

  const TerminalScreen({super.key, required this.service});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final List<String> _history = [];
  int _historyIndex = -1;
  AnsiTerminalController? _term;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _connected = false;
  bool _ctrl = false;
  bool _shift = false;
  bool _started = false;
  SSHSession? _session;

  static const _letters = [
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  ];

  @override
  void initState() {
    super.initState();
    _term = AnsiTerminalController(cols: 80);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final width = MediaQuery.of(context).size.width;
    _term!.emulator.cols = (width / 7.8).floor().clamp(40, 160);
    _connectShell();
  }

  Future<void> _connectShell() async {
    final s = AppStrings.of(context);
    try {
      final client = widget.service.sshClient;
      if (client == null) {
        _appendOutput('${s.text('SSH не подключён. Переподключитесь.')}\n');
        return;
      }
      _session = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: _term!.emulator.cols,
          height: 40,
        ),
      );
      _connected = true;
      _appendOutput('=== ${s.text('Терминал (Beta)')} OpenWRT Global ===\r\n');
      _appendOutput('${s.text('Для выхода закройте экран')}\r\n\r\n');

      _stdoutSub = _session!.stdout.cast<List<int>>().transform(utf8.decoder).listen((data) {
        _appendOutput(data);
      });
      _stderrSub = _session!.stderr.cast<List<int>>().transform(utf8.decoder).listen((data) {
        _appendOutput(data);
      });
      _session!.done.then((_) {
        if (mounted) {
          setState(() => _connected = false);
          _appendOutput('\r\n=== ${s.text('Соединение закрыто')} ===\r\n');
        }
      }).catchError((_) {
        if (mounted) setState(() => _connected = false);
      });
    } catch (e) {
      _appendOutput('${s.text('Ошибка подключения')}: $e\n');
    }
  }

  void _appendOutput(String text) {
    _term?.feed(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 40), curve: Curves.easeOut);
      }
    });
  }

  void _sendCommand(String cmd) {
    if (cmd.isEmpty || _session == null) return;
    try {
      _session!.stdin.add(utf8.encode('$cmd\n'));
    } catch (e) {
      _appendOutput('${AppStrings.of(context).text('Ошибка')}: $e\n');
    }
  }

  void _sendCtrl(int code) {
    if (_session == null) return;
    try {
      _session!.stdin.add(Uint8List.fromList([code]));
    } catch (_) {}
  }

  void _sendRaw(String text) {
    if (_session == null) return;
    try {
      _session!.stdin.add(utf8.encode(text));
    } catch (_) {}
  }

  void _sendLetter(String letter) {
    if (_session == null) return;
    if (_ctrl) {
      // Ctrl + буква → управляющий код (0x01..0x1A)
      _sendCtrl(letter.toLowerCase().codeUnitAt(0) & 0x1F);
      setState(() => _ctrl = false);
    } else {
      _sendRaw(_shift ? letter.toUpperCase() : letter);
      setState(() => _shift = false);
    }
  }

  void _disconnect() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _session?.close();
    _session = null;
    _connected = false;
    _appendOutput('\r\n=== ${AppStrings.of(context).text('Отключено')} ===\r\n');
  }

  void _clear() {
    _term?.clear();
  }

  void _copy() {
    final text = _term?.plainText ?? '';
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.of(context).text('Скопировано в буфер')),
        ));
      }
    }
  }

  void _sendLine(String line) {
    if (line.isNotEmpty) {
      _history.removeWhere((e) => e == line);
      _history.add(line);
      _historyIndex = _history.length;
    }
    _sendCommand(line);
    _input.clear();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _session?.close();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.text('Терминал (Beta)')),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_copy),
            onPressed: _copy,
            tooltip: s.text('Скопировать'),
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clear,
            tooltip: s.text('Очистить'),
          ),
          if (_connected)
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: _disconnect,
              tooltip: s.text('Отключиться'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(8),
              child: AnsiTerminalView(
                controller: _term!,
                scrollController: _scroll,
                baseStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _modBtn('Ctrl', _ctrl, () => setState(() => _ctrl = !_ctrl)),
                    const SizedBox(width: 4),
                    _modBtn('Shift', _shift, () => setState(() => _shift = !_shift)),
                    const SizedBox(width: 4),
                    _ctrlBtn('^C', 3),
                    const SizedBox(width: 2),
                    _ctrlBtn('^D', 4),
                    const SizedBox(width: 2),
                    _ctrlBtn('^Z', 26),
                    const SizedBox(width: 2),
                    _ctrlBtn('^L', 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: _connected,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _connected ? s.text('Введите команду...') : s.text('Терминал не подключён'),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onSubmitted: _sendLine,
                        onChanged: (_) => _historyIndex = _history.length,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      onPressed: _connected
                          ? () {
                              if (_history.isNotEmpty && _historyIndex > 0) {
                                _historyIndex--;
                                _input.text = _history[_historyIndex];
                                _input.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _input.text.length));
                              }
                            }
                          : null,
                      tooltip: s.text('История ↑'),
                    ),
                    FilledButton(
                      onPressed: _connected && _input.text.isNotEmpty
                          ? () => _sendLine(_input.text)
                          : null,
                      child: const Text('OK'),
                    ),
                  ],
                ),
                if (_ctrl || _shift) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final letter in _letters)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Material(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: _connected ? () => _sendLetter(letter) : null,
                                child: Container(
                                  width: 30,
                                  alignment: Alignment.center,
                                  child: Text(
                                    _ctrl ? 'Ctrl+${letter.toUpperCase()}' : (_shift ? letter.toUpperCase() : letter),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _connected ? theme.colorScheme.onPrimaryContainer : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modBtn(String label, bool active, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Material(
      color: active ? theme.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: active ? theme.colorScheme.primary : Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: active ? theme.colorScheme.onPrimary : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ctrlBtn(String label, int code) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _connected ? () => _sendCtrl(code) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _connected ? (theme.brightness == Brightness.dark ? Colors.white70 : Colors.black54) : Colors.grey,
              )),
        ),
      ),
    );
  }
}
