import 'package:flutter/material.dart';
import '../../../models/playlist.dart';
import '../../../models/track.dart';

class MobileControlPanel extends StatelessWidget {
  final Track? currentTrack;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const MobileControlPanel({
    Key? key,
    required this.currentTrack,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Track Info
          Text(
            currentTrack?.title ?? 'No Track Selected',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            currentTrack?.artist ?? '',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          // Seek Slider (Dummy)
          Slider(
            value: 0.3,
            onChanged: (val) {},
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.shuffle),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 32),
                onPressed: onPrev,
              ),
              FloatingActionButton(
                elevation: 0,
                onPressed: onPlayPause,
                child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 32),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 32),
                onPressed: onNext,
              ),
              IconButton(
                icon: const Icon(Icons.repeat),
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}
