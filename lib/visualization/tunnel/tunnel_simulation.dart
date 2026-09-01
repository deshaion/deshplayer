import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'tunnel_path.dart';

/// Camera/path progression, independent of Flutter and audio playback.
class TunnelSimulation {
  TunnelSimulation({required this.path, this.travelSpeed = 6.0});

  final TunnelPath path;
  final double travelSpeed;
  double _distance = 0;
  double get distance => _distance;

  void advance(double deltaSeconds) {
    // Clamp lifecycle hiccups so resuming the app cannot skip many chunks in
    // one frame. Normal 60 FPS deltas pass through unchanged.
    _distance += travelSpeed * deltaSeconds.clamp(0, 0.1);
  }

  vm.Vector3 get cameraPosition => path.sample(_distance + 1).position;
  vm.Vector3 get cameraTarget => path.sample(_distance + 7).position;

  // A restrained roll keeps the camera alive without compromising the
  // forward-motion read. Curved path frames replace this in Phase 2.
  vm.Vector3 get cameraUp {
    final tangent = path.sample(_distance + 1).tangent;
    final worldUp = vm.Vector3(0, 1, 0);
    final normal = (worldUp - tangent * worldUp.dot(tangent)).normalized();
    final binormal = tangent.cross(normal).normalized();
    final roll = math.sin(_distance * 0.075) * 0.045;
    return (normal * math.cos(roll) + binormal * math.sin(roll)).normalized();
  }
}
