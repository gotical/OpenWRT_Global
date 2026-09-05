import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';

/// Источник проверки обновлений приложения.
///
/// Пользователь выбирает в настройках:
/// - [UpdateSource.github] — GitHub Releases (gotical/OpenWRT_Global)
/// - [UpdateSource.website] — официальный сайт (rybinsklab.ru/openwrt/)
/// - [UpdateSource.disabled] — не проверять обновления
enum UpdateSource {
  github('github', 'GitHub'),
  website('website', 'rybinsklab.ru'),
  disabled('disabled', 'Отключено');

  final String value;
  final String label;
  const UpdateSource(this.value, this.label);

  static UpdateSource fromString(String? v) {
    for (final s in UpdateSource.values) {
      if (s.value == v) return s;
    }
    return UpdateSource.github;
  }
}

/// Информация о доступном обновлении.
class UpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;
  final String source;
  final DateTime? publishedAt;
  final bool forceUpdate;

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.source,
    this.publishedAt,
    this.forceUpdate = false,
  });
}

/// Сервис проверки обновлений приложения.
///
/// Поддерживает несколько источников, настраиваемых пользователем:
/// - GitHub API (https://api.github.com/repos/gotical/OpenWRT_Global/releases/latest)
/// - Сайт rybinsklab.ru/openwrt/version.json (где админка публикует версии)
///
/// По умолчанию — GitHub. Чтобы переключить — Settings → Источник обновлений.
class UpdateService {
  static const String _sourceKey = 'update_source';
  static const String _lastCheckKey = 'update_last_check';
  static const String _skippedVersionKey = 'update_skipped_version';

  /// GitHub API endpoint для последнего релиза.
  /// Repository указывается в _getSourceConfig.
  static const String _githubApiBase = 'https://api.github.com/repos';

  /// Сайт с JSON-файлом последней версии (публикуется через админку).
  /// Формат JSON:
  /// {
  ///   "version": "4.3.0",
  ///   "notes": "Release notes (markdown)",
  ///   "url": "https://rybinsklab.ru/openwrt/app-release.apk",
  ///   "publishedAt": "2026-09-05T13:00:00Z",
  ///   "force": false
  /// }
  static const String _websiteVersionUrl =
      'https://rybinsklab.ru/openwrt/version.json';

  /// Текущая версия приложения (из pubspec.yaml).
  /// Передаётся из main.dart через setCurrentVersion().
  static String _currentVersion = '0.0.0';

  static void setCurrentVersion(String v) {
    _currentVersion = v;
  }

  /// Получает сохранённый источник.
  static Future<UpdateSource> getSource() async {
    final prefs = await SharedPreferences.getInstance();
    return UpdateSource.fromString(prefs.getString(_sourceKey));
  }

  /// Устанавливает источник.
  static Future<void> setSource(UpdateSource s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceKey, s.value);
  }

  /// Проверяет обновления через выбранный источник.
  /// Возвращает null если обновлений нет или проверка отключена.
  static Future<UpdateInfo?> checkForUpdate() async {
    final source = await getSource();
    if (source == UpdateSource.disabled) {
      AppLogger.i('UpdateService: проверка обновлений отключена');
      return null;
    }
    try {
      UpdateInfo? info;
      switch (source) {
        case UpdateSource.github:
          info = await _checkGithub();
        case UpdateSource.website:
          info = await _checkWebsite();
        case UpdateSource.disabled:
          return null;
      }
      // Сохраняем timestamp последней проверки.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      // Если пользователь пропустил эту версию — не показываем.
      if (info != null) {
        final skipped = prefs.getString(_skippedVersionKey);
        if (skipped == info.latestVersion && !info.forceUpdate) {
          return null;
        }
      }
      return info;
    } catch (e) {
      AppLogger.w('UpdateService: check failed: $e');
      return null;
    }
  }

  /// Проверка через GitHub API.
  /// Использует public endpoint — лимиты 60 запросов/час.
  static Future<UpdateInfo?> _checkGithub() async {
    final url = Uri.parse('$_githubApiBase/gotical/OpenWRT_Global/releases/latest');
    final resp = await http.get(
      url,
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      AppLogger.w('GitHub API: ${resp.statusCode}');
      return null;
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    final version = tag.replaceFirst(RegExp(r'^v'), '').trim();
    if (version.isEmpty) return null;

    // Ищем APK asset.
    String downloadUrl = (json['html_url'] as String?) ?? '';
    final assets = (json['assets'] as List?) ?? [];
    for (final a in assets) {
      if (a is Map && a['name'] is String) {
        final name = a['name'] as String;
        if (name.toLowerCase().endsWith('.apk')) {
          downloadUrl = (a['browser_download_url'] as String?) ?? downloadUrl;
          break;
        }
      }
    }

    // Сравниваем версии.
    if (!_isNewer(version, _currentVersion)) return null;

    return UpdateInfo(
      latestVersion: version,
      releaseNotes: (json['body'] as String?) ?? '',
      downloadUrl: downloadUrl,
      source: 'GitHub',
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? ''),
      forceUpdate: (json['prerelease'] as bool?) ?? false,
    );
  }

  /// Проверка через сайт (админка публикует version.json).
  static Future<UpdateInfo?> _checkWebsite() async {
    final resp = await http
        .get(Uri.parse(_websiteVersionUrl))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      AppLogger.w('Website version.json: ${resp.statusCode}');
      return null;
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final version = (json['version'] as String?)?.trim() ?? '';
    if (version.isEmpty) return null;
    if (!_isNewer(version, _currentVersion)) return null;

    return UpdateInfo(
      latestVersion: version,
      releaseNotes: (json['notes'] as String?) ?? '',
      downloadUrl: (json['url'] as String?) ?? '',
      source: 'rybinsklab.ru',
      publishedAt: DateTime.tryParse((json['publishedAt'] as String?) ?? ''),
      forceUpdate: json['force'] == true,
    );
  }

  /// Сравнение semver: 4.3.0 > 4.2.0, 4.10.0 > 4.2.0
  static bool _isNewer(String latest, String current) {
    try {
      final l = _parseVersion(latest);
      final c = _parseVersion(current);
      for (var i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static List<int> _parseVersion(String v) {
    final clean = v.replaceAll(RegExp(r'[^\d.]'), '');
    final parts = clean.split('.');
    return [
      int.tryParse(parts.length > 0 ? parts[0] : '0') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
    ];
  }

  /// Timestamp последней проверки (Unix seconds).
  static Future<int?> lastCheckTs() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastCheckKey);
    if (ms == null) return null;
    return ms ~/ 1000;
  }

  /// Помечает версию как пропущенную — больше не показывать.
  static Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedVersionKey, version);
  }

  /// Открыть ссылку на обновление через url_launcher.
  static Future<void> openDownload(String url) async {
    // Реализация вызова url_launcher — упрощено, в реальном коде:
    // import 'package:url_launcher/url_launcher.dart';
    // await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    AppLogger.i('UpdateService: open download $url');
  }
}
