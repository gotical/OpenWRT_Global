import 'package:logger/logger.dart';

class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 120,
      colors: true,
      printEmojis: false,
    ),
  );

  static void d(String message, [dynamic error, StackTrace? stack]) =>
      _logger.d(message, error: error, stackTrace: stack);

  static void i(String message) => _logger.i(message);

  static void w(String message, [dynamic error, StackTrace? stack]) =>
      _logger.w(message, error: error, stackTrace: stack);

  static void e(String message, [dynamic error, StackTrace? stack]) =>
      _logger.e(message, error: error, stackTrace: stack);
}