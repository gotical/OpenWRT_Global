import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/router_connection.dart';

class StorageService {
  static const String _routersKey = 'routers';
  static const String _selectedKey = 'selected_router';

  static Future<List<RouterConnection>> loadRouters() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_routersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => RouterConnection.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRouters(List<RouterConnection> routers) async {
    final prefs = await SharedPreferences.getInstance();
    final data = routers.map((r) => r.toJson()).toList();
    await prefs.setString(_routersKey, jsonEncode(data));
  }

  static Future<int> loadSelectedIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_selectedKey) ?? 0;
  }

  static Future<void> saveSelectedIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_selectedKey, index);
  }

  static Future<Map<String, int>> loadTrafficLimits() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('traffic_limits');
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k.toLowerCase(), (v is int) ? v : int.tryParse(v.toString()) ?? 0));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveTrafficLimits(Map<String, int> limits) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('traffic_limits', jsonEncode(limits));
  }

  static Future<void> setTrafficLimit(String mac, int bytes) async {
    final limits = await loadTrafficLimits();
    if (bytes <= 0) {
      limits.remove(mac.toLowerCase());
    } else {
      limits[mac.toLowerCase()] = bytes;
    }
    await saveTrafficLimits(limits);
  }

  static Future<bool> wasDepsChecked(String host) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('deps_checked_$host') ?? false;
  }

  static Future<void> markDepsChecked(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('deps_checked_$host', true);
  }

  static Future<void> resetDepsChecked(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('deps_checked_$host', false);
  }

  static Future<bool> isDepsReminderHidden() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hide_dep_reminder') ?? false;
  }

  static Future<void> setDepsReminderHidden(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_dep_reminder', v);
  }

  static Future<bool> isHideNonFunctionalSections() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hide_nonfunctional_sections') ?? false;
  }

  static Future<void> setHideNonFunctionalSections(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_nonfunctional_sections', v);
  }

  static Future<bool> isNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_enabled') ?? false;
  }

  static Future<void> setNotificationsEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', v);
  }

  static Future<Set<String>> loadKnownClients() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('known_clients') ?? []).toSet();
  }

  static Future<void> saveKnownClients(Set<String> known) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('known_clients', known.toList());
  }

  static Future<List<Map<String, String>>> loadConnLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('conn_log');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, String>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveConnLog(List<Map<String, String>> log) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conn_log', jsonEncode(log));
  }

  static Future<Map<String, String>> loadDeviceNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('device_names');
    if (raw == null || raw.isEmpty) return {};
    try { return Map<String, String>.from(jsonDecode(raw) as Map); } catch (_) { return {}; }
  }

  static Future<void> saveDeviceName(String mac, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final names = await loadDeviceNames();
    if (name.isEmpty) { names.remove(mac.toLowerCase()); }
    else { names[mac.toLowerCase()] = name; }
    await prefs.setString('device_names', jsonEncode(names));
  }

  static Future<String?> loadApiKey(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_key_$provider');
  }

  static Future<void> saveApiKey(String provider, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key_$provider', key);
  }

  static Future<String?> loadActiveAiProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_ai_provider');
  }

  static Future<void> saveActiveAiProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_ai_provider', provider);
  }
}
