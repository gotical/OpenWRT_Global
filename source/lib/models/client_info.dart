import 'package:intl/intl.dart';

class ClientInfo {
  final String hostname;
  final String mac;
  final String? ip;
  final String? interface;
  final int? leaseExpiry;
  final bool active;
  final int rxBytes;
  final int txBytes;
  final int? signal;
  final String? connectionType; // 'Wi-Fi 2.4GHz', 'Wi-Fi 5GHz', 'Wi-Fi 6GHz', 'LAN'
  final String? accessPoint; // hostapd iface / radio / iface name
  final double? dlSpeed; // Мбит/с (скорость скачивания клиента)
  final double? ulSpeed; // Мбит/с (скорость загрузки клиента)
  final String? rxBitrate; // текущий битрейт приёма (напр. "585.0 MBit/s")
  final String? txBitrate; // текущий битрейт передачи
  final int monthRxBytes; // трафик за месяц (nlbw)
  final int monthTxBytes;
  final int? frequency; // частота WiFi в MHz

  ClientInfo({
    required this.hostname,
    required this.mac,
    this.ip,
    this.interface,
    this.leaseExpiry,
    this.active = true,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.signal,
    this.connectionType,
    this.accessPoint,
    this.dlSpeed,
    this.ulSpeed,
    this.rxBitrate,
    this.txBitrate,
    this.monthRxBytes = 0,
    this.monthTxBytes = 0,
    this.frequency,
  });

  int get totalBytes => rxBytes + txBytes;
  int get monthTotalBytes => monthRxBytes + monthTxBytes;

  bool get isWifi => connectionType?.contains('Wi-Fi') ?? false;
  bool get isLan => !isWifi;

  String get bandLabel {
    if (!isWifi) return 'LAN';
    return connectionType ?? 'Wi-Fi';
  }

  String get rxHuman => _formatBytes(rxBytes);
  String get txHuman => _formatBytes(txBytes);
  String get totalHuman => _formatBytes(totalBytes);
  String get monthRxHuman => _formatBytes(monthRxBytes);
  String get monthTxHuman => _formatBytes(monthTxBytes);
  String get monthTotalHuman => _formatBytes(monthTotalBytes);

  String get dlSpeedHuman =>
      dlSpeed != null ? '${dlSpeed!.toStringAsFixed(1)} Мбит/с' : '—';
  String get ulSpeedHuman =>
      ulSpeed != null ? '${ulSpeed!.toStringAsFixed(1)} Мбит/с' : '—';

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${NumberFormat('#0.0').format(d)} ${suffixes[i]}';
  }
}