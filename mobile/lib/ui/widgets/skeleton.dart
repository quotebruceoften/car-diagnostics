import 'package:flutter/material.dart';

/// Placeholder shapes that gently pulse while content loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.cards = 3, this.tiles = false});

  /// Number of placeholder cards.
  final int cards;

  /// Start with a row of two square tiles (dashboard-like screens).
  final bool tiles;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block({double? width, required double height, double radius = 12}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(radius)),
    );

    Widget card() => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            block(width: 44, height: 44, radius: 14),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  block(width: 160, height: 14, radius: 7),
                  const SizedBox(height: 10),
                  block(height: 10, radius: 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
        child: Column(
          children: [
            if (widget.tiles)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: block(height: 120, radius: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: block(height: 120, radius: 20)),
                  ],
                ),
              ),
            for (var i = 0; i < widget.cards; i++) card(),
          ],
        ),
      ),
    );
  }
}
