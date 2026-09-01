import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'tunnel_path.dart';

/// Reusable CPU storage for one bounded tunnel chunk.
class TunnelSegmentData {
  TunnelSegmentData({required this.ringCount, required this.verticesPerRing})
    : positions = Float32List(ringCount * verticesPerRing * 3),
      basePositions = Float32List(ringCount * verticesPerRing * 3),
      normals = Float32List(ringCount * verticesPerRing * 3),
      colors = Float32List(ringCount * verticesPerRing * 4),
      baseColors = Float32List(ringCount * verticesPerRing * 4),
      radialDirections = Float32List(ringCount * verticesPerRing * 3),
      pulsePerRing = Float32List(ringCount),
      indices = _makeIndices(ringCount, verticesPerRing);

  final int ringCount;
  final int verticesPerRing;
  final Float32List positions;
  final Float32List basePositions;
  final Float32List normals;
  final Float32List colors;
  final Float32List baseColors;
  final Float32List radialDirections;
  final Float32List pulsePerRing;
  final List<int> indices;
  int startRing = 0;

  static List<int> _makeIndices(int ringCount, int verticesPerRing) {
    final result = List<int>.filled(
      (ringCount - 1) * verticesPerRing * 6,
      0,
      growable: false,
    );
    var cursor = 0;
    for (var ring = 0; ring < ringCount - 1; ring++) {
      for (var side = 0; side < verticesPerRing; side++) {
        final nextSide = (side + 1) % verticesPerRing;
        final a = ring * verticesPerRing + side;
        final b = ring * verticesPerRing + nextSide;
        final c = (ring + 1) * verticesPerRing + side;
        final d = (ring + 1) * verticesPerRing + nextSide;
        result[cursor++] = a;
        result[cursor++] = c;
        result[cursor++] = b;
        result[cursor++] = b;
        result[cursor++] = c;
        result[cursor++] = d;
      }
    }
    return result;
  }
}

/// Deterministically fills pooled ring chunks at arbitrary world positions.
class TunnelGenerator {
  TunnelGenerator({
    this.seed = 0xD35A,
    this.verticesPerRing = 24,
    this.ringSpacing = 1,
    this.radius = 4.6,
  }) : path = TunnelPath(seed: seed);

  final int seed;
  final int verticesPerRing;
  final double ringSpacing;
  final double radius;
  final TunnelPath path;

  TunnelSegmentData createSegmentData(int ringCount) =>
      TunnelSegmentData(ringCount: ringCount, verticesPerRing: verticesPerRing);

  void fillSegment(TunnelSegmentData data, int startRing) {
    assert(data.verticesPerRing == verticesPerRing);
    data.startRing = startRing;

    for (var localRing = 0; localRing < data.ringCount; localRing++) {
      final globalRing = startRing + localRing;
      final distance = globalRing * ringSpacing;
      final sample = path.sample(distance);
      final ringNormal = _minimumTwistNormal(sample.tangent);
      final ringBinormal = sample.tangent.cross(ringNormal).normalized();
      final ringAccent = globalRing % 8 == 0;

      for (var side = 0; side < verticesPerRing; side++) {
        final angle = side * math.pi * 2 / verticesPerRing;
        final radial =
            ringNormal * math.cos(angle) + ringBinormal * math.sin(angle);
        final position = sample.position + radial * radius;
        final vertex = localRing * verticesPerRing + side;
        final p = vertex * 3;
        final c = vertex * 4;
        data.positions[p] = position.x;
        data.positions[p + 1] = position.y;
        data.positions[p + 2] = position.z;
        data.basePositions[p] = position.x;
        data.basePositions[p + 1] = position.y;
        data.basePositions[p + 2] = position.z;
        data.radialDirections[p] = radial.x;
        data.radialDirections[p + 1] = radial.y;
        data.radialDirections[p + 2] = radial.z;
        data.normals[p] = -radial.x;
        data.normals[p + 1] = -radial.y;
        data.normals[p + 2] = -radial.z;

        final sideAccent = side % 6 == 0;
        final glow = ringAccent || sideAccent ? 2.8 : 0.12;
        final magenta = (side ~/ 3).isOdd;
        data.colors[c] = magenta ? glow : glow * 0.05;
        data.colors[c + 1] = magenta ? glow * 0.08 : glow * 0.75;
        data.colors[c + 2] = glow;
        data.colors[c + 3] = 1;
        data.baseColors[c] = data.colors[c];
        data.baseColors[c + 1] = data.colors[c + 1];
        data.baseColors[c + 2] = data.colors[c + 2];
        data.baseColors[c + 3] = 1;
      }
    }
  }

  void deformSegment(
    TunnelSegmentData data, {
    required double bass,
    required double mids,
    required double treble,
    required double elapsedSeconds,
  }) {
    for (var localRing = 0; localRing < data.ringCount; localRing++) {
      final globalRing = data.startRing + localRing;
      final distance = globalRing * ringSpacing;
      final midWave = math.sin(distance * 0.62 + elapsedSeconds * 2.2);
      final pulse = data.pulsePerRing[localRing];
      final displacement =
          radius * (bass * 0.13 + mids * 0.035 * midWave) +
          radius * pulse * 0.17;
      final brightness = 1 + treble * 0.7 + pulse * 2.2;

      for (var side = 0; side < verticesPerRing; side++) {
        final vertex = localRing * verticesPerRing + side;
        final p = vertex * 3;
        final c = vertex * 4;
        data.positions[p] =
            data.basePositions[p] + data.radialDirections[p] * displacement;
        data.positions[p + 1] =
            data.basePositions[p + 1] +
            data.radialDirections[p + 1] * displacement;
        data.positions[p + 2] =
            data.basePositions[p + 2] +
            data.radialDirections[p + 2] * displacement;
        data.colors[c] = data.baseColors[c] * brightness;
        data.colors[c + 1] = data.baseColors[c + 1] * brightness;
        data.colors[c + 2] = data.baseColors[c + 2] * brightness;
      }
    }
  }

  MeshGeometry createGeometry(TunnelSegmentData data) =>
      MeshGeometry.fromArrays(
        positions: data.positions,
        normals: data.normals,
        colors: data.colors,
        indices: data.indices,
        storage: GeometryStorage.updatable,
      );

  void updateGeometry(MeshGeometry geometry, TunnelSegmentData data) {
    geometry.updatePositions(data.positions);
    geometry.updateColors(data.colors);
  }

  /// Rotates world-up by the shortest rotation from +Z to [tangent]. It is a
  /// deterministic rotation-minimizing frame, so neighboring pooled chunks
  /// agree exactly at their duplicated boundary ring.
  static vm.Vector3 _minimumTwistNormal(vm.Vector3 tangent) {
    final forward = vm.Vector3(0, 0, 1);
    final worldUp = vm.Vector3(0, 1, 0);
    final axis = forward.cross(tangent);
    final sine = axis.length;
    if (sine < 1e-7) return worldUp;
    axis.scale(1 / sine);
    final cosine = forward.dot(tangent);
    return (worldUp * cosine +
            axis.cross(worldUp) * sine +
            axis * axis.dot(worldUp) * (1 - cosine))
        .normalized();
  }
}
