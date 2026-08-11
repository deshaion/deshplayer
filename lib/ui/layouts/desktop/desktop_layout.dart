import '../../utils/search_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/playlist.dart';
import '../../../services/player_provider.dart';
import '../../pages/manage_playlists_page.dart';
import '../../components/playlist_dialogs.dart';
import 'desktop_control_panel.dart';
import '../../pages/settings_page.dart';
import '../../pages/queue/queue_page.dart';
import '../../pages/stats/stats_page.dart';
import '../../widgets/track_list_tile.dart';
import '../../pages/import/cloud_import_page.dart';
import '../../../services/hive_storage_service.dart';

class DesktopLayout extends StatefulWidget {
  final List<Playlist> playlists;
  final Function(String) onAddPlaylist;
  final Function(String, String) onRenamePlaylist;
  final Function(String) onDeletePlaylist;
  final VoidCallback onPlaylistsChanged;

  const DesktopLayout({
    super.key,
    required this.playlists,
    required this.onAddPlaylist,
    required this.onRenamePlaylist,
    required this.onDeletePlaylist,
    required this.onPlaylistsChanged,
  });

  @override
  State<DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<DesktopLayout> {
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
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Left Sidebar (Playlists)
                SizedBox(
                  width: 250,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(76),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'DeshPlayer',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                        leading: const Icon(Icons.home),
                        title: const Text('Home'),
                        onTap: () {},
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                        leading: const Icon(Icons.bar_chart),
                        title: const Text('Stats'),
                        onTap: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsPage())); },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                        leading: const Icon(Icons.queue),
                        title: const Text('Queue'),
                        onTap: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QueuePage())); },
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                        leading: const Icon(Icons.settings),
                        title: const Text('Settings'),
                        onTap: () {
                           Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
                        },
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
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
                                ).then((_) => widget.onPlaylistsChanged());
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: widget.playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = widget.playlists[index];
                            final isSelected = playlist.id == selectedPlaylist?.id;
                            final isPlayingPlaylist = playlist.id == player.playingPlaylist?.id;

                            IconData playlistIcon = Icons.queue_music;
                            if (isPlayingPlaylist) {
                              playlistIcon = player.isPlaying ? Icons.volume_up : Icons.pause;
                            }
                            return GestureDetector(
                              onSecondaryTapDown: (details) {
                                _showPlaylistMenu(context, details.globalPosition, playlist);
                              },
                              onLongPressStart: (details) {
                                _showPlaylistMenu(context, details.globalPosition, playlist);
                              },
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                leading: Icon(playlistIcon, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
                                title: Text(
                                  playlist.name,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Theme.of(context).colorScheme.primary : null,
                                  ),
                                ),
                                onTap: () => player.selectPlaylist(playlist),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                // Main Area (Tracks)
                Expanded(
                  child: selectedPlaylist == null
                      ? const Center(child: Text('No Playlist Selected'))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth >= 800) { // Keep Row layout if there is enough space
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                selectedPlaylist.name,
                                                style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                '${selectedPlaylist.trackIds.length} tracks',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
                                              ),
                                            ],
                                        ),
                                        ),
                                        SizedBox(
                                          width: 250,
                                          child: TextField(
                                            decoration: InputDecoration(
                                              hintText: 'Search tracks...',
                                              prefixIcon: const Icon(Icons.search),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8.0),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                                            ),
                                            onChanged: (value) {
                                              setState(() {
                                                _searchQuery = value;
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) => CloudImportPage(playlist: selectedPlaylist),
                                              ),
                                            ).then((_) {
                                               setState((){});
                                            });
                                          },
                                          icon: const Icon(Icons.cloud_download),
                                          label: const Text('Import Cloud Media'),
                                        )
                                      ],
                                    );
                                  } else {
                                     return Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 16.0,
                                        runSpacing: 16.0,
                                        children: [
                                          SizedBox(
                                            width: double.infinity,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  selectedPlaylist.name,
                                                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                                                ),
                                                Text(
                                                  '${selectedPlaylist.trackIds.length} tracks',
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 250,
                                            child: TextField(
                                              decoration: InputDecoration(
                                                hintText: 'Search tracks...',
                                                prefixIcon: const Icon(Icons.search),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8.0),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                                              ),
                                              onChanged: (value) {
                                                setState(() {
                                                  _searchQuery = value;
                                                });
                                              },
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              player.setActivePlaylist(selectedPlaylist);
                                            },
                                            icon: const Icon(Icons.radio_button_checked),
                                            label: const Text('Active'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: player.playingPlaylist?.id == selectedPlaylist.id
                                                  ? Theme.of(context).colorScheme.primary
                                                  : null,
                                              foregroundColor: player.playingPlaylist?.id == selectedPlaylist.id
                                                  ? Theme.of(context).colorScheme.onPrimary
                                                  : null,
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
                                                 setState((){});
                                              });
                                            },
                                            icon: const Icon(Icons.cloud_download),
                                            label: const Text('Import Cloud Media'),
                                          )
                                        ],
                                      );
                                  }
                                },
                              ),
                            ),

                            if (
                                player.playingPlaylist?.id != selectedPlaylist.id &&
                                (selectedPlaylist.isBookMode || (player.playingPlaylist?.isBookMode ?? false)) &&
                                HiveStorageService().getPlaybackState(selectedPlaylist.id)?.currentTrackId != null)
                              Builder(
                                builder: (context) {
                                  final state = HiveStorageService().getPlaybackState(selectedPlaylist.id);
                                  final track = state?.currentTrackId != null ? player.getTrack(state!.currentTrackId!) : null;
                                  final trackName = track?.title ?? track?.cloudPath.split('/').last.split('.').first ?? 'Unknown Track';

                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.menu_book),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Resume from track "$trackName"',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.play_circle_fill, size: 36),
                                          color: Theme.of(context).colorScheme.primary,
                                          onPressed: () {
                                            player.resumePlaylist(selectedPlaylist);
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                            const Divider(height: 1),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  List<String> filteredTrackIds = selectedPlaylist.trackIds;

                                  if (_searchQuery.trim().length >= 2) {
                                    final query = _searchQuery.trim();

                                    // 1. Calculate scores and keep matching tracks
                                    final List<MapEntry<String, int>> scoredTracks = [];
                                    for (final trackId in selectedPlaylist.trackIds) {
                                      final track = player.getTrack(trackId);
                                      if (track == null) continue;

                                      String searchString = _searchCache[trackId] ?? '';
                                      if (searchString.isEmpty) {
                                        if (track.title != null && track.title!.isNotEmpty) {
                                          searchString = '${track.artist ?? ""} ${track.title}';
                                        } else {
                                          searchString = track.cloudPath.split('/').last.split('.').first;
                                        }
                                        _searchCache[trackId] = searchString;
                                      }

                                      final score = SearchUtils.calculateMatchScore(query, searchString);
                                      if (score > 0) {
                                        scoredTracks.add(MapEntry(trackId, score));
                                      }
                                    }

                                    // 2. Sort by score descending (stable sort is naturally achieved in dart for same scores,
                                    // but to be perfectly safe, since original order is insertion order, dart's sort is stable)
                                    scoredTracks.sort((a, b) => b.value.compareTo(a.value));

                                    // 3. Extract the track IDs
                                    filteredTrackIds = scoredTracks.map((e) => e.key).toList();
                                  }

                                  return ListView.separated(
                                    padding: const EdgeInsets.all(16.0),
                                    itemCount: filteredTrackIds.length,
                                    separatorBuilder: (context, index) => const Divider(),
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
                                           player.playTrackDirectly(track);
                                        },
                                        onRemoveFromPlaylist: () {
                                           setState(() {
                                              selectedPlaylist.trackIds.remove(track.id);
                                              HiveStorageService().savePlaylist(selectedPlaylist);
                                           });
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
              ],
            ),
          ),
          // Persistent Bottom Control Panel
          const DesktopControlPanel(),
        ],
      ),
    );
  }
}
