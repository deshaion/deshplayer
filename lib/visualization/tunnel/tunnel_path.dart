import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

class TunnelPathSample {
  const TunnelPathSample({required this.position, required this.tangent});

  final vm.Vector3 position;
  final vm.Vector3 tangent;
}

class TunnelJunction {
  const TunnelJunction({
    required this.index,
    required this.centerDistance,
    required this.direction,
    required this.selectedSign,
  });

  final int index;
  final double centerDistance;
  final vm.Vector2 direction;
  final double selectedSign;

  double get splitStart => centerDistance - 24;
  double get fullSplit => centerDistance + 16;
  double get branchEnd => centerDistance + 54;
  double get recoveryEnd => centerDistance + 82;
}

/// An infinite deterministic Catmull-Rom centerline advancing along +Z.
///
/// Control points are generated independently from `(seed, index)`, so any
/// portion of the world can be reconstructed without retaining its history.
class TunnelPath {
  const TunnelPath({
    required this.seed,
    this.controlPointSpacing = 16,
    this.firstJunctionDistance = 60,
    this.junctionSpacing = 180,
    this.branchOffset = 8.5,
  });

  final int seed;
  final double controlPointSpacing;
  final double firstJunctionDistance;
  final double junctionSpacing;
  final double branchOffset;

  TunnelPathSample sample(double distance) {
    final base = _sampleBase(distance);
    final offset = vm.Vector2.zero();
    final derivative = vm.Vector2.zero();
    final nearby = ((distance - firstJunctionDistance) / junctionSpacing)
        .floor();
    for (var index = math.max(0, nearby - 1); index <= nearby + 1; index++) {
      final junction = junctionAt(index);
      final profile = _mainProfile(distance, junction);
      if (profile.$1 == 0 && profile.$2 == 0) continue;
      final signedDirection =
          junction.direction * junction.selectedSign * branchOffset;
      offset.add(signedDirection * profile.$1);
      derivative.add(signedDirection * profile.$2);
    }
    return TunnelPathSample(
      position: base.position + vm.Vector3(offset.x, offset.y, 0),
      tangent: (base.tangent + vm.Vector3(derivative.x, derivative.y, 0))
          .normalized(),
    );
  }

  /// Samples the passage the camera will not take. It shares the exact same
  /// centerline at [TunnelJunction.splitStart] and then bends to the opposite
  /// side, producing a physical Y rather than a scene transition.
  TunnelPathSample sampleUnselectedBranch(
    double distance,
    TunnelJunction junction,
  ) {
    final base = _sampleBase(distance);
    final profile = _branchProfile(distance, junction);
    final signedDirection =
        junction.direction * -junction.selectedSign * branchOffset;
    final offset = signedDirection * profile.$1;
    final derivative = signedDirection * profile.$2;
    return TunnelPathSample(
      position: base.position + vm.Vector3(offset.x, offset.y, 0),
      tangent: (base.tangent + vm.Vector3(derivative.x, derivative.y, 0))
          .normalized(),
    );
  }

  TunnelJunction junctionAt(int index) {
    final angle = (_unitHash(seed ^ (index * 0x6c8e9cf5)) - 0.5) * 1.15;
    final direction = vm.Vector2(math.cos(angle), math.sin(angle)).normalized();
    final selected = _unitHash((seed + 0x51ed270b) ^ (index * 0x165667b1));
    return TunnelJunction(
      index: index,
      centerDistance: firstJunctionDistance + index * junctionSpacing,
      direction: direction,
      selectedSign: selected < 0.5 ? -1 : 1,
    );
  }

  int nextJunctionIndex(double distance) {
    if (distance <= firstJunctionDistance) return 0;
    return ((distance - firstJunctionDistance) / junctionSpacing).ceil();
  }

  TunnelPathSample _sampleBase(double distance) {
    final segmentValue = distance / controlPointSpacing;
    final segment = segmentValue.floor();
    final t = segmentValue - segment;
    final p0 = _point(segment - 1);
    final p1 = _point(segment);
    final p2 = _point(segment + 1);
    final p3 = _point(segment + 2);
    final lateral = _catmullRom(p0, p1, p2, p3, t);
    final derivative =
        _catmullRomDerivative(p0, p1, p2, p3, t) / controlPointSpacing;

    return TunnelPathSample(
      position: vm.Vector3(lateral.x, lateral.y, distance),
      tangent: vm.Vector3(derivative.x, derivative.y, 1).normalized(),
    );
  }

  (double, double) _mainProfile(double distance, TunnelJunction junction) {
    if (distance <= junction.splitStart || distance >= junction.recoveryEnd) {
      return (0, 0);
    }
    if (distance < junction.fullSplit) {
      return _smoothRamp(distance, junction.splitStart, junction.fullSplit);
    }
    final fall = _smoothRamp(
      distance,
      junction.fullSplit,
      junction.recoveryEnd,
    );
    return (1 - fall.$1, -fall.$2);
  }

  (double, double) _branchProfile(double distance, TunnelJunction junction) {
    if (distance <= junction.splitStart) return (0, 0);
    if (distance < junction.fullSplit) {
      return _smoothRamp(distance, junction.splitStart, junction.fullSplit);
    }
    // Continue opening slightly so the unused passage clearly separates.
    final extension =
        ((distance - junction.fullSplit) /
                (junction.branchEnd - junction.fullSplit))
            .clamp(0, 1);
    return (
      1 + extension * 0.18,
      0.18 / (junction.branchEnd - junction.fullSplit),
    );
  }

  static (double, double) _smoothRamp(double value, double start, double end) {
    final t = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return (t * t * (3 - 2 * t), 6 * t * (1 - t) / (end - start));
  }

  vm.Vector2 _point(int index) {
    final x = _unitHash(seed ^ (index * 0x45d9f3b));
    final y = _unitHash((seed + 0x632be5ab) ^ (index * 0x27d4eb2d));
    return vm.Vector2((x * 2 - 1) * 2.5, (y * 2 - 1) * 1.75);
  }

  static double _unitHash(int value) {
    var hash = value & 0xFFFFFFFF;
    hash = ((hash ^ (hash >> 16)) * 0x7feb352d) & 0xFFFFFFFF;
    hash = ((hash ^ (hash >> 15)) * 0x846ca68b) & 0xFFFFFFFF;
    hash = (hash ^ (hash >> 16)) & 0xFFFFFFFF;
    return hash / 0xFFFFFFFF;
  }

  static vm.Vector2 _catmullRom(
    vm.Vector2 p0,
    vm.Vector2 p1,
    vm.Vector2 p2,
    vm.Vector2 p3,
    double t,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;
    return (p1 * 2 +
            (p2 - p0) * t +
            (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
            (-p0 + p1 * 3 - p2 * 3 + p3) * t3) *
        0.5;
  }

  static vm.Vector2 _catmullRomDerivative(
    vm.Vector2 p0,
    vm.Vector2 p1,
    vm.Vector2 p2,
    vm.Vector2 p3,
    double t,
  ) {
    return ((p2 - p0) +
            (p0 * 2 - p1 * 5 + p2 * 4 - p3) * (2 * t) +
            (-p0 + p1 * 3 - p2 * 3 + p3) * (3 * t * t)) *
        0.5;
  }
}
