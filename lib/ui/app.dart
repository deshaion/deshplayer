import 'package:flutter/material.dart';
import '../../services/mock_media_service.dart';
import '../../models/playlist.dart';
import 'layouts/responsive_layout.dart';
import 'layouts/mobile/mobile_layout.dart';
import 'layouts/desktop/desktop_layout.dart';

class DeshPlayerApp extends StatefulWidget {
  const DeshPlayerApp({super.key});

  @override
  State<DeshPlayerApp> createState() => _DeshPlayerAppState();
}

class _DeshPlayerAppState extends State<DeshPlayerApp> {
  final MockMediaService _mediaService = MockMediaService();
  List<Playlist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final playlists = await _mediaService.fetchPlaylists();
    setState(() {
      _playlists = playlists;
      _isLoading = false;
    });
  }

  void _addPlaylist(String name) {
    setState(() {
      final newPlaylist = Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        tracks: [],
      );
      _playlists = [..._playlists, newPlaylist];
    });
  }

  void _renamePlaylist(String id, String newName) {
    setState(() {
      _playlists = _playlists.map((p) {
        if (p.id == id) {
          return Playlist(id: p.id, name: newName, tracks: p.tracks);
        }
        return p;
      }).toList();
    });
  }

  void _deletePlaylist(String id) {
    setState(() {
      _playlists = _playlists.where((p) => p.id != id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeshPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto', // Default clean font
      ),
      home: _isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ResponsiveLayout(
              mobileLayout: MobileLayout(
                playlists: _playlists,
                onAddPlaylist: _addPlaylist,
                onRenamePlaylist: _renamePlaylist,
                onDeletePlaylist: _deletePlaylist,
              ),
              desktopLayout: DesktopLayout(
                playlists: _playlists,
                onAddPlaylist: _addPlaylist,
                onRenamePlaylist: _renamePlaylist,
                onDeletePlaylist: _deletePlaylist,
              ),
            ),
    );
  }
}
