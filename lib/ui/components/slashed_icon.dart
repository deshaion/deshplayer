import 'package:flutter/material.dart';

class SlashedIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color iconColor;
  final Color lineColor;
  final double strokeWidth;

  const SlashedIcon({
    super.key,
    required this.icon,
    this.size = 24.0,
    this.iconColor = Colors.black,
    this.lineColor = Colors.red,
    this.strokeWidth = 2.5,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _SlashPainter(
        color: lineColor,
        strokeWidth: strokeWidth,
      ),
      child: Icon(
        icon,
        size: size,
        color: iconColor,
      ),
    );
  }
}

class _SlashPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _SlashPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draws line from top-right to bottom-left
    canvas.drawLine(
      Offset(size.width * 0.85, size.height * 0.15),
      Offset(size.width * 0.15, size.height * 0.85),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
