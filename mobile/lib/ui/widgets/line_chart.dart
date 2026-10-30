import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../settings.dart';

/// A time series chart with value labels and optional limit lines.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.points,
    required this.window,
    required this.now,
    this.limits = const [],
    this.minY,
    this.maxY,
    this.height = 220,
  });

  /// (time, value), oldest first.
  final List<(DateTime, double)> points;
  final Duration window;
  final DateTime now;

  /// Horizontal lines, e.g. alert thresholds.
  final List<double> limits;
  final double? minY;
  final double? maxY;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ChartPainter(
          points: points,
          window: window,
          now: now,
          limits: limits,
          minY: minY,
          maxY: maxY,
          line: scheme.primary,
          grid: scheme.outlineVariant,
          label: (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
          ),
          limit: const Color(0xFFC62828),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.window,
    required this.now,
    required this.limits,
    required this.minY,
    required this.maxY,
    required this.line,
    required this.grid,
    required this.label,
    required this.limit,
  });

  final List<(DateTime, double)> points;
  final Duration window;
  final DateTime now;
  final List<double> limits;
  final double? minY;
  final double? maxY;
  final Color line;
  final Color grid;
  final TextStyle label;
  final Color limit;

  static const _labelWidth = 44.0;

  @override
  void paint(Canvas canvas, Size size) {
    final start = now.subtract(window);
    final visible = points.where((p) => !p.$1.isBefore(start)).toList();
    final data = [for (final p in visible) p.$2];
    var lo = minY ?? (data.isEmpty ? 0 : data.reduce(math.min));
    var hi = maxY ?? (data.isEmpty ? 1 : data.reduce(math.max));
    // Nearby limits widen the scale so they show; far ones would flatten the line.
    if (data.isNotEmpty && minY == null && maxY == null) {
      final span = math.max(hi - lo, hi.abs() * 0.1 + 1);
      for (final l in limits) {
        if (l > lo - span && l < hi + span) {
          lo = math.min(lo, l);
          hi = math.max(hi, l);
        }
      }
    }
    if (minY == null && maxY == null) {
      final pad = math.max((hi - lo) * 0.15, hi.abs() * 0.02 + 0.5);
      lo -= pad;
      hi += pad;
    }
    if (hi - lo < 1e-9) hi = lo + 1;

    final chart = Rect.fromLTWH(_labelWidth, 8, size.width - _labelWidth, size.height - 24);
    double y(double v) => chart.bottom - (v - lo) / (hi - lo) * chart.height;
    double x(DateTime t) => chart.left + t.difference(start).inMicroseconds / window.inMicroseconds * chart.width;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = lo + (hi - lo) * i / 4;
      final yy = y(v);
      canvas.drawLine(Offset(chart.left, yy), Offset(chart.right, yy), gridPaint);
      _text(canvas, AppSettings.number(double.parse(v.toStringAsFixed(1))), Offset(0, yy - 7), _labelWidth - 6);
    }
    _text(canvas, '-${_span(window)}', Offset(chart.left, chart.bottom + 4), 80, align: TextAlign.left);
    _text(canvas, 'now', Offset(chart.right - 60, chart.bottom + 4), 60);

    for (final l in limits) {
      final yy = y(l);
      if (yy < chart.top || yy > chart.bottom) continue;
      final dash = Paint()
        ..color = limit
        ..strokeWidth = 1.5;
      for (var xx = chart.left; xx < chart.right; xx += 10) {
        canvas.drawLine(Offset(xx, yy), Offset(math.min(xx + 5, chart.right), yy), dash);
      }
    }

    if (visible.length < 2) return;
    canvas.save();
    canvas.clipRect(chart);
    final path = Path()..moveTo(x(visible.first.$1), y(visible.first.$2));
    for (final p in visible.skip(1)) {
      path.lineTo(x(p.$1), y(p.$2));
    }
    final fill = Path.from(path)
      ..lineTo(x(visible.last.$1), chart.bottom)
      ..lineTo(x(visible.first.$1), chart.bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = line.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  static String _span(Duration d) => d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s';

  void _text(Canvas canvas, String text, Offset at, double width, {TextAlign align = TextAlign.right}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: label),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
