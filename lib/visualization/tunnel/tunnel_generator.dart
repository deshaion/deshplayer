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
  bool topologyDirty = true;
  final Set<int> junctionRings = <int>{};

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
    this.verticesPerRing = 144,
    this.ringSpacing = 0.5,
    this.radius = 4.6,
  }) : path = TunnelPath(seed: seed),
       _phase1 = _phaseFor(seed, 0x19),
       _phase2 = _phaseFor(seed, 0x47),
       _phase3 = _phaseFor(seed, 0x83);

  final int seed;
  final int verticesPerRing;
  final double ringSpacing;
  final double radius;
  final TunnelPath path;
  final double _phase1;
  final double _phase2;
  final double _phase3;

  TunnelSegmentData createSegmentData(int ringCount) =>
      TunnelSegmentData(ringCount: ringCount, verticesPerRing: verticesPerRing);

  void fillSegment(TunnelSegmentData data, int startRing) {
    _fillSegment(data, startRing, path.sample);
    _openJunctions(data);
  }

  void fillUnselectedBranch(TunnelSegmentData data, TunnelJunction junction) {
    final startRing = (junction.splitStart / ringSpacing).round();
    _fillSegment(
      data,
      startRing,
      (distance) => path.sampleUnselectedBranch(distance, junction),
    );
    _openJunctions(data, branch: junction);
  }

  void _fillSegment(
    TunnelSegmentData data,
    int startRing,
    TunnelPathSample Function(double distance) samplePath,
  ) {
    assert(data.verticesPerRing == verticesPerRing);
    data.startRing = startRing;
    data.junctionRings.clear();
    data.topologyDirty = true;
    data.indices.setAll(
      0,
      TunnelSegmentData._makeIndices(data.ringCount, verticesPerRing),
    );

    for (var localRing = 0; localRing < data.ringCount; localRing++) {
      final globalRing = startRing + localRing;
      final distance = globalRing * ringSpacing;
      final sample = samplePath(distance);
      final ringNormal = _minimumTwistNormal(sample.tangent);
      final ringBinormal = sample.tangent.cross(ringNormal).normalized();
      final ringAccent = globalRing % 16 == 0;

      for (var side = 0; side < verticesPerRing; side++) {
        // Cluster vertices around six rails, giving the lights a narrow
        // luminous core without painting broad gradients across the walls.
        final angle = _angleForSide(side);
        final radial =
            ringNormal * math.cos(angle) + ringBinormal * math.sin(angle);
        final caveRadius = radius + _organicDisplacement(distance, angle);
        final position = sample.position + radial * caveRadius;
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

        final railDistance = (angle / (math.pi / 3)) % 1;
        final rail = math.min(railDistance, 1 - railDistance);
        final core = math.exp(-math.pow(rail / 0.012, 2));
        final halo = math.exp(-math.pow(rail / 0.075, 2));
        // Violet above, glacial cyan below: one continuous palette instead
        // of alternating hot-colored wedges.
        final violet = (0.5 + 0.5 * math.cos(angle)).clamp(0.0, 1.0);
        final red = 0.12 + violet * 0.42;
        final green = 0.82 - violet * 0.46;
        final rib = ringAccent ? 0.32 : 0.0;
        final light = core * 1.65 + halo * 0.09 + rib;
        final wall = 0.018 + 0.018 * math.pow(math.sin(angle), 2);
        data.colors[c] = wall * 0.38 + light * red + core * 0.18;
        data.colors[c + 1] = wall * 0.65 + light * green + core * 0.18;
        data.colors[c + 2] = wall + light + core * 0.18;
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
      final displacement = data.junctionRings.contains(localRing)
          ? 0.0
          : radius * (bass * 0.055 + mids * 0.018 * midWave + pulse * 0.065);
      final brightness = 1 + treble * 0.25 + pulse * 0.85;

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
    if (data.topologyDirty) {
      geometry.rebuild(
        positions: data.positions,
        normals: data.normals,
        colors: data.colors,
        indices: data.indices,
      );
      data.topologyDirty = false;
      return;
    }
    geometry.updatePositions(data.positions);
    geometry.updateColors(data.colors);
  }

  /// Remove the walls inside the other passage, preserving the outer shell.
  /// Degenerate triangles keep the pooled index buffer at its fixed capacity.
  void _openJunctions(TunnelSegmentData data, {TunnelJunction? branch}) {
    for (var ring = 0; ring < data.ringCount - 1; ring++) {
      final distance = (data.startRing + ring + 0.5) * ringSpacing;
      final index =
          ((distance - path.firstJunctionDistance + 24) / path.junctionSpacing)
              .floor();
      if (index < 0) continue;
      final junction = branch ?? path.junctionAt(index);
      if (distance < junction.splitStart || distance > junction.branchEnd) {
        continue;
      }
      final other = branch == null
          ? path.sampleUnselectedBranch(distance, junction)
          : path.sample(distance);
      data.junctionRings.addAll([ring, ring + 1]);
      for (var side = 0; side < verticesPerRing; side++) {
        final start = (ring * verticesPerRing + side) * 6;
        for (var triangle = start; triangle < start + 6; triangle += 3) {
          final center = vm.Vector3.zero();
          for (var corner = 0; corner < 3; corner++) {
            final p = data.indices[triangle + corner] * 3;
            center.add(
              vm.Vector3(
                data.positions[p],
                data.positions[p + 1],
                data.positions[p + 2],
              ),
            );
          }
          center.scale(1 / 3);
          // Refine longitudinal position because curved rings are not XY planes.
          final otherAtVertex = branch == null
              ? path.sampleUnselectedBranch(center.z, junction)
              : path.sample(center.z);
          final offset = center - otherAtVertex.position;
          final normal = _minimumTwistNormal(otherAtVertex.tangent);
          final binormal = otherAtVertex.tangent.cross(normal).normalized();
          final angle = math.atan2(offset.dot(binormal), offset.dot(normal));
          final wallRadius = radius + _organicDisplacement(center.z, angle);
          final radial = offset - other.tangent * offset.dot(other.tangent);
          if (radial.length < wallRadius - 0.08) {
            data.indices[triangle + 1] = data.indices[triangle];
            data.indices[triangle + 2] = data.indices[triangle];
          }
        }
      }
    }
  }

  double _organicDisplacement(double distance, double angle) {
    // Periodic angular harmonics make the seam exact; low longitudinal
    // frequencies keep neighboring rings coherent instead of producing noise.
    final broad =
        math.sin(angle * 2 + distance * 0.045 + _phase1) * 0.30 +
        math.sin(angle * 3 - distance * 0.032 + _phase2) * 0.16;
    final shelves = math.sin(angle + distance * 0.07 + _phase3) * 0.12;
    return broad + shelves;
  }

  double _angleForSide(int side) {
    if (verticesPerRing != 144) return side * math.pi * 2 / verticesPerRing;
    final step = side % 24;
    final fraction = switch (step) {
      0 => 0.0,
      1 => 0.012,
      23 => 0.988,
      _ => (step - 1) / 22,
    };
    return (side ~/ 24 + fraction) * math.pi / 3;
  }

  static double _phaseFor(int seed, int salt) {
    var hash = (seed ^ salt) & 0xFFFFFFFF;
    hash = ((hash ^ (hash >> 16)) * 0x7feb352d) & 0xFFFFFFFF;
    hash = (hash ^ (hash >> 15)) & 0xFFFFFFFF;
    return hash / 0xFFFFFFFF * math.pi * 2;
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
