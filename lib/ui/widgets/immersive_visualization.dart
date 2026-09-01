import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../visualization/tunnel/tunnel_visualizer_widget.dart';

class ImmersiveVisualization extends StatefulWidget {
  final int sceneIndex;
  final bool isPlaying;
  final VoidCallback onNext;
  final VoidCallback onClose;

  const ImmersiveVisualization({
    super.key,
    required this.sceneIndex,
    required this.isPlaying,
    required this.onNext,
    required this.onClose,
  });

  @override
  State<ImmersiveVisualization> createState() => _ImmersiveVisualizationState();
}

class _ImmersiveVisualizationState extends State<ImmersiveVisualization>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void didUpdateWidget(ImmersiveVisualization oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) _controller.repeat();
    if (!widget.isPlaying && _controller.isAnimating) _controller.stop();
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isPlaying) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xff03040b),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onNext,
              child: widget.sceneIndex == 0
                  ? TunnelVisualizerWidget(isPlaying: widget.isPlaying)
                  : AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) =>
                          CustomPaint(painter: _RoadPainter(_controller.value)),
                    ),
            ),
          ),
          Positioned(
            left: 24,
            bottom: 20,
            child: IgnorePointer(
              child: Text(
                widget.sceneIndex == 0 ? 'NEON TUNNEL' : 'NIGHT DRIVE',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: IconButton.filledTonal(
              tooltip: 'Close visualization',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadPainter extends CustomPainter {
  final double phase;
  _RoadPainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * .38;
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xff07091d), Color(0xff34215c), Color(0xffff6a65)],
      ).createShader(Offset.zero & Size(size.width, horizon + 30));
    canvas.drawRect(Offset.zero & size, sky);
    final vanishing = Offset(size.width / 2, horizon);
    final road = Path()
      ..moveTo(vanishing.dx - 18, horizon)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(vanishing.dx + 18, horizon)
      ..close();
    canvas.drawPath(road, Paint()..color = const Color(0xff10111b));
    final edgePaint = Paint()
      ..color = const Color(0xffff3dbb)
      ..strokeWidth = 3;
    canvas.drawLine(vanishing, Offset(0, size.height), edgePaint);
    canvas.drawLine(vanishing, Offset(size.width, size.height), edgePaint);

    final buildingPaint = Paint()..color = const Color(0xff090b18);
    final windowPaint = Paint()..color = const Color(0xffffd85a);
    for (final side in [-1, 1]) {
      for (var i = 0; i < 10; i++) {
        final depth = ((i / 10 + phase * .65) % 1);
        final scale = math.pow(depth, 2).toDouble();
        final innerX = vanishing.dx + side * (20 + scale * size.width * .44);
        final width = 15 + scale * 75;
        final height = 25 + scale * (90 + (i % 4) * 35);
        final left = side < 0 ? innerX - width : innerX;
        final rect = Rect.fromLTWH(
          left,
          horizon - height + scale * 45,
          width,
          height,
        );
        canvas.drawRect(rect, buildingPaint);
        if (depth > .22) {
          for (var row = 0; row < 3; row++) {
            final y = rect.top + 10 + row * 15 * depth;
            final x = rect.left + rect.width * .35;
            canvas.drawRect(
              Rect.fromLTWH(x, y, 3 + 5 * depth, 2 + 3 * depth),
              windowPaint,
            );
          }
        }
      }
    }
    final lanePaint = Paint()..color = Colors.white.withValues(alpha: .8);
    for (var i = 0; i < 9; i++) {
      final z1 = ((i / 9 + phase * 1.4) % 1);
      final z2 = math.min(1.0, z1 + .055);
      final y1 = horizon + math.pow(z1, 2) * (size.height - horizon);
      final y2 = horizon + math.pow(z2, 2) * (size.height - horizon);
      final w1 = 1 + z1 * 8;
      final w2 = 1 + z2 * 8;
      canvas.drawPath(
        Path()
          ..moveTo(vanishing.dx - w1, y1)
          ..lineTo(vanishing.dx + w1, y1)
          ..lineTo(vanishing.dx + w2, y2)
          ..lineTo(vanishing.dx - w2, y2)
          ..close(),
        lanePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter oldDelegate) =>
      oldDelegate.phase != phase;
}
