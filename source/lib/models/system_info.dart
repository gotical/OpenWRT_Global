class SystemInfo {
  final String hostname;
  final String model;
  final String firmwareVersion;
  final String kernelVersion;
  final String uptime;
  final double cpuLoad;
  final int memoryTotal;
  final int memoryFree;
  final int memoryUsed;

  SystemInfo({
    required this.hostname,
    required this.model,
    required this.firmwareVersion,
    required this.kernelVersion,
    required this.uptime,
    required this.cpuLoad,
    required this.memoryTotal,
    required this.memoryFree,
    required this.memoryUsed,
  });

  factory SystemInfo.fromUbusJson(Map<String, dynamic> json) {
    // OpenWrt 24.x возвращает system board как корень, system info тоже может быть корнем
    final Map<String, dynamic> info;
    if (json.containsKey('kernel') || json.containsKey('release')) {
      info = json;
    } else if (json['info'] is Map) {
      info = json['info'] as Map<String, dynamic>;
    } else {
      info = {};
    }

    final system = info['system'] is Map ? info['system'] as Map<String, dynamic> : {};
    final release = info['release'] is Map ? info['release'] as Map<String, dynamic> : {};
    final memory = info['memory'] is Map ? info['memory'] as Map<String, dynamic> : {};

    final memTotal = _toInt(memory['total']);
    final memFree = _toInt(memory['available'] ?? memory['free']);

    return SystemInfo(
      hostname: info['hostname']?.toString() ?? 'OpenWrt',
      model: system['model']?.toString() ?? 'Unknown',
      firmwareVersion: '${release['distribution'] ?? 'OpenWrt'} ${release['version'] ?? ''}'.trim(),
      kernelVersion: release['revision']?.toString() ?? '',
      uptime: _formatUptime(_toInt(info['uptime'])),
      cpuLoad: _parseLoad(info['load']),
      memoryTotal: memTotal,
      memoryFree: memFree,
      memoryUsed: memTotal - memFree,
    );
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static double _parseLoad(dynamic load) {
    if (load is! List || load.isEmpty) return 0.0;
    try {
      final v = load[0];
      if (v == null) return 0.0;
      double d;
      if (v is num) {
        d = v.toDouble();
      } else {
        d = double.tryParse(v.toString()) ?? 0.0;
      }
      // Старые версии OpenWrt возвращают load*65536, новые — уже усреднённое значение
      if (d > 100) d = d / 65536.0;
      return d;
    } catch (_) {
      return 0.0;
    }
  }

  static String _formatUptime(int seconds) {
    if (seconds <= 0) return '0 мин.';
    final d = Duration(seconds: seconds);
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '$days д. $hours ч. $minutes мин.';
    if (hours > 0) return '$hours ч. $minutes мин.';
    return '$minutes мин.';
  }
}
