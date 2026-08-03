import 'package:flutter/services.dart';

class SecureScreen {
  static const _channel = MethodChannel('com.openwrtmanager/secure');

  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('setSecureFlag', true);
    } catch (_) {}
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('setSecureFlag', false);
    } catch (_) {}
  }
}