import 'package:flutter/material.dart';

/// Компактный индикатор состояния SSH-соединения.
///
/// Зелёная точка + "Online" — SSH-сессия активна.
/// Красная точка + "Offline" — нет связи с роутером, используется кеш.
///
/// Используется в AppBar/Drawer на всех экранах. По тапу — попытка
/// переподключения через [onRetry].
class ConnectionDot extends StatelessWidget {
  final bool online;
  final int? cachedAgeSec;
  final VoidCallback? onRetry;
  final bool compact;

  const ConnectionDot({
    super.key,
    required this.online,
    this.cachedAgeSec,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = online ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final icon = online ? Icons.wifi : Icons.wifi_off;
    final label = online ? 'Online' : 'Offline';

    if (compact) {
      // Только цветная точка + тултип "Online/Offline + age".
      final tooltip = online
          ? 'Online'
          : (cachedAgeSec != null
              ? 'Offline — кеш ${_formatAge(cachedAgeSec!)}'
              : 'Offline');
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onRetry,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Полная панелька (для drawer/баннера).
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(color),
            const SizedBox(width: 8),
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            if (cachedAgeSec != null) ...[
              const SizedBox(width: 6),
              Text(
                '(${_formatAge(cachedAgeSec!)})',
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  String _formatAge(int sec) {
    if (sec < 60) return '${sec}с';
    if (sec < 3600) return '${sec ~/ 60}м';
    if (sec < 86400) return '${sec ~/ 3600}ч';
    return '${sec ~/ 86400}д';
  }
}
