import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../../../services/player_provider.dart';

class MobileControlPanel extends StatelessWidget {
  const MobileControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final currentTrack = player.currentTrack;
    final isPlaying = player.isPlaying;
    final isShuffle = player.settings.shuffle;
    final repeatMode = player.settings.repeatMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
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
          // Seek Slider
          ProgressBar(
            progress: player.position,
            total: currentTrack?.duration ?? player.duration,
            onSeek: player.seek,
            barHeight: 4,
            thumbRadius: 6,
            timeLabelTextStyle: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle, color: isShuffle ? Theme.of(context).colorScheme.primary : Colors.grey),
                onPressed: player.toggleShuffle,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 32),
                onPressed: player.playPrevious,
              ),
              FloatingActionButton(
                elevation: 0,
                onPressed: player.togglePlayPause,
                child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 32),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 32),
                onPressed: player.playNext,
              ),
              IconButton(
                icon: Icon(repeatMode == 2 ? Icons.repeat_one : Icons.repeat,
                            color: repeatMode > 0 ? Theme.of(context).colorScheme.primary : Colors.grey),
                onPressed: player.toggleRepeat,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
