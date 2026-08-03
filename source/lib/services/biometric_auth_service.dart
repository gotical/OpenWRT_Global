import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  static final _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    try {
      final biometrics = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return biometrics || supported;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({String reason = 'Подтвердите личность'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // biometricOnly=false: кроме отпечатка допускаем откат на PIN/пароль
        // устройства, чтобы приложение нельзя было заблокировать навсегда.
        // persistAcrossBackgrounding=true: запрос повторяется при возврате
        // в приложение, если авторизация прервалась.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
