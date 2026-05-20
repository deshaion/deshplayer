import 'package:flutter/material.dart';
import '../../../models/track.dart';

class DesktopControlPanel extends StatelessWidget {
  final Track? currentTrack;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const DesktopControlPanel({
    super.key,
    required this.currentTrack,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          // Left: Track Info
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.music_note, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentTrack?.title ?? 'No Track',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Center: Controls and Seek Slider
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: const Icon(Icons.shuffle), onPressed: () {}),
                    IconButton(icon: const Icon(Icons.skip_previous), onPressed: onPrev),
                    FloatingActionButton.small(
                      elevation: 0,
                      onPressed: onPlayPause,
                      child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    ),
                    IconButton(icon: const Icon(Icons.skip_next), onPressed: onNext),
                    IconButton(icon: const Icon(Icons.repeat), onPressed: () {}),
                  ],
                ),
                Row(
                  children: [
                    const Text('0:00', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: 0.3,
                          onChanged: (val) {},
                          activeColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    Text(
                      currentTrack != null
                        ? '${currentTrack!.duration.inMinutes}:${(currentTrack!.duration.inSeconds % 60).toString().padLeft(2, '0')}'
                        : '0:00',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Right: Volume Control
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.volume_down, color: Colors.grey),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: 0.7,
                      onChanged: (val) {},
                    ),
                  ),
                ),
                const Icon(Icons.volume_up, color: Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
