import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/router_connection.dart';

/// Хранение данных приложения.
///
/// Секреты (пароли и ssh-ключи роутеров) хранятся только в Android Keystore
/// через [FlutterSecureStorage]. В SharedPreferences остаются лишь
/// неконфиденциальные настройки и несекретные поля конфигураций.
class StorageService {
  static const String _routersKey = 'routers';
  static const String _selectedKey = 'selected_router';

  // Keystore (AES-GCM), отдельная запись на хост.
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _pwKey(String host, String user) => 'router_pw_${host}_$user';
  static String _keyKey(String host, String user) => 'router_key_${host}_$user';

  // ---- Секреты в Keystore ----

  static Future<void> _saveSecrets(RouterConnection r) async {
    if (r.password.isNotEmpty) {
      await _secure.write(key: _pwKey(r.host, r.username), value: r.password);
    } else {
      await _secure.delete(key: _pwKey(r.host, r.username));
    }
    if (r.sshKey != null && r.sshKey!.isNotEmpty) {
      await _secure.write(key: _keyKey(r.host, r.username), value: r.sshKey!);
    } else {
      await _secure.delete(key: _keyKey(r.host, r.username));
    }
  }

  // ---- Список роутеров ----

  static Future<List<RouterConnection>> loadRouters() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_routersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final routers = list
          .map((e) => RouterConnection.fromJson(e as Map<String, dynamic>))
          .toList();
      // Подтягиваем секреты из Keystore.
      final out = <RouterConnection>[];
      for (final r in routers) {
        out.add(await _withSecrets(r));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> hasSavedSecrets(RouterConnection r) async {
    try {
      final pw = await _secure.read(key: _pwKey(r.host, r.username));
      final key = await _secure.read(key: _keyKey(r.host, r.username));
      return (pw != null && pw.isNotEmpty) || (key != null && key.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Возвращает копию конфигурации с секретами из Keystore.
  static Future<RouterConnection> _withSecrets(RouterConnection r) async {
    String pw = '';
    String? key;
    try {
      pw = await _secure.read(key: _pwKey(r.host, r.username)) ?? '';
      key = await _secure.read(key: _keyKey(r.host, r.username));
    } catch (_) {}
    return RouterConnection(
      name: r.name,
      host: r.host,
      port: r.port,
      username: r.username,
      password: pw,
      sshKey: key,
      useKey: r.useKey,
      useHttps: r.useHttps,
      fingerprint: r.fingerprint,
    );
  }

  static Future<void> saveRouters(List<RouterConnection> routers) async {
    // Сначала скрываем секреты в Keystore.
    for (final r in routers) {
      await _saveSecrets(r);
    }
    final prefs = await SharedPreferences.getInstance();
    // Сериализуем без секретов (toJson их не содержит).
    final data = routers.map((r) => _publicJson(r)).toList();
    await prefs.setString(_routersKey, jsonEncode(data));
  }

  static Map<String, dynamic> _publicJson(RouterConnection r) => {
        'name': r.name,
        'host': r.host,
        'port': r.port,
        'username': r.username,
        'useKey': r.useKey,
        'useHttps': r.useHttps,
        'fingerprint': r.fingerprint,
      };

  /// Удаляет секреты роутера из Keystore (при удалении/очистке).
  static Future<void> removeSecrets(String host, String username) async {
    try {
      await _secure.delete(key: _pwKey(host, username));
      await _secure.delete(key: _keyKey(host, username));
    } catch (_) {}
  }

  // ---- Отпечаток SSH ключа хоста ----

  static Future<String?> loadFingerprint(String host) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fp_$host');
  }

  static Future<void> saveFingerprint(String host, String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fp_$host', fingerprint);
  }

  static Future<void> removeFingerprint(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fp_$host');
  }

  // --- процедурные заготовки (устарели, удалены) ---
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
    // API-ключи AI — чувствительные данные → Keystore.
    try { return await _secure.read(key: 'api_key_$provider'); } catch (_) { return null; }
  }

  static Future<void> saveApiKey(String provider, String key) async {
    await _secure.write(key: 'api_key_$provider', value: key);
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