import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Цвета терминала (палитра xterm, 16 базовых).
const _baseColors = <Color>[
  Color(0xFF000000), // 0 black
  Color(0xFFCD3131), // 1 red
  Color(0xFF0DBC79), // 2 green
  Color(0xFFE5E510), // 3 yellow
  Color(0xFF2472C8), // 4 blue
  Color(0xFFBC3FBC), // 5 magenta
  Color(0xFF11A8CD), // 6 cyan
  Color(0xFFE5E5E5), // 7 light gray
  Color(0xFF666666), // 8 dark gray
  Color(0xFFF14C4C), // 9 bright red
  Color(0xFF23D18B), // 10 bright green
  Color(0xFFF5F543), // 11 bright yellow
  Color(0xFF3B8EEA), // 12 bright blue
  Color(0xFFD670D6), // 13 bright magenta
  Color(0xFF29B8DB), // 14 bright cyan
  Color(0xFFFFFFFF), // 15 white
];

Color _color256(int index) {
  if (index < 16) return _baseColors[index];
  if (index < 232) {
    final v = index - 16;
    final r = v ~/ 36, g = (v % 36) ~/ 6, b = v % 6;
    int cube(int c) => c == 0 ? 0 : 55 + c * 40;
    return Color(0xFF000000 | (cube(r) << 16) | (cube(g) << 8) | cube(b));
  }
  final gray = 8 + (index - 232) * 10;
  return Color(0xFF000000 | (gray << 16) | (gray << 8) | gray);
}

class TermSpan {
  final String text;
  final Color fg;
  final Color bg;
  final bool bold;
  final bool underline;
  const TermSpan(this.text, {required this.fg, required this.bg, this.bold = false, this.underline = false});
}

class TermLine {
  final List<TermSpan> spans = [];
  bool get isEmpty => spans.isEmpty || spans.every((s) => s.text.isEmpty);
}

/// Простой VT100-эмулятор: обрабатывает ANSI-последовательности и
/// хранит буфер строк с цветами (SGR 0-256, курсор, очистка).
class AnsiEmulator {
  int cols;
  final int maxLines;
  final List<TermLine> lines = [TermLine()];
  int row = 0;
  int col = 0;
  int fg = 7;
  int bg = 0;
  bool bold = false;
  bool underline = false;

  AnsiEmulator({this.cols = 80, this.maxLines = 1000});

  bool _inEsc = false;
  bool _inCsi = false;
  bool _inOsc = false;
  String _seq = '';

  Color get _fgColor => _color256(fg.clamp(0, 255));
  Color get _bgColor => _color256(bg.clamp(0, 255));

  TermLine get _line => lines[row];

  void _ensureLine(int r) {
    while (lines.length <= r) {
      lines.add(TermLine());
    }
  }

  void _truncate() {
    if (lines.length > maxLines) {
      final overflow = lines.length - maxLines;
      lines.removeRange(0, overflow);
      row -= overflow;
      if (row < 0) row = 0;
    }
  }

  void _putChar(String ch) {
    if (col >= cols) {
      _newline();
    }
    final line = _line;
    final curFg = _fgColor, curBg = _bgColor;
    if (line.spans.isNotEmpty) {
      final last = line.spans.last;
      if (last.fg == curFg && last.bg == curBg && last.bold == bold && last.underline == underline) {
        line.spans[line.spans.length - 1] = TermSpan(last.text + ch, fg: last.fg, bg: last.bg, bold: last.bold, underline: last.underline);
        col++;
        return;
      }
    }
    line.spans.add(TermSpan(ch, fg: curFg, bg: curBg, bold: bold, underline: underline));
    col++;
  }

  void _newline() {
    row++;
    col = 0;
    _ensureLine(row);
    _truncate();
  }

  void _cr() => col = 0;

  void _backspace() {
    final line = _line;
    if (col == 0) return;
    col--;
    // Удаляем один символ из последнего сегмента.
    while (line.spans.isNotEmpty) {
      final last = line.spans.removeLast();
      if (last.text.length > 1) {
        final kept = last.text.substring(0, last.text.length - 1);
        if (kept.isNotEmpty) line.spans.add(TermSpan(kept, fg: last.fg, bg: last.bg, bold: last.bold, underline: last.underline));
        break;
      }
      if (line.spans.isEmpty) break;
    }
  }

  void _eraseLine(int mode) {
    final line = _line;
    if (mode == 2) {
      line.spans.clear();
    } else if (mode == 0 || mode == 1) {
      final keep = <TermSpan>[];
      var keptChars = 0;
      for (final s in line.spans) {
        if (mode == 0 && keptChars >= col) continue;
        if (mode == 1 && keptChars + s.text.length <= col) {
          keep.add(s);
          keptChars += s.text.length;
        } else if (mode == 1) {
          final off = col - keptChars;
          if (off > 0) keep.add(TermSpan(s.text.substring(0, off), fg: s.fg, bg: s.bg, bold: s.bold, underline: s.underline));
          break;
        } else {
          keep.add(s);
        }
        keptChars += s.text.length;
      }
      line.spans
        ..clear()
        ..addAll(keep);
    }
  }

  void _eraseScreen(int mode) {
    if (mode == 2) {
      lines
        ..clear()
        ..add(TermLine());
      row = 0;
      col = 0;
    } else if (mode == 0) {
      _eraseLine(0);
      final above = lines.length - 1 - row;
      if (above > 0) lines.removeRange(row + 1, lines.length);
    } else if (mode == 1) {
      _eraseLine(1);
      final above = row;
      if (above > 0) lines.removeRange(0, above);
      row = 0;
    }
  }

  void _cursorUp(int n) {
    row -= n;
    if (row < 0) row = 0;
  }

  void _cursorDown(int n) {
    row += n;
    _ensureLine(row);
  }

  void _cursorForward(int n) {
    col += n;
    if (col > cols) col = cols;
  }

  void _cursorBack(int n) {
    col -= n;
    if (col < 0) col = 0;
  }

  void _cursorSet(int r, int c) {
    row = (r <= 0 ? 0 : r - 1);
    col = (c <= 0 ? 0 : c - 1);
    if (col >= cols) col = cols - 1;
    _ensureLine(row);
  }

  void _applySgr(List<int> params) {
    if (params.isEmpty) params = [0];
    var i = 0;
    while (i < params.length) {
      final p = params[i];
      if (p == 0) {
        fg = 7; bg = 0; bold = false; underline = false;
      } else if (p == 1) {
        bold = true;
      } else if (p == 4) {
        underline = true;
      } else if (p == 7) {
        final t = fg; fg = bg; bg = t;
      } else if (p == 22) {
        bold = false;
      } else if (p == 24) {
        underline = false;
      } else if (p == 27) {
        final t = fg; fg = bg; bg = t;
      } else if (p >= 30 && p <= 37) {
        fg = p - 30;
      } else if (p >= 90 && p <= 97) {
        fg = p - 90 + 8;
      } else if (p >= 40 && p <= 47) {
        bg = p - 40;
      } else if (p >= 100 && p <= 107) {
        bg = p - 100 + 8;
      } else if (p == 38 || p == 48) {
        if (i + 1 < params.length) {
          if (params[i + 1] == 5 && i + 2 < params.length) {
            final v = params[i + 2].clamp(0, 255);
            if (p == 38) fg = v; else bg = v;
            i += 2;
          } else if (params[i + 1] == 2 && i + 4 < params.length) {
            final r = params[i + 2].clamp(0, 255), g = params[i + 3].clamp(0, 255), b = params[i + 4].clamp(0, 255);
            if (p == 38) {
              fg = 16 + (r ~/ 36) * 36 + (g ~/ 36) * 6 + b ~/ 36;
            } else {
              bg = 16 + (r ~/ 36) * 36 + (g ~/ 36) * 6 + b ~/ 36;
            }
            i += 4;
          }
        }
      }
      i++;
    }
  }

  /// Подать фрагмент вывода терминала.
  void feed(String text) {
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (_inEsc) {
        if (_seq == '') {
          if (ch == '[') {
            _inCsi = true;
            _inEsc = false;
            _seq = '';
            continue;
          }
          if (ch == ']') {
            _inOsc = true;
            _inEsc = false;
            _seq = '';
            continue;
          }
          if (ch == '(' || ch == ')' || ch == '#' || ch == '%' || ch == '>' || ch == '=' || ch == '<') {
            _seq = ch; // выбор кодировки/клавиатуры — ждём и игнорируем следующий символ
            continue;
          }
          _inEsc = false;
          _seq = '';
          continue; // одиночная ESC-последовательность — игнорируем
        }
        _inEsc = false;
        _seq = '';
        continue;
      }
      if (_inOsc) {
        _seq += ch;
        if (ch == '\u0007' || (_seq.length > 1 && _seq.endsWith('\x1b\\'))) {
          _inOsc = false;
          _seq = '';
        } else if (_seq.length > 4096) {
          _inOsc = false;
          _seq = '';
        }
        continue;
      }
      if (_inCsi) {
        if (ch == '?' || ch == '>' || ch == '=' || ch == '!' || ch == ' ' || ch == '#' || ch == ';' || ch == ':' ||
            (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x3F)) {
          _seq += ch;
          continue;
        }
        _inCsi = false;
        _handleCsi(_seq, ch);
        _seq = '';
        continue;
      }
      if (ch == '\x1b') {
        _inEsc = true;
        _seq = '';
        continue;
      }
      final cu = ch.codeUnitAt(0);
      if (cu == 0x0A) {
        _newline();
      } else if (cu == 0x0D) {
        _cr();
      } else if (cu == 0x08) {
        _backspace();
      } else if (cu == 0x09) {
        final next = ((col ~/ 8) + 1) * 8;
        while (col < next) _putChar(' ');
      } else if (cu < 0x20) {
        // прочие управляющие — игнорируем
      } else {
        _putChar(ch);
      }
    }
  }

  void _handleCsi(String seq, String code) {
    // Возможен стартовый промежуточный символ, отбрасываем '?' и т.п. (сохранён в seq)
    final cleaned = seq.replaceAll('?', '').replaceAll('>', '').replaceAll('=', '').replaceAll('!', '').replaceAll(' ', '').replaceAll('#', '');
    final parts = cleaned.split(';');
    final params = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      params.add(v ?? 0);
    }
    final n = params.isNotEmpty && params[0] > 0 ? params[0] : 1;
    switch (code) {
      case 'A': _cursorUp(n);
      case 'B': _cursorDown(n);
      case 'C': _cursorForward(n);
      case 'D': _cursorBack(n);
      case 'G': case '`': col = (params[0] <= 0 ? 0 : params[0] - 1); if (col >= cols) col = cols - 1;
      case 'H': case 'f': _cursorSet(params.isNotEmpty ? params[0] : 1, params.length > 1 ? params[1] : 1);
      case 'J': _eraseScreen(params.isNotEmpty ? params[0] : 0);
      case 'K': _eraseLine(params.isNotEmpty ? params[0] : 0);
      case 'm': _applySgr(params);
      case 'r': case 's': case 'u': case 'l': case 'h': case 'd': case 'X': break; // режимы/скролл — игнорируем
      default: break;
    }
  }

  /// Полный текст (для копирования).
  String get plainText => lines.map((l) => l.spans.map((s) => s.text).join()).join('\n').trimRight();

  void clear() {
    lines
      ..clear()
      ..add(TermLine());
    row = 0;
    col = 0;
    fg = 7; bg = 0; bold = false; underline = false;
  }
}

/// Контроллер терминала для виджета.
class AnsiTerminalController extends ChangeNotifier {
  final AnsiEmulator emulator;
  AnsiTerminalController({int cols = 80, int maxLines = 1000})
      : emulator = AnsiEmulator(cols: cols, maxLines: maxLines);

  void feed(String text) {
    emulator.feed(text);
    notifyListeners();
  }

  void clear() {
    emulator.clear();
    notifyListeners();
  }

  String get plainText => emulator.plainText;
}

/// Отрисовка буфера терминала.
class AnsiTerminalView extends StatelessWidget {
  final AnsiTerminalController controller;
  final ScrollController scrollController;
  final TextStyle? baseStyle;

  const AnsiTerminalView({super.key, required this.controller, required this.scrollController, this.baseStyle});

  @override
  Widget build(BuildContext context) {
    final lines = controller.emulator.lines;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                SizedBox(
                  width: double.infinity,
                  child: RichText(
                    textScaleFactor: 1.0,
                    maxLines: 1,
                    text: TextSpan(
                      style: baseStyle,
                      children: line.spans.isEmpty
                          ? [const TextSpan(text: '\u00A0')]
                          : line.spans
                              .map((s) => TextSpan(
                                    text: s.text,
                                    style: TextStyle(
                                      color: s.fg,
                                      backgroundColor: s.bg,
                                      fontWeight: s.bold ? FontWeight.bold : FontWeight.normal,
                                      decoration: s.underline ? TextDecoration.underline : null,
                                    ),
                                  ))
                              .toList(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
