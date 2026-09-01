import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../audio/audio_analysis.dart';
import 'tunnel_generator.dart';
import 'tunnel_simulation.dart';

/// Owns retained scene and GPU resources. No geometry is allocated per frame.
class TunnelRenderer {
  TunnelRenderer({
    required this.generator,
    required this.simulation,
    this.chunkCount = 8,
    this.ringsPerChunk = 17,
  }) : assert(chunkCount >= 3),
       assert(ringsPerChunk >= 2) {
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponentialSquared
      ..color = vm.Vector3(0.002, 0.003, 0.012)
      ..start = 12
      ..density = 0.045;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 0.65
      ..intensity = 0.9
      ..scatter = 0.72;
    scene.postProcess.vignette
      ..enabled = true
      ..intensity = 0.55
      ..radius = 0.82
      ..smoothness = 0.55;
    scene.exposure = 1.15;

    _material = UnlitMaterial()
      ..doubleSided = true
      ..vertexColorWeight = 1
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1);

    final ringSpan = ringsPerChunk - 1;
    for (var index = 0; index < chunkCount; index++) {
      final startRing = (index - 1) * ringSpan;
      final data = generator.createSegmentData(ringsPerChunk);
      generator.fillSegment(data, startRing);
      final geometry = generator.createGeometry(data);
      final node = Node(mesh: Mesh(geometry, _material));
      final chunk = _TunnelChunk(data: data, geometry: geometry, node: node);
      _chunks.add(chunk);
      scene.add(node);
    }
  }

  final TunnelGenerator generator;
  final TunnelSimulation simulation;
  final int chunkCount;
  final int ringsPerChunk;
  final Scene scene = Scene();
  final ListQueue<_TunnelChunk> _chunks = ListQueue<_TunnelChunk>();
  late final UnlitMaterial _material;
  final List<_TravellingPulse> _pulses = <_TravellingPulse>[];
  double _elapsedSeconds = 0;
  double _deformAccumulator = 0;

  int get activeChunkCount => _chunks.length;

  void advance(
    double deltaSeconds,
    AudioFeatures audio, {
    required bool travel,
  }) {
    if (travel) simulation.advance(deltaSeconds);
    _elapsedSeconds += deltaSeconds;
    _deformAccumulator += deltaSeconds;
    for (final pulse in _pulses) {
      pulse.age += deltaSeconds;
    }
    _pulses.removeWhere((pulse) => pulse.age >= pulse.lifetime);
    if (audio.beat) {
      _pulses.add(_TravellingPulse(origin: simulation.distance + 4));
    }
    _streamAroundCamera();

    final brightness = 0.42 + audio.amplitude * 0.9 + audio.treble * 0.3;
    _material.baseColorFactor.setValues(brightness, brightness, brightness, 1);
    scene.postProcess.bloom.intensity = 0.55 + audio.treble * 1.15;

    // Geometry/audio uploads are capped at 30 Hz. Camera travel remains at
    // display refresh rate and shader interpolation keeps the response fluid.
    if (_deformAccumulator < 1 / 30) return;
    _deformAccumulator = 0;
    for (final chunk in _chunks) {
      _fillPulseEnergies(chunk.data);
      generator.deformSegment(
        chunk.data,
        bass: audio.bass,
        mids: audio.mids,
        treble: audio.treble,
        elapsedSeconds: _elapsedSeconds,
      );
      generator.updateGeometry(chunk.geometry, chunk.data);
    }
  }

  void _fillPulseEnergies(TunnelSegmentData data) {
    for (var localRing = 0; localRing < data.ringCount; localRing++) {
      final distance = (data.startRing + localRing) * generator.ringSpacing;
      var energy = 0.0;
      for (final pulse in _pulses) {
        final center = pulse.origin + pulse.age * 18;
        final offset = distance - center;
        final envelope = 1 - pulse.age / pulse.lifetime;
        energy += math.exp(-(offset * offset) / 7.5) * envelope;
      }
      data.pulsePerRing[localRing] = energy.clamp(0, 1.4);
    }
  }

  void _streamAroundCamera() {
    final ringSpan = ringsPerChunk - 1;
    final recycleBefore =
        simulation.distance - ringSpan * generator.ringSpacing;

    while (_chunkEndDistance(_chunks.first) < recycleBefore) {
      final recycled = _chunks.removeFirst();
      final nextStartRing = _chunks.last.data.startRing + ringSpan;

      // Detach stale world geometry, overwrite its existing CPU/GPU storage,
      // then attach the same node at the generated front of the tunnel.
      scene.remove(recycled.node);
      generator.fillSegment(recycled.data, nextStartRing);
      generator.updateGeometry(recycled.geometry, recycled.data);
      scene.add(recycled.node);
      _chunks.addLast(recycled);
    }
  }

  double _chunkEndDistance(_TunnelChunk chunk) =>
      (chunk.data.startRing + ringsPerChunk - 1) * generator.ringSpacing;

  PerspectiveCamera camera() => PerspectiveCamera(
    position: simulation.cameraPosition,
    target: simulation.cameraTarget,
    up: simulation.cameraUp,
    fovRadiansY: 68 * vm.degrees2Radians,
    fovNear: 0.08,
    fovFar: (chunkCount - 1) * (ringsPerChunk - 1) * generator.ringSpacing,
  );
}

class _TunnelChunk {
  const _TunnelChunk({
    required this.data,
    required this.geometry,
    required this.node,
  });

  final TunnelSegmentData data;
  final MeshGeometry geometry;
  final Node node;
}

class _TravellingPulse {
  _TravellingPulse({required this.origin});

  final double origin;
  final double lifetime = 1.35;
  double age = 0;
}
