import '../../utils/search_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
import '../../../services/hive_storage_service.dart';

class MobileLayout extends StatefulWidget {
  final List<Playlist> playlists;
  final Function(String) onAddPlaylist;
  final Function(String, String) onRenamePlaylist;
  final Function(String) onDeletePlaylist;
  final VoidCallback onPlaylistsChanged;

  const MobileLayout({
    super.key,
    required this.playlists,
    required this.onAddPlaylist,
    required this.onRenamePlaylist,
    required this.onDeletePlaylist,
    required this.onPlaylistsChanged,
  });

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout> {
  String _searchQuery = '';
  final Map<String, String> _searchCache = {};
  bool _isSearchExpanded = false;
  bool _isControlPanelCollapsed = false;
  final TextEditingController _searchController = TextEditingController();

  void _showPlaylistMenu(
    BuildContext context,
    Offset position,
    Playlist playlist,
  ) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final selectedPlaylist = player.currentPlaylist;
    final currentTrack = player.currentTrack;

    return Scaffold(
      floatingActionButton: selectedPlaylist == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'mobile_queue',
                  tooltip: 'Queue',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QueuePage()),
                    );
                  },
                  child: const Icon(Icons.queue_music),
                ),
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(context).copyWith(
                    floatingActionButtonTheme: Theme.of(context)
                        .floatingActionButtonTheme
                        .copyWith(
                          extendedSizeConstraints: const BoxConstraints(
                            minHeight: 48,
                            maxHeight: 48,
                          ),
                        ),
                  ),
                  child: FloatingActionButton.extended(
                    heroTag: 'mobile_active_playlist',
                    tooltip: 'Set active playlist',
                    onPressed: () {
                      player.setActivePlaylist(selectedPlaylist);
                    },
                    backgroundColor:
                        player.playingPlaylist?.id == selectedPlaylist.id
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    foregroundColor:
                        player.playingPlaylist?.id == selectedPlaylist.id
                        ? Theme.of(context).colorScheme.onPrimary
                        : null,
                    extendedPadding: const EdgeInsets.symmetric(horizontal: 12),
                    extendedIconLabelSpacing: 6,
                    extendedTextStyle: const TextStyle(fontSize: 13),
                    icon: const Icon(Icons.radio_button_checked, size: 18),
                    label: const Text('Active'),
                  ),
                ),
              ],
            ),
      drawer: Drawer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withAlpha(76),
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
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const StatsPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue),
              title: const Text('Queue'),
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const QueuePage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  const Text(
                    'PLAYLISTS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
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
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (context) => const ManagePlaylistsPage(),
                            ),
                          )
                          .then((_) => widget.onPlaylistsChanged());
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 24.0,
                ),
                itemCount: widget.playlists.length,
                itemBuilder: (context, index) {
                  final playlist = widget.playlists[index];
                  final isSelected = playlist.id == selectedPlaylist?.id;
                  final isPlayingPlaylist =
                      playlist.id == player.playingPlaylist?.id;

                  IconData playlistIcon = Icons.queue_music;
                  if (isPlayingPlaylist) {
                    playlistIcon = player.isPlaying
                        ? Icons.volume_up
                        : Icons.pause;
                  }
                  return GestureDetector(
                    onLongPressStart: (details) {
                      _showPlaylistMenu(
                        context,
                        details.globalPosition,
                        playlist,
                      );
                    },
                    child: ListTile(
                      leading: Icon(
                        playlistIcon,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: Text(
                        playlist.name,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      onTap: () {
                        player.selectPlaylist(playlist);
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
            // Control Panel at the top
            MobileControlPanel(compact: _isControlPanelCollapsed),

            // Resume Block
            if (selectedPlaylist != null &&
                player.playingPlaylist?.id != selectedPlaylist.id &&
                (selectedPlaylist.isBookMode ||
                    (player.playingPlaylist?.isBookMode ?? false)) &&
                HiveStorageService()
                        .getPlaybackState(selectedPlaylist.id)
                        ?.currentTrackId !=
                    null)
              Builder(
                builder: (context) {
                  final state = HiveStorageService().getPlaybackState(
                    selectedPlaylist.id,
                  );
                  final track = state?.currentTrackId != null
                      ? player.getTrack(state!.currentTrackId!)
                      : null;
                  final trackName =
                      track?.title ??
                      track?.cloudPath.split('/').last.split('.').first ??
                      'Unknown Track';

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
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
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
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

            // Playlist Name Header
            if (selectedPlaylist == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Open navigation menu',
                        icon: const Icon(Icons.menu),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No Playlist Selected',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            if (selectedPlaylist != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: _isSearchExpanded
                      ? [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () {
                              setState(() {
                                _isSearchExpanded = false;
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                hintText: 'Search...',
                                border: InputBorder.none,
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          setState(() {
                                            _searchController.clear();
                                            _searchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                });
                              },
                            ),
                          ),
                        ]
                      : [
                          Builder(
                            builder: (context) => IconButton(
                              tooltip: 'Open navigation menu',
                              icon: const Icon(Icons.menu),
                              onPressed: () {
                                Scaffold.of(context).openDrawer();
                              },
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedPlaylist.name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${selectedPlaylist.trackIds.length} tracks',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              setState(() {
                                _isSearchExpanded = true;
                              });
                            },
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Playlist actions',
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              if (value == 'import') {
                                Navigator.of(context)
                                    .push(
                                      MaterialPageRoute(
                                        builder: (context) => CloudImportPage(
                                          playlist: selectedPlaylist,
                                        ),
                                      ),
                                    )
                                    .then((_) {
                                      if (mounted) setState(() {});
                                    });
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'import',
                                child: ListTile(
                                  leading: Icon(Icons.cloud_download),
                                  title: Text('Import'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
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
                        List<String> filteredTrackIds =
                            selectedPlaylist.trackIds;

                        if (_searchQuery.trim().length >= 2) {
                          final query = _searchQuery.trim();

                          // 1. Calculate scores and keep matching tracks
                          final List<MapEntry<String, int>> scoredTracks = [];
                          for (final trackId in selectedPlaylist.trackIds) {
                            final track = player.getTrack(trackId);
                            if (track == null) continue;

                            String searchString = _searchCache[trackId] ?? '';
                            if (searchString.isEmpty) {
                              if (track.title != null &&
                                  track.title!.isNotEmpty) {
                                searchString =
                                    '${track.artist ?? ""} ${track.title}';
                              } else {
                                searchString = track.cloudPath
                                    .split('/')
                                    .last
                                    .split('.')
                                    .first;
                              }
                              _searchCache[trackId] = searchString;
                            }

                            final score = SearchUtils.calculateMatchScore(
                              query,
                              searchString,
                            );
                            if (score > 0) {
                              scoredTracks.add(MapEntry(trackId, score));
                            }
                          }

                          // 2. Sort by score descending (stable sort is naturally achieved in dart for same scores,
                          // but to be perfectly safe, since original order is insertion order, dart's sort is stable)
                          scoredTracks.sort(
                            (a, b) => b.value.compareTo(a.value),
                          );

                          // 3. Extract the track IDs
                          filteredTrackIds = scoredTracks
                              .map((e) => e.key)
                              .toList();
                        }

                        return NotificationListener<UserScrollNotification>(
                          onNotification: (notification) {
                            final shouldCollapse =
                                notification.direction ==
                                ScrollDirection.reverse;
                            final shouldExpand =
                                notification.direction ==
                                ScrollDirection.forward;

                            if (shouldCollapse && !_isControlPanelCollapsed) {
                              setState(() {
                                _isControlPanelCollapsed = true;
                              });
                            } else if (shouldExpand &&
                                _isControlPanelCollapsed) {
                              setState(() {
                                _isControlPanelCollapsed = false;
                              });
                            }
                            return false;
                          },
                          child: ListView.builder(
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
                                  player.playTrackDirectly(track);
                                },
                                onRemoveFromPlaylist: () {
                                  setState(() {
                                    selectedPlaylist.trackIds.remove(track.id);
                                    HiveStorageService().savePlaylist(
                                      selectedPlaylist,
                                    );
                                  });
                                },
                              );
                            },
                          ),
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
