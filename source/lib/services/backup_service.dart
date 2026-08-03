import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/src/registry/registry.dart';
import 'app_logger.dart';

/// Сервис для экспорта/импорта конфигураций роутеров с AES-256 шифрованием.
class BackupService {
  static const _salt = 'OpenWRT_Global_Salt_v1';
  static const _iterations = 10000;

  static String encrypt(String plaintext, String password) {
    try {
      final key = _deriveKey(password);
      final iv = _generateIv();
      final cipher = CBCBlockCipher(AESEngine())
        ..init(true, ParametersWithIV(KeyParameter(key), iv));
      final padded = _pad(utf8.encode(plaintext));
      final output = Uint8List(padded.length);
      var offset = 0;
      while (offset < padded.length) {
        offset += cipher.processBlock(padded, offset, output, offset);
      }
      final combined = Uint8List(iv.length + output.length);
      combined.setAll(0, iv);
      combined.setAll(iv.length, output);
      return base64.encode(combined);
    } catch (e) {
      AppLogger.e('Encryption failed', e);
      rethrow;
    }
  }

  static String decrypt(String ciphertext, String password) {
    try {
      final combined = base64.decode(ciphertext);
      final iv = combined.sublist(0, 16);
      final data = combined.sublist(16);
      final key = _deriveKey(password);
      final cipher = CBCBlockCipher(AESEngine())
        ..init(false, ParametersWithIV(KeyParameter(key), iv));
      final output = Uint8List(data.length);
      var offset = 0;
      while (offset < data.length) {
        offset += cipher.processBlock(data, offset, output, offset);
      }
      final unpadded = _unpad(output);
      return utf8.decode(unpadded);
    } catch (e) {
      AppLogger.e('Decryption failed', e);
      rethrow;
    }
  }

  static Uint8List _deriveKey(String password) {
    final digest = SHA256Digest();
    final pbkdf2 = PBKDF2KeyDerivator(HMac(digest, 64));
    pbkdf2.init(Pbkdf2Parameters(utf8.encode(_salt) as Uint8List, _iterations, 32));
    return pbkdf2.process(utf8.encode(password) as Uint8List);
  }

  static Uint8List _generateIv() {
    final secureRandom = FortunaRandom();
    final seed = Uint8List(32);
    secureRandom.seed(KeyParameter(seed));
    return secureRandom.nextBytes(16);
  }

  static Uint8List _pad(Uint8List data) {
    final padLen = 16 - (data.length % 16);
    final padded = Uint8List(data.length + padLen);
    padded.setAll(0, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLen;
    }
    return padded;
  }

  static Uint8List _unpad(Uint8List data) {
    final padLen = data[data.length - 1];
    return data.sublist(0, data.length - padLen);
  }

  static String exportToJson(Map<String, dynamic> data, String password) {
    final json = jsonEncode(data);
    return encrypt(json, password);
  }

  static Map<String, dynamic> importFromJson(String encrypted, String password) {
    final json = decrypt(encrypted, password);
    return jsonDecode(json) as Map<String, dynamic>;
  }
}