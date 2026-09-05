import 'dart:async';
import 'dart:io';

import 'app_logger.dart';

/// Результат обнаружения одного роутера в локальной сети.
class DiscoveredRouter {
  final String host;
  final int port;
  final String? sshBanner;
  final String? hostname;
  final bool likelyOpenWrt;
  final Duration latency;

  const DiscoveredRouter({
    required this.host,
    required this.port,
    this.sshBanner,
    this.hostname,
    this.likelyOpenWrt = false,
    this.latency = Duration.zero,
  });

  /// Человеко-читаемое имя по умолчанию (например "OpenWrt 192.168.1.1").
  String get suggestedName {
    if (hostname != null && hostname!.isNotEmpty) {
      // Убираем .local и .lan суффиксы, чтобы было чище.
      var h = hostname!;
      for (final sfx in const ['.local', '.lan', '.home']) {
        if (h.toLowerCase().endsWith(sfx)) {
          h = h.substring(0, h.length - sfx.length);
        }
      }
      return h;
    }
    return 'OpenWrt $host';
  }

  @override
  String toString() => 'DiscoveredRouter($host:$port, openwrt=$likelyOpenWrt)';
}

/// Сканирует локальную сеть на наличие роутеров OpenWrt (SSH на порту 22).
///
/// Алгоритм:
/// 1. По заданному локальному IP вычисляет /24 подсеть.
/// 2. Параллельно проверяет TCP-порт 22 на каждом адресе (с ограничением concurrency).
/// 3. Для отвечающих пытается прочитать SSH-баннер (OpenSSH 8.x / Dropbear).
/// 4. По баннеру и/или ответу на пустую SSH-команду определяет, что это OpenWrt.
///
/// Не требует root/привилегий. mDNS-обнаружение не используется (не работает
/// на Android без дополнительных пакетов и редко публикуется на OpenWrt).
class DiscoveryService {
  /// Максимум одновременных TCP-подключений (не перегружаем сеть и UI-поток).
  static const int _maxConcurrency = 32;

  /// Таймаут одного TCP-коннекта.
  static const Duration _connectTimeout = Duration(milliseconds: 800);

  /// Сколько хостов максимум проверяем (защита от /16 сетей).
  static const int _maxHosts = 254;

  /// Публичный IP локального интерфейса (например "192.168.1.42").
  /// Если null — попробуем определить автоматически через сетевые интерфейсы.
  final String? localIp;

  DiscoveryService({this.localIp});

  /// Сканирует подсеть и возвращает поток найденных роутеров.
  /// Прогресс приходит стримом, чтобы UI мог показывать по мере нахождения.
  Stream<DiscoveredRouter> scan({
    int port = 22,
    Duration perHostTimeout = const Duration(seconds: 3),
  }) async* {
    final base = _subnetBase(localIp ?? await _detectLocalIp());
    if (base == null) {
      AppLogger.w('Discovery: не удалось определить локальный IP');
      return;
    }
    AppLogger.i('Discovery: сканируем $base.0/24 на порт $port');

    final results = <DiscoveredRouter>[];
    final queue = <int>[];
    for (var i = 1; i <= 254 && queue.length < _maxHosts; i++) {
      queue.add(i);
    }

    final completer = Completer<void>();
    int inFlight = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final i = queue.removeAt(0);
        final host = '$base.$i';
        try {
          final r = await _probe(host, port, perHostTimeout);
          if (r != null) results.add(r);
        } catch (_) {}
      }
      inFlight--;
      if (inFlight == 0) completer.complete();
    }

    for (var w = 0; w < _maxConcurrency; w++) {
      inFlight++;
      // ignore: unawaited_futures
      worker();
    }

    // Эмитим результаты по мере поступления (через polling).
    final seen = <String>{};
    while (!completer.isCompleted || results.isNotEmpty) {
      while (results.isNotEmpty) {
        final r = results.removeAt(0);
        if (seen.add('${r.host}:${r.port}')) yield r;
      }
      if (!completer.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } else {
        break;
      }
    }
  }

  /// Проверяет один хост: TCP-коннект + чтение SSH-баннера.
  Future<DiscoveredRouter?> _probe(
    String host,
    int port,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: _connectTimeout,
      );
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
    final latency = stopwatch.elapsed;

    String? banner;
    try {
      // SSH-сервер шлёт баннер в первые ~0.5с: "SSH-2.0-OpenSSH_8.x ..."
      // или "SSH-2.0-dropbear_2022.x".
      final completer = Completer<String?>();
      late StreamSubscription sub;
      sub = socket.listen(
        (data) {
          try {
            final s = String.fromCharCodes(data);
            if (!completer.isCompleted) {
              completer.complete(s);
              sub.cancel();
            }
          } catch (_) {}
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: true,
      );
      final raw = await completer.future
          .timeout(timeout - stopwatch.elapsed, onTimeout: () => null);
      await sub.cancel();
      if (raw != null) {
        final firstLine = raw.split('\n').first.trim();
        banner = firstLine.isEmpty ? null : firstLine;
      }
    } catch (_) {
      // Не критично, без баннера тоже ОК.
    } finally {
      try {
        socket.destroy();
      } catch (_) {}
    }

    final likelyOpenWrt = _looksLikeOpenWrt(banner, host);
    return DiscoveredRouter(
      host: host,
      port: port,
      sshBanner: banner,
      likelyOpenWrt: likelyOpenWrt,
      latency: latency,
    );
  }

  /// Эвристика определения OpenWrt по SSH-баннеру.
  /// Dropbear — практически 100% индикатор OpenWrt (он там дефолтный SSH).
  /// OpenSSH — может быть что угодно, помечаем как "возможно".
  bool _looksLikeOpenWrt(String? banner, String host) {
    if (banner == null) return false;
    final b = banner.toLowerCase();
    if (b.contains('dropbear')) return true;
    if (b.contains('openssh')) return true; // OpenWrt тоже может ставить openssh
    return false;
  }

  /// Вычисляет базу /24 подсети по локальному IP.
  /// "192.168.1.42" → "192.168.1".
  /// "fe80::1" → null (IPv6 не поддерживаем).
  String? _subnetBase(String? ip) {
    if (ip == null || ip.isEmpty) return null;
    if (ip.contains(':')) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  /// Пытается определить локальный IPv4 (не loopback, не link-local).
  Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        // Пропускаем мобильные интерфейсы — нам нужен WiFi/LAN.
        final name = iface.name.toLowerCase();
        if (name.contains('rmnet') ||
            name.contains('ppp') ||
            name.contains('tun') ||
            name.contains('docker') ||
            name.contains('veth')) {
          continue;
        }
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('10.') ||
              ip.startsWith('192.168.') ||
              _isPrivate172(ip)) {
            return ip;
          }
        }
      }
    } catch (e) {
      AppLogger.w('Discovery: _detectLocalIp failed: $e');
    }
    return null;
  }

  bool _isPrivate172(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  /// Удобный wrapper: вернуть список сразу (без стрима).
  /// Полезно для вызовов, которым не нужен прогресс.
  Future<List<DiscoveredRouter>> scanAll({
    int port = 22,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final list = <DiscoveredRouter>[];
    try {
      await for (final r in scan(port: port).timeout(timeout)) {
        list.add(r);
      }
    } on TimeoutException {
      // Нормально: часть подсети могла не успеть, но найденное вернём.
    } catch (e) {
      AppLogger.w('Discovery: scanAll error: $e');
    }
    // Дедупликация.
    final uniq = <String, DiscoveredRouter>{};
    for (final r in list) {
      uniq['${r.host}:${r.port}'] = r;
    }
    final out = uniq.values.toList()
      ..sort((a, b) => a.host.compareTo(b.host));
    return out;
  }
}
