import 'package:flutter/material.dart';

class TriangleVolumeSlider extends StatelessWidget {
  final double volume; // 0.0 to 1.0
  final ValueChanged<double> onChanged;

  const TriangleVolumeSlider({
    super.key,
    required this.volume,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          volume == 0
              ? Icons.volume_off
              : volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
          color: Colors.grey,
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onPanUpdate: (details) => _updateVolume(details.localPosition, context),
          onPanDown: (details) => _updateVolume(details.localPosition, context),
          child: SizedBox(
            width: 80,
            height: 20,
            child: CustomPaint(
              painter: _TriangleVolumePainter(
                volume: volume,
                activeColor: Theme.of(context).colorScheme.primary,
                inactiveColor: Colors.grey.shade300,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _updateVolume(Offset localPosition, BuildContext context) {
    const double width = 80;
    double newVolume = (localPosition.dx / width).clamp(0.0, 1.0);
    onChanged(newVolume);
  }
}

class _TriangleVolumePainter extends CustomPainter {
  final double volume;
  final Color activeColor;
  final Color inactiveColor;

  _TriangleVolumePainter({
    required this.volume,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    final Path fullTriangle = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(fullTriangle, inactivePaint);

    final Paint activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final double fillWidth = size.width * volume;
    final double fillHeight = size.height * (1 - volume);

    final Path activeTriangle = Path()
      ..moveTo(0, size.height)
      ..lineTo(fillWidth, fillHeight)
      ..lineTo(fillWidth, size.height)
      ..close();

    canvas.drawPath(activeTriangle, activePaint);
  }

  @override
  bool shouldRepaint(covariant _TriangleVolumePainter oldDelegate) {
    return oldDelegate.volume != volume ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
