import 'package:flutter/material.dart';

/// Анимированные скелетоны-заглушки (идея из luci-mobile luci_loading_states).
/// Показываются вместо спиннеров при загрузке — экран не «прыгает».
class AppSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const AppSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 12,
    this.margin,
  });

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        color: base,
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final v = _animation.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  base,
                  base.withValues(alpha: 0.4),
                  base,
                ],
                stops: [
                  (v - 0.3).clamp(0.0, 1.0),
                  v.clamp(0.0, 1.0),
                  (v + 0.3).clamp(0.0, 1.0),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

/// Скелетон карточки (заголовок + пара строк) для списков и дашборда.
class AppCardSkeleton extends StatelessWidget {
  const AppCardSkeleton({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSkeleton(width: 160, height: 20),
            const SizedBox(height: 12),
            for (var i = 0; i < lines; i++) ...[
              AppSkeleton(
                width: i == lines - 1 ? 100 : 240,
                height: 14,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
