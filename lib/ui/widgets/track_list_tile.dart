import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../models/playlist.dart';
import '../../services/player_provider.dart';
import '../../services/hive_storage_service.dart';

class TrackListTile extends StatelessWidget {
  final Track track;
  final int index;
  final Playlist playlist;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onRemoveFromPlaylist;

  const TrackListTile({
    super.key,
    required this.track,
    required this.index,
    required this.playlist,
    required this.isSelected,
    required this.onTap,
    this.onRemoveFromPlaylist,
  });

  void _showTrackMenu(BuildContext context, Offset position) async {
    final player = context.read<PlayerProvider>();
    final storage = HiveStorageService();

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(
          value: 'queue',
          child: Text('Add to Queue'),
        ),
        const PopupMenuItem(
          value: 'playlist',
          child: Text('Send to Playlist'),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: Text('Remove from Playlist'),
        ),
      ],
    );

    if (!context.mounted) return;

    if (value == 'queue') {
       player.addToQueue(track);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${track.title} added to queue')));
    } else if (value == 'playlist') {
       _showPlaylistDialog(context, storage);
    } else if (value == 'remove') {
       if (onRemoveFromPlaylist != null) {
         onRemoveFromPlaylist!();
       }
    }
  }

  void _showPlaylistDialog(BuildContext context, HiveStorageService storage) {
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
                                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to ${p.name}')));
                                     } else {
                                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Already in ${p.name}')));
                                     }
                                     Navigator.of(context).pop();
                                 },
                             );
                         }
                     )
                 ),
                 actions: [
                     TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))
                 ],
             );
         }
      );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) => _showTrackMenu(context, details.globalPosition),
      onLongPressStart: (details) => _showTrackMenu(context, details.globalPosition),
      child: ListTile(
        leading: isSelected
            ? Icon(Icons.volume_up, color: Theme.of(context).colorScheme.primary)
            : SizedBox(width: 24, child: Center(child: Text('${index + 1}', style: const TextStyle(color: Colors.grey)))),
        title: Text(
          track.title != null && track.title!.isNotEmpty ? track.title! : track.cloudPath.split('/').last.split('.').first,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        subtitle: Text(track.artist ?? 'Unknown Artist'),
        trailing: Text(
          '${track.duration.inMinutes}:${(track.duration.inSeconds % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(color: Colors.grey),
        ),
        onTap: onTap,
      ),
    );
  }
}
