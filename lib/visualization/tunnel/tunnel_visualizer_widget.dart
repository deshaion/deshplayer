import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../audio/audio_analysis.dart';
import 'tunnel_generator.dart';
import 'tunnel_renderer.dart';
import 'tunnel_simulation.dart';

/// Flutter lifecycle shell for the tunnel engine.
class TunnelVisualizerWidget extends StatefulWidget {
  const TunnelVisualizerWidget({
    super.key,
    required this.isPlaying,
    this.seed = 0xD35A,
    this.travelSpeed = 6,
  });

  final bool isPlaying;
  final int seed;
  final double travelSpeed;

  @override
  State<TunnelVisualizerWidget> createState() => _TunnelVisualizerWidgetState();
}

class _TunnelVisualizerWidgetState extends State<TunnelVisualizerWidget> {
  late final AudioAnalysis _audioAnalysis = AudioAnalysis();
  late final TunnelGenerator _generator = TunnelGenerator(seed: widget.seed);
  late final TunnelSimulation _simulation = TunnelSimulation(
    path: _generator.path,
    travelSpeed: widget.travelSpeed,
  );
  late final TunnelRenderer _renderer = TunnelRenderer(
    generator: _generator,
    simulation: _simulation,
  );

  @override
  void dispose() {
    _audioAnalysis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xff02030c),
      child: SceneView(
        _renderer.scene,
        cameraBuilder: (_) => _renderer.camera(),
        onTick: (_, deltaSeconds) {
          final audio = _audioAnalysis.update(
            deltaSeconds,
            isPlaying: widget.isPlaying,
          );
          _renderer.advance(deltaSeconds, audio, travel: widget.isPlaying);
        },
        loadingBuilder: (_, progress) => const ColoredBox(
          color: Color(0xff02030c),
          child: Center(
            child: CircularProgressIndicator(color: Color(0xff00e5ff)),
          ),
        ),
      ),
    );
  }
}
