import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/system_info.dart';
import '../models/wifi_info.dart';
import '../models/client_info.dart';
import '../models/vpn_info.dart';
import '../models/network_info.dart';
import '../models/package_info.dart';
import 'app_logger.dart';

/// Кеш последних данных роутера для офлайн-режима.
///
/// Хранит в SharedPreferences с версионированием: если структура моделей
/// изменится — старый кеш игнорируется. TTL — 24 часа (по умолчанию),
/// настраивается через [maxAge].
///
/// Не путать с persistent storage роутеров (StorageService) — здесь кеш
/// "последних данных", привязанный к host+port+username.
class OfflineCacheService {
  /// Версия схемы кеша. Инкрементить при несовместимых изменениях моделей.
  static const int _schemaVersion = 1;

  static String _key(String suffix) => 'offline_cache_v$_schemaVersion:$suffix';

  /// Максимальный возраст кеша. Старше — игнорируется.
  static const Duration defaultMaxAge = Duration(hours: 24);

  // ---- Запись ----

  static Future<void> saveSystemInfo(String hostKey, SystemInfo info) async {
    await _write(hostKey, 'system', _serializeSystem(info));
  }

  static Future<void> saveWifiNetworks(String hostKey, List<WifiNetwork> nets) async {
    await _write(hostKey, 'wifi_networks', nets.map(_serializeWifiNetwork).toList());
  }

  static Future<void> saveWifiStations(String hostKey, List<WifiStation> stations) async {
    await _write(hostKey, 'wifi_stations', stations.map(_serializeWifiStation).toList());
  }

  static Future<void> saveClients(String hostKey, List<ClientInfo> clients) async {
    await _write(hostKey, 'clients', clients.map(_serializeClient).toList());
  }

  static Future<void> saveVpnInterfaces(String hostKey, List<VpnInterface> vpns) async {
    await _write(hostKey, 'vpn', vpns.map(_serializeVpn).toList());
  }

  static Future<void> saveNetworkInterfaces(String hostKey, List<NetworkInterface> nets) async {
    await _write(hostKey, 'network', nets.map(_serializeNetwork).toList());
  }

  static Future<void> savePackages(String hostKey, List<PackageInfo> packages) async {
    await _write(hostKey, 'packages', packages.map(_serializePackage).toList());
  }

  // ---- Чтение ----

  static Future<SystemInfo?> loadSystemInfo(String hostKey, {Duration? maxAge}) async {
    final raw = await _read(hostKey, 'system', maxAge: maxAge);
    if (raw is! Map) return null;
    try {
      return _deserializeSystem(Map<String, dynamic>.from(raw));
    } catch (e) {
      AppLogger.w('OfflineCache: loadSystemInfo failed: $e');
      return null;
    }
  }

  static Future<List<WifiNetwork>> loadWifiNetworks(String hostKey, {Duration? maxAge}) async {
    final raw = await _read(hostKey, 'wifi_networks', maxAge: maxAge);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _deserializeWifiNetwork(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<WifiStation>> loadWifiStations(String hostKey, {Duration? maxAge}) async {
    final raw = await _read(hostKey, 'wifi_stations', maxAge: maxAge);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _deserializeWifiStation(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<ClientInfo>> loadClients(String hostKey, {Duration? maxAge}) async {
    final raw = await _read(hostKey, 'clients', maxAge: maxAge);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _deserializeClient(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<VpnInterface>> loadVpnInterfaces(String hostKey, {Duration? maxAge}) async {
    final raw = await _read(hostKey, 'vpn', maxAge: maxAge);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _deserializeVpn(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<NetworkInterface>> loadNetworkInterfaces(String hostKey, {Duration? maxAge}) async {
    final raw = await _read(hostKey, 'network', maxAge: maxAge);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _deserializeNetwork(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<PackageInfo>> loadPackages(String hostKey, {Duration? maxAge}) async {
    final raw = await _read(hostKey, 'packages', maxAge: maxAge);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _deserializePackage(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ---- Метаданные ----

  /// Возвращает timestamp последнего обновления для данной секции.
  static Future<DateTime?> lastUpdated(String hostKey, String section) async {
    final raw = await _readMeta(hostKey, section);
    if (raw == null) return null;
    final ts = raw['ts'];
    if (ts is int) {
      return DateTime.fromMillisecondsSinceEpoch(ts);
    }
    return null;
  }

  /// Сколько секунд прошло с последнего обновления.
  static Future<int?> ageSeconds(String hostKey, String section) async {
    final ts = await lastUpdated(hostKey, section);
    if (ts == null) return null;
    return DateTime.now().difference(ts).inSeconds;
  }

  /// Удаляет весь кеш для роутера.
  static Future<void> clearForRouter(String hostKey) async {
    final prefs = await SharedPreferences.getInstance();
    for (final section in const [
      'system',
      'wifi_networks',
      'wifi_stations',
      'clients',
      'vpn',
      'network',
      'packages',
    ]) {
      await prefs.remove(_key('$hostKey/$section'));
    }
  }

  // ---- Низкоуровневые ----

  static Future<void> _write(String hostKey, String section, Object data) async {
    final prefs = await SharedPreferences.getInstance();
    final meta = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'host': hostKey,
    };
    final value = {
      'meta': meta,
      'data': data,
    };
    await prefs.setString(_key('$hostKey/$section'), jsonEncode(value));
  }

  static Future<Object?> _read(String hostKey, String section, {Duration? maxAge}) async {
    final raw = await _readRaw(hostKey, section);
    if (raw == null) return null;
    final meta = raw['meta'] as Map?;
    if (meta == null) return null;
    final ts = meta['ts'];
    if (ts is! int) return null;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    final limit = (maxAge ?? defaultMaxAge).inMilliseconds;
    if (age > limit) return null; // истёк
    return raw['data'];
  }

  static Future<Map?> _readMeta(String hostKey, String section) async {
    final raw = await _readRaw(hostKey, section);
    if (raw == null) return null;
    return raw['meta'] is Map ? Map<String, dynamic>.from(raw['meta'] as Map) : null;
  }

  static Future<Map?> _readRaw(String hostKey, String section) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_key('$hostKey/$section'));
      if (s == null || s.isEmpty) return null;
      final m = jsonDecode(s);
      if (m is! Map) return null;
      return Map<String, dynamic>.from(m);
    } catch (_) {
      return null;
    }
  }

  /// Уникальный ключ роутера для кеша (host + port + username).
  static String hostKey(String host, int port, String username) =>
      '$host:$port@$username';

  // ---- Сериализация моделей ----
  // Модели не имеют toJson/fromJson, делаем вручную — минимально,
  // только то, что нужно для офлайн-показа.

  static Map<String, dynamic> _serializeSystem(SystemInfo s) => {
        'hostname': s.hostname,
        'model': s.model,
        'firmwareVersion': s.firmwareVersion,
        'kernelVersion': s.kernelVersion,
        'uptime': s.uptime,
        'cpuLoad': s.cpuLoad,
        'memoryTotal': s.memoryTotal,
        'memoryFree': s.memoryFree,
        'memoryUsed': s.memoryUsed,
      };

  static SystemInfo _deserializeSystem(Map<String, dynamic> m) => SystemInfo(
        hostname: m['hostname']?.toString() ?? '',
        model: m['model']?.toString() ?? '',
        firmwareVersion: m['firmwareVersion']?.toString() ?? '',
        kernelVersion: m['kernelVersion']?.toString() ?? '',
        uptime: m['uptime']?.toString() ?? '',
        cpuLoad: (m['cpuLoad'] as num?)?.toDouble() ?? 0.0,
        memoryTotal: (m['memoryTotal'] as num?)?.toInt() ?? 0,
        memoryFree: (m['memoryFree'] as num?)?.toInt() ?? 0,
        memoryUsed: (m['memoryUsed'] as num?)?.toInt() ?? 0,
      );

  static Map<String, dynamic> _serializeWifiNetwork(WifiNetwork w) => {
        'section': w.section,
        'ssid': w.ssid,
        'device': w.device,
        'disabled': w.disabled,
        'encryption': w.encryption,
        'mode': w.mode,
      };

  static WifiNetwork _deserializeWifiNetwork(Map<String, dynamic> m) => WifiNetwork(
        section: m['section']?.toString() ?? '',
        ssid: m['ssid']?.toString() ?? '',
        device: m['device']?.toString() ?? '',
        disabled: m['disabled'] == true,
        encryption: m['encryption']?.toString(),
        mode: m['mode']?.toString(),
      );

  static Map<String, dynamic> _serializeWifiStation(WifiStation w) => {
        'mac': w.mac,
        'signal': w.signal,
        'noise': w.noise,
        'rxRate': w.rxRate,
        'txRate': w.txRate,
        'authorized': w.authorized,
      };

  static WifiStation _deserializeWifiStation(Map<String, dynamic> m) => WifiStation(
        mac: m['mac']?.toString() ?? '',
        signal: m['signal']?.toString(),
        noise: m['noise']?.toString(),
        rxRate: (m['rxRate'] as num?)?.toDouble(),
        txRate: (m['txRate'] as num?)?.toDouble(),
        authorized: m['authorized'] == true,
      );

  static Map<String, dynamic> _serializeClient(ClientInfo c) => {
        'hostname': c.hostname,
        'mac': c.mac,
        'ip': c.ip,
        'interface': c.interface,
        'active': c.active,
        'rxBytes': c.rxBytes,
        'txBytes': c.txBytes,
        'signal': c.signal,
        'connectionType': c.connectionType,
        'accessPoint': c.accessPoint,
        'dlSpeed': c.dlSpeed,
        'ulSpeed': c.ulSpeed,
        'rxBitrate': c.rxBitrate,
        'txBitrate': c.txBitrate,
        'monthRxBytes': c.monthRxBytes,
        'monthTxBytes': c.monthTxBytes,
        'frequency': c.frequency,
      };

  static ClientInfo _deserializeClient(Map<String, dynamic> m) => ClientInfo(
        hostname: m['hostname']?.toString() ?? '',
        mac: m['mac']?.toString() ?? '',
        ip: m['ip']?.toString(),
        interface: m['interface']?.toString(),
        active: m['active'] != false,
        rxBytes: (m['rxBytes'] as num?)?.toInt() ?? 0,
        txBytes: (m['txBytes'] as num?)?.toInt() ?? 0,
        signal: (m['signal'] as num?)?.toInt(),
        connectionType: m['connectionType']?.toString(),
        accessPoint: m['accessPoint']?.toString(),
        dlSpeed: (m['dlSpeed'] as num?)?.toDouble(),
        ulSpeed: (m['ulSpeed'] as num?)?.toDouble(),
        rxBitrate: m['rxBitrate']?.toString(),
        txBitrate: m['txBitrate']?.toString(),
        monthRxBytes: (m['monthRxBytes'] as num?)?.toInt() ?? 0,
        monthTxBytes: (m['monthTxBytes'] as num?)?.toInt() ?? 0,
        frequency: (m['frequency'] as num?)?.toInt(),
      );

  static Map<String, dynamic> _serializeVpn(VpnInterface v) => {
        'name': v.name,
        'type': v.type,
        'up': v.up,
        'peer': v.peer,
        'endpoint': v.endpoint,
        'transfer': v.transfer,
        'latestHandshake': v.latestHandshake?.toIso8601String(),
        'device': v.device,
        'enabled': v.enabled,
      };

  static VpnInterface _deserializeVpn(Map<String, dynamic> m) => VpnInterface(
        name: m['name']?.toString() ?? '',
        type: m['type']?.toString() ?? '',
        up: m['up'] == true,
        peer: m['peer']?.toString(),
        endpoint: m['endpoint']?.toString(),
        transfer: m['transfer']?.toString(),
        latestHandshake: m['latestHandshake'] is String
            ? DateTime.tryParse(m['latestHandshake'] as String)
            : null,
        device: m['device']?.toString(),
        enabled: m['enabled'] != false,
      );

  static Map<String, dynamic> _serializeNetwork(NetworkInterface n) => {
        'name': n.name,
        'up': n.up,
        'protocol': n.protocol,
        'device': n.device,
        'ipAddresses': n.ipAddresses,
        'ipv6Addresses': n.ipv6Addresses,
        'gateway': n.gateway,
        'dns': n.dns,
        'stats': n.stats,
      };

  static NetworkInterface _deserializeNetwork(Map<String, dynamic> m) =>
      NetworkInterface(
        name: m['name']?.toString() ?? '',
        up: m['up'] != false,
        protocol: m['protocol']?.toString(),
        device: m['device']?.toString(),
        ipAddresses: (m['ipAddresses'] as List?)?.map((e) => e.toString()).toList(),
        ipv6Addresses: (m['ipv6Addresses'] as List?)?.map((e) => e.toString()).toList(),
        gateway: m['gateway']?.toString(),
        dns: m['dns']?.toString(),
        stats: m['stats'] is Map
            ? Map<String, dynamic>.from(m['stats'] as Map)
            : null,
      );

  static Map<String, dynamic> _serializePackage(PackageInfo p) => {
        'name': p.name,
        'version': p.version,
        'size': p.size,
        'section': p.section,
        'description': p.description,
        'installed': p.installed,
      };

  static PackageInfo _deserializePackage(Map<String, dynamic> m) => PackageInfo(
        name: m['name']?.toString() ?? '',
        version: m['version']?.toString() ?? '',
        size: m['size']?.toString(),
        section: m['section']?.toString(),
        description: m['description']?.toString(),
        installed: m['installed'] == true,
      );
}
