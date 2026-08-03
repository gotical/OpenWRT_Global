import 'dart:io';
import 'package:flutter/services.dart';
import 'app_logger.dart';

class DeviceSecurity {
  static bool? _isRooted;
  static bool? _isEmulator;
  static bool? _isDebug;
  static bool? _isProxySet;

  static Future<bool> isRooted() async {
    if (_isRooted != null) return _isRooted!;
    try {
      final paths = [
        '/system/app/Superuser.apk',
        '/sbin/su',
        '/system/bin/su',
        '/system/xbin/su',
        '/data/local/xbin/su',
        '/data/local/bin/su',
        '/system/sd/xbin/su',
        '/system/bin/failsafe/su',
        '/data/local/su',
        '/su/bin/su',
      ];
      for (final path in paths) {
        if (await File(path).exists()) {
          _isRooted = true;
          AppLogger.w('Root detected: $path');
          return true;
        }
      }
      _isRooted = false;
      return false;
    } catch (_) {
      _isRooted = false;
      return false;
    }
  }

  static Future<bool> isEmulator() async {
    if (_isEmulator != null) return _isEmulator!;
    try {
      final props = await _getSystemProperties();
      final emuSignals = ['generic', 'sdk', 'emulator', 'android_google', 'google_sdk', 'vbox'];
      for (final signal in emuSignals) {
        if (props.values.any((v) => v.toLowerCase().contains(signal))) {
          _isEmulator = true;
          AppLogger.w('Emulator detected');
          return true;
        }
      }
      _isEmulator = false;
      return false;
    } catch (_) {
      _isEmulator = false;
      return false;
    }
  }

  static Future<bool> isDebug() async {
    if (_isDebug != null) return _isDebug!;
    try {
      // Проверка через platform channel или adb
      const channel = MethodChannel('com.openwrtmanager/secure');
      final result = await channel.invokeMethod<bool>('isDebug');
      _isDebug = result ?? false;
    } catch (_) {
      _isDebug = false;
    }
    return _isDebug!;
  }

  static Future<bool> isProxySet() async {
    if (_isProxySet != null) return _isProxySet!;
    try {
      // Проверка HTTP_PROXY / HTTPS_PROXY переменных окружения
      final env = Platform.environment;
      if (env.containsKey('http_proxy') || env.containsKey('https_proxy') ||
          env.containsKey('HTTP_PROXY') || env.containsKey('HTTPS_PROXY')) {
        _isProxySet = true;
        AppLogger.w('Proxy detected in environment');
        return true;
      }
      // Проверка системного proxy через getprop
      final httpProxy = await _getProp('http_proxy');
      if (httpProxy != null && httpProxy.isNotEmpty) {
        _isProxySet = true;
        AppLogger.w('System proxy detected');
        return true;
      }
      _isProxySet = false;
      return false;
    } catch (_) {
      _isProxySet = false;
      return false;
    }
  }

  static Future<Map<String, String>> _getSystemProperties() async {
    try {
      final result = await Process.run('getprop', []);
      if (result.exitCode != 0) return {};
      final props = <String, String>{};
      for (final line in (result.stdout as String).split('\n')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          final key = parts[0].trim().replaceAll('[', '').replaceAll(']', '');
          final val = parts.sublist(1).join(':').trim().replaceAll('[', '').replaceAll(']', '');
          props[key] = val;
        }
      }
      return props;
    } catch (_) {
      return {};
    }
  }

  static Future<String?> _getProp(String name) async {
    try {
      final result = await Process.run('getprop', [name]);
      if (result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return null;
  }
}