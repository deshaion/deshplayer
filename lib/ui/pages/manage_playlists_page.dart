import 'package:flutter/material.dart';
import '../../services/hive_storage_service.dart';
import '../../models/playlist.dart';
import '../components/playlist_dialogs.dart';
import '../components/slashed_icon.dart';

class ManagePlaylistsPage extends StatefulWidget {
  const ManagePlaylistsPage({super.key});

  @override
  State<ManagePlaylistsPage> createState() => _ManagePlaylistsPageState();
}

class _ManagePlaylistsPageState extends State<ManagePlaylistsPage> {
  List<Playlist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  void _loadPlaylists() {
    final storage = HiveStorageService();
    final playlists = storage.getPlaylists();
    setState(() {
      _playlists = playlists;
      _isLoading = false;
    });
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _playlists.removeAt(oldIndex);
      _playlists.insert(newIndex, item);
    });

    final storage = HiveStorageService();
    for (int i = 0; i < _playlists.length; i++) {
      _playlists[i].order = i;
      await storage.savePlaylist(_playlists[i]);
    }
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final newName = await showRenamePlaylistDialog(context, playlist.name);
    if (newName != null && newName.isNotEmpty && newName != playlist.name) {
      playlist.name = newName;
      await HiveStorageService().savePlaylist(playlist);
      _loadPlaylists();
    }
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDeletePlaylistDialog(context, playlist.name);
    if (confirm) {
      await HiveStorageService().deletePlaylist(playlist.id);
      _loadPlaylists();
    }
  }

  Future<void> _toggleStatistics(Playlist playlist) async {
    playlist.excludeFromStatistics = !playlist.excludeFromStatistics;
    await HiveStorageService().savePlaylist(playlist);
    _loadPlaylists();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  String _getPlaylistDuration(Playlist playlist) {
    final storage = HiveStorageService();
    Duration totalDuration = Duration.zero;
    for (final trackId in playlist.trackIds) {
      final track = storage.getTrack(trackId);
      if (track != null) {
        totalDuration += track.duration;
      }
    }
    return _formatDuration(totalDuration);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text('Manage Playlists'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? const Center(child: Text('No playlists available'))
              : ReorderableListView.builder(
                  itemCount: _playlists.length,
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    final trackCount = playlist.trackIds.length;
                    final totalTimeStr = _getPlaylistDuration(playlist);

                    return ListTile(
                      key: ValueKey(playlist.id),
                      leading: const Icon(Icons.drag_handle),
                      title: Text(playlist.name),
                      subtitle: Text('$trackCount tracks - $totalTimeStr'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: playlist.excludeFromStatistics
                                ? SlashedIcon(
                                    icon: Icons.leaderboard,
                                    iconColor: Theme.of(context).iconTheme.color ?? Colors.black,
                                  )
                                : const Icon(Icons.leaderboard),
                            onPressed: () => _toggleStatistics(playlist),
                            tooltip: playlist.excludeFromStatistics
                                ? 'Include in statistics'
                                : 'Exclude from statistics',
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _renamePlaylist(playlist),
                            tooltip: 'Rename',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deletePlaylist(playlist),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
