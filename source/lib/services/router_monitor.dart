import 'dart:async';
import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/router_connection.dart';
import 'app_logger.dart';
import 'notification_service.dart';
import 'offline_cache.dart';
import 'openwrt_service.dart';

/// Сервис фонового мониторинга роутера.
///
/// Периодически проверяет SSH-соединение с роутером через WorkManager.
/// Если роутер недоступен >N минут — показывает уведомление.
/// Если восстановился — снимает уведомление и обновляет виджет.
///
/// Без сторонних сервисов: всё работает локально на устройстве.
class RouterMonitorService {
  static const String taskName = 'openwrt_router_monitor';
  static const Duration _checkInterval = Duration(minutes: 15);
  static const Duration _offlineThreshold = Duration(minutes: 5);
  static const String _offlinePrefsKey = 'router_offline_since';

  /// Запускает периодическую проверку.
  /// Безопасно вызывать многократно.
  static Future<void> startMonitoring() async {
    try {
      await Workmanager().registerPeriodicTask(
        'router_monitor_task',
        taskName,
        frequency: _checkInterval,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
      AppLogger.i('RouterMonitor: periodic task scheduled');
    } catch (e) {
      AppLogger.w('RouterMonitor: registerPeriodicTask failed: $e');
    }
  }

  static Future<void> stopMonitoring() async {
    try {
      await Workmanager().cancelByUniqueName('router_monitor_task');
    } catch (_) {}
  }

  /// Проверяет текущее состояние роутера. Вызывается в фоне.
  /// Возвращает true если роутер доступен.
  static Future<bool> checkOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hostKey = prefs.getString('monitor_host_key');
      if (hostKey == null) return true; // нет настроенного роутера

      final routerJson = prefs.getString('monitor_router_json');
      if (routerJson == null) return true;
      final router = RouterConnection.fromJson(
        Map<String, dynamic>.from(jsonDecode(routerJson) as Map),
      );

      final service = OpenWrtService(router);
      try {
        await service.connect();
        final info = await service.fetchSystemInfo();
        await service.disconnect();

        // Сохраняем успешные данные в кеш.
        await OfflineCacheService.saveSystemInfo(hostKey, info);

        // Если были offline — снимаем уведомление.
        await _markOnline();
        await _updateWidget(info: info, online: true);
        return true;
      } catch (e) {
        AppLogger.w('RouterMonitor: check failed: $e');
        await _handleOffline();
        await _updateWidget(online: false);
        return false;
      }
    } catch (e) {
      AppLogger.e('RouterMonitor: checkOnce error', e);
      return false;
    }
  }

  /// Помечает, что роутер онлайн (сбрасывает offline-таймер).
  static Future<void> _markOnline() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_offlinePrefsKey)) {
      await prefs.remove(_offlinePrefsKey);
      // Снимаем уведомление об оффлайне.
      await NotificationService.cancel(1001);
    }
  }

  /// Помечает, что роутер оффлайн. Показывает уведомление только если
  /// оффлайн длится > _offlineThreshold.
  static Future<void> _handleOffline() async {
    final prefs = await SharedPreferences.getInstance();
    final since = prefs.getInt(_offlinePrefsKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (since == null) {
      // Первый раз заметили оффлайн.
      await prefs.setInt(_offlinePrefsKey, now);
      return;
    }
    final offlineMs = now - since;
    if (offlineMs >= _offlineThreshold.inMilliseconds) {
      // Уже долго оффлайн — показываем/обновляем уведомление.
      final mins = (offlineMs / 60000).round();
      final routerName = prefs.getString('monitor_router_name') ?? 'Router';
      await NotificationService.showWarning(
        id: 1001,
        title: 'OpenWRT: $routerName недоступен',
        body: 'Нет связи уже $mins мин. Откройте приложение для проверки.',
      );
    }
  }

  /// Обновляет данные виджета на рабочем столе.
  static Future<void> _updateWidget({
    dynamic info,
    required bool online,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final routerName = prefs.getString('monitor_router_name') ?? 'Router';

      String model = '—';
      String uptime = '—';
      if (info != null && online) {
        try {
          model = (info as dynamic).model?.toString() ?? '—';
          uptime = (info).uptime?.toString() ?? '—';
        } catch (_) {}
      }

      // Данные для home widget (рабочий стол).
      await HomeWidget.saveWidgetData<String>('router_name', routerName);
      await HomeWidget.saveWidgetData<String>('router_status', online ? 'online' : 'offline');
      await HomeWidget.saveWidgetData<String>('router_model', model);
      await HomeWidget.saveWidgetData<String>('router_uptime', online ? uptime : '—');
      await HomeWidget.saveWidgetData<String>(
        'last_update',
        DateTime.now().toIso8601String(),
      );
      await HomeWidget.updateWidget(
        name: 'OpenWrtWidgetProvider',
        androidName: 'OpenWrtWidgetProvider',
      );

      // Данные для Quick Settings Tile (шторка).
      // Плитка читает из SharedPreferences с префиксом "flutter.".
      await HomeWidget.saveWidgetData<String>('router.status', online ? 'online' : 'offline');
      // Принудительно обновляем плитку, если она показана в шторке.
      // (TileService подхватит обновление при следующем onStartListening —
      // обычно когда пользователь открывает шторку.)
    } catch (e) {
      AppLogger.w('RouterMonitor: widget update failed: $e');
    }
  }

  /// Регистрирует роутер для фонового мониторинга.
  /// Сохраняет конфигурацию (без пароля) для использования в фоне.
  static Future<void> registerRouter(RouterConnection r) async {
    final prefs = await SharedPreferences.getInstance();
    final key = OfflineCacheService.hostKey(r.host, r.port, r.username);
    await prefs.setString('monitor_host_key', key);
    await prefs.setString('monitor_router_name', r.name);
    // Сохраняем только не-секретные поля. Пароль подтянем из Keystore
    // (если поддерживается WorkManager + биометрика, иначе используем
    // SSH-ключ из Keystore через спец. bridge).
    // Для простоты сохраняем только host/port/username — пользователь должен
    // настроить SSH-ключ для фонового мониторинга без пароля.
    final safeJson = jsonEncode({
      'name': r.name,
      'host': r.host,
      'port': r.port,
      'username': r.username,
      'useKey': r.useKey,
      'fingerprint': r.fingerprint,
      'host2': r.host2,
    });
    await prefs.setString('monitor_router_json', safeJson);
  }

  static Future<void> unregisterRouter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('monitor_host_key');
    await prefs.remove('monitor_router_name');
    await prefs.remove('monitor_router_json');
    await prefs.remove(_offlinePrefsKey);
    await NotificationService.cancel(1001);
  }
}

/// Background callback для WorkManager.
/// Должен быть top-level или static.
@pragma('vm:entry-point')
void routerMonitorCallback() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await RouterMonitorService.checkOnce();
      return true;
    } catch (e) {
      return false;
    }
  });
}
