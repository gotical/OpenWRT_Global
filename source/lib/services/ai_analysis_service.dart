import 'dart:convert';
import 'dart:io';
import 'app_logger.dart';
import 'storage_service.dart';

class AiAnalysisService {
  static String? _activeProvider;
  static String? _apiKey;

  static Future<void> init() async {
    _activeProvider = await StorageService.loadActiveAiProvider();
    if (_activeProvider != null) {
      _apiKey = await StorageService.loadApiKey(_activeProvider!);
    }
  }

  static Future<String?> analyzeLog(String logText) async {
    return _query('Проанализируй лог OpenWrt и найди проблемы:\n$logText');
  }

  static Future<String?> analyzeSecurity(String logText) async {
    return _query('Найди угрозы безопасности в этом логе OpenWrt:\n$logText');
  }

  static Future<String?> analyzePerformance(String data) async {
    return _query('Проанализируй производительность OpenWrt:\n$data');
  }

  static Future<String?> getRecommendations(String context) async {
    return _query('Дай рекомендации по настройке OpenWrt:\n$context');
  }

  static Future<String?> _query(String prompt) async {
    if (_apiKey == null || _apiKey!.isEmpty) return null;
    try {
      final payload = jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.3,
        'max_tokens': 1024,
      });
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer $_apiKey');
      request.add(utf8.encode(payload));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      return json['choices']?[0]?['message']?['content'] as String?;
    } catch (e) {
      AppLogger.e('AI query failed', e);
      return null;
    }
  }
}