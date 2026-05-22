import 'package:flutter/material.dart';
import '../../../models/playlist.dart';
import '../../../models/track.dart';
import 'mobile_control_panel.dart';
import '../../components/playlist_dialogs.dart';
import '../../pages/manage_playlists_page.dart';

class MobileLayout extends StatefulWidget {
  final List<Playlist> playlists;
  final void Function(String name) onAddPlaylist;
  final void Function(String id, String newName) onRenamePlaylist;
  final void Function(String id) onDeletePlaylist;

  const MobileLayout({
    super.key,
    required this.playlists,
    required this.onAddPlaylist,
    required this.onRenamePlaylist,
    required this.onDeletePlaylist,
  });

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout> {
  Playlist? _selectedPlaylist;
  Track? _currentTrack;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.playlists.isNotEmpty) {
      _selectedPlaylist = widget.playlists.first;
      if (_selectedPlaylist!.tracks.isNotEmpty) {
        _currentTrack = _selectedPlaylist!.tracks.first;
      }
    }
  }

  void _playTrack(Track track) {
    setState(() {
      _currentTrack = track;
      _isPlaying = true;
    });
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _nextTrack() {
    if (_selectedPlaylist == null || _currentTrack == null) return;
    final tracks = _selectedPlaylist!.tracks;
    final currentIndex = tracks.indexOf(_currentTrack!);
    if (currentIndex < tracks.length - 1) {
      _playTrack(tracks[currentIndex + 1]);
    }
  }

  void _prevTrack() {
    if (_selectedPlaylist == null || _currentTrack == null) return;
    final tracks = _selectedPlaylist!.tracks;
    final currentIndex = tracks.indexOf(_currentTrack!);
    if (currentIndex > 0) {
      _playTrack(tracks[currentIndex - 1]);
    }
  }

  void _selectPlaylist(Playlist playlist) {
    setState(() {
      _selectedPlaylist = playlist;
      if (playlist.tracks.isNotEmpty) {
        _currentTrack = playlist.tracks.first;
        _isPlaying = true;
      } else {
        _currentTrack = null;
        _isPlaying = false;
      }
    });
    // Close Drawer
    Navigator.of(context).pop();
  }

  void _showPlaylistMenu(BuildContext context, Offset position, Playlist playlist) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(
          value: 'rename',
          child: Text('Rename'),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete'),
        ),
      ],
    );

    if (!context.mounted) return;

    if (value == 'rename') {
      final newName = await showRenamePlaylistDialog(context, playlist.name);
      if (newName != null && newName.isNotEmpty && newName != playlist.name) {
        widget.onRenamePlaylist(playlist.id, newName);
      }
    } else if (value == 'delete') {
      final confirm = await showDeletePlaylistDialog(context, playlist.name);
      if (confirm) {
        widget.onDeletePlaylist(playlist.id);
        if (_selectedPlaylist?.id == playlist.id) {
          setState(() {
            _selectedPlaylist = null;
            _currentTrack = null;
            _isPlaying = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(76),
              ),
              child: const Text(
                'DeshPlayer',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Stats'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: const Text('Queue'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {},
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  const Text(
                    'PLAYLISTS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final name = await showCreatePlaylistDialog(context);
                      if (name != null && name.isNotEmpty) {
                        widget.onAddPlaylist(name);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.settings_applications, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ManagePlaylistsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: widget.playlists.length,
                itemBuilder: (context, index) {
                  final playlist = widget.playlists[index];
                  final isSelected = playlist == _selectedPlaylist;
                  return GestureDetector(
                    onLongPressStart: (details) {
                      _showPlaylistMenu(context, details.globalPosition, playlist);
                    },
                    child: ListTile(
                      leading: Icon(Icons.queue_music, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
                      title: Text(
                        playlist.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                      onTap: () => _selectPlaylist(playlist),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar with Hamburger menu in SafeArea to open Drawer
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      return IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                      );
                    }
                  ),
                  const Spacer(),
                ],
              ),
            ),
            // Control Panel at the top
            MobileControlPanel(
              currentTrack: _currentTrack,
              isPlaying: _isPlaying,
              onPlayPause: _togglePlayPause,
              onNext: _nextTrack,
              onPrev: _prevTrack,
            ),
            // Playlist Name Header
            if (_selectedPlaylist != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.list),
                    const SizedBox(width: 8),
                    Text(
                      _selectedPlaylist!.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            // Tracks List
            Expanded(
              child: _selectedPlaylist == null
                  ? const Center(child: Text('No Playlist Selected'))
                  : ListView.builder(
                      itemCount: _selectedPlaylist!.tracks.length,
                      itemBuilder: (context, index) {
                        final track = _selectedPlaylist!.tracks[index];
                        final isSelected = track == _currentTrack;
                        return ListTile(
                          leading: isSelected
                              ? Icon(Icons.volume_up, color: Theme.of(context).colorScheme.primary)
                              : Text('${index + 1}', style: const TextStyle(color: Colors.grey)),
                          title: Text(
                            track.title,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Theme.of(context).colorScheme.primary : null,
                            ),
                          ),
                          subtitle: Text(track.artist),
                          trailing: Text(
                            '${track.duration.inMinutes}:${(track.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          onTap: () => _playTrack(track),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
