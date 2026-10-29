import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../brands/brand.dart';
import 'car_model.dart';

/// What a hotspot shows: a colour (status) and a short text.
class Hotspot {
  const Hotspot({required this.color, required this.label, this.icon});
  final Color color;
  final String label;
  final IconData? icon;
}

/// An interactive 3D car: drag to turn it, tap a hotspot to open that area.
class CarView extends StatefulWidget {
  const CarView({
    super.key,
    required this.style,
    required this.paint,
    this.hotspots = const {},
    this.onZoneTap,
    this.height = 240,
  });

  final BodyStyle style;
  final Color paint;
  final Map<CarZone, Hotspot> hotspots;
  final void Function(CarZone zone)? onZoneTap;
  final double height;

  @override
  State<CarView> createState() => _CarViewState();
}

class _CarViewState extends State<CarView> with SingleTickerProviderStateMixin {
  static const _restYaw = 0.62; // front three-quarter view
  late CarMesh _mesh = buildCar(widget.style, widget.paint);
  double _yaw = _restYaw;
  double _pitch = 0.30;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..addListener(() => setState(() => _yaw = _restYaw + 1.1 * (1 - Curves.easeOutCubic.transform(_intro.value))))
    ..forward();

  @override
  void didUpdateWidget(CarView old) {
    super.didUpdateWidget(old);
    if (old.style != widget.style || old.paint != widget.paint) _mesh = buildCar(widget.style, widget.paint);
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          final camera = _Camera(size, _mesh, _yaw, _pitch);
          return GestureDetector(
            onPanStart: (_) => _intro.stop(),
            onPanUpdate: (d) => setState(() {
              _yaw -= d.delta.dx * 0.012;
              _pitch = (_pitch + d.delta.dy * 0.006).clamp(0.05, 0.75);
            }),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CarPainter(
                      _mesh,
                      camera,
                      shadow: theme.brightness == Brightness.dark ? Colors.black : const Color(0xFF1B2A3A),
                    ),
                  ),
                ),
                for (final entry in widget.hotspots.entries)
                  if (_mesh.anchors[entry.key] case final anchor?)
                    _hotspot(context, camera, entry.key, anchor, entry.value),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _hotspot(BuildContext context, _Camera camera, CarZone zone, Anchor anchor, Hotspot spot) {
    final point = camera.project(anchor.position);
    final facing = anchor.normal.normalized.dot((camera.eye - anchor.position).normalized);
    final opacity = ((facing + 0.25) * 2.5).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    return Positioned(
      left: point.dx,
      top: point.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: IgnorePointer(
          ignoring: opacity < 0.4,
          child: Opacity(
            opacity: opacity,
            child: Semantics(
              button: true,
              label: '${zone.label}: ${spot.label}',
              child: GestureDetector(
                onTap: widget.onZoneTap == null ? null : () => widget.onZoneTap!(zone),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: spot.color, width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(color: spot.color, shape: BoxShape.circle),
                        child: spot.icon == null ? null : Icon(spot.icon, size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Text(spot.label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Orbit camera looking at the middle of the car.
class _Camera {
  _Camera(this.size, CarMesh mesh, double yaw, double pitch) {
    final target = Vec3(0, mesh.height * 0.42, 0);
    const distance = 11.0;
    eye = target + Vec3(math.cos(pitch) * math.cos(yaw), math.sin(pitch), math.cos(pitch) * math.sin(yaw)) * distance;
    forward = (target - eye).normalized;
    right = forward.cross(const Vec3(0, 1, 0)).normalized;
    up = right.cross(forward);
    // Fit the car's bounding sphere (horizontal extent) into the view.
    final halfSpan = mesh.boundingRadius;
    focal = math.min(size.width * 0.5, size.height * 0.95) * distance / halfSpan * 0.9;
    centre = Offset(size.width / 2, size.height * 0.52);
  }

  final Size size;
  late final Vec3 eye, forward, right, up;
  late final double focal;
  late final Offset centre;

  double depth(Vec3 p) => (p - eye).dot(forward);

  Offset project(Vec3 p) {
    final d = p - eye;
    final z = d.dot(forward);
    return centre + Offset(d.dot(right) / z * focal, -d.dot(up) / z * focal);
  }
}

class _CarPainter extends CustomPainter {
  _CarPainter(this.mesh, this.camera, {required this.shadow});

  final CarMesh mesh;
  final _Camera camera;
  final Color shadow;

  static final _light = const Vec3(0.35, 1, 0.55).normalized;

  @override
  void paint(Canvas canvas, Size size) {
    _paintShadow(canvas);

    // Draw order: far-side attachments, then body and cabin, then near-side
    // attachments (each part is convex, so culled triangles never overlap).
    // Attachments sit on the left or right, so only the side the camera is on matters.
    bool near(Part p) => p.centre.z * camera.eye.z > 0;
    int byDepth(Part a, Part b) => camera.depth(b.centre).compareTo(camera.depth(a.centre));
    final attached = mesh.parts.where((p) => p.attached).toList()..sort(byDepth);
    final ordered = [
      ...attached.where((p) => !near(p)),
      ...mesh.parts.where((p) => !p.attached),
      ...attached.where(near),
    ];
    final visible = [
      for (final part in ordered)
        for (final t in [...part.tris, ...part.decals])
          if (t.normal.dot(camera.eye - t.centroid) > 0) t,
    ];

    final positions = Float32List(visible.length * 6);
    final colors = Int32List(visible.length * 3);
    var i = 0;
    for (final t in visible) {
      final a = camera.project(t.a), b = camera.project(t.b), c = camera.project(t.c);
      // Grow each triangle by a fraction of a pixel to hide seams between neighbours.
      final m = (a + b + c) / 3;
      Offset grow(Offset p) {
        final d = p - m;
        final l = d.distance;
        return l == 0 ? p : p + d / l * 0.45;
      }

      for (final p in [grow(a), grow(b), grow(c)]) {
        positions[i++] = p.dx;
        positions[i++] = p.dy;
      }
      final color = _shade(t);
      final k = (i ~/ 2) - 3;
      colors[k] = colors[k + 1] = colors[k + 2] = color.toARGB32();
    }
    canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, positions, colors: colors), BlendMode.dst, Paint());
  }

  Color _shade(Tri t) {
    final diffuse = math.max(0.0, t.normal.dot(_light));
    final toEye = (camera.eye - t.centroid).normalized;
    final half = (_light + toEye).normalized;
    final spec = t.gloss == 0 ? 0.0 : math.pow(math.max(0.0, t.normal.dot(half)), 28).toDouble() * 0.55 * t.gloss;
    final k = 0.52 + 0.55 * diffuse;
    int ch(double v) => (v * k * 255 + spec * 255).clamp(0, 255).round();
    return Color.fromARGB(255, ch(t.color.r), ch(t.color.g), ch(t.color.b));
  }

  void _paintShadow(Canvas canvas) {
    final l = mesh.length / 2 + 0.15, w = mesh.width / 2 + 0.12;
    final corners = [
      for (var a = 0; a < 24; a++)
        camera.project(Vec3(l * math.cos(2 * math.pi * a / 24), 0, w * math.sin(2 * math.pi * a / 24))),
    ];
    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = shadow.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  @override
  bool shouldRepaint(_CarPainter old) => true;
}
