import 'package:vector_math/vector_math.dart' as vm;

class TunnelPathSample {
  const TunnelPathSample({required this.position, required this.tangent});

  final vm.Vector3 position;
  final vm.Vector3 tangent;
}

/// An infinite deterministic Catmull-Rom centerline advancing along +Z.
///
/// Control points are generated independently from `(seed, index)`, so any
/// portion of the world can be reconstructed without retaining its history.
class TunnelPath {
  const TunnelPath({required this.seed, this.controlPointSpacing = 9});

  final int seed;
  final double controlPointSpacing;

  TunnelPathSample sample(double distance) {
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
