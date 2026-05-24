import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../../../services/player_provider.dart';
import '../../../services/hive_storage_service.dart';
import '../../widgets/triangle_volume_slider.dart';
import '../../widgets/music_visualizer.dart';

class DesktopControlPanel extends StatefulWidget {
  const DesktopControlPanel({super.key});

  @override
  State<DesktopControlPanel> createState() => _DesktopControlPanelState();
}

class _DesktopControlPanelState extends State<DesktopControlPanel> {
  final GlobalKey _iconKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1200) {
          return _buildWideLayout(context);
        } else {
          return _buildNarrowLayout(context);
        }
      },
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final currentTrack = player.currentTrack;
    final isPlaying = player.isPlaying;
    final isShuffle = player.settings.shuffle;
    final repeatMode = player.settings.repeatMode;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Visualizer
          MusicVisualizer(
            isPlaying: isPlaying,
            width: 80,
            height: 80,
            barCount: 7,
          ),
          const SizedBox(width: 24),
          // Right Side: 2 Rows (Progress Bar top, Controls bottom)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Progress Bar
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ProgressBar(
                    progress: player.position,
                    total: currentTrack?.duration ?? player.duration,
                    onSeek: player.seek,
                    barHeight: 4,
                    thumbRadius: 6,
                    timeLabelTextStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                // Bottom Row: Meta + Playback + Volume
                Row(
                  children: [
                    // Meta (Title - Artist)
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              currentTrack?.title ?? 'No Track',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (currentTrack?.artist != null && currentTrack!.artist!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Text('-', style: TextStyle(color: Colors.grey)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                currentTrack.artist!,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Playback Controls
                    Expanded(
                      flex: 1,
                      child: Row(
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
                    ),
                    // Volume + Menu
                    Expanded(
                      flex: 1,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TriangleVolumeSlider(
                            volume: player.settings.volume,
                            onChanged: player.setVolume,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: _iconKey,
                            icon: const Icon(Icons.more_vert, color: Colors.grey),
                            onPressed: currentTrack != null
                                ? () => _showTrackMenu(context, player, currentTrack, _iconKey)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final currentTrack = player.currentTrack;
    final isPlaying = player.isPlaying;
    final isShuffle = player.settings.shuffle;
    final repeatMode = player.settings.repeatMode;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Visualizer (Narrower)
          MusicVisualizer(
            isPlaying: isPlaying,
            width: 60,
            height: 100, // Taller to match 3 rows roughly
            barCount: 5,
          ),
          const SizedBox(width: 24),
          // Right Side: 3 Rows
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Progress Bar
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ProgressBar(
                    progress: player.position,
                    total: currentTrack?.duration ?? player.duration,
                    onSeek: player.seek,
                    barHeight: 4,
                    thumbRadius: 6,
                    timeLabelTextStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                // Middle Row: Meta (Title - Artist) full width
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          currentTrack?.title ?? 'No Track',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (currentTrack?.artist != null && currentTrack!.artist!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Text('-', style: TextStyle(color: Colors.grey)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            currentTrack.artist!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Bottom Row: Playback Controls & Volume
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Playback Controls
                    Row(
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
                    // Volume + Menu
                    Row(
                      children: [
                        TriangleVolumeSlider(
                          volume: player.settings.volume,
                          onChanged: player.setVolume,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: _iconKey,
                          icon: const Icon(Icons.more_vert, color: Colors.grey),
                          onPressed: currentTrack != null
                              ? () => _showTrackMenu(context, player, currentTrack, _iconKey)
                              : null,
                        ),
                      ],
                    ),
                  ],
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
