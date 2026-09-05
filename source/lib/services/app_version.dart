import 'package:flutter/services.dart' show rootBundle;

/// Сервис для получения текущей версии приложения.
///
/// Читает `pubspec.yaml` (берёт поле `version:`) и кеширует в памяти.
/// Используется в:
/// - AppBar / Drawer / Splash (отображение "v4.4.0")
/// - AboutScreen (полная информация)
/// - UpdateService (сравнение с серверной версией)
///
/// Не требует package_info_plus — обходится стандартным rootBundle.
class AppVersion {
  static String _version = '0.0.0';
  static String _build = '0';
  static bool _loaded = false;

  /// Мажорная версия (например "4.4.0").
  static String get version => _version;

  /// Код сборки (например "426"). Из pubspec.yaml: `version: 4.4.0+426`.
  static String get build => _build;

  /// Полная строка для отображения: "v4.4.0 (426)".
  static String get display => 'v$_version ($_build)';

  /// Загружает версию из pubspec.yaml. Безопасно вызывать многократно.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final pubspec = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(r'version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?').firstMatch(pubspec);
      if (match != null) {
        _version = match.group(1) ?? '0.0.0';
        _build = match.group(2) ?? '0';
      }
    } catch (_) {
      // ignore
    }
    _loaded = true;
  }

  /// Принудительно перезагрузить (для тестов).
  static void reset() {
    _version = '0.0.0';
    _build = '0';
    _loaded = false;
  }
}
