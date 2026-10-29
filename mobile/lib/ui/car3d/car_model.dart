/// A stylised low-poly car, generated from side profiles so one generator
/// covers every body style (and every make).
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../brands/brand.dart';

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  Vec3 get normalized {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }

  static Vec3 lerp(Vec3 a, Vec3 b, double t) => a + (b - a) * t;
}

/// One flat-shaded triangle. [normal] points out of the car.
class Tri {
  Tri(this.a, this.b, this.c, this.color, this.normal, {this.gloss = 0});
  final Vec3 a, b, c;
  final Color color;
  final Vec3 normal;

  /// 0 = matte, 1 = shiny (paint and glass get highlights).
  final double gloss;

  Vec3 get centroid => (a + b + c) * (1 / 3);
}

/// A point on the car where a zone's hotspot is pinned.
class Anchor {
  const Anchor(this.position, this.normal);
  final Vec3 position;
  final Vec3 normal;
}

/// A convex piece of the car plus flat details ("decals") lying on it.
///
/// Because each part is convex, its front-facing triangles never overlap, so
/// parts can be drawn whole in a fixed order instead of sorting triangles:
/// far-side attachments, body, cabin, near-side attachments.
class Part {
  Part(this.centre, {this.attached = false});

  /// Used to decide which side of the car an attachment is on.
  final Vec3 centre;

  /// Wheels and mirrors: drawn before the body when on the far side, after it when near.
  final bool attached;
  final tris = <Tri>[];
  final decals = <Tri>[];
}

class CarMesh {
  CarMesh(this.parts, this.anchors, {required this.length, required this.width, required this.height});
  final List<Part> parts;
  final Map<CarZone, Anchor> anchors;
  final double length, width, height;

  double get boundingRadius => math.sqrt(length * length + width * width + height * height) / 2;
}

/// Dimensions (metres) and profile points for one body style.
class _Proportions {
  const _Proportions({
    required this.length,
    required this.width,
    required this.height,
    required this.wheelbase,
    required this.frontOverhang,
    required this.wheelRadius,
    required this.clearance,
    required this.belt,
    required this.hoodFront,
    required this.hoodLength,
    required this.roofFront,
    required this.roofRear,
    required this.tailTop,
    required this.cabinRearBase,
  });

  final double length, width, height, wheelbase, frontOverhang, wheelRadius, clearance;

  /// Height of the window line.
  final double belt;

  /// Height of the front edge of the bonnet.
  final double hoodFront;

  /// Distance from the nose to the bottom of the windscreen.
  final double hoodLength;

  /// Distances from the nose to the front and rear ends of the roof.
  final double roofFront, roofRear;

  /// Height of the rear body edge (boot lid / tailgate bottom).
  final double tailTop;

  /// Distance from the nose to the bottom of the rear window.
  final double cabinRearBase;

  static _Proportions of(BodyStyle style) => switch (style) {
    BodyStyle.hatchback => const _Proportions(
      length: 4.26,
      width: 1.80,
      height: 1.45,
      wheelbase: 2.62,
      frontOverhang: 0.86,
      wheelRadius: 0.32,
      clearance: 0.15,
      belt: 0.96,
      hoodFront: 0.76,
      hoodLength: 1.22,
      roofFront: 1.95,
      roofRear: 3.80,
      tailTop: 1.00,
      cabinRearBase: 4.14,
    ),
    BodyStyle.sedan => const _Proportions(
      length: 4.77,
      width: 1.83,
      height: 1.46,
      wheelbase: 2.79,
      frontOverhang: 0.95,
      wheelRadius: 0.33,
      clearance: 0.15,
      belt: 0.97,
      hoodFront: 0.76,
      hoodLength: 1.35,
      roofFront: 2.10,
      roofRear: 3.50,
      tailTop: 1.04,
      cabinRearBase: 4.00,
    ),
    BodyStyle.wagon => const _Proportions(
      length: 4.66,
      width: 1.80,
      height: 1.48,
      wheelbase: 2.68,
      frontOverhang: 0.88,
      wheelRadius: 0.32,
      clearance: 0.15,
      belt: 0.97,
      hoodFront: 0.76,
      hoodLength: 1.25,
      roofFront: 2.00,
      roofRear: 4.35,
      tailTop: 1.00,
      cabinRearBase: 4.58,
    ),
    BodyStyle.suv => const _Proportions(
      length: 4.49,
      width: 1.84,
      height: 1.66,
      wheelbase: 2.68,
      frontOverhang: 0.90,
      wheelRadius: 0.37,
      clearance: 0.21,
      belt: 1.12,
      hoodFront: 0.92,
      hoodLength: 1.25,
      roofFront: 1.98,
      roofRear: 4.02,
      tailTop: 1.14,
      cabinRearBase: 4.36,
    ),
  };
}

class _Builder {
  final parts = <Part>[];
  late Part _part;
  bool _decal = false;

  /// Starts a new part; following faces belong to it.
  void part(Vec3 centre, {bool attached = false}) {
    _part = Part(centre, attached: attached);
    parts.add(_part);
    _decal = false;
  }

  /// Following faces are details drawn on top of the current part.
  void decals() => _decal = true;

  /// Adds a convex polygon, oriented so its normal points away from [inside].
  void face(List<Vec3> pts, Color color, Vec3 inside, {double gloss = 0}) {
    if (pts.length < 3) return;
    var n = (pts[1] - pts[0]).cross(pts[2] - pts[0]);
    // Use the largest cross product for numerical robustness on thin faces.
    for (var i = 2; i < pts.length; i++) {
      final c = (pts[i - 1] - pts[0]).cross(pts[i] - pts[0]);
      if (c.length > n.length) n = c;
    }
    n = n.normalized;
    final centre = pts.fold(const Vec3(0, 0, 0), (Vec3 s, p) => s + p) * (1 / pts.length);
    final flip = n.dot(centre - inside) < 0;
    if (flip) n = n * -1;
    for (var i = 1; i < pts.length - 1; i++) {
      _add(
        flip
            ? Tri(pts[0], pts[i + 1], pts[i], color, n, gloss: gloss)
            : Tri(pts[0], pts[i], pts[i + 1], color, n, gloss: gloss),
      );
    }
  }

  void _add(Tri t) => (_decal ? _part.decals : _part.tris).add(t);

  /// Extrudes a convex side profile (x, y) across the car. [halfWidth] gives
  /// the half width at a height, so cabins can lean in (tumblehome).
  /// [edgeColors][i] colours the face between profile points i and i+1;
  /// [sideColor] colours the two side faces.
  void extrude(
    List<Offset> profile,
    double Function(double y) halfWidth, {
    required List<Color> edgeColors,
    required Color sideColor,
    List<double>? edgeGloss,
    double sideGloss = 0,
  }) {
    final left = [for (final p in profile) Vec3(p.dx, p.dy, -halfWidth(p.dy))];
    final right = [for (final p in profile) Vec3(p.dx, p.dy, halfWidth(p.dy))];
    final cx = profile.fold(0.0, (s, p) => s + p.dx) / profile.length;
    final cy = profile.fold(0.0, (s, p) => s + p.dy) / profile.length;
    final inside = Vec3(cx, cy, 0);
    face(left, sideColor, inside, gloss: sideGloss);
    face(right, sideColor, inside, gloss: sideGloss);
    for (var i = 0; i < profile.length; i++) {
      final j = (i + 1) % profile.length;
      face([left[i], left[j], right[j], right[i]], edgeColors[i], inside, gloss: edgeGloss?[i] ?? 0);
    }
  }

  /// A cylinder along z (a wheel), from z0 to z1.
  void wheel(double x, double y, double r, double z0, double z1, {required Color tyre, required Color rim}) {
    const n = 18;
    final inside = Vec3(x, y, (z0 + z1) / 2);
    part(inside, attached: true);
    Vec3 at(int i, double z, double rr) {
      final a = 2 * math.pi * i / n;
      return Vec3(x + rr * math.cos(a), y + rr * math.sin(a), z);
    }

    for (var i = 0; i < n; i++) {
      face([at(i, z0, r), at(i + 1, z0, r), at(i + 1, z1, r), at(i, z1, r)], tyre, inside);
    }
    final outer = z1.abs() > z0.abs() ? z1 : z0;
    final innerCap = outer == z1 ? z0 : z1;
    face([for (var i = 0; i < n; i++) at(i, innerCap, r)], tyre, inside);
    face([for (var i = 0; i < n; i++) at(i, outer, r)], tyre, inside);
    // Rim and hub, just proud of the tyre wall.
    decals();
    final sign = outer.sign;
    face([for (var i = 0; i < n; i++) at(i, outer + sign * 0.006, r * 0.66)], rim, inside, gloss: 0.6);
    face([for (var i = 0; i < 8; i++) at(i * n ~/ 8, outer + sign * 0.012, r * 0.18)], tyre, inside);
  }
}

const _tyre = Color(0xFF26282B);
const _rim = Color(0xFFC3C8CF);
const _glass = Color(0xFF1C2733);
const _trim = Color(0xFF2E3237);
const _headlight = Color(0xFFEFF4FA);
const _taillight = Color(0xFFC62828);
const _underbody = Color(0xFF1A1C1E);

/// Builds the car for [style] painted [paint].
CarMesh buildCar(BodyStyle style, Color paint) {
  final p = _Proportions.of(style);
  final b = _Builder();
  final front = p.length / 2, rear = -p.length / 2, hw = p.width / 2;
  double nose(double d) => front - d; // distance from nose -> x
  final axles = [nose(p.frontOverhang), nose(p.frontOverhang + p.wheelbase)];

  // ---- Lower body: nose -> bonnet -> window line -> boot -> tail -> underside.
  final body = [
    Offset(front - 0.10, p.clearance),
    Offset(front, p.clearance + 0.36),
    Offset(front - 0.05, p.hoodFront),
    Offset(nose(p.hoodLength), p.belt),
    Offset(nose(p.cabinRearBase), p.tailTop),
    Offset(rear + 0.08, p.tailTop - 0.02), // boot deck (long on sedans)
    Offset(rear, p.tailTop - 0.30),
    Offset(rear + 0.06, p.clearance),
  ];
  b.part(Vec3(0, p.belt / 2, 0));
  b.extrude(
    body,
    (y) => hw,
    edgeColors: [paint, paint, paint, paint, paint, paint, paint, _underbody],
    edgeGloss: [0.3, 0.6, 0.8, 0.8, 0.8, 0.6, 0.3, 0],
    sideColor: paint,
    sideGloss: 0.5,
  );

  b.decals();
  for (final side in [-1.0, 1.0]) {
    // Wheel arches and side skirt.
    for (final axle in axles) {
      const n = 12;
      final r = p.wheelRadius + 0.07;
      final arch = [
        for (var i = 0; i <= n; i++)
          Vec3(
            axle + r * math.cos(math.pi * i / n),
            p.wheelRadius + r * math.sin(math.pi * i / n) * 0.95,
            side * (hw + 0.004),
          ),
      ];
      b.face(arch, _underbody, Vec3(axle, 0.5, 0));
    }
    final skirtFront = axles[0] - p.wheelRadius - 0.08, skirtRear = axles[1] + p.wheelRadius + 0.08;
    b.face(
      [
        Vec3(skirtFront, p.clearance, side * (hw + 0.004)),
        Vec3(skirtFront, p.clearance + 0.09, side * (hw + 0.004)),
        Vec3(skirtRear, p.clearance + 0.09, side * (hw + 0.004)),
        Vec3(skirtRear, p.clearance, side * (hw + 0.004)),
      ],
      _trim,
      Vec3(0, 0.5, 0),
    );
  }

  // Front: grille, headlights, lower intake. They follow the slope of the nose.
  Vec3 fv(double z, double y) {
    final t = ((y - (p.clearance + 0.36)) / (p.hoodFront - (p.clearance + 0.36))).clamp(0.0, 1.0);
    return Vec3(front + 0.004 - 0.05 * t, y, z);
  }

  final inFront = Vec3(front - 0.5, 0.6, 0);
  final lightY = p.hoodFront - 0.04;
  b.face(
    [fv(-0.36, lightY - 0.13), fv(0.36, lightY - 0.13), fv(0.36, lightY - 0.03), fv(-0.36, lightY - 0.03)],
    _trim,
    inFront,
  );
  for (final s in [-1.0, 1.0]) {
    b.face(
      [
        fv(s * 0.40, lightY - 0.14),
        fv(s * (hw - 0.06), lightY - 0.11),
        fv(s * (hw - 0.06), lightY),
        fv(s * 0.40, lightY - 0.02),
      ],
      _headlight,
      inFront,
      gloss: 1,
    );
  }
  b.face(
    [
      fv(-0.62, p.clearance + 0.08),
      fv(0.62, p.clearance + 0.08),
      fv(0.66, p.clearance + 0.26),
      fv(-0.66, p.clearance + 0.26),
    ],
    _trim,
    inFront,
  );

  // Rear: tail lights and bumper. The rear face leans in 8 cm towards the boot edge.
  Vec3 rv(double z, double y) {
    final t = ((y - (p.tailTop - 0.30)) / 0.28).clamp(0.0, 1.0);
    return Vec3(rear - 0.004 + 0.08 * t, y, z);
  }

  final inRear = Vec3(rear + 0.5, 0.6, 0);
  final tlY = p.tailTop - 0.12;
  for (final s in [-1.0, 1.0]) {
    b.face(
      [
        rv(s * (hw - 0.04), tlY - 0.07),
        rv(s * (hw - 0.44), tlY - 0.07),
        rv(s * (hw - 0.44), tlY + 0.06),
        rv(s * (hw - 0.04), tlY + 0.06),
      ],
      _taillight,
      inRear,
      gloss: 0.8,
    );
  }
  b.face(
    [
      Vec3(rear + 0.06 - 0.004, p.clearance + 0.02, -hw + 0.1),
      Vec3(rear + 0.06 - 0.004, p.clearance + 0.02, hw - 0.1),
      Vec3(rear + 0.02 - 0.004, p.clearance + 0.16, hw - 0.1),
      Vec3(rear + 0.02 - 0.004, p.clearance + 0.16, -hw + 0.1),
    ],
    _trim,
    inRear,
  );

  // ---- Cabin, leaning in towards the roof.
  final cabin = [
    Offset(nose(p.hoodLength), p.belt),
    Offset(nose(p.roofFront), p.height),
    Offset(nose(p.roofRear), p.height),
    Offset(nose(p.cabinRearBase), p.tailTop),
  ];
  double cabinHalf(double y) {
    final t = ((y - p.belt) / (p.height - p.belt)).clamp(0.0, 1.0);
    return hw - 0.05 - t * 0.17;
  }

  final centre = cabin.fold(Offset.zero, (s, o) => s + o) / cabin.length.toDouble();
  b.part(Vec3(centre.dx, centre.dy, 0));
  b.extrude(
    cabin,
    cabinHalf,
    edgeColors: [_glass, paint, _glass, paint],
    edgeGloss: [1, 0.8, 1, 0],
    sideColor: paint,
    sideGloss: 0.5,
  );

  // Side windows: the cabin side shrunk inwards, split by the B pillar.
  b.decals();
  final glass = [for (final o in cabin) centre + (o - centre) * 0.86];
  final pillarX = nose((p.roofFront + p.roofRear) / 2 - 0.15);
  for (final side in [-1.0, 1.0]) {
    Vec3 v(Offset o, double out) => Vec3(o.dx, o.dy, side * (cabinHalf(o.dy) + out));
    b.face([for (final o in glass) v(o, 0.006)], _glass, Vec3(centre.dx, centre.dy, 0), gloss: 1);
    b.face(
      [
        v(Offset(pillarX - 0.05, p.belt), 0.012),
        v(Offset(pillarX + 0.05, p.belt), 0.012),
        v(Offset(pillarX + 0.05, p.height), 0.012),
        v(Offset(pillarX - 0.05, p.height), 0.012),
      ],
      paint,
      Vec3(pillarX, centre.dy, 0),
      gloss: 0.4,
    );
  }

  // ---- Attachments: mirrors and wheels.
  for (final side in [-1.0, 1.0]) {
    final mx = nose(p.hoodLength) - 0.06, my = p.belt + 0.05, root = cabinHalf(p.belt) - 0.02;
    const reach = 0.20, h = 0.11, d = 0.16;
    final c = Vec3(mx - d / 2, my + h / 2, side * (root + reach / 2));
    b.part(c, attached: true);
    // A small box from the door to the mirror tip.
    Vec3 m(double dx, double dy, double out) => Vec3(mx - dx, my + dy, side * (root + out));
    final corners = [
      [m(0, 0, 0), m(d, 0, 0), m(d, h, 0), m(0, h, 0)],
      [m(0, 0, reach), m(d, 0, reach), m(d, h, reach), m(0, h, reach)],
    ];
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      b.face([corners[0][i], corners[0][j], corners[1][j], corners[1][i]], i == 3 ? _trim : paint, c, gloss: 0.5);
    }
    b.face(corners[1], paint, c, gloss: 0.5);

    for (final axle in axles) {
      b.wheel(axle, p.wheelRadius, p.wheelRadius, side * (hw - 0.24), side * (hw + 0.012), tyre: _tyre, rim: _rim);
    }
  }

  final roofMid = nose((p.roofFront + p.roofRear) / 2);
  final anchors = {
    CarZone.engine: Anchor(
      Vec3(nose(p.hoodLength * 0.45), (p.hoodFront + p.belt) / 2 + 0.05, 0),
      const Vec3(0.3, 1, 0),
    ),
    CarZone.interior: Anchor(Vec3(roofMid + 0.3, p.height + 0.02, 0), const Vec3(0, 1, 0)),
    CarZone.chassis: Anchor(Vec3(axles[1], p.wheelRadius, hw + 0.03), const Vec3(0, 0.2, 1)),
    CarZone.body: Anchor(Vec3(front - 0.02, lightY - 0.06, hw - 0.25), const Vec3(1, 0.1, 0.5)),
  };
  return CarMesh(b.parts, anchors, length: p.length, width: p.width, height: p.height);
}
