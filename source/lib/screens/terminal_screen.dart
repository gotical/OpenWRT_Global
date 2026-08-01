import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import '../services/openwrt_service.dart';

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
  String _output = '';
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;
  bool _connected = false;
  SSHSession? _session;

  @override
  void initState() {
    super.initState();
    _connectShell();
  }

  Future<void> _connectShell() async {
    try {
      final client = widget.service.sshClient;
      if (client == null) {
        _appendOutput('SSH не подключён. Переподключитесь.\n');
        return;
      }
      _session = await client.shell(
        pty: const SSHPtyConfig(
          type: 'xterm-256color',
          width: 120,
          height: 40,
        ),
      );
      _connected = true;
      _appendOutput('=== Терминал OpenWRT Global (Beta) ===\r\n');
      _appendOutput('Для выхода закройте экран\r\n\r\n');

      _stdoutSub = _session!.stdout.listen((data) {
        _appendOutput(utf8.decode(data));
      });
      _stderrSub = _session!.stderr.listen((data) {
        _appendOutput(utf8.decode(data));
      });
      _session!.done.then((_) {
        if (mounted) {
          setState(() => _connected = false);
          _appendOutput('\r\n=== Соединение закрыто ===\r\n');
        }
      }).catchError((_) {
        if (mounted) setState(() => _connected = false);
      });
    } catch (e) {
      _appendOutput('Ошибка подключения: $e\n');
    }
  }

  void _appendOutput(String text) {
    setState(() {
      _output += text;
      if (_output.length > 50000) {
        _output = _output.substring(_output.length - 50000);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 50), curve: Curves.easeOut);
      }
    });
  }

  void _sendCommand(String cmd) {
    if (cmd.isEmpty || _session == null) return;
    try {
      _session!.stdin.add(utf8.encode('$cmd\n'));
    } catch (e) {
      _appendOutput('Ошибка: $e\n');
    }
  }

  void _sendCtrl(int code) {
    if (_session == null) return;
    try {
      _session!.stdin.add(Uint8List.fromList([code]));
    } catch (_) {}
  }

  void _disconnect() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _session?.close();
    _session = null;
    _connected = false;
    setState(() => _output += '\r\n=== Отключено ===\r\n');
  }

  void _clear() {
    setState(() => _output = '');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Терминал (Beta)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clear,
            tooltip: 'Очистить',
          ),
          if (_connected)
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: _disconnect,
              tooltip: 'Отключиться',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: () {},
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: SelectableText(
                    _output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0xFF00FF00),
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
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
                      hintText: _connected ? 'Введите команду...' : 'Терминал не подключён',
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
                  tooltip: 'История ↑',
                ),
                FilledButton(
                  onPressed: _connected && _input.text.isNotEmpty
                      ? () => _sendLine(_input.text)
                      : null,
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctrlBtn(String label, int code) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _connected ? () => _sendCtrl(code) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _connected ? null : Colors.grey)),
        ),
      ),
    );
  }
}