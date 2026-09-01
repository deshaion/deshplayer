import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../../../services/player_provider.dart';
import '../../../services/hive_storage_service.dart';

class MobileControlPanel extends StatefulWidget {
  final bool compact;

  const MobileControlPanel({super.key, this.compact = false});

  @override
  State<MobileControlPanel> createState() => _MobileControlPanelState();
}

class _MobileControlPanelState extends State<MobileControlPanel> {
  final GlobalKey _iconKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final currentTrack = player.currentTrack;
    final isPlaying = player.isPlaying;
    final isShuffle = player.settings.shuffle;
    final repeatMode = player.settings.repeatMode;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: widget.compact ? 8.0 : 24.0,
      ),
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
          if (widget.compact)
            Row(
              children: [
                Expanded(
                  child: Text(
                    currentTrack?.title ?? 'No Track Selected',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (currentTrack?.artist?.isNotEmpty ?? false) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      currentTrack!.artist!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            )
          else ...[
            Text(
              currentTrack?.title ?? 'No Track Selected',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              currentTrack?.artist ?? '',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: widget.compact ? 4 : 16),
          // Seek Slider
          ProgressBar(
            progress: player.position,
            total: currentTrack?.duration ?? player.duration,
            onSeek: player.seek,
            barHeight: 4,
            thumbRadius: 6,
            timeLabelTextStyle: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          // Controls
          if (!widget.compact)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(
                  width: 48,
                ), // Placeholder to balance the more_vert icon and perfectly center the controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        color: isShuffle
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      onPressed: player.toggleShuffle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 32),
                      onPressed: player.playPrevious,
                    ),
                    FloatingActionButton(
                      elevation: 0,
                      onPressed: player.togglePlayPause,
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 32),
                      onPressed: player.playNext,
                    ),
                    IconButton(
                      icon: Icon(
                        repeatMode == 2 ? Icons.repeat_one : Icons.repeat,
                        color: repeatMode > 0
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      onPressed: player.toggleRepeat,
                    ),
                  ],
                ),
                IconButton(
                  key: _iconKey,
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  onPressed: currentTrack != null
                      ? () => _showTrackMenu(
                          context,
                          player,
                          currentTrack,
                          _iconKey,
                        )
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showTrackMenu(
    BuildContext context,
    PlayerProvider player,
    dynamic currentTrack,
    GlobalKey iconKey,
  ) async {
    final storage = HiveStorageService();

    final RenderBox? renderBox =
        iconKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero);
    final dx = offset?.dx ?? 1000;
    final dy = offset?.dy ?? 1000;

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        dx,
        dy - 50,
        dx + 50,
        dy,
      ), // Adjust to show above icon
      items: [
        const PopupMenuItem(value: 'playlist', child: Text('Send to Playlist')),
      ],
    );

    if (!context.mounted) return;

    if (value == 'playlist') {
      _showPlaylistDialog(context, storage, currentTrack);
    }
  }

  void _showPlaylistDialog(
    BuildContext context,
    HiveStorageService storage,
    dynamic track,
  ) {
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
                        SnackBar(content: Text('Added to ${p.name}')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Already in ${p.name}')),
                      );
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
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
