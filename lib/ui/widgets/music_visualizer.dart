import 'package:flutter/material.dart';
import 'dart:math';

class MusicVisualizer extends StatefulWidget {
  final bool isPlaying;
  final int barCount;
  final Color? barColor;
  final double width;
  final double height;

  const MusicVisualizer({
    super.key,
    required this.isPlaying,
    this.barCount = 5,
    this.barColor,
    this.width = 56,
    this.height = 56,
  });

  @override
  State<MusicVisualizer> createState() => _MusicVisualizerState();
}

class _MusicVisualizerState extends State<MusicVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  late List<double> _barHeights;
  late List<double> _targetBarHeights;

  @override
  void initState() {
    super.initState();
    _barHeights = List.generate(widget.barCount, (index) => 0.1);
    _targetBarHeights = List.generate(widget.barCount, (index) => 0.1);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150), // How fast bars update
    )..addListener(() {
        setState(() {
          for (int i = 0; i < widget.barCount; i++) {
            // Lerp towards target for smooth animation
            _barHeights[i] += (_targetBarHeights[i] - _barHeights[i]) * 0.3;
          }
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && widget.isPlaying) {
          _generateNewTargets();
          _controller.forward(from: 0.0);
        }
      });

    if (widget.isPlaying) {
      _generateNewTargets();
      _controller.forward();
    }
  }

  void _generateNewTargets() {
    for (int i = 0; i < widget.barCount; i++) {
      // Random height between 0.1 and 1.0
      _targetBarHeights[i] = _random.nextDouble() * 0.9 + 0.1;
    }
  }

  @override
  void didUpdateWidget(MusicVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _generateNewTargets();
        _controller.forward(from: _controller.value);
      } else {
        // Smoothly animate back to minimum height when paused
        _controller.stop();
        for (int i = 0; i < widget.barCount; i++) {
           _targetBarHeights[i] = 0.1;
        }
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.barColor ?? Theme.of(context).colorScheme.primary;
    final spacing = 2.0;
    final horizontalPadding = 16.0; // 8.0 on left, 8.0 on right
    final availableWidth = widget.width - horizontalPadding;
    final barWidth = (availableWidth - (spacing * (widget.barCount - 1))) / widget.barCount;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (index) {
          return Container(
            width: barWidth,
            height: _barHeights[index] * (widget.height - 16.0), // -16 for padding
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
