import 'package:flutter/material.dart';

/// Тематическая иллюстрация для пустого состояния экрана.
class EmptyState extends StatelessWidget {
  final String asset;
  final String title;
  final String? message;
  final IconData? icon;
  final VoidCallback? onAction;
  final String? actionLabel;

  const EmptyState({
    super.key,
    required this.asset,
    required this.title,
    this.message,
    this.icon,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1.0),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Image.asset(asset, width: 200, height: 200,
                  fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: Icon(icon ?? Icons.refresh),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
