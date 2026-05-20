import 'package:flutter/material.dart';
import '../../../models/playlist.dart';
import '../../../models/track.dart';
import 'mobile_control_panel.dart';

class MobileLayout extends StatefulWidget {
  final List<Playlist> playlists;

  const MobileLayout({super.key, required this.playlists});

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout> {
  late PageController _pageController;
  Playlist? _selectedPlaylist;
  Track? _currentTrack;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1); // Start on main view
    if (widget.playlists.isNotEmpty) {
      _selectedPlaylist = widget.playlists.first;
      if (_selectedPlaylist!.tracks.isNotEmpty) {
        _currentTrack = _selectedPlaylist!.tracks.first;
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    // Swipe back to Main View
    _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      children: [
        _buildPlaylistsView(),
        _buildMainView(),
      ],
    );
  }

  Widget _buildPlaylistsView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        elevation: 0,
      ),
      body: ListView.builder(
        itemCount: widget.playlists.length,
        itemBuilder: (context, index) {
          final playlist = widget.playlists[index];
          return ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.queue_music),
            ),
            title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${playlist.tracks.length} tracks'),
            onTap: () => _selectPlaylist(playlist),
          );
        },
      ),
    );
  }

  Widget _buildMainView() {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
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
                    const Spacer(),
                    const Text('Swipe left for playlists', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
