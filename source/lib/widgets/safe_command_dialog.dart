import 'package:flutter/material.dart';

class SafeCommandDialog extends StatelessWidget {
  final String title;
  final String description;
  final List<MapEntry<String, String>> changes;
  final String warning;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const SafeCommandDialog({
    super.key,
    required this.title,
    required this.description,
    this.changes = const [],
    this.warning = '',
    required this.onConfirm,
    this.onCancel,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String description,
    List<MapEntry<String, String>> changes = const [],
    String warning = '',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => SafeCommandDialog(
        title: title,
        description: description,
        changes: changes,
        warning: warning,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChanges = changes.isNotEmpty;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description, style: const TextStyle(fontSize: 14)),
            if (hasChanges) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Будут изменены:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.primary)),
                    const SizedBox(height: 6),
                    ...changes.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text('${c.key}: ', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, fontFamily: 'monospace')),
                          Text(c.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ],
            if (warning.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(warning, style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: onCancel ?? () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(
          onPressed: onConfirm,
          child: const Text('Применить'),
        ),
      ],
    );
  }
}