import 'package:flutter/material.dart';

/// A minimal line chart of recent values.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.min, required this.max, this.height = 36});

  final List<double> values;
  final double min;
  final double max;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _SparklinePainter(values, min, max, Theme.of(context).colorScheme.primary)),
  );
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.min, this.max, this.color);

  final List<double> values;
  final double min;
  final double max;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final range = (max - min).abs() < 1e-9 ? 1.0 : max - min;
    final dx = size.width / (values.length - 1);
    Offset point(int i) => Offset(i * dx, size.height - ((values[i] - min) / range).clamp(0.0, 1.0) * size.height);
    final line = Path()..moveTo(0, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(point(i).dx, point(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => true;
}
