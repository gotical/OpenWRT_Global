import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_logger.dart';

class ErrorHandler {
  static void handle(dynamic error, [StackTrace? stack]) {
    AppLogger.e('Unhandled error', error, stack);
  }

  /// Человекочитаемое объяснение ошибки вместо сырого e.toString()
  /// (идея из OpenWrtManager OverviewWidgetBase).
  static String friendlyMessage(dynamic error) {
    final s = error?.toString().toLowerCase() ?? '';
    if (s.contains('connection refused') || s.contains('refused')) {
      return 'Подключение отклонено. Проверьте адрес, порт и что SSH включён на роутере.';
    }
    if (s.contains('timed out') || s.contains('timeout')) {
      return 'Таймаут подключения — роутер недоступен по этому адресу. Проверьте сеть.';
    }
    if (s.contains('command not found') || s.contains('not found')) {
      return 'Команда не найдена на роутере. Возможно, старая версия OpenWrt или нужен пакет.';
    }
    if (s.contains('permission denied') || s.contains('auth') || s.contains('password')) {
      return 'Ошибка авторизации. Проверьте логин, пароль или SSH-ключ.';
    }
    if (s.contains('host key') || s.contains('fingerprint')) {
      return 'Не удалось проверить ключ хоста (возможна MITM-атака).';
    }
    if (s.contains('unreachable') || s.contains('no route')) {
      return 'Сеть недоступна — проверьте, что телефон подключён к сети роутера.';
    }
    return s;
  }

  static void copyDiagnostics(BuildContext context, String details) {
    Clipboard.setData(ClipboardData(text: details));
    showSuccess(context, 'Диагностика скопирована');
  }

  static void showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}