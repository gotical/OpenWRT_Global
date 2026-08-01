import 'package:wifi_scan/wifi_scan.dart';
import '../models/channel_scan_result.dart';

class WifiScanStatus {
  final bool success;
  final String message;
  final List<ChannelScanResult> results;

  const WifiScanStatus({
    required this.success,
    this.message = '',
    this.results = const [],
  });
}

class LocalWifiScanner {
  static bool _permissionRequested = false;

  static int _wiFiChannelWidthToMhz(WiFiChannelWidth? width) {
    switch (width) {
      case WiFiChannelWidth.mhz20: return 20;
      case WiFiChannelWidth.mhz40: return 40;
      case WiFiChannelWidth.mhz80: return 80;
      case WiFiChannelWidth.mhz160:
      case WiFiChannelWidth.mhz80Plus80: return 160;
      default: return 20;
    }
  }

  static int _freqToChannel(int freq) {
    if (freq >= 2412 && freq <= 2484) return (freq - 2407) ~/ 5;
    if (freq >= 5000 && freq <= 5995) return (freq - 5000) ~/ 5;
    if (freq >= 5940 && freq <= 7125) return (freq - 5940) ~/ 5;
    return 0;
  }

  static int _getCenterChannel(int controlChannel, int width, int centerFreq0) {
    if (width <= 20) return controlChannel;
    if (centerFreq0 > 0) return _freqToChannel(centerFreq0);
    if (controlChannel <= 14) {
      if (controlChannel <= 7) return controlChannel + 2;
      return controlChannel - 2;
    }
    return controlChannel;
  }

  /// Запрос всех необходимых разрешений для WiFi сканирования
  static Future<bool> requestPermissions() async {
    if (_permissionRequested) {
      final can = await WiFiScan.instance.canGetScannedResults(askPermissions: false);
      return can == CanGetScannedResults.yes;
    }
    _permissionRequested = true;

    try {
      // Запрашиваем разрешения через canStartScan (он сам покажет диалог)
      final canStart = await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canStart == CanStartScan.yes) {
        // Дополнительно проверяем доступ к результатам
        final canGet = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
        return canGet == CanGetScannedResults.yes;
      }
      // Если canStartScan не поддерживается, пробуем только canGetScannedResults
      final canGet = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
      return canGet == CanGetScannedResults.yes;
    } catch (e) {
      return false;
    }
  }

  /// Сканирование WiFi с телефона
  static Future<WifiScanStatus> scan() async {
    // Проверяем разрешения
    final canGet = await WiFiScan.instance.canGetScannedResults(askPermissions: false);

    if (canGet == CanGetScannedResults.notSupported) {
      return const WifiScanStatus(
        success: false,
        message: 'Платформа не поддерживает сканирование WiFi.\n'
            'Используйте сканирование с роутера.',
      );
    }

    if (canGet != CanGetScannedResults.yes) {
      // Разрешения не даны — пробуем запросить
      final granted = await requestPermissions();
      if (!granted) {
        // Узнаём причину
        final reason = await WiFiScan.instance.canGetScannedResults(askPermissions: false);
        switch (reason) {
          case CanGetScannedResults.noLocationPermissionDenied:
            return const WifiScanStatus(
              success: false,
              message: 'Разрешения на геолокацию отклонены.\n'
                  'Включите в настройках: Настройки → Приложения → OPENWRT Global → Разрешения → Геолокация → Разрешить',
            );
          case CanGetScannedResults.noLocationPermissionRequired:
          case CanGetScannedResults.noLocationPermissionUpgradeAccuracy:
            return const WifiScanStatus(
              success: false,
              message: 'Требуется разрешение геолокации.\n'
                  'Нажмите "Разрешить" в диалоговом окне.',
            );
          case CanGetScannedResults.noLocationServiceDisabled:
            return const WifiScanStatus(
              success: false,
              message: 'GPS/Геолокация выключена.\n'
                  'Включите GPS в настройках телефона, затем повторите сканирование.\n'
                  '(Android 10+ требует GPS для сканирования WiFi)',
            );
          default:
            return const WifiScanStatus(
              success: false,
              message: 'Не удалось получить разрешения на сканирование WiFi.',
            );
        }
      }
    }

    // Запускаем активное сканирование
    try {
      final canStart = await WiFiScan.instance.canStartScan(askPermissions: false);
      if (canStart == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (_) {}

    // Получаем результаты
    try {
      final results = await WiFiScan.instance.getScannedResults();
      final scans = <ChannelScanResult>[];
      final seen = <String>{};

      for (final ap in results) {
        final bssid = ap.bssid;
        final ssid = ap.ssid;
        final key = '$bssid-$ssid';
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);

        final freq = ap.frequency;
        if (freq == 0) continue;

        final channel = _freqToChannel(freq);
        if (channel == 0) continue;

        final width = _wiFiChannelWidthToMhz(ap.channelWidth);
        final centerCh = _getCenterChannel(channel, width, ap.centerFrequency0 ?? 0);

        scans.add(ChannelScanResult(
          channel: channel,
          frequency: freq,
          width: width,
          centerChannel: centerCh,
          signalStrength: ap.level,
          ssid: ssid,
          bssid: bssid,
          source: 'phone',
        ));
      }

      if (scans.isEmpty) {
        return const WifiScanStatus(
          success: true,
          message: 'Сети не найдены. Убедитесь что WiFi включён и вы находитесь в зоне действия сети.',
          results: [],
        );
      }

      return WifiScanStatus(
        success: true,
        message: 'Найдено сетей: ${scans.length}',
        results: scans,
      );
    } catch (e) {
      return WifiScanStatus(
        success: false,
        message: 'Ошибка сканирования: $e',
      );
    }
  }

  static String bandForChannel(int ch) {
    if (ch <= 14) return '2.4g';
    if (ch <= 165) return '5g';
    return '6g';
  }
}