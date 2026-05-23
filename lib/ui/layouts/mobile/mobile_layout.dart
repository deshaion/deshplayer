import '../../utils/search_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/playlist.dart';
import '../../../services/player_provider.dart';
import '../../pages/manage_playlists_page.dart';
import '../../components/playlist_dialogs.dart';
import 'mobile_control_panel.dart';
import '../../pages/settings_page.dart';
import '../../pages/queue/queue_page.dart';
import '../../pages/stats/stats_page.dart';
import '../../widgets/track_list_tile.dart';
import '../../pages/import/cloud_import_page.dart';

class MobileLayout extends StatefulWidget {
  final List<Playlist> playlists;
  final Function(String) onAddPlaylist;
  final Function(String, String) onRenamePlaylist;
  final Function(String) onDeletePlaylist;

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
  String _searchQuery = '';
  final Map<String, String> _searchCache = {};

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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final selectedPlaylist = player.currentPlaylist;
    final currentTrack = player.currentTrack;

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
              onTap: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsPage())); },
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: const Text('Queue'),
              onTap: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QueuePage())); },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
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
                  final isSelected = playlist.id == selectedPlaylist?.id;
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
                      onTap: () {
                        player.playPlaylist(playlist);
                        Navigator.of(context).pop();
                      },
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
            const MobileControlPanel(),
            // Playlist Name Header
            if (selectedPlaylist != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.list),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedPlaylist.name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${selectedPlaylist.trackIds.length} tracks',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          prefixIcon: const Icon(Icons.search, size: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CloudImportPage(playlist: selectedPlaylist),
                          ),
                        ).then((_) {
                           // Trigger rebuild to show new tracks
                           setState((){});
                        });
                      },
                      icon: const Icon(Icons.cloud_download, size: 16),
                      label: const Text('Import'),
                    )
                  ],
                ),
              ),
            const Divider(height: 1),
            // Tracks List
            Expanded(
              child: selectedPlaylist == null
                  ? const Center(child: Text('No Playlist Selected'))
                  : Builder(
                      builder: (context) {
                        List<String> filteredTrackIds = selectedPlaylist.trackIds;

                        if (_searchQuery.trim().length >= 2) {
                          filteredTrackIds = selectedPlaylist.trackIds.where((trackId) {
                            final track = player.getTrack(trackId);
                            if (track == null) return false;

                            String searchString = _searchCache[trackId] ?? '';
                            if (searchString.isEmpty) {
                              if (track.title != null && track.title!.isNotEmpty) {
                                searchString = '${track.artist ?? ""} ${track.title}';
                              } else {
                                searchString = track.cloudPath.split('/').last.split('.').first;
                              }
                              _searchCache[trackId] = searchString;
                            }

                            return SearchUtils.matchesSubsequence(_searchQuery.trim(), searchString);
                          }).toList();
                        }

                        return ListView.builder(
                          itemCount: filteredTrackIds.length,
                          itemBuilder: (context, index) {
                            final trackId = filteredTrackIds[index];
                            final track = player.getTrack(trackId);
                            if (track == null) return const SizedBox.shrink();

                            final isSelected = track.id == currentTrack?.id;
                            return TrackListTile(
                              track: track,
                              index: index,
                              playlist: selectedPlaylist,
                              isSelected: isSelected,
                              onTap: () {
                                if (selectedPlaylist.id == player.currentPlaylist?.id) {
                                  player.playTrackDirectly(track);
                                } else {
                                  player.playPlaylist(selectedPlaylist, startTrack: track);
                                }
                              },
                            );
                          },
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
