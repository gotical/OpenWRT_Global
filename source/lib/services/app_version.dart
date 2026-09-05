/// Сервис для получения текущей версии приложения.
///
/// Использует const-значения VERSION/BUILD, обновляемые при каждом релизе.
/// (pubspec.yaml недоступен через rootBundle в release-сборках.)
///
/// Используется в:
/// - AppBar / Drawer / Splash (отображение "v4.4.1")
/// - AboutScreen (полная информация)
/// - UpdateService (сравнение с серверной версией)
class AppVersion {
  /// Мажорная версия (например "4.4.1").
  static const String version = '4.4.4';

  /// Код сборки (например "428"). Из pubspec.yaml: `version: 4.4.1+428`.
  static const String build = '431';

  /// Полная строка для отображения: "v4.4.1 (428)".
  static String get display => 'v$version ($build)';
}
