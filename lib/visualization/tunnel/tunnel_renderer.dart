import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../audio/audio_analysis.dart';
import 'tunnel_generator.dart';
import 'tunnel_audio_response.dart';
import 'tunnel_simulation.dart';

/// Owns retained scene and GPU resources. No geometry is allocated per frame.
class TunnelRenderer {
  TunnelRenderer({
    required this.generator,
    required this.simulation,
    this.chunkCount = 8,
    this.ringsPerChunk = 33,
  }) : assert(chunkCount >= 3),
       assert(ringsPerChunk >= 2) {
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponentialSquared
      ..color = vm.Vector3(0.0015, 0.0025, 0.009)
      ..start = 10
      ..density = 0.028
      ..maxOpacity = 0.995;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 0.85
      ..intensity = 0.28
      ..scatter = 0.5;
    scene.postProcess.vignette
      ..enabled = true
      ..intensity = 0.32
      ..radius = 0.9
      ..smoothness = 0.55;
    scene.postProcess.chromaticAberration.enabled = false;
    scene.postProcess.filmGrain.enabled = false;
    scene.postProcess.colorGrading
      ..enabled = true
      ..brightness = 1.0
      ..contrast = 1.06
      ..saturation = 0.95
      ..lift = vm.Vector3(0, 0.002, 0.008)
      ..gain = vm.Vector3(1.03, 1.04, 1.09);
    scene.exposure = 1.0;

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

    final firstJunction = generator.path.junctionAt(0);
    final branchRings =
        ((firstJunction.branchEnd - firstJunction.splitStart) /
                generator.ringSpacing)
            .round() +
        1;
    final branchData = generator.createSegmentData(branchRings);
    generator.fillUnselectedBranch(branchData, firstJunction);
    final branchGeometry = generator.createGeometry(branchData);
    _branchChunk = _TunnelChunk(
      data: branchData,
      geometry: branchGeometry,
      node: Node(mesh: Mesh(branchGeometry, _material)),
    );
  }

  final TunnelGenerator generator;
  final TunnelSimulation simulation;
  final int chunkCount;
  final int ringsPerChunk;
  final Scene scene = Scene();
  final ListQueue<_TunnelChunk> _chunks = ListQueue<_TunnelChunk>();
  late final UnlitMaterial _material;
  late final _TunnelChunk _branchChunk;
  int _junctionIndex = 0;
  bool _branchAttached = false;
  final List<_TravellingPulse> _pulses = <_TravellingPulse>[];
  double _elapsedSeconds = 0;
  double _deformAccumulator = 0;
  double _speedImpulse = 0;
  double _visualEnergy = 0;
  final _response = TunnelAudioResponse();

  int get activeChunkCount => _chunks.length;

  void advance(
    double deltaSeconds,
    AudioFeatures audio, {
    required bool travel,
  }) {
    if (audio.beat) _speedImpulse = math.min(0.16, _speedImpulse + 0.075);
    _speedImpulse *= math.exp(-deltaSeconds / 0.28);
    if (travel) {
      simulation.advance(deltaSeconds, speedMultiplier: 1 + _speedImpulse);
    }
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
    _updateJunctionBranch();

    _response.advance(
      deltaSeconds,
      audio.amplitude * 0.45 + audio.bass * 0.35 + audio.mids * 0.2,
    );
    _visualEnergy = _response.energy;
    final brightness = 0.82 + _visualEnergy * 0.18;
    _material.baseColorFactor.setValues(brightness, brightness, brightness, 1);
    scene.postProcess.bloom.intensity = 0.28 + _visualEnergy * 0.18;
    scene.fog.density = 0.028;

    // Geometry/audio uploads are capped at 30 Hz. Camera travel remains at
    // display refresh rate and shader interpolation keeps the response fluid.
    if (_deformAccumulator < 1 / 30) return;
    _deformAccumulator = 0;
    for (final chunk in _chunks) {
      _deformChunk(chunk, audio);
    }
    if (_branchAttached) _deformChunk(_branchChunk, audio);
  }

  void _deformChunk(_TunnelChunk chunk, AudioFeatures audio) {
    _fillPulseEnergies(chunk.data);
    generator.deformSegment(
      chunk.data,
      bass: audio.bass * _visualEnergy,
      mids: audio.mids * _visualEnergy,
      treble: audio.treble * _visualEnergy,
      elapsedSeconds: _elapsedSeconds,
    );
    generator.updateGeometry(chunk.geometry, chunk.data);
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

  void _updateJunctionBranch() {
    var junction = generator.path.junctionAt(_junctionIndex);
    while (simulation.distance > junction.branchEnd + 18) {
      if (_branchAttached) {
        scene.remove(_branchChunk.node);
        _branchAttached = false;
      }
      _junctionIndex++;
      junction = generator.path.junctionAt(_junctionIndex);
    }

    final revealDistance = junction.splitStart - 70;
    if (!_branchAttached && simulation.distance >= revealDistance) {
      generator.fillUnselectedBranch(_branchChunk.data, junction);
      generator.updateGeometry(_branchChunk.geometry, _branchChunk.data);
      scene.add(_branchChunk.node);
      _branchAttached = true;
    }
  }

  double _chunkEndDistance(_TunnelChunk chunk) =>
      (chunk.data.startRing + ringsPerChunk - 1) * generator.ringSpacing;

  PerspectiveCamera camera() => PerspectiveCamera(
    position: simulation.cameraPosition,
    target: simulation.cameraTarget,
    up: simulation.cameraUp,
    fovRadiansY:
        (64 + _visualEnergy * 0.8 + _speedImpulse * 2) * vm.degrees2Radians,
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
