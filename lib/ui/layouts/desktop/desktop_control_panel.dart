import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../../../services/player_provider.dart';
import '../../../services/hive_storage_service.dart';

class DesktopControlPanel extends StatelessWidget {
  const DesktopControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final currentTrack = player.currentTrack;
    final isPlaying = player.isPlaying;
    final isShuffle = player.settings.shuffle;
    final repeatMode = player.settings.repeatMode;

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
                    IconButton(
                        icon: Icon(Icons.shuffle, color: isShuffle ? Theme.of(context).colorScheme.primary : Colors.grey),
                        onPressed: player.toggleShuffle),
                    IconButton(icon: const Icon(Icons.skip_previous), onPressed: player.playPrevious),
                    FloatingActionButton.small(
                      elevation: 0,
                      onPressed: player.togglePlayPause,
                      child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    ),
                    IconButton(icon: const Icon(Icons.skip_next), onPressed: player.playNext),
                    IconButton(
                        icon: Icon(repeatMode == 2 ? Icons.repeat_one : Icons.repeat,
                            color: repeatMode > 0 ? Theme.of(context).colorScheme.primary : Colors.grey),
                        onPressed: player.toggleRepeat),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ProgressBar(
                    progress: player.position,
                    total: currentTrack?.duration ?? player.duration,
                    onSeek: player.seek,
                    barHeight: 4,
                    thumbRadius: 6,
                    timeLabelTextStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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
                      value: player.settings.volume,
                      onChanged: player.setVolume,
                    ),
                  ),
                ),
                const Icon(Icons.volume_up, color: Colors.grey),
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final iconKey = GlobalKey();
                    return IconButton(
                      key: iconKey,
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      onPressed: currentTrack != null
                          ? () => _showTrackMenu(context, player, currentTrack, iconKey)
                          : null,
                    );
                  }
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTrackMenu(BuildContext context, PlayerProvider player, dynamic currentTrack, GlobalKey iconKey) async {
    final storage = HiveStorageService();

    final RenderBox? renderBox = iconKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero);
    final dx = offset?.dx ?? 1000;
    final dy = offset?.dy ?? 1000;

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(dx, dy - 50, dx + 50, dy), // Adjust to show above icon
      items: [
        const PopupMenuItem(
          value: 'playlist',
          child: Text('Send to Playlist'),
        ),
      ],
    );

    if (!context.mounted) return;

    if (value == 'playlist') {
      _showPlaylistDialog(context, storage, currentTrack);
    }
  }

  void _showPlaylistDialog(BuildContext context, HiveStorageService storage, dynamic track) {
    final playlists = storage.getPlaylists();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send to Playlist'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, idx) {
                final p = playlists[idx];
                return ListTile(
                  title: Text(p.name),
                  onTap: () {
                    if (!p.trackIds.contains(track.id)) {
                      p.trackIds.add(track.id);
                      storage.savePlaylist(p);
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to ${p.name}')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Already in ${p.name}')));
                    }
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'))
          ],
        );
      },
    );
  }
}
