import 'dart:async';
import 'openwrt_service.dart';
import 'storage_service.dart';

/// Периодически опрашивает роутер и уведомляет о новых подключившихся устройствах.
/// Работает, пока приложение открыто (в т.ч. свёрнуто — Timer продолжает тикать).
class ClientMonitor {
  ClientMonitor._();
  static final ClientMonitor instance = ClientMonitor._();

  OpenWrtService? _service;
  Timer? _timer;
  bool running = false;
  bool notificationsEnabled = false;
  Set<String> _known = {};
  List<Map<String, String>> log = [];

  /// Вызывается при новом подключении (из фонового таймера).
  void Function(Map<String, String> client)? onClientConnected;

  Future<void> _init() async {
    notificationsEnabled = await StorageService.isNotificationsEnabled();
    _known = await StorageService.loadKnownClients();
    log = await StorageService.loadConnLog();
  }

  Future<void> start(OpenWrtService service) async {
    await _init();
    _service = service;
    if (running) return;
    running = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
    _poll();
  }

  Future<void> stop() async {
    running = false;
    _timer?.cancel();
    _timer = null;
    _service = null;
  }

  Future<void> refreshNotificationsFlag() async {
    notificationsEnabled = await StorageService.isNotificationsEnabled();
  }

  Future<void> _poll() async {
    final svc = _service;
    if (svc == null || !running) return;
    try {
      final clients = await svc.fetchClients();
      final newOnes = clients.where((c) => !_known.contains(c.mac)).toList();
      if (newOnes.isEmpty) return;
      for (final c in newOnes) {
        _known.add(c.mac);
        final entry = {
          'time': DateTime.now().toString().substring(0, 19).replaceAll('T', ' '),
          'mac': c.mac,
          'ip': c.ip ?? '',
          'hostname': c.hostname,
        };
        log.insert(0, entry);
        if (log.length > 30) log.removeRange(30, log.length);
        if (notificationsEnabled && onClientConnected != null) {
          onClientConnected!(entry);
        }
      }
      await StorageService.saveKnownClients(_known);
      // Ограничиваем рост списка известных клиентов (каждое новое устройство
      // оставалось там навсегда — при большом числе гостей список разрастался).
      if (_known.length > 500) {
        _known = _known.take(500).toSet();
        await StorageService.saveKnownClients(_known);
      }
      await StorageService.saveConnLog(log);
    } catch (_) {}
  }

  Future<void> clearLog() async {
    log.clear();
    await StorageService.saveConnLog(log);
  }
}
